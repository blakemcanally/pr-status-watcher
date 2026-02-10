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
            HStack(spacing: 3) {
                Image(nsImage: manager.menuBarImage)
                if !manager.pullRequests.isEmpty {
                    Text("\(manager.pullRequests.count)")
                        .font(.caption2)
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
