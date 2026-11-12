import SwiftUI

@main
struct UsageBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var accounts = UsageAccounts()

    var body: some Scene {
        MenuBarExtra {
            UsagePopover(accounts: accounts)
        } label: {
            AccountMenuBarLabel(accounts: accounts)
        }
        .menuBarExtraStyle(.window)

        Settings {
            AccountSettingsView(accounts: accounts)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // O .app tem LSUIElement no Info.plist; via `swift run` não há Info.plist, então vale o código.
        NSApp.setActivationPolicy(.accessory)
    }
}
