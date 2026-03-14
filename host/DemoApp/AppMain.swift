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
