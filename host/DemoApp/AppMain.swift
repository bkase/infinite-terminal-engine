import SwiftUI

struct HostShellView: View {
    @StateObject private var runtime = EngineRuntime()
    @StateObject private var terminalAdapter: GhosttySurfaceAdapter

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
        _terminalAdapter = StateObject(wrappedValue: GhosttySurfaceAdapter(profile: profile))
    }

    var body: some View {
        HSplitView {
            ZStack(alignment: .topLeading) {
                CanvasView(runtime: runtime, textureSource: terminalAdapter)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Spatial Terminal Host")
                        .font(.headline)
                    Text(runtime.statsSummary)
                        .font(.system(.caption, design: .monospaced))
                    Text("Render shell: DemoApp")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(12)
                if let bootError = runtime.bootError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Render Profile Error")
                            .font(.headline)
                        Text(bootError)
                            .font(.system(.body, design: .monospaced))
                    }
                    .padding(16)
                    .frame(maxWidth: 420, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .padding(24)
                }
            }
            .frame(minWidth: 520)

            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    GhosttyTerminalPane(adapter: terminalAdapter)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(terminalAdapter.title)
                            .font(.headline)
                        Text(terminalAdapter.bootError ?? terminalAdapter.status)
                            .font(.system(.caption, design: .monospaced))
                        Text("texture generation \(terminalAdapter.latestTextureGeneration())")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(12)
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Host Scaffold")
                        .font(.headline)
                    Text("DemoApp is the canonical Step 1 shell and presents embedded Ghostty surfaces through the local adapter contract.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(nsColor: .windowBackgroundColor))
            }
            .frame(minWidth: 380)
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.environment["ITE_GHOSTTY_SELFTEST"] == "1" {
                GhosttySurfaceSelfTestView()
            } else {
                HostShellView()
            }
        }
    }
}
