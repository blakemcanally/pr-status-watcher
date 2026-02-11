import Foundation

/// Abstraction over UNUserNotificationCenter for local notification delivery.
protocol NotificationServiceProtocol {
    var isAvailable: Bool { get }
    func requestPermission()
    func send(title: String, body: String, url: URL?)
}
