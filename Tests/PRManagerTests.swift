import Testing
import Foundation
@testable import PRStatusWatcher

@MainActor
@Suite struct PRManagerTests {
    let mockService: MockGitHubService
    let mockSettings: MockSettingsStore
    let mockNotifications: MockNotificationService

    init() {
        mockService = MockGitHubService()
        mockSettings = MockSettingsStore()
        mockNotifications = MockNotificationService()
    }

    private func makeManager() -> PRManager {
        PRManager(
            service: mockService,
            settingsStore: mockSettings,
            notificationService: mockNotifications
        )
    }

    // MARK: - Init

    @Test func initLoadsSettingsFromStore() {
        mockSettings.refreshInterval = 120
        mockSettings.collapsedRepos = ["a/b"]
        mockSettings.filterSettings = FilterSettings(hideDrafts: false)

        let manager = makeManager()

        #expect(manager.refreshInterval == 120)
        #expect(manager.collapsedRepos == ["a/b"])
        #expect(manager.filterSettings == FilterSettings(hideDrafts: false))
    }

    @Test func initRequestsNotificationPermission() {
        _ = makeManager()
        #expect(mockNotifications.permissionRequested)
    }

    // MARK: - refreshAll

    @Test func refreshAllSuccessUpdatesPullRequests() async {
        let prs = [PullRequest.fixture(number: 1), PullRequest.fixture(number: 2)]
        mockService.myPRsResult = .success(prs)
        mockService.reviewPRsResult = .success([])

        let manager = makeManager()
        manager.ghUser = "testuser"
        await manager.refreshAll()

        #expect(manager.pullRequests.count == 2)
        #expect(manager.lastError == nil)
        #expect(manager.hasCompletedInitialLoad)
    }

    @Test func refreshAllSuccessUpdatesReviewPRs() async {
        let reviewPRs = [PullRequest.fixture(number: 10)]
        mockService.myPRsResult = .success([])
        mockService.reviewPRsResult = .success(reviewPRs)

        let manager = makeManager()
        manager.ghUser = "testuser"
        await manager.refreshAll()

        #expect(manager.reviewPRs.count == 1)
    }

    @Test func refreshAllMyPRsFailureSetsLastError() async {
        mockService.myPRsResult = .failure(
            NSError(domain: "test", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Network timeout",
            ])
        )

        let manager = makeManager()
        manager.ghUser = "testuser"
        await manager.refreshAll()

        #expect(manager.lastError == "Network timeout")
    }

    @Test func refreshAllNilUserSetsAuthError() async {
        let manager = makeManager()
        manager.ghUser = nil
        await manager.refreshAll()

        #expect(manager.lastError == "gh not authenticated")
    }

    @Test func refreshAllFirstLoadSkipsNotifications() async {
        mockService.myPRsResult = .success([
            PullRequest.fixture(number: 1, ciStatus: .failure),
        ])

        let manager = makeManager()
        manager.ghUser = "testuser"
        await manager.refreshAll()

        #expect(mockNotifications.sentNotifications.isEmpty)
    }

    @Test func refreshAllSecondLoadSendsNotifications() async {
        let manager = makeManager()
        manager.ghUser = "testuser"

        // First load: pending
        mockService.myPRsResult = .success([
            PullRequest.fixture(number: 1, ciStatus: .pending),
        ])
        await manager.refreshAll()
        #expect(mockNotifications.sentNotifications.isEmpty)

        // Second load: failure
        mockService.myPRsResult = .success([
            PullRequest.fixture(number: 1, ciStatus: .failure),
        ])
        await manager.refreshAll()

        #expect(mockNotifications.sentNotifications.count == 1)
        #expect(mockNotifications.sentNotifications.first?.title == "CI Failed")
    }

    @Test func refreshAllReviewPRsFailureKeepsExistingData() async {
        let manager = makeManager()
        manager.ghUser = "testuser"

        // First load succeeds
        mockService.myPRsResult = .success([])
        mockService.reviewPRsResult = .success([PullRequest.fixture(number: 5)])
        await manager.refreshAll()
        #expect(manager.reviewPRs.count == 1)

        // Second load: review PRs fail
        mockService.reviewPRsResult = .failure(
            NSError(domain: "test", code: 1)
        )
        await manager.refreshAll()

        // Should keep existing review PRs
        #expect(manager.reviewPRs.count == 1)
    }

    // MARK: - Settings Persistence

    @Test func filterSettingsDidSetSavesToStore() {
        let manager = makeManager()
        // didSet fires once during init, so reset the count
        let initialCount = mockSettings.saveFilterSettingsCallCount
        manager.filterSettings = FilterSettings(hideDrafts: false, hideCIFailing: true)

        #expect(mockSettings.saveFilterSettingsCallCount == initialCount + 1)
        #expect(mockSettings.filterSettings == FilterSettings(hideDrafts: false, hideCIFailing: true))
    }

    @Test func refreshIntervalDidSetSavesToStore() {
        let manager = makeManager()
        let initialCount = mockSettings.saveRefreshIntervalCallCount
        manager.refreshInterval = 300

        #expect(mockSettings.saveRefreshIntervalCallCount == initialCount + 1)
        #expect(mockSettings.refreshInterval == 300)
    }

    @Test func collapsedReposDidSetSavesToStore() {
        let manager = makeManager()
        let initialCount = mockSettings.saveCollapsedReposCallCount
        manager.collapsedRepos = ["org/repo"]

        #expect(mockSettings.saveCollapsedReposCallCount == initialCount + 1)
        #expect(mockSettings.collapsedRepos == ["org/repo"])
    }

    // MARK: - Delegated Properties

    @Test func notificationsAvailableDelegatesToService() {
        mockNotifications.isAvailable = false
        let manager = makeManager()
        #expect(!manager.notificationsAvailable)
    }
}
