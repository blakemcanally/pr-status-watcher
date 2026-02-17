import Foundation

/// Abstraction over UNUserNotificationCenter for local notification delivery.
protocol NotificationServiceProtocol {
    var isAvailable: Bool { get }

    /// Whether the user has granted notification permission.
    /// Returns `false` until permission is explicitly granted.
    var permissionGranted: Bool { get }

    func requestPermission()
    func send(title: String, body: String, url: URL?)
}
