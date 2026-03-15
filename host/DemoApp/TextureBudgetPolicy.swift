import CoreGraphics
import Foundation

struct SurfaceTextureMemoryEstimate: Equatable {
    let surfaceID: TerminalSurfaceID
    let pixelSize: CGSize
    let bytes: Int
}

struct TextureBudgetReport: Equatable {
    let surfaceEstimates: [SurfaceTextureMemoryEstimate]
    let totalBytes: Int
    let oversizedSurfaceIDs: [TerminalSurfaceID]
    let exceedsRoomBudget: Bool
}

enum TextureBudgetPolicy {
    static let bytesPerPixel = 4
    static let bufferCount = 2
    static let mipFactor = 1.0
    static let roomBudgetBytes = 512 * 1024 * 1024
    static let maxSurfaceBytes = 2048 * 1280 * bytesPerPixel * bufferCount

    static func pixelSize(
        cols: Int,
        rows: Int,
        profile: RenderProfile,
        backingScale: CGFloat
    ) -> CGSize {
        let logicalSize = profile.surfaceLogicalSize(cols: cols, rows: rows)
        return CGSize(
            width: (logicalSize.width * backingScale).rounded(),
            height: (logicalSize.height * backingScale).rounded()
        )
    }

    static func estimatedBytes(pixelSize: CGSize, mipmapped: Bool = false) -> Int {
        let mipScale = mipmapped ? (4.0 / 3.0) : mipFactor
        let pixelCount = Int(pixelSize.width) * Int(pixelSize.height)
        return Int(Double(pixelCount * bytesPerPixel * bufferCount) * mipScale)
    }

    static func assessRoom(
        surfaces: SurfaceStore,
        profilesByID: [String: RenderProfile],
        backingScale: CGFloat
    ) -> TextureBudgetReport {
        let estimates = surfaces.orderedSurfaces().compactMap { surface -> SurfaceTextureMemoryEstimate? in
            guard let profile = profilesByID[surface.profileID] else { return nil }
            let pixelSize = pixelSize(
                cols: surface.cols,
                rows: surface.rows,
                profile: profile,
                backingScale: backingScale
            )
            return SurfaceTextureMemoryEstimate(
                surfaceID: surface.id,
                pixelSize: pixelSize,
                bytes: estimatedBytes(pixelSize: pixelSize)
            )
        }

        let totalBytes = estimates.reduce(0) { $0 + $1.bytes }
        let oversizedSurfaceIDs = estimates.compactMap { estimate in
            estimate.bytes > maxSurfaceBytes ? estimate.surfaceID : nil
        }
        return TextureBudgetReport(
            surfaceEstimates: estimates,
            totalBytes: totalBytes,
            oversizedSurfaceIDs: oversizedSurfaceIDs,
            exceedsRoomBudget: totalBytes > roomBudgetBytes
        )
    }

    static func megabytesString(for bytes: Int) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
    }
}
