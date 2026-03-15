import Darwin
import Foundation
import Metal
import SwiftUI

private enum GhosttySurfaceSelfTestError: LocalizedError {
    case timedOut(String)
    case missingTexture(String)

    var errorDescription: String? {
        switch self {
        case .timedOut(let message):
            return message
        case .missingTexture(let message):
            return message
        }
    }
}

@MainActor
final class GhosttySurfaceSelfTestDriver: ObservableObject {
    let adapter: GhosttySurfaceAdapter

    init() {
        let profile = (try? RenderProfileCatalog.defaultProfile()) ?? RenderProfile(
            id: RenderProfileCatalog.defaultProfileID,
            themeID: "terminal-dark-v1",
            pointSize: 14,
            cellWidth: 7,
            lineHeight: 16,
            paddingX: 10,
            paddingY: 10,
            titlebarHeight: 28,
            regularFontFile: "PragmataPro_Mono_R_09.ttf",
            boldFontFile: "PragmataPro_Mono_B_09.ttf",
            italicFontFile: "PragmataPro_Mono_I_09.ttf"
        )
        self.adapter = GhosttySurfaceAdapter(profile: profile, bootstrap: .mockLoopback)
    }

    func run() async {
        let exitCode: Int32
        do {
            try await exerciseAdapter()
            fputs("ghostty-surface-selftest: PASS\n", stderr)
            exitCode = 0
        } catch {
            fputs("ghostty-surface-selftest: FAIL \(error.localizedDescription)\n", stderr)
            exitCode = 1
        }

        adapter.shutdown()
        fflush(stderr)
        exit(exitCode)
    }

    private func exerciseAdapter() async throws {
        try await expect("surface never became ready") {
            self.adapter.status == "ready" || self.adapter.status == "running"
        }

        let initialTexture = try await expectTexture("surface never produced an IOSurface-backed texture")
        adapter.ingestOutput("selftest-visible-alpha\n")
        adapter.requestRender()

        try await expect("loopback text never became visible") {
            self.adapter.visibleText().contains("selftest-visible-alpha")
        }

        adapter.resizeHost(to: CGSize(width: 720, height: 420))
        adapter.requestRender()
        adapter.ingestOutput("selftest-visible-beta\n")

        try await expect("post-resize text never became visible") {
            let text = self.adapter.visibleText()
            return text.contains("selftest-visible-alpha") && text.contains("selftest-visible-beta")
        }

        try await expect("surface never produced a resized texture") {
            guard let texture = self.adapter.latestFrontTexture() else { return false }
            return texture.width != initialTexture.width || texture.height != initialTexture.height
        }

        guard adapter.latestFrontTexture() != nil else {
            throw GhosttySurfaceSelfTestError.missingTexture("surface lost its published front texture after resize")
        }
    }

    private func expectTexture(_ failure: String) async throws -> MTLTexture {
        try await expect(failure) {
            self.adapter.latestFrontTexture() != nil
        }
        guard let texture = adapter.latestFrontTexture() else {
            throw GhosttySurfaceSelfTestError.missingTexture(failure)
        }
        return texture
    }

    private func expect(_ failure: String, condition: @escaping @MainActor () -> Bool) async throws {
        let timeout: TimeInterval = 3
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            adapter.tick()
            adapter.requestRender()
            try? await Task.sleep(for: .milliseconds(50))
        }

        if !condition() {
            throw GhosttySurfaceSelfTestError.timedOut(failure)
        }
    }
}

struct GhosttySurfaceSelfTestView: View {
    @StateObject private var driver = GhosttySurfaceSelfTestDriver()

    var body: some View {
        GhosttyTerminalPane(adapter: driver.adapter)
            .frame(minWidth: 420, minHeight: 280)
            .task {
                await driver.run()
            }
    }
}
