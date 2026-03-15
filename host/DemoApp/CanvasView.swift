import AppKit
import GhosttyKit
import MetalKit
import SwiftUI

struct CanvasView: NSViewRepresentable {
    @ObservedObject var runtime: EngineRuntime
    @ObservedObject var textureSource: GhosttySurfaceAdapter

    func makeCoordinator() -> Coordinator {
        Coordinator(runtime: runtime, textureSource: textureSource)
    }

    func makeNSView(context: Context) -> MetalCanvasView {
        let view = MetalCanvasView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        guard let device = view.device else { return view }
        view.clearColor = MTLClearColorMake(0.04, 0.05, 0.06, 1)
        view.colorPixelFormat = .rgba8Unorm
        view.preferredFramesPerSecond = 120
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        view.delegate = context.coordinator
        view.inputHandler = context.coordinator
        context.coordinator.attach(view: view, device: device)
        return view
    }

    func updateNSView(_ nsView: MetalCanvasView, context: Context) {
        _ = nsView
    }

    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate, CanvasInputHandler {
        private let runtime: EngineRuntime
        private let textureSource: GhosttySurfaceAdapter
        private weak var view: MetalCanvasView?
        private var queue: MTLCommandQueue?
        private var frameScheduler = FrameScheduler()
        private var dragState: DragState?

        private enum DragState {
            case canvasPan(lastPoint: CGPoint)
            case surfaceChrome(surfaceID: TerminalSurfaceID, lastPoint: CGPoint)
            case terminalContent(surfaceID: TerminalSurfaceID)
        }

        init(runtime: EngineRuntime, textureSource: GhosttySurfaceAdapter) {
            self.runtime = runtime
            self.textureSource = textureSource
        }

        func attach(view: MTKView, device: MTLDevice) {
            self.view = view as? MetalCanvasView
            queue = device.makeCommandQueue()
            if let queue {
                runtime.initializeIfNeeded(device: device, queue: queue)
            }
            runtime.onFrameInvalidation = { [weak self] reasons in
                self?.requestRedraw(reasons: reasons)
            }
            textureSource.onFrameInvalidation = { [weak self] reasons in
                self?.requestRedraw(reasons: reasons)
            }
            runtime.setBackingScale(view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
            runtime.resize(width: Int(view.drawableSize.width), height: Int(view.drawableSize.height))
            requestRedraw(reasons: [.camera, .surfaces])
        }

        func draw(in view: MTKView) {
            guard frameScheduler.pendingDraw() != nil else { return }
            guard let drawable = view.currentDrawable else { return }
            runtime.setSharedTerminalTexture(
                textureSource.latestFrontTexture(),
                generation: textureSource.latestTextureGeneration()
            )
            runtime.render(drawable: drawable)
            _ = frameScheduler.completePendingDraw()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            runtime.setBackingScale(view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
            runtime.resize(width: Int(size.width), height: Int(size.height))
        }

        func canvasPointerDown(at point: CGPoint, event: NSEvent) {
            switch InputRouter.routePointerDown(
                screenPoint: point,
                surfaces: runtime.surfaces,
                profilesByID: runtime.profilesByID,
                camera: runtime.camera,
                backingScale: runtime.backingScale
            ) {
            case .canvasPan:
                dragState = .canvasPan(lastPoint: point)
                runtime.focusSurface(nil)
                textureSource.focusChanged(false)
            case .surfaceChrome(let surfaceID):
                dragState = .surfaceChrome(surfaceID: surfaceID, lastPoint: point)
                runtime.focusSurface(surfaceID)
                textureSource.focusChanged(true)
            case .terminalMouse(let surfaceID, let localPoint):
                dragState = .terminalContent(surfaceID: surfaceID)
                runtime.focusSurface(surfaceID)
                textureSource.focusChanged(true)
                _ = textureSource.routeMouseButton(mouseButtonInput(for: event, localPoint: localPoint, pressed: true))
            case .canvasZoom, .terminalKeyboard, .terminalCopy, .terminalPaste, .terminalScroll, .ignored:
                dragState = nil
            }
        }

        func canvasPointerDragged(to point: CGPoint, event: NSEvent) {
            switch dragState {
            case .canvasPan(let lastPoint):
                runtime.pan(delta: InputNormalizer.panDelta(from: lastPoint, to: point))
                dragState = .canvasPan(lastPoint: point)
            case .surfaceChrome(let surfaceID, let lastPoint):
                runtime.moveSurface(surfaceID, delta: InputNormalizer.panDelta(from: lastPoint, to: point))
                dragState = .surfaceChrome(surfaceID: surfaceID, lastPoint: point)
            case .terminalContent(let surfaceID):
                guard let localPoint = terminalLocalPoint(at: point, expectedSurfaceID: surfaceID) else { return }
                _ = textureSource.routeMouseMove(
                    location: localPoint,
                    mods: InputNormalizer.ghosttyMods(from: event.modifierFlags)
                )
            case .none:
                break
            }
        }

        func canvasPointerUp(at point: CGPoint, event: NSEvent) {
            defer { dragState = nil }
            guard case .terminalContent(let surfaceID) = dragState,
                  let localPoint = terminalLocalPoint(at: point, expectedSurfaceID: surfaceID) else {
                return
            }
            _ = textureSource.routeMouseButton(mouseButtonInput(for: event, localPoint: localPoint, pressed: false))
        }

        func canvasPointerMoved(to point: CGPoint, event: NSEvent) {
            guard let localPoint = terminalLocalPoint(at: point) else { return }
            _ = textureSource.routeMouseMove(
                location: localPoint,
                mods: InputNormalizer.ghosttyMods(from: event.modifierFlags)
            )
        }

        func canvasScroll(at point: CGPoint, event: NSEvent) {
            switch InputRouter.routeScroll(
                screenPoint: point,
                surfaces: runtime.surfaces,
                profilesByID: runtime.profilesByID,
                camera: runtime.camera,
                backingScale: runtime.backingScale
            ) {
            case .terminalScroll(_, let localPoint):
                var input = InputNormalizer.normalizedScrollInput(from: event)
                _ = textureSource.routeMouseMove(
                    location: localPoint,
                    mods: InputNormalizer.ghosttyMods(from: event.modifierFlags)
                )
                input = GhosttyScrollInput(
                    deltaX: input.deltaX,
                    deltaY: input.deltaY,
                    scrollMods: input.scrollMods
                )
                _ = textureSource.routeScroll(input)
            case .canvasZoom:
                runtime.zoom(
                    factor: InputNormalizer.fallbackZoomFactor(forScrollDeltaY: event.scrollingDeltaY),
                    anchor: point
                )
            case .canvasPan, .terminalKeyboard, .terminalCopy, .terminalPaste, .terminalMouse, .surfaceChrome, .ignored:
                break
            }
        }

        func canvasMagnify(factor: Float, anchor: CGPoint) {
            runtime.zoom(factor: factor, anchor: anchor)
        }

        func canvasKeyDown(_ event: NSEvent) {
            guard case .terminalKeyboard = InputRouter.routeKeyboard(
                focusedSurfaceID: runtime.surfaces.focusedSurfaceID(),
                surfaces: runtime.surfaces
            ),
            let input = InputNormalizer.normalizedKeyInput(from: event) else {
                return
            }
            _ = textureSource.routeKeyInput(input)
        }

        func canvasKeyUp(_ event: NSEvent) {
            guard case .terminalKeyboard = InputRouter.routeKeyboard(
                focusedSurfaceID: runtime.surfaces.focusedSurfaceID(),
                surfaces: runtime.surfaces
            ),
            let input = InputNormalizer.normalizedKeyInput(from: event, action: GhosttyKeyActionCode.release) else {
                return
            }
            _ = textureSource.routeKeyInput(input)
        }

        func canvasCopy() {
            guard case .terminalCopy = InputRouter.routeCopy(
                focusedSurfaceID: runtime.surfaces.focusedSurfaceID(),
                surfaces: runtime.surfaces
            ) else {
                return
            }
            textureSource.copySelectionToClipboard()
        }

        func canvasPaste() {
            guard case .terminalPaste = InputRouter.routePaste(
                focusedSurfaceID: runtime.surfaces.focusedSurfaceID(),
                surfaces: runtime.surfaces
            ) else {
                return
            }
            _ = textureSource.pasteRequest()
        }

        private func requestRedraw(reasons: FrameInvalidationReasons) {
            guard frameScheduler.invalidate(reasons), let view else { return }
            view.needsDisplay = true
        }

        private func terminalLocalPoint(
            at point: CGPoint,
            expectedSurfaceID: TerminalSurfaceID? = nil
        ) -> CGPoint? {
            guard case .some(let hit) = InputRouter.topmostHit(
                screenPoint: point,
                surfaces: runtime.surfaces,
                profilesByID: runtime.profilesByID,
                camera: runtime.camera,
                backingScale: runtime.backingScale
            ) else {
                return nil
            }
            guard expectedSurfaceID == nil || hit.surfaceID == expectedSurfaceID else { return nil }
            guard case .content(let localPoint) = hit.region else { return nil }
            return localPoint
        }

        private func mouseButtonInput(
            for event: NSEvent,
            localPoint: CGPoint,
            pressed: Bool
        ) -> GhosttyMouseButtonInput {
            GhosttyMouseButtonInput(
                state: Int32((pressed ? GHOSTTY_MOUSE_PRESS : GHOSTTY_MOUSE_RELEASE).rawValue),
                button: {
                    switch event.type {
                    case .rightMouseDown, .rightMouseUp:
                        return Int32(GHOSTTY_MOUSE_RIGHT.rawValue)
                    case .otherMouseDown, .otherMouseUp:
                        return Int32(GHOSTTY_MOUSE_MIDDLE.rawValue)
                    default:
                        return Int32(GHOSTTY_MOUSE_LEFT.rawValue)
                    }
                }(),
                mods: Int32(InputNormalizer.ghosttyMods(from: event.modifierFlags)),
                location: localPoint
            )
        }
    }
}
