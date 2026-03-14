import Darwin
import EngineABI
import Foundation

typealias EngineCreateFn = @convention(c) (UnsafeMutablePointer<OpaquePointer?>?, UnsafePointer<ite_EngineConfig>?) -> ite_EngineStatus
typealias EngineDestroyFn = @convention(c) (OpaquePointer?) -> Void
typealias EngineInitPathFn = @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> ite_EngineStatus
typealias EngineReplaceRectsFn = @convention(c) (OpaquePointer?, UnsafePointer<ite_Rect>?, Int) -> ite_EngineStatus
typealias EngineResizeFn = @convention(c) (OpaquePointer?, UInt32, UInt32) -> ite_EngineStatus
typealias EnginePanFn = @convention(c) (OpaquePointer?, Float, Float) -> ite_EngineStatus
typealias EngineZoomFn = @convention(c) (OpaquePointer?, Float, Float, Float) -> ite_EngineStatus
typealias EngineRenderFn = @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> ite_EngineStatus
typealias EngineStatsFn = @convention(c) (OpaquePointer?, UnsafeMutablePointer<ite_FrameStats>?) -> ite_EngineStatus
typealias EngineErrorFn = @convention(c) (OpaquePointer?) -> UnsafePointer<CChar>?
typealias EngineVersionFn = @convention(c) () -> UInt32

final class EngineBindings: @unchecked Sendable {
    static let shared = try! EngineBindings()

    let headerVersion: EngineVersionFn
    let create: EngineCreateFn
    let destroy: EngineDestroyFn
    let initWithMetallibPath: EngineInitPathFn
    let replaceRects: EngineReplaceRectsFn
    let resize: EngineResizeFn
    let pan: EnginePanFn
    let zoom: EngineZoomFn
    let render: EngineRenderFn
    let getStats: EngineStatsFn
    let getLastError: EngineErrorFn

    private let handle: UnsafeMutableRawPointer

    init() throws {
        guard let dylibURL = Bundle.module.url(forResource: "libengine", withExtension: "dylib") else {
            throw NSError(domain: "EngineBindings", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing libengine.dylib"])
        }
        guard let handle = dlopen(dylibURL.path, RTLD_NOW | RTLD_LOCAL) else {
            throw NSError(domain: "EngineBindings", code: 2, userInfo: [NSLocalizedDescriptionKey: String(cString: dlerror())])
        }
        self.handle = handle

        func load<T>(_ symbol: String, as type: T.Type) throws -> T {
            guard let raw = dlsym(handle, symbol) else {
                throw NSError(domain: "EngineBindings", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing symbol \(symbol)"])
            }
            return unsafeBitCast(raw, to: type)
        }

        headerVersion = try load("ite_engine_header_version", as: EngineVersionFn.self)
        create = try load("ite_engine_create", as: EngineCreateFn.self)
        destroy = try load("ite_engine_destroy", as: EngineDestroyFn.self)
        initWithMetallibPath = try load("ite_engine_init_with_metallib_path", as: EngineInitPathFn.self)
        replaceRects = try load("ite_engine_replace_rects", as: EngineReplaceRectsFn.self)
        resize = try load("ite_engine_resize", as: EngineResizeFn.self)
        pan = try load("ite_engine_pan", as: EnginePanFn.self)
        zoom = try load("ite_engine_zoom", as: EngineZoomFn.self)
        render = try load("ite_engine_render", as: EngineRenderFn.self)
        getStats = try load("ite_engine_get_stats", as: EngineStatsFn.self)
        getLastError = try load("ite_engine_get_last_error", as: EngineErrorFn.self)
    }

    deinit {
        dlclose(handle)
    }
}
