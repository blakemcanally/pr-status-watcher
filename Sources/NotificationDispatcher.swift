import Foundation
import UserNotifications
import os

private let logger = Logger(subsystem: "PRStatusWatcher", category: "NotificationDispatcher")

// MARK: - Notification Dispatcher

/// Delivers local notifications via UNUserNotificationCenter.
/// Conforms to NotificationServiceProtocol for mock injection.
final class NotificationDispatcher: NotificationServiceProtocol {
    private(set) var permissionGranted: Bool = false

    var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    func requestPermission() {
        guard isAvailable else {
            logger.info("requestPermission: skipped — no bundle identifier")
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { [weak self] granted, error in
            self?.permissionGranted = granted
            if let error {
                logger.error("requestPermission: failed: \(error.localizedDescription, privacy: .public)")
            } else {
                logger.info("requestPermission: granted=\(granted)")
            }
        }
    }

    func send(title: String, body: String, url: URL?) {
        guard isAvailable else {
            logger.debug("send: skipped — no bundle identifier")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let url {
            content.userInfo = [AppConstants.Notification.urlInfoKey: url.absoluteString]
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.error("send: delivery failed: \(error.localizedDescription, privacy: .public)")
            } else {
                logger.debug("send: delivered '\(title, privacy: .public)'")
            }
        }
    }
}
