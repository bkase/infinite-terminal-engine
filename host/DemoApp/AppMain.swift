import SwiftUI

struct ContentView: View {
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
                CanvasView(runtime: runtime)
                Text(runtime.statsSummary)
                    .font(.system(.caption, design: .monospaced))
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
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

            ZStack(alignment: .topLeading) {
                GhosttyTerminalPane(adapter: terminalAdapter)
                VStack(alignment: .leading, spacing: 6) {
                    Text(terminalAdapter.title)
                        .font(.headline)
                    Text(terminalAdapter.bootError ?? terminalAdapter.status)
                        .font(.system(.caption, design: .monospaced))
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(12)
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
                ContentView()
            }
        }
    }
}
