import SwiftUI

@main
struct WayinkSpikeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Wayink 定位 Spike")
                .font(.title2)
            Text("階段一：確認 CI 編譯管線可用")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
