import Testing
import Foundation
@testable import PRStatusWatcher

// MARK: - PullRequest Test Fixture

extension PullRequest {
    /// Create a PullRequest with sensible defaults for testing.
    /// Override only the properties relevant to each test case.
    static func fixture(
        owner: String = "test",
        repo: String = "repo",
        number: Int = 1,
        title: String = "Test PR",
        author: String = "testuser",
        state: PRState = .open,
        ciStatus: CIStatus = .success,
        isInMergeQueue: Bool = false,
        checksTotal: Int = 1,
        checksPassed: Int = 1,
        checksFailed: Int = 0,
        url: URL = URL(string: "https://github.com/test/repo/pull/1")!,
        headSHA: String = "abc1234",
        headRefName: String = "feature",
        lastFetched: Date = Date(),
        publishedAt: Date? = nil,
        reviewDecision: ReviewDecision = .reviewRequired,
        mergeable: MergeableState = .mergeable,
        queuePosition: Int? = nil,
        approvalCount: Int = 0,
        failedChecks: [CheckInfo] = [],
        checkResults: [CheckResult] = [],
        viewerHasApproved: Bool = false
    ) -> PullRequest {
        PullRequest(
            owner: owner,
            repo: repo,
            number: number,
            title: title,
            author: author,
            state: state,
            ciStatus: ciStatus,
            isInMergeQueue: isInMergeQueue,
            checksTotal: checksTotal,
            checksPassed: checksPassed,
            checksFailed: checksFailed,
            url: url,
            headSHA: headSHA,
            headRefName: headRefName,
            lastFetched: lastFetched,
            publishedAt: publishedAt,
            reviewDecision: reviewDecision,
            mergeable: mergeable,
            queuePosition: queuePosition,
            approvalCount: approvalCount,
            failedChecks: failedChecks,
            checkResults: checkResults,
            viewerHasApproved: viewerHasApproved
        )
    }
}

// MARK: - FilterSettings Default Values

@Suite struct FilterSettingsDefaultsTests {
    @Test func defaultHideDraftsIsTrue() {
        #expect(FilterSettings().hideDrafts)
    }

    @Test func defaultRequiredCheckNamesIsEmpty() {
        #expect(FilterSettings().requiredCheckNames.isEmpty)
    }

    @Test func defaultIgnoredCheckNamesIsEmpty() {
        #expect(FilterSettings().ignoredCheckNames.isEmpty)
    }

    @Test func defaultHideApprovedByMeIsFalse() {
        #expect(!FilterSettings().hideApprovedByMe)
    }

    @Test func defaultHideNotReadyIsFalse() {
        #expect(!FilterSettings().hideNotReady)
    }

    @Test func defaultIgnoredRepositoriesIsEmpty() {
        #expect(FilterSettings().ignoredRepositories.isEmpty)
    }

    @Test func defaultReviewSLAEnabledIsFalse() {
        #expect(!FilterSettings().reviewSLAEnabled)
    }

    @Test func defaultReviewSLAMinutesIs480() {
        #expect(FilterSettings().reviewSLAMinutes == 480)
    }
}

// MARK: - FilterSettings Codable

@Suite struct FilterSettingsCodableTests {
    @Test func codableRoundTripDefaultValues() throws {
        let original = FilterSettings()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: data)
        #expect(decoded == original)
    }

    @Test func codableRoundTripCustomValues() throws {
        let original = FilterSettings(hideDrafts: false, requiredCheckNames: ["build"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: data)
        #expect(decoded == original)
    }

    @Test func decodingEmptyJSONUsesDefaults() throws {
        let json = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: json)
        #expect(decoded == FilterSettings())
    }

    @Test func decodingPartialJSONUsesDefaultsForMissingKeys() throws {
        let json = #"{"hideDrafts": false}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: json)
        #expect(!decoded.hideDrafts)
        #expect(decoded.requiredCheckNames.isEmpty)
    }

    @Test func codableRoundTripWithRequiredCheckNames() throws {
        let original = FilterSettings(requiredCheckNames: ["build", "lint"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: data)
        #expect(decoded.requiredCheckNames == ["build", "lint"])
    }

    @Test func decodingWithoutRequiredCheckNamesDefaultsToEmpty() throws {
        let json = #"{"hideDrafts": true}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: json)
        #expect(decoded.requiredCheckNames.isEmpty)
    }

    @Test func codableRoundTripWithIgnoredCheckNames() throws {
        let original = FilterSettings(ignoredCheckNames: ["flaky-check", "graphite/stack"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: data)
        #expect(decoded.ignoredCheckNames == ["flaky-check", "graphite/stack"])
    }

    @Test func decodingWithoutIgnoredCheckNamesDefaultsToEmpty() throws {
        let json = #"{"hideDrafts": true, "requiredCheckNames": ["build"]}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: json)
        #expect(decoded.ignoredCheckNames.isEmpty)
        #expect(decoded.requiredCheckNames == ["build"])
    }

    @Test func codableRoundTripWithBothCheckLists() throws {
        let original = FilterSettings(
            requiredCheckNames: ["build"],
            ignoredCheckNames: ["flaky-lint"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: data)
        #expect(decoded.requiredCheckNames == ["build"])
        #expect(decoded.ignoredCheckNames == ["flaky-lint"])
    }

    @Test func codableRoundTripWithHideApprovedByMe() throws {
        let original = FilterSettings(hideApprovedByMe: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: data)
        #expect(decoded.hideApprovedByMe)
    }

    @Test func decodingWithoutHideApprovedByMeDefaultsToFalse() throws {
        let json = #"{"hideDrafts": true}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: json)
        #expect(!decoded.hideApprovedByMe)
    }

    @Test func codableRoundTripWithHideNotReady() throws {
        let original = FilterSettings(hideNotReady: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: data)
        #expect(decoded.hideNotReady)
    }

    @Test func decodingWithoutHideNotReadyDefaultsToFalse() throws {
        let json = #"{"hideDrafts": true}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: json)
        #expect(!decoded.hideNotReady)
    }

    @Test func codableRoundTripWithIgnoredRepositories() throws {
        let original = FilterSettings(ignoredRepositories: ["org/repo-a", "org/repo-b"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: data)
        #expect(decoded.ignoredRepositories == ["org/repo-a", "org/repo-b"])
    }

    @Test func decodingWithoutIgnoredRepositoriesDefaultsToEmpty() throws {
        let json = #"{"hideDrafts": true, "requiredCheckNames": ["build"]}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: json)
        #expect(decoded.ignoredRepositories.isEmpty)
        #expect(decoded.requiredCheckNames == ["build"])
    }

    @Test func codableRoundTripWithIgnoredReposAndIgnoredChecks() throws {
        let original = FilterSettings(
            ignoredCheckNames: ["flaky-lint"],
            ignoredRepositories: ["org/noisy-repo"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: data)
        #expect(decoded.ignoredCheckNames == ["flaky-lint"])
        #expect(decoded.ignoredRepositories == ["org/noisy-repo"])
    }

    @Test func decodingOldJSONWithoutSLAFieldsUsesDefaults() throws {
        let json = """
        {"hideDrafts": true, "hideApprovedByMe": false, "hideNotReady": false,
         "requiredCheckNames": [], "ignoredCheckNames": [], "ignoredRepositories": []}
        """
        let data = json.data(using: .utf8)!
        let settings = try JSONDecoder().decode(FilterSettings.self, from: data)
        #expect(!settings.reviewSLAEnabled)
        #expect(settings.reviewSLAMinutes == 480)
    }

    @Test func decodingJSONWithSLAFieldsPreservesValues() throws {
        let json = """
        {"hideDrafts": true, "hideApprovedByMe": false, "hideNotReady": false,
         "requiredCheckNames": [], "ignoredCheckNames": [], "ignoredRepositories": [],
         "reviewSLAEnabled": true, "reviewSLAMinutes": 240}
        """
        let data = json.data(using: .utf8)!
        let settings = try JSONDecoder().decode(FilterSettings.self, from: data)
        #expect(settings.reviewSLAEnabled)
        #expect(settings.reviewSLAMinutes == 240)
    }

    @Test func codableRoundTripWithSLASettings() throws {
        let original = FilterSettings(reviewSLAEnabled: true, reviewSLAMinutes: 240)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: data)
        #expect(decoded.reviewSLAEnabled)
        #expect(decoded.reviewSLAMinutes == 240)
    }
}

// MARK: - Filter Predicate: hideDrafts

@Suite struct FilterPredicateTests {
    @Test func defaultSettingsHideDraftPRs() {
        let prs = [
            PullRequest.fixture(number: 1, state: .draft),
            PullRequest.fixture(number: 2, state: .open),
        ]
        let result = FilterSettings().applyReviewFilters(to: prs)
        #expect(result.count == 1)
        #expect(result.first?.number == 2)
    }

    @Test func hideDraftsDisabledShowsDraftPRs() {
        let settings = FilterSettings(hideDrafts: false)
        let prs = [PullRequest.fixture(state: .draft)]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.count == 1)
    }

    @Test func hideDraftsDoesNotAffectOpenPRs() {
        let prs = [PullRequest.fixture(state: .open)]
        let result = FilterSettings().applyReviewFilters(to: prs)
        #expect(result.count == 1)
    }

    @Test func hideApprovedByMeFiltersApprovedPRs() {
        let settings = FilterSettings(hideDrafts: false, hideApprovedByMe: true)
        let prs = [
            PullRequest.fixture(number: 1, viewerHasApproved: true),
            PullRequest.fixture(number: 2, viewerHasApproved: false),
            PullRequest.fixture(number: 3, viewerHasApproved: true),
        ]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.count == 1)
        #expect(result.first?.number == 2)
    }

    @Test func hideApprovedByMeDisabledShowsAllPRs() {
        let settings = FilterSettings(hideDrafts: false, hideApprovedByMe: false)
        let prs = [
            PullRequest.fixture(number: 1, viewerHasApproved: true),
            PullRequest.fixture(number: 2, viewerHasApproved: false),
        ]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.count == 2)
    }

    @Test func hideApprovedByMeDoesNotAffectNonApprovedPRs() {
        let settings = FilterSettings(hideApprovedByMe: true)
        let prs = [PullRequest.fixture(viewerHasApproved: false)]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.count == 1)
    }

    @Test func hideNotReadyFiltersNotReadyPRs() {
        let settings = FilterSettings(hideDrafts: false, hideNotReady: true)
        let prs = [
            PullRequest.fixture(number: 1, state: .open, ciStatus: .success),
            PullRequest.fixture(number: 2, state: .open, ciStatus: .failure),
            PullRequest.fixture(number: 3, state: .open, ciStatus: .pending),
            PullRequest.fixture(number: 4, state: .draft),
        ]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.count == 1)
        #expect(result.first?.number == 1)
    }

    @Test func hideNotReadyDisabledShowsAllPRs() {
        let settings = FilterSettings(hideDrafts: false, hideNotReady: false)
        let prs = [
            PullRequest.fixture(number: 1, state: .open, ciStatus: .failure),
            PullRequest.fixture(number: 2, state: .open, ciStatus: .success),
        ]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.count == 2)
    }

    @Test func hideNotReadyKeepsReadyPRs() {
        let settings = FilterSettings(hideDrafts: false, hideNotReady: true)
        let prs = [
            PullRequest.fixture(number: 1, state: .open, ciStatus: .success, mergeable: .mergeable),
        ]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.count == 1)
    }

    @Test func hideNotReadyFiltersConflictingPRs() {
        let settings = FilterSettings(hideDrafts: false, hideNotReady: true)
        let prs = [
            PullRequest.fixture(number: 1, state: .open, ciStatus: .success, mergeable: .conflicting),
        ]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.isEmpty)
    }

    @Test func hideNotReadyRespectsRequiredCheckNames() {
        let settings = FilterSettings(
            hideDrafts: false,
            hideNotReady: true,
            requiredCheckNames: ["build"]
        )
        let prs = [
            // CI overall success, but required check "build" is failing → not ready
            PullRequest.fixture(
                number: 1,
                state: .open,
                ciStatus: .success,
                checkResults: [
                    PullRequest.CheckResult(name: "build", status: .failed, detailsUrl: nil),
                    PullRequest.CheckResult(name: "lint", status: .passed, detailsUrl: nil),
                ]
            ),
            // Required check "build" is passing → ready
            PullRequest.fixture(
                number: 2,
                state: .open,
                ciStatus: .success,
                checkResults: [
                    PullRequest.CheckResult(name: "build", status: .passed, detailsUrl: nil),
                    PullRequest.CheckResult(name: "lint", status: .passed, detailsUrl: nil),
                ]
            ),
        ]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.count == 1)
        #expect(result.first?.number == 2)
    }

    @Test func hideNotReadyRespectsIgnoredCheckNames() {
        let settings = FilterSettings(
            hideDrafts: false,
            hideNotReady: true,
            ignoredCheckNames: ["flaky-check"]
        )
        let prs = [
            // CI failing overall, but only the ignored check fails → effective status is success → ready
            PullRequest.fixture(
                number: 1,
                state: .open,
                ciStatus: .failure,
                checkResults: [
                    PullRequest.CheckResult(name: "build", status: .passed, detailsUrl: nil),
                    PullRequest.CheckResult(name: "flaky-check", status: .failed, detailsUrl: nil),
                ]
            ),
            // Non-ignored check failing → not ready
            PullRequest.fixture(
                number: 2,
                state: .open,
                ciStatus: .failure,
                checkResults: [
                    PullRequest.CheckResult(name: "build", status: .failed, detailsUrl: nil),
                    PullRequest.CheckResult(name: "flaky-check", status: .failed, detailsUrl: nil),
                ]
            ),
        ]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.count == 1)
        #expect(result.first?.number == 1)
    }

    @Test func hideNotReadyWithUnknownCIStatusIsReady() {
        let settings = FilterSettings(hideDrafts: false, hideNotReady: true)
        let prs = [
            PullRequest.fixture(number: 1, state: .open, ciStatus: .unknown, checksTotal: 0, checksPassed: 0, checkResults: []),
        ]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.count == 1)
    }
}

// MARK: - Filter Edge Cases

@Suite struct FilterCombinationTests {
    @Test func hideDraftsLeavesNonDraftPRs() {
        let settings = FilterSettings(hideDrafts: true)
        let prs = [
            PullRequest.fixture(number: 1, state: .draft),
            PullRequest.fixture(number: 2, ciStatus: .failure),
            PullRequest.fixture(number: 3, mergeable: .conflicting),
            PullRequest.fixture(number: 4, state: .open, ciStatus: .success),
        ]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.count == 3)
        #expect(result.map(\.number) == [2, 3, 4])
    }

    @Test func noFiltersEnabledReturnsAllPRs() {
        let settings = FilterSettings(hideDrafts: false)
        let prs = [
            PullRequest.fixture(number: 1, state: .draft),
            PullRequest.fixture(number: 2, ciStatus: .failure),
            PullRequest.fixture(number: 3, mergeable: .conflicting),
            PullRequest.fixture(number: 4, reviewDecision: .approved),
        ]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.count == 4)
    }

    @Test func emptyInputReturnsEmpty() {
        let settings = FilterSettings()
        let result = settings.applyReviewFilters(to: [])
        #expect(result.isEmpty)
    }

    @Test func allPRsFilteredReturnsEmpty() {
        let settings = FilterSettings(hideDrafts: true)
        let prs = [
            PullRequest.fixture(number: 1, state: .draft),
            PullRequest.fixture(number: 2, state: .draft),
        ]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.isEmpty)
    }

    @Test func hideDraftsAndHideApprovedCombined() {
        let settings = FilterSettings(hideDrafts: true, hideApprovedByMe: true)
        let prs = [
            PullRequest.fixture(number: 1, state: .draft, viewerHasApproved: false),
            PullRequest.fixture(number: 2, state: .open, viewerHasApproved: true),
            PullRequest.fixture(number: 3, state: .open, viewerHasApproved: false),
            PullRequest.fixture(number: 4, state: .draft, viewerHasApproved: true),
        ]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.count == 1)
        #expect(result.first?.number == 3)
    }

    @Test func allPRsApprovedAndHiddenReturnsEmpty() {
        let settings = FilterSettings(hideDrafts: false, hideApprovedByMe: true)
        let prs = [
            PullRequest.fixture(number: 1, viewerHasApproved: true),
            PullRequest.fixture(number: 2, viewerHasApproved: true),
        ]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.isEmpty)
    }

    @Test func hideNotReadyAndHideApprovedCombined() {
        let settings = FilterSettings(hideDrafts: false, hideApprovedByMe: true, hideNotReady: true)
        let prs = [
            PullRequest.fixture(number: 1, state: .open, ciStatus: .success, viewerHasApproved: true),
            PullRequest.fixture(number: 2, state: .open, ciStatus: .failure, viewerHasApproved: false),
            PullRequest.fixture(number: 3, state: .open, ciStatus: .success, viewerHasApproved: false),
        ]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.count == 1)
        #expect(result.first?.number == 3)
    }

    @Test func allThreeFiltersHideEverything() {
        let settings = FilterSettings(hideDrafts: true, hideApprovedByMe: true, hideNotReady: true)
        let prs = [
            PullRequest.fixture(number: 1, state: .draft),
            PullRequest.fixture(number: 2, state: .open, ciStatus: .success, viewerHasApproved: true),
            PullRequest.fixture(number: 3, state: .open, ciStatus: .failure),
        ]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.isEmpty)
    }

    @Test func filterPreservesOriginalOrder() {
        let settings = FilterSettings(hideDrafts: true)
        let prs = [
            PullRequest.fixture(number: 5, state: .open),
            PullRequest.fixture(number: 3, state: .draft),
            PullRequest.fixture(number: 1, state: .open),
            PullRequest.fixture(number: 4, state: .draft),
            PullRequest.fixture(number: 2, state: .open),
        ]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.map(\.number) == [5, 1, 2])
    }
}

// MARK: - FilterSettings Persistence

@Suite final class FilterSettingsPersistenceTests {
    private let testKey: String

    init() {
        testKey = "filter_settings_test_\(UUID().uuidString)"
    }

    deinit {
        UserDefaults.standard.removeObject(forKey: testKey)
    }

    @Test func persistAndReloadViaUserDefaults() throws {
        let original = FilterSettings(hideDrafts: false, requiredCheckNames: ["build"])
        let data = try JSONEncoder().encode(original)
        UserDefaults.standard.set(data, forKey: testKey)

        let loaded = try #require(UserDefaults.standard.data(forKey: testKey))
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: loaded)
        #expect(decoded == original)
    }

    @Test func persistAndReloadIgnoredCheckNamesViaUserDefaults() throws {
        let original = FilterSettings(ignoredCheckNames: ["flaky-check"])
        let data = try JSONEncoder().encode(original)
        UserDefaults.standard.set(data, forKey: testKey)

        let loaded = try #require(UserDefaults.standard.data(forKey: testKey))
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: loaded)
        #expect(decoded.ignoredCheckNames == ["flaky-check"])
    }

    @Test func persistAndReloadHideNotReadyViaUserDefaults() throws {
        let original = FilterSettings(hideNotReady: true)
        let data = try JSONEncoder().encode(original)
        UserDefaults.standard.set(data, forKey: testKey)

        let loaded = try #require(UserDefaults.standard.data(forKey: testKey))
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: loaded)
        #expect(decoded.hideNotReady)
    }

    @Test func persistAndReloadHideApprovedByMeViaUserDefaults() throws {
        let original = FilterSettings(hideApprovedByMe: true)
        let data = try JSONEncoder().encode(original)
        UserDefaults.standard.set(data, forKey: testKey)

        let loaded = try #require(UserDefaults.standard.data(forKey: testKey))
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: loaded)
        #expect(decoded.hideApprovedByMe)
    }

    @Test func persistAndReloadIgnoredRepositoriesViaUserDefaults() throws {
        let original = FilterSettings(ignoredRepositories: ["org/repo-a"])
        let data = try JSONEncoder().encode(original)
        UserDefaults.standard.set(data, forKey: testKey)

        let loaded = try #require(UserDefaults.standard.data(forKey: testKey))
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: loaded)
        #expect(decoded.ignoredRepositories == ["org/repo-a"])
    }

    @Test func missingKeyReturnsNilData() {
        let data = UserDefaults.standard.data(forKey: "nonexistent_filter_key_\(UUID().uuidString)")
        #expect(data == nil)
    }

    @Test func corruptedDataFallsBackGracefully() {
        UserDefaults.standard.set(Data("not json".utf8), forKey: testKey)
        let data = UserDefaults.standard.data(forKey: testKey)!
        let decoded = try? JSONDecoder().decode(FilterSettings.self, from: data)
        #expect(decoded == nil)
    }
}
