import SwiftUI

@main
struct UsageBarApp: App {
    var body: some Scene {
        MenuBarExtra("UsageBar", systemImage: "gauge.with.dots.needle.33percent") {
            Text("UsageBar")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
