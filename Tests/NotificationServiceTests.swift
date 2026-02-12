import Testing
import Foundation
@testable import PRStatusWatcher

@Suite struct NotificationServiceProtocolTests {

    // MARK: - Mock behavior

    @Test func mockDefaultsToPermissionGranted() {
        let mock = MockNotificationService()
        #expect(mock.permissionGranted)
    }

    @Test func mockTracksPermissionRequest() {
        let mock = MockNotificationService()
        #expect(!mock.permissionRequested)
        mock.requestPermission()
        #expect(mock.permissionRequested)
    }

    @Test func mockRecordsSentNotifications() {
        let mock = MockNotificationService()
        let url = URL(string: "https://github.com/test/repo/pull/1")!
        mock.send(title: "CI Failed", body: "test/repo #1: Fix the thing", url: url)

        #expect(mock.sentNotifications.count == 1)
        #expect(mock.sentNotifications.first?.title == "CI Failed")
        #expect(mock.sentNotifications.first?.url == url)
    }

    @Test func mockPermissionDeniedSimulation() {
        let mock = MockNotificationService()
        mock.permissionGranted = false
        #expect(!mock.permissionGranted)
    }

    // MARK: - Concrete dispatcher observable state

    @Test func dispatcherDefaultsToPermissionNotGranted() {
        let dispatcher = NotificationDispatcher()
        #expect(!dispatcher.permissionGranted)
    }
}
