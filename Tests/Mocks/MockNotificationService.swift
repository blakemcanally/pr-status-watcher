import Foundation
@testable import PRStatusWatcher

final class MockNotificationService: NotificationServiceProtocol {
    var isAvailable: Bool = true
    var sentNotifications: [(title: String, body: String, url: URL?)] = []
    var permissionRequested = false

    func requestPermission() { permissionRequested = true }
    func send(title: String, body: String, url: URL?) {
        sentNotifications.append((title, body, url))
    }
}
