import Foundation
import UserNotifications

// MARK: - Notification Dispatcher

/// Delivers local notifications via UNUserNotificationCenter.
/// Conforms to NotificationServiceProtocol for mock injection.
final class NotificationDispatcher: NotificationServiceProtocol {
    var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    func requestPermission() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in }
    }

    func send(title: String, body: String, url: URL?) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let url {
            content.userInfo = ["url": url.absoluteString]
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
