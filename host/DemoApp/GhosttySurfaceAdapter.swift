import AppKit
import Darwin
import Foundation
import GhosttyKit
import IOSurface
import Metal

struct GhosttySurfaceBootstrap: Sendable {
    let command: String?
    let initialInput: String?

    static func loginShellBanner(shellPath: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh") -> Self {
        Self(
            command: "\(shellPath) -l",
            initialInput: "printf '\\033[32mEmbedded Ghostty ready\\033[0m\\r\\n'\n"
        )
    }

    static let mockLoopback = Self(command: "perl -ne 'print'", initialInput: nil)
}

private func ghosttyAdapterFromUserdata(_ userdata: UnsafeMutableRawPointer?) -> GhosttySurfaceAdapter? {
    guard let userdata else { return nil }
    return Unmanaged<GhosttySurfaceAdapter>.fromOpaque(userdata).takeUnretainedValue()
}

private func readClipboardString(location: ghostty_clipboard_e) -> String? {
    let pasteboard = location == GHOSTTY_CLIPBOARD_SELECTION ? NSPasteboard.general : NSPasteboard.general
    return pasteboard.string(forType: .string)
}

private func shouldConfirmClipboardRead(text: String, request: ghostty_clipboard_request_e) -> Bool {
    _ = request
    return !text.isEmpty
}

private func writeClipboard(
    location: ghostty_clipboard_e,
    content: UnsafePointer<ghostty_clipboard_content_s>?,
    len: Int,
    confirm: Bool
) {
    _ = location
    _ = confirm
    guard let content, len > 0 else { return }
    let items = UnsafeBufferPointer(start: content, count: len)
    guard let first = items.first(where: {
        guard let mime = $0.mime else { return false }
        return String(cString: mime) == "text/plain"
    }) ?? items.first,
    let data = first.data
    else {
        return
    }

    let string = String(cString: data)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
}

private func ghosttyWakeupCallback(_ userdata: UnsafeMutableRawPointer?) {
    guard let adapter = ghosttyAdapterFromUserdata(userdata) else { return }
    Task { @MainActor in
        adapter.tick()
    }
}

private func ghosttyActionCallback(
    _ app: ghostty_app_t?,
    _ target: ghostty_target_s,
    _ action: ghostty_action_s
) -> Bool {
    return false
}

private func ghosttyReadClipboardCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ location: ghostty_clipboard_e,
    _ state: UnsafeMutableRawPointer?
) -> Bool {
    guard
        let adapter = ghosttyAdapterFromUserdata(userdata),
        let surface = adapter.surface,
        let state,
        let text = readClipboardString(location: location)
    else {
        return false
    }

    text.withCString { ptr in
        ghostty_surface_complete_clipboard_request(surface, ptr, state, true)
    }
    return true
}

private func ghosttyConfirmReadClipboardCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ text: UnsafePointer<CChar>?,
    _ state: UnsafeMutableRawPointer?,
    _ request: ghostty_clipboard_request_e
) {
    guard
        let adapter = ghosttyAdapterFromUserdata(userdata),
        let surface = adapter.surface,
        let state,
        let text
    else {
        return
    }

    let string = String(cString: text)
    string.withCString { ptr in
        ghostty_surface_complete_clipboard_request(surface, ptr, state, shouldConfirmClipboardRead(text: string, request: request))
    }
}

private func ghosttyWriteClipboardCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ location: ghostty_clipboard_e,
    _ content: UnsafePointer<ghostty_clipboard_content_s>?,
    _ len: Int,
    _ confirm: Bool
) {
    guard ghosttyAdapterFromUserdata(userdata) != nil else { return }
    writeClipboard(location: location, content: content, len: len, confirm: confirm)
}

private func ghosttyCloseSurfaceCallback(_ userdata: UnsafeMutableRawPointer?, _ processAlive: Bool) {
    guard let adapter = ghosttyAdapterFromUserdata(userdata) else { return }
    Task { @MainActor in
        adapter.markClosed()
    }
}

@MainActor
final class GhosttySurfaceAdapter: ObservableObject {
    private(set) var title = "Terminal"
    private(set) var status = "booting"
    private(set) var bootError: String?

    let profile: RenderProfile
    let bootstrap: GhosttySurfaceBootstrap

    private var config: ghostty_config_t?
    private var app: ghostty_app_t?
    nonisolated(unsafe) fileprivate var surface: ghostty_surface_t?
    private weak var hostView: NSView?
    private var lastPixelSize: CGSize = .zero
    private let textureDevice = MTLCreateSystemDefaultDevice()
    private lazy var texturePublisher = TerminalTexturePublisher(device: textureDevice)

    init(
        profile: RenderProfile,
        bootstrap: GhosttySurfaceBootstrap = .loginShellBanner()
    ) {
        self.profile = profile
        self.bootstrap = bootstrap
        do {
            try Self.initializeGhosttyIfNeeded()
            self.config = try Self.loadConfig()
        } catch {
            self.bootError = error.localizedDescription
            self.status = "failed"
        }
    }

    func attach(to view: NSView) {
        guard bootError == nil else { return }
        hostView = view
        guard Self.isRenderable(view: view) else { return }
        if surface == nil {
            do {
                try createSurface(in: view)
            } catch {
                bootError = error.localizedDescription
                status = "failed"
                return
            }
        }

        updateSize()
    }

    func updateSize() {
        guard let hostView, let surface else { return }
        guard Self.isRenderable(view: hostView) else { return }
        let scale = Double(hostView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        resize(to: hostView.convertToBacking(hostView.bounds.size), backingScale: scale, surface: surface)
    }

    func requestRender() {
        guard let surface else { return }
        ghostty_surface_refresh(surface)
        ghostty_surface_draw(surface)
        tick()
        publishLatestSurfaceTexture()
    }

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
        status = bootError == nil ? "running" : "failed"
        publishLatestSurfaceTexture()
    }

    func ingestOutput(_ text: String) {
        guard let surface else { return }
        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(text.lengthOfBytes(using: .utf8)))
        }
    }

    func routeKeyInput(_ input: GhosttyKeyInput) -> TerminalInputRoute {
        guard input.action != GhosttyKeyActionCode.release else {
            if let surface {
                withSurfaceKeyEvent(input) { ghostty_surface_key(surface, $0) }
            }
            return .terminalInteraction
        }

        guard let bytes = Self.encodeKeyBytes(input) else {
            if let surface {
                withSurfaceKeyEvent(input) { ghostty_surface_key(surface, $0) }
                return .terminalInteraction
            }
            return .ignored
        }

        if let surface {
            withSurfaceKeyEvent(input) { ghostty_surface_key(surface, $0) }
        }
        return .terminalBytes(bytes)
    }

    func routeTextInput(_ text: String) -> TerminalInputRoute {
        guard !text.isEmpty else { return .ignored }
        let payload = Data(text.utf8)
        if let surface {
            text.withCString { ptr in
                ghostty_surface_text(surface, ptr, UInt(text.lengthOfBytes(using: .utf8)))
            }
        }
        return .terminalBytes(payload)
    }

    func routePaste(_ text: String, bracketed: Bool) -> TerminalInputRoute {
        guard !text.isEmpty else { return .ignored }
        let payload = InputNormalizer.encodedPasteBytes(for: text, bracketed: bracketed)
        if let surface {
            text.withCString { ptr in
                ghostty_surface_text(surface, ptr, UInt(text.lengthOfBytes(using: .utf8)))
            }
        }
        return .terminalBytes(payload)
    }

    func routeMouseButton(_ input: GhosttyMouseButtonInput) -> TerminalInputRoute {
        guard let surface else { return .terminalInteraction }
        ghostty_surface_mouse_pos(surface, input.location.x, input.location.y, ghostty_input_mods_e(rawValue: UInt32(input.mods)))
        _ = ghostty_surface_mouse_button(
            surface,
            ghostty_input_mouse_state_e(rawValue: UInt32(input.state)),
            ghostty_input_mouse_button_e(rawValue: UInt32(input.button)),
            ghostty_input_mods_e(rawValue: UInt32(input.mods))
        )
        return .terminalInteraction
    }

    func routeMouseMove(location: CGPoint, mods: UInt16) -> TerminalInputRoute {
        guard let surface else { return .terminalInteraction }
        ghostty_surface_mouse_pos(surface, location.x, location.y, ghostty_input_mods_e(rawValue: UInt32(mods)))
        return .terminalInteraction
    }

    func routeScroll(_ input: GhosttyScrollInput) -> TerminalInputRoute {
        guard let surface else { return .terminalInteraction }
        ghostty_surface_mouse_scroll(surface, input.deltaX, input.deltaY, input.scrollMods)
        return .terminalInteraction
    }

    func selectionState() -> String? {
        guard let surface, ghostty_surface_has_selection(surface) else { return nil }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        return String(cString: text.text)
    }

    func copySelectionToClipboard() {
        guard let selection = selectionState() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selection, forType: .string)
    }

    func pasteRequest() -> TerminalInputRoute {
        guard let text = readClipboardString(location: GHOSTTY_CLIPBOARD_STANDARD) else { return .ignored }
        return routePaste(text, bracketed: true)
    }

    func performBindingAction(_ action: String) -> Bool {
        guard let surface else { return false }
        return action.withCString { ptr in
            ghostty_surface_binding_action(surface, ptr, UInt(action.lengthOfBytes(using: .utf8)))
        }
    }

    func imePoint() -> CGRect? {
        guard let surface else { return nil }
        var x = 0.0
        var y = 0.0
        var width = 0.0
        var height = 0.0
        ghostty_surface_ime_point(surface, &x, &y, &width, &height)
        guard width >= 0, height >= 0 else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    func resize(to pixelSize: CGSize, backingScale: Double) {
        guard let surface else { return }
        resize(to: pixelSize, backingScale: backingScale, surface: surface)
    }

    func resizeHost(to pointSize: CGSize) {
        guard let hostView else { return }
        hostView.setFrameSize(pointSize)
        hostView.window?.setContentSize(pointSize)
        let scale = Double(hostView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        resize(to: hostView.convertToBacking(pointSize), backingScale: scale)
    }

    func visibleText() -> String {
        guard let surface else { return "" }
        let viewport = ghostty_selection_s(
            top_left: ghostty_point_s(
                tag: GHOSTTY_POINT_VIEWPORT,
                coord: GHOSTTY_POINT_COORD_TOP_LEFT,
                x: 0,
                y: 0
            ),
            bottom_right: ghostty_point_s(
                tag: GHOSTTY_POINT_VIEWPORT,
                coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
                x: 0,
                y: 0
            ),
            rectangle: false
        )
        var text = ghostty_text_s()
        guard ghostty_surface_read_text(surface, viewport, &text) else {
            return ""
        }
        defer { ghostty_surface_free_text(surface, &text) }
        return String(cString: text.text)
    }

    func latestFrontTexture() -> MTLTexture? {
        texturePublisher?.latestFrontTexture
    }

    func latestTextureGeneration() -> UInt64 {
        texturePublisher?.latestGeneration ?? 0
    }

    private func publishLatestSurfaceTexture() {
        guard let sourceTexture = makeLiveSurfaceTexture() else { return }
        texturePublisher?.publishSnapshot(from: sourceTexture)
    }

    private func makeLiveSurfaceTexture() -> MTLTexture? {
        guard
            let hostView,
            let layer = hostView.layer,
            let device = textureDevice
        else {
            return nil
        }
        let contents = layer.contents as AnyObject
        guard CFGetTypeID(contents) == IOSurfaceGetTypeID() else {
            return nil
        }
        let surface = unsafeDowncast(contents, to: IOSurfaceRef.self)

        let width = IOSurfaceGetWidth(surface)
        let height = IOSurfaceGetHeight(surface)
        guard width > 0, height > 0 else { return nil }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        return device.makeTexture(descriptor: descriptor, iosurface: surface, plane: 0)
    }

    func shutdown() {
        if let surface {
            ghostty_surface_free(surface)
            self.surface = nil
        }
        if let app {
            ghostty_app_free(app)
            self.app = nil
        }
        if let config {
            ghostty_config_free(config)
            self.config = nil
        }
        status = "stopped"
    }

    func markClosed() {
        status = "closed"
    }

    func focusChanged(_ isFocused: Bool) {
        guard let surface else { return }
        ghostty_surface_set_focus(surface, isFocused)
    }

    private func createSurface(in view: NSView) throws {
        guard let config else { throw GhosttyAdapterError.configUnavailable }

        var runtimeConfig = ghostty_runtime_config_s()
        runtimeConfig.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtimeConfig.supports_selection_clipboard = true
        runtimeConfig.wakeup_cb = ghosttyWakeupCallback
        runtimeConfig.action_cb = ghosttyActionCallback
        runtimeConfig.read_clipboard_cb = ghosttyReadClipboardCallback
        runtimeConfig.confirm_read_clipboard_cb = ghosttyConfirmReadClipboardCallback
        runtimeConfig.write_clipboard_cb = ghosttyWriteClipboardCallback
        runtimeConfig.close_surface_cb = ghosttyCloseSurfaceCallback

        guard let app = ghostty_app_new(&runtimeConfig, config) else {
            throw GhosttyAdapterError.appCreationFailed
        }
        self.app = app

        var surfaceConfig = ghostty_surface_config_new()
        surfaceConfig.platform_tag = GHOSTTY_PLATFORM_MACOS
        surfaceConfig.platform.macos.nsview = Unmanaged.passUnretained(view).toOpaque()
        surfaceConfig.userdata = Unmanaged.passUnretained(self).toOpaque()
        surfaceConfig.scale_factor = Double(view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        surfaceConfig.font_size = Float(profile.pointSize)
        surfaceConfig.context = GHOSTTY_SURFACE_CONTEXT_WINDOW
        surfaceConfig.command = bootstrap.command.flatMap(Self.duplicatedCString)
        surfaceConfig.initial_input = bootstrap.initialInput.flatMap(Self.duplicatedCString)
        defer {
            if let command = surfaceConfig.command {
                free(UnsafeMutableRawPointer(mutating: command))
            }
            if let initialInput = surfaceConfig.initial_input {
                free(UnsafeMutableRawPointer(mutating: initialInput))
            }
        }

        guard let surface = ghostty_surface_new(app, &surfaceConfig) else {
            throw GhosttyAdapterError.surfaceCreationFailed
        }
        self.surface = surface
        status = "ready"
    }

    private func resize(to pixelSize: CGSize, backingScale: Double, surface: ghostty_surface_t) {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return }
        if pixelSize == lastPixelSize { return }
        lastPixelSize = pixelSize
        let width = UInt32(max(Int(pixelSize.width), 1))
        let height = UInt32(max(Int(pixelSize.height), 1))
        ghostty_surface_set_content_scale(surface, backingScale, backingScale)
        ghostty_surface_set_size(surface, width, height)
    }

    private func withSurfaceKeyEvent(_ input: GhosttyKeyInput, _ body: (ghostty_input_key_s) -> Void) {
        input.text.withCString { textPtr in
            body(ghostty_input_key_s(
                action: ghostty_input_action_e(rawValue: UInt32(input.action)),
                mods: ghostty_input_mods_e(rawValue: UInt32(input.mods)),
                consumed_mods: ghostty_input_mods_e(rawValue: UInt32(input.consumedMods)),
                keycode: UInt32(input.keyCode),
                text: textPtr,
                unshifted_codepoint: input.unshiftedCodepoint,
                composing: input.composing
            ))
        }
    }

    static func encodeKeyBytes(_ input: GhosttyKeyInput) -> Data? {
        let mods = input.mods
        let hasSuper = (mods & UInt16(GHOSTTY_MODS_SUPER.rawValue)) != 0
        let hasControl = (mods & UInt16(GHOSTTY_MODS_CTRL.rawValue)) != 0

        if hasSuper {
            return nil
        }

        if hasControl, let scalar = input.text.unicodeScalars.first, scalar.isASCII {
            return Data([UInt8(scalar.value & 0x1f)])
        }

        if !input.text.isEmpty, mods == 0 || mods == UInt16(GHOSTTY_MODS_SHIFT.rawValue) {
            return Data(input.text.utf8)
        }

        switch UInt32(input.keyCode) {
        case GHOSTTY_KEY_ENTER.rawValue:
            return Data("\r".utf8)
        case GHOSTTY_KEY_TAB.rawValue:
            return Data("\t".utf8)
        case GHOSTTY_KEY_ESCAPE.rawValue:
            return Data([0x1b])
        case GHOSTTY_KEY_BACKSPACE.rawValue:
            return Data([0x7f])
        case GHOSTTY_KEY_DELETE.rawValue:
            return Data("\u{1b}[3~".utf8)
        case GHOSTTY_KEY_HOME.rawValue:
            return Data("\u{1b}[H".utf8)
        case GHOSTTY_KEY_END.rawValue:
            return Data("\u{1b}[F".utf8)
        case GHOSTTY_KEY_PAGE_UP.rawValue:
            return Data("\u{1b}[5~".utf8)
        case GHOSTTY_KEY_PAGE_DOWN.rawValue:
            return Data("\u{1b}[6~".utf8)
        case GHOSTTY_KEY_ARROW_UP.rawValue:
            return Data("\u{1b}[A".utf8)
        case GHOSTTY_KEY_ARROW_DOWN.rawValue:
            return Data("\u{1b}[B".utf8)
        case GHOSTTY_KEY_ARROW_RIGHT.rawValue:
            return Data("\u{1b}[C".utf8)
        case GHOSTTY_KEY_ARROW_LEFT.rawValue:
            return Data("\u{1b}[D".utf8)
        default:
            return nil
        }
    }

    private static func duplicatedCString(_ string: String) -> UnsafePointer<CChar>? {
        guard let ptr = strdup(string) else { return nil }
        return UnsafePointer(ptr)
    }

    private static func loadConfig() throws -> ghostty_config_t {
        guard let config = ghostty_config_new() else {
            throw GhosttyAdapterError.configUnavailable
        }
        ghostty_config_load_default_files(config)
        ghostty_config_finalize(config)
        return config
    }

    private static func initializeGhosttyIfNeeded() throws {
        if didInitialize { return }
        let status = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        guard status == GHOSTTY_SUCCESS else {
            throw GhosttyAdapterError.initializationFailed(status)
        }
        didInitialize = true
    }

    private static var didInitialize = false

    private static func isRenderable(view: NSView) -> Bool {
        guard view.window != nil else { return false }
        let size = view.convertToBacking(view.bounds.size)
        return size.width >= 32 && size.height >= 32
    }
}

enum GhosttyAdapterError: LocalizedError {
    case initializationFailed(Int32)
    case configUnavailable
    case appCreationFailed
    case surfaceCreationFailed

    var errorDescription: String? {
        switch self {
        case .initializationFailed(let status):
            return "ghostty_init failed with status \(status)"
        case .configUnavailable:
            return "ghostty config initialization failed"
        case .appCreationFailed:
            return "ghostty_app_new failed"
        case .surfaceCreationFailed:
            return "ghostty_surface_new failed"
        }
    }
}
