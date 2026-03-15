import SwiftUI

struct ContentView: View {
    @StateObject private var runtime = EngineRuntime()

    var body: some View {
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
        .frame(minWidth: 900, minHeight: 600)
    }
}

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
