import CoreGraphics
import Metal

struct TerminalTexturePublishState<Texture> {
    private(set) var frontTexture: Texture?
    private(set) var backTexture: Texture?
    private(set) var frontGeneration: UInt64 = 0
    private(set) var backGeneration: UInt64 = 0
    private(set) var frontSize: CGSize = .zero
    private(set) var pendingSize: CGSize = .zero
    private(set) var pendingGeneration: UInt64 = 0
    private(set) var publishInFlight = false

    mutating func beginPublish(backTexture: Texture, size: CGSize) -> UInt64? {
        guard !publishInFlight else { return nil }
        self.backTexture = backTexture
        pendingSize = size
        backGeneration = max(backGeneration + 1, frontGeneration + 1)
        pendingGeneration = backGeneration
        publishInFlight = true
        return pendingGeneration
    }

    mutating func completePublish(_ generation: UInt64) -> Bool {
        guard publishInFlight, generation == pendingGeneration, let backTexture else { return false }
        let previousFront = frontTexture
        frontTexture = backTexture
        frontGeneration = generation
        frontSize = pendingSize
        self.backTexture = previousFront
        pendingSize = .zero
        pendingGeneration = 0
        publishInFlight = false
        return true
    }

    mutating func cancelPublish(_ generation: UInt64) {
        guard publishInFlight, generation == pendingGeneration else { return }
        pendingSize = .zero
        pendingGeneration = 0
        publishInFlight = false
    }
}

@MainActor
final class TerminalTexturePublisher {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    var didPublishGeneration: ((UInt64) -> Void)?
    private(set) var state = TerminalTexturePublishState<MTLTexture>()

    init?(device: MTLDevice?) {
        guard let device, let commandQueue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = commandQueue
    }

    var latestFrontTexture: MTLTexture? {
        state.frontTexture
    }

    var latestGeneration: UInt64 {
        state.frontGeneration
    }

    func publishSnapshot(from sourceTexture: MTLTexture) {
        let size = CGSize(width: sourceTexture.width, height: sourceTexture.height)
        guard let backTexture = reusableBackTexture(for: sourceTexture) else { return }
        guard let generation = state.beginPublish(backTexture: backTexture, size: size) else { return }
        guard
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let blitEncoder = commandBuffer.makeBlitCommandEncoder()
        else {
            state.cancelPublish(generation)
            return
        }

        blitEncoder.copy(
            from: sourceTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: sourceTexture.width, height: sourceTexture.height, depth: 1),
            to: backTexture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        blitEncoder.endEncoding()

        commandBuffer.addCompletedHandler { [weak self] buffer in
            let completed = buffer.status == .completed
            Task { @MainActor in
                guard let self else { return }
                if completed {
                    if self.state.completePublish(generation) {
                        self.didPublishGeneration?(generation)
                    }
                } else {
                    self.state.cancelPublish(generation)
                }
            }
        }
        commandBuffer.commit()
    }

    private func reusableBackTexture(for sourceTexture: MTLTexture) -> MTLTexture? {
        if let backTexture = state.backTexture,
            backTexture.width == sourceTexture.width,
            backTexture.height == sourceTexture.height,
            backTexture.pixelFormat == sourceTexture.pixelFormat
        {
            return backTexture
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: sourceTexture.pixelFormat,
            width: sourceTexture.width,
            height: sourceTexture.height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .renderTarget]
        return device.makeTexture(descriptor: descriptor)
    }
}
