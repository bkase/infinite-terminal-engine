import AppKit
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Infinite Terminal Engine")
                .font(.title2)
            Text("Host shell scaffold")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 480)
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
