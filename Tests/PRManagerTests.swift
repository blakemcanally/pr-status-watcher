import XCTest
@testable import PRStatusWatcher

@MainActor
final class PRManagerTests: XCTestCase {
    private var mockService: MockGitHubService!
    private var mockSettings: MockSettingsStore!
    private var mockNotifications: MockNotificationService!

    override func setUp() {
        super.setUp()
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

    func testInitLoadsSettingsFromStore() {
        mockSettings.refreshInterval = 120
        mockSettings.collapsedRepos = ["a/b"]
        mockSettings.filterSettings = FilterSettings(hideDrafts: false)

        let manager = makeManager()

        XCTAssertEqual(manager.refreshInterval, 120)
        XCTAssertEqual(manager.collapsedRepos, ["a/b"])
        XCTAssertEqual(manager.filterSettings, FilterSettings(hideDrafts: false))
    }

    func testInitRequestsNotificationPermission() {
        _ = makeManager()
        XCTAssertTrue(mockNotifications.permissionRequested)
    }

    // MARK: - refreshAll

    func testRefreshAllSuccessUpdatesPullRequests() async {
        let prs = [PullRequest.fixture(number: 1), PullRequest.fixture(number: 2)]
        mockService.myPRsResult = .success(prs)
        mockService.reviewPRsResult = .success([])

        let manager = makeManager()
        manager.ghUser = "testuser"
        await manager.refreshAll()

        XCTAssertEqual(manager.pullRequests.count, 2)
        XCTAssertNil(manager.lastError)
        XCTAssertTrue(manager.hasCompletedInitialLoad)
    }

    func testRefreshAllSuccessUpdatesReviewPRs() async {
        let reviewPRs = [PullRequest.fixture(number: 10)]
        mockService.myPRsResult = .success([])
        mockService.reviewPRsResult = .success(reviewPRs)

        let manager = makeManager()
        manager.ghUser = "testuser"
        await manager.refreshAll()

        XCTAssertEqual(manager.reviewPRs.count, 1)
    }

    func testRefreshAllMyPRsFailureSetsLastError() async {
        mockService.myPRsResult = .failure(
            NSError(domain: "test", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Network timeout"
            ])
        )

        let manager = makeManager()
        manager.ghUser = "testuser"
        await manager.refreshAll()

        XCTAssertEqual(manager.lastError, "Network timeout")
    }

    func testRefreshAllNilUserSetsAuthError() async {
        let manager = makeManager()
        manager.ghUser = nil
        await manager.refreshAll()

        XCTAssertEqual(manager.lastError, "gh not authenticated")
    }

    func testRefreshAllFirstLoadSkipsNotifications() async {
        mockService.myPRsResult = .success([
            PullRequest.fixture(number: 1, ciStatus: .failure)
        ])

        let manager = makeManager()
        manager.ghUser = "testuser"
        await manager.refreshAll()

        XCTAssertTrue(mockNotifications.sentNotifications.isEmpty)
    }

    func testRefreshAllSecondLoadSendsNotifications() async {
        let manager = makeManager()
        manager.ghUser = "testuser"

        // First load: pending
        mockService.myPRsResult = .success([
            PullRequest.fixture(number: 1, ciStatus: .pending)
        ])
        await manager.refreshAll()
        XCTAssertTrue(mockNotifications.sentNotifications.isEmpty)

        // Second load: failure
        mockService.myPRsResult = .success([
            PullRequest.fixture(number: 1, ciStatus: .failure)
        ])
        await manager.refreshAll()

        XCTAssertEqual(mockNotifications.sentNotifications.count, 1)
        XCTAssertEqual(mockNotifications.sentNotifications.first?.title, "CI Failed")
    }

    func testRefreshAllReviewPRsFailureKeepsExistingData() async {
        let manager = makeManager()
        manager.ghUser = "testuser"

        // First load succeeds
        mockService.myPRsResult = .success([])
        mockService.reviewPRsResult = .success([PullRequest.fixture(number: 5)])
        await manager.refreshAll()
        XCTAssertEqual(manager.reviewPRs.count, 1)

        // Second load: review PRs fail
        mockService.reviewPRsResult = .failure(
            NSError(domain: "test", code: 1)
        )
        await manager.refreshAll()

        // Should keep existing review PRs
        XCTAssertEqual(manager.reviewPRs.count, 1)
    }

    // MARK: - Settings Persistence

    func testFilterSettingsDidSetSavesToStore() {
        let manager = makeManager()
        // didSet fires once during init, so reset the count
        let initialCount = mockSettings.saveFilterSettingsCallCount
        manager.filterSettings = FilterSettings(hideDrafts: false, hideCIFailing: true)

        XCTAssertEqual(mockSettings.saveFilterSettingsCallCount, initialCount + 1)
        XCTAssertEqual(mockSettings.filterSettings, FilterSettings(hideDrafts: false, hideCIFailing: true))
    }

    func testRefreshIntervalDidSetSavesToStore() {
        let manager = makeManager()
        let initialCount = mockSettings.saveRefreshIntervalCallCount
        manager.refreshInterval = 300

        XCTAssertEqual(mockSettings.saveRefreshIntervalCallCount, initialCount + 1)
        XCTAssertEqual(mockSettings.refreshInterval, 300)
    }

    func testCollapsedReposDidSetSavesToStore() {
        let manager = makeManager()
        let initialCount = mockSettings.saveCollapsedReposCallCount
        manager.collapsedRepos = ["org/repo"]

        XCTAssertEqual(mockSettings.saveCollapsedReposCallCount, initialCount + 1)
        XCTAssertEqual(mockSettings.collapsedRepos, ["org/repo"])
    }

    // MARK: - Delegated Properties

    func testNotificationsAvailableDelegatesToService() {
        mockNotifications.isAvailable = false
        let manager = makeManager()
        XCTAssertFalse(manager.notificationsAvailable)
    }
}
