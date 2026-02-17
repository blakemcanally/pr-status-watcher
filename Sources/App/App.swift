import SwiftUI
import UserNotifications
import os

private let logger = Logger(subsystem: "PRStatusWatcher", category: "App")

// MARK: - App Delegate (hide from Dock, menu-bar only)

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("applicationDidFinishLaunching: setting activation policy to .accessory")
        NSApplication.shared.setActivationPolicy(.accessory)
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
            logger.info("applicationDidFinishLaunching: notification delegate registered")
        } else {
            logger.warning("applicationDidFinishLaunching: no bundle identifier — notifications disabled")
        }
    }

    /// Open the PR URL when the user clicks a notification.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let urlString = response.notification.request.content
            .userInfo[AppConstants.Notification.urlInfoKey] as? String,
           let url = URL(string: urlString) {
            logger.info("notification tapped: opening \(urlString, privacy: .public)")
            NSWorkspace.shared.open(url)
        } else {
            logger.warning("notification tapped: no valid URL in userInfo")
        }
        completionHandler()
    }
}

// MARK: - App Entry Point

@main
struct PRStatusWatcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var manager = PRManager(
        service: GitHubService(),
        settingsStore: SettingsStore(defaults: .standard),
        notificationService: NotificationDispatcher()
    )

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(manager)
        } label: {
            HStack(spacing: 2) {
                Image(nsImage: manager.menuBarImage)
                Text(manager.statusBarSummary)
                    .font(.system(size: AppConstants.Layout.MenuBar.statusFontSize, weight: .medium, design: .monospaced))
            }
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView()
                .environmentObject(manager)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
