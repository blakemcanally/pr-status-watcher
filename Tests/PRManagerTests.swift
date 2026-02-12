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

        #expect(manager.lastError == Strings.Error.ghNotAuthenticated)
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
        #expect(mockNotifications.sentNotifications.first?.title == Strings.Notification.ciFailed)
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

    // MARK: - Review PR Error Surfacing

    @Test func reviewPRFailureSetsLastError() async {
        mockService.myPRsResult = .success([])
        mockService.reviewPRsResult = .failure(
            NSError(domain: "test", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "API rate limit exceeded",
            ])
        )

        let manager = makeManager()
        manager.ghUser = "testuser"
        await manager.refreshAll()

        #expect(manager.lastError?.contains("Reviews:") == true)
        #expect(manager.lastError?.contains("API rate limit exceeded") == true)
    }

    @Test func bothFailuresCombinesErrors() async throws {
        mockService.myPRsResult = .failure(
            NSError(domain: "test", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Network timeout",
            ])
        )
        mockService.reviewPRsResult = .failure(
            NSError(domain: "test", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "API rate limit exceeded",
            ])
        )

        let manager = makeManager()
        manager.ghUser = "testuser"
        await manager.refreshAll()

        let error = try #require(manager.lastError)
        #expect(error.contains("Network timeout"))
        #expect(error.contains("Reviews:"))
        #expect(error.contains("API rate limit exceeded"))
        #expect(error.contains("|"))
    }

    @Test func reviewSuccessClearsReviewError() async {
        let manager = makeManager()
        manager.ghUser = "testuser"

        // First refresh: review PRs fail
        mockService.myPRsResult = .success([])
        mockService.reviewPRsResult = .failure(
            NSError(domain: "test", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "API error",
            ])
        )
        await manager.refreshAll()
        #expect(manager.lastError != nil)

        // Second refresh: both succeed → error should clear
        mockService.myPRsResult = .success([])
        mockService.reviewPRsResult = .success([])
        await manager.refreshAll()
        #expect(manager.lastError == nil)
    }

    // MARK: - Timeout Error Propagation

    @Test func timeoutErrorSurfacedToUser() async {
        mockService.myPRsResult = .failure(GHError.timeout)
        mockService.reviewPRsResult = .success([])

        let manager = makeManager()
        manager.ghUser = "testuser"
        await manager.refreshAll()

        #expect(manager.lastError?.contains("timed out") == true)
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

    // MARK: - toggleRepoCollapsed

    @Test func toggleRepoCollapsedAddsRepo() {
        let manager = makeManager()
        #expect(!manager.collapsedRepos.contains("org/repo"))

        manager.toggleRepoCollapsed("org/repo")

        #expect(manager.collapsedRepos.contains("org/repo"))
    }

    @Test func toggleRepoCollapsedRemovesRepo() {
        let manager = makeManager()
        manager.collapsedRepos = ["org/repo"]

        manager.toggleRepoCollapsed("org/repo")

        #expect(!manager.collapsedRepos.contains("org/repo"))
    }

    @Test func toggleRepoCollapsedSavesToStore() {
        let manager = makeManager()
        let initialCount = mockSettings.saveCollapsedReposCallCount

        manager.toggleRepoCollapsed("org/repo")

        #expect(mockSettings.saveCollapsedReposCallCount == initialCount + 1)
    }

    // MARK: - Error Type Propagation

    @Test func graphQLApiErrorSurfaced() async {
        mockService.myPRsResult = .failure(GHError.apiError("API rate limit exceeded"))
        mockService.reviewPRsResult = .success([])

        let manager = makeManager()
        manager.ghUser = "testuser"
        await manager.refreshAll()

        #expect(manager.lastError?.contains("rate limit exceeded") == true)
    }

    @Test func processLaunchFailedSurfaced() async {
        mockService.myPRsResult = .failure(GHError.processLaunchFailed("Permission denied"))
        mockService.reviewPRsResult = .success([])

        let manager = makeManager()
        manager.ghUser = "testuser"
        await manager.refreshAll()

        #expect(manager.lastError?.contains("Failed to launch") == true)
    }

    @Test func invalidJSONErrorSurfaced() async {
        mockService.myPRsResult = .failure(GHError.invalidJSON)
        mockService.reviewPRsResult = .success([])

        let manager = makeManager()
        manager.ghUser = "testuser"
        await manager.refreshAll()

        #expect(manager.lastError?.contains("Invalid response") == true)
    }

    // MARK: - Large Result Sets

    @Test func refreshAllHandlesLargeResultSet() async {
        let prs = (1...150).map { PullRequest.fixture(number: $0) }
        mockService.myPRsResult = .success(prs)
        mockService.reviewPRsResult = .success([])

        let manager = makeManager()
        manager.ghUser = "testuser"
        await manager.refreshAll()

        #expect(manager.pullRequests.count == 150)
        #expect(manager.lastError == nil)
    }

    // MARK: - Menu Bar Image Caching

    @Test func menuBarImageUpdatesOnPullRequestsChange() async {
        let manager = makeManager()
        manager.ghUser = "testuser"

        // Initial state: no PRs
        let initialImage = manager.menuBarImage

        // Add a failing PR
        mockService.myPRsResult = .success([
            PullRequest.fixture(number: 1, ciStatus: .failure),
        ])
        mockService.reviewPRsResult = .success([])
        await manager.refreshAll()

        // Image should have changed (now has failure badge)
        #expect(manager.menuBarImage !== initialImage)
    }

    @Test func menuBarImageStableWhenStatusUnchanged() async {
        let manager = makeManager()
        manager.ghUser = "testuser"

        // First refresh with success PRs
        mockService.myPRsResult = .success([
            PullRequest.fixture(number: 1, ciStatus: .success),
        ])
        mockService.reviewPRsResult = .success([])
        await manager.refreshAll()

        let imageAfterFirst = manager.menuBarImage

        // Second refresh with same status
        await manager.refreshAll()

        // Image should be the same object (not regenerated)
        #expect(manager.menuBarImage === imageAfterFirst)
    }
}
