import SwiftUI

// MARK: - App Delegate (hide from Dock, menu-bar only)

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}

// MARK: - App Entry Point

@main
struct PRStatusWatcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var manager = PRManager()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(manager)
        } label: {
            HStack(spacing: 2) {
                Image(nsImage: manager.menuBarImage)
                Text(manager.statusBarSummary)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
        }
        .menuBarExtraStyle(.window)
    }
}
