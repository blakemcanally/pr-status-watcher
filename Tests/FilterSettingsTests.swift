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
        reviewDecision: ReviewDecision = .reviewRequired,
        mergeable: MergeableState = .mergeable,
        queuePosition: Int? = nil,
        approvalCount: Int = 0,
        failedChecks: [CheckInfo] = []
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
            reviewDecision: reviewDecision,
            mergeable: mergeable,
            queuePosition: queuePosition,
            approvalCount: approvalCount,
            failedChecks: failedChecks
        )
    }
}

// MARK: - FilterSettings Default Values

@Suite struct FilterSettingsDefaultsTests {
    @Test func defaultHideDraftsIsTrue() {
        #expect(FilterSettings().hideDrafts)
    }

    @Test func defaultHideCIFailingIsFalse() {
        #expect(!FilterSettings().hideCIFailing)
    }

    @Test func defaultHideCIPendingIsFalse() {
        #expect(!FilterSettings().hideCIPending)
    }

    @Test func defaultHideConflictingIsFalse() {
        #expect(!FilterSettings().hideConflicting)
    }

    @Test func defaultHideApprovedIsFalse() {
        #expect(!FilterSettings().hideApproved)
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
        let original = FilterSettings(
            hideDrafts: false,
            hideCIFailing: true,
            hideCIPending: true,
            hideConflicting: true,
            hideApproved: true
        )
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
        // All other properties should have their defaults
        #expect(!decoded.hideCIFailing)
        #expect(!decoded.hideCIPending)
        #expect(!decoded.hideConflicting)
        #expect(!decoded.hideApproved)
    }
}

// MARK: - Filter Predicate: Individual Filters

@Suite struct FilterPredicateTests {
    // MARK: hideDrafts

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

    // MARK: hideCIFailing

    @Test func hideCIFailingFiltersFailingPRs() {
        let settings = FilterSettings(hideDrafts: false, hideCIFailing: true)
        let prs = [
            PullRequest.fixture(number: 1, ciStatus: .failure),
            PullRequest.fixture(number: 2, ciStatus: .success),
        ]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.count == 1)
        #expect(result.first?.number == 2)
    }

    @Test func hideCIFailingDoesNotAffectPendingOrSuccess() {
        let settings = FilterSettings(hideDrafts: false, hideCIFailing: true)
        let prs = [
            PullRequest.fixture(number: 1, ciStatus: .pending),
            PullRequest.fixture(number: 2, ciStatus: .success),
            PullRequest.fixture(number: 3, ciStatus: .unknown),
        ]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.count == 3)
    }

    // MARK: hideCIPending

    @Test func hideCIPendingFiltersPendingPRs() {
        let settings = FilterSettings(hideDrafts: false, hideCIPending: true)
        let prs = [
            PullRequest.fixture(number: 1, ciStatus: .pending),
            PullRequest.fixture(number: 2, ciStatus: .success),
        ]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.count == 1)
        #expect(result.first?.number == 2)
    }

    @Test func hideCIPendingDoesNotAffectFailureOrSuccess() {
        let settings = FilterSettings(hideDrafts: false, hideCIPending: true)
        let prs = [
            PullRequest.fixture(number: 1, ciStatus: .failure),
            PullRequest.fixture(number: 2, ciStatus: .success),
        ]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.count == 2)
    }

    // MARK: hideConflicting

    @Test func hideConflictingFiltersConflictingPRs() {
        let settings = FilterSettings(hideDrafts: false, hideConflicting: true)
        let prs = [
            PullRequest.fixture(number: 1, mergeable: .conflicting),
            PullRequest.fixture(number: 2, mergeable: .mergeable),
        ]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.count == 1)
        #expect(result.first?.number == 2)
    }

    @Test func hideConflictingDoesNotFilterUnknownMergeable() {
        let settings = FilterSettings(hideDrafts: false, hideConflicting: true)
        let prs = [PullRequest.fixture(mergeable: .unknown)]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.count == 1)
    }

    // MARK: hideApproved

    @Test func hideApprovedFiltersApprovedPRs() {
        let settings = FilterSettings(hideDrafts: false, hideApproved: true)
        let prs = [
            PullRequest.fixture(number: 1, reviewDecision: .approved),
            PullRequest.fixture(number: 2, reviewDecision: .reviewRequired),
        ]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.count == 1)
        #expect(result.first?.number == 2)
    }

    @Test func hideApprovedDoesNotAffectOtherDecisions() {
        let settings = FilterSettings(hideDrafts: false, hideApproved: true)
        let prs = [
            PullRequest.fixture(number: 1, reviewDecision: .reviewRequired),
            PullRequest.fixture(number: 2, reviewDecision: .changesRequested),
            PullRequest.fixture(number: 3, reviewDecision: .none),
        ]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.count == 3)
    }
}

// MARK: - Filter Predicate: Combinations & Edge Cases

@Suite struct FilterCombinationTests {
    @Test func multipleFiltersApplySimultaneously() {
        let settings = FilterSettings(
            hideDrafts: true,
            hideCIFailing: true,
            hideConflicting: true
        )
        let prs = [
            PullRequest.fixture(number: 1, state: .draft),                           // hidden: draft
            PullRequest.fixture(number: 2, ciStatus: .failure),                       // hidden: CI failing
            PullRequest.fixture(number: 3, mergeable: .conflicting),                  // hidden: conflicts
            PullRequest.fixture(number: 4, state: .open, ciStatus: .success),         // visible
        ]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.count == 1)
        #expect(result.first?.number == 4)
    }

    @Test func allFiltersEnabledOnlyShowsCleanOpenPRs() {
        let settings = FilterSettings(
            hideDrafts: true,
            hideCIFailing: true,
            hideCIPending: true,
            hideConflicting: true,
            hideApproved: true
        )
        // This PR is: open, CI success, mergeable, review required — passes all filters
        let clean = PullRequest.fixture(
            number: 1,
            state: .open,
            ciStatus: .success,
            reviewDecision: .reviewRequired,
            mergeable: .mergeable
        )
        let result = settings.applyReviewFilters(to: [clean])
        #expect(result.count == 1)
    }

    @Test func noFiltersEnabledReturnsAllPRs() {
        let settings = FilterSettings(
            hideDrafts: false,
            hideCIFailing: false,
            hideCIPending: false,
            hideConflicting: false,
            hideApproved: false
        )
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

    @Test func prMatchingMultipleFiltersIsHiddenOnce() {
        // A draft PR with failing CI and conflicts — should be hidden, not double-counted
        let settings = FilterSettings(
            hideDrafts: true,
            hideCIFailing: true,
            hideConflicting: true
        )
        let pr = PullRequest.fixture(state: .draft, ciStatus: .failure, mergeable: .conflicting)
        let result = settings.applyReviewFilters(to: [pr])
        #expect(result.isEmpty)
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
        let original = FilterSettings(
            hideDrafts: false,
            hideCIFailing: true,
            hideCIPending: true,
            hideConflicting: true,
            hideApproved: true
        )
        let data = try JSONEncoder().encode(original)
        UserDefaults.standard.set(data, forKey: testKey)

        let loaded = try #require(UserDefaults.standard.data(forKey: testKey))
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: loaded)
        #expect(decoded == original)
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
