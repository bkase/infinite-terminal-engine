import AppKit
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
    return false
}

private func ghosttyConfirmReadClipboardCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ text: UnsafePointer<CChar>?,
    _ state: UnsafeMutableRawPointer?,
    _ request: ghostty_clipboard_request_e
) {
}

private func ghosttyWriteClipboardCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ location: ghostty_clipboard_e,
    _ content: UnsafePointer<ghostty_clipboard_content_s>?,
    _ len: Int,
    _ confirm: Bool
) {
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
    private var surface: ghostty_surface_t?
    private weak var hostView: NSView?
    private var lastPixelSize: CGSize = .zero
    private let textureDevice = MTLCreateSystemDefaultDevice()

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
    }

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
        status = bootError == nil ? "running" : "failed"
    }

    func ingestOutput(_ text: String) {
        guard let surface else { return }
        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(text.lengthOfBytes(using: .utf8)))
        }
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
