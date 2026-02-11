import XCTest
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

final class FilterSettingsDefaultsTests: XCTestCase {
    func testDefaultHideDraftsIsTrue() {
        XCTAssertTrue(FilterSettings().hideDrafts)
    }

    func testDefaultHideCIFailingIsFalse() {
        XCTAssertFalse(FilterSettings().hideCIFailing)
    }

    func testDefaultHideCIPendingIsFalse() {
        XCTAssertFalse(FilterSettings().hideCIPending)
    }

    func testDefaultHideConflictingIsFalse() {
        XCTAssertFalse(FilterSettings().hideConflicting)
    }

    func testDefaultHideApprovedIsFalse() {
        XCTAssertFalse(FilterSettings().hideApproved)
    }
}

// MARK: - FilterSettings Codable

final class FilterSettingsCodableTests: XCTestCase {
    func testCodableRoundTripDefaultValues() throws {
        let original = FilterSettings()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testCodableRoundTripCustomValues() throws {
        let original = FilterSettings(
            hideDrafts: false,
            hideCIFailing: true,
            hideCIPending: true,
            hideConflicting: true,
            hideApproved: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testDecodingEmptyJSONUsesDefaults() throws {
        let json = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: json)
        XCTAssertEqual(decoded, FilterSettings())
    }

    func testDecodingPartialJSONUsesDefaultsForMissingKeys() throws {
        let json = #"{"hideDrafts": false}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: json)
        XCTAssertFalse(decoded.hideDrafts)
        // All other properties should have their defaults
        XCTAssertFalse(decoded.hideCIFailing)
        XCTAssertFalse(decoded.hideCIPending)
        XCTAssertFalse(decoded.hideConflicting)
        XCTAssertFalse(decoded.hideApproved)
    }
}

// MARK: - Filter Predicate: Individual Filters

final class FilterPredicateTests: XCTestCase {
    // MARK: hideDrafts

    func testDefaultSettingsHideDraftPRs() {
        let prs = [
            PullRequest.fixture(number: 1, state: .draft),
            PullRequest.fixture(number: 2, state: .open),
        ]
        let result = FilterSettings().applyReviewFilters(to: prs)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.number, 2)
    }

    func testHideDraftsDisabledShowsDraftPRs() {
        let settings = FilterSettings(hideDrafts: false)
        let prs = [PullRequest.fixture(state: .draft)]
        let result = settings.applyReviewFilters(to: prs)
        XCTAssertEqual(result.count, 1)
    }

    func testHideDraftsDoesNotAffectOpenPRs() {
        let prs = [PullRequest.fixture(state: .open)]
        let result = FilterSettings().applyReviewFilters(to: prs)
        XCTAssertEqual(result.count, 1)
    }

    // MARK: hideCIFailing

    func testHideCIFailingFiltersFailingPRs() {
        let settings = FilterSettings(hideDrafts: false, hideCIFailing: true)
        let prs = [
            PullRequest.fixture(number: 1, ciStatus: .failure),
            PullRequest.fixture(number: 2, ciStatus: .success),
        ]
        let result = settings.applyReviewFilters(to: prs)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.number, 2)
    }

    func testHideCIFailingDoesNotAffectPendingOrSuccess() {
        let settings = FilterSettings(hideDrafts: false, hideCIFailing: true)
        let prs = [
            PullRequest.fixture(number: 1, ciStatus: .pending),
            PullRequest.fixture(number: 2, ciStatus: .success),
            PullRequest.fixture(number: 3, ciStatus: .unknown),
        ]
        let result = settings.applyReviewFilters(to: prs)
        XCTAssertEqual(result.count, 3)
    }

    // MARK: hideCIPending

    func testHideCIPendingFiltersPendingPRs() {
        let settings = FilterSettings(hideDrafts: false, hideCIPending: true)
        let prs = [
            PullRequest.fixture(number: 1, ciStatus: .pending),
            PullRequest.fixture(number: 2, ciStatus: .success),
        ]
        let result = settings.applyReviewFilters(to: prs)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.number, 2)
    }

    func testHideCIPendingDoesNotAffectFailureOrSuccess() {
        let settings = FilterSettings(hideDrafts: false, hideCIPending: true)
        let prs = [
            PullRequest.fixture(number: 1, ciStatus: .failure),
            PullRequest.fixture(number: 2, ciStatus: .success),
        ]
        let result = settings.applyReviewFilters(to: prs)
        XCTAssertEqual(result.count, 2)
    }

    // MARK: hideConflicting

    func testHideConflictingFiltersConflictingPRs() {
        let settings = FilterSettings(hideDrafts: false, hideConflicting: true)
        let prs = [
            PullRequest.fixture(number: 1, mergeable: .conflicting),
            PullRequest.fixture(number: 2, mergeable: .mergeable),
        ]
        let result = settings.applyReviewFilters(to: prs)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.number, 2)
    }

    func testHideConflictingDoesNotFilterUnknownMergeable() {
        let settings = FilterSettings(hideDrafts: false, hideConflicting: true)
        let prs = [PullRequest.fixture(mergeable: .unknown)]
        let result = settings.applyReviewFilters(to: prs)
        XCTAssertEqual(result.count, 1)
    }

    // MARK: hideApproved

    func testHideApprovedFiltersApprovedPRs() {
        let settings = FilterSettings(hideDrafts: false, hideApproved: true)
        let prs = [
            PullRequest.fixture(number: 1, reviewDecision: .approved),
            PullRequest.fixture(number: 2, reviewDecision: .reviewRequired),
        ]
        let result = settings.applyReviewFilters(to: prs)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.number, 2)
    }

    func testHideApprovedDoesNotAffectOtherDecisions() {
        let settings = FilterSettings(hideDrafts: false, hideApproved: true)
        let prs = [
            PullRequest.fixture(number: 1, reviewDecision: .reviewRequired),
            PullRequest.fixture(number: 2, reviewDecision: .changesRequested),
            PullRequest.fixture(number: 3, reviewDecision: .none),
        ]
        let result = settings.applyReviewFilters(to: prs)
        XCTAssertEqual(result.count, 3)
    }
}

// MARK: - Filter Predicate: Combinations & Edge Cases

final class FilterCombinationTests: XCTestCase {
    func testMultipleFiltersApplySimultaneously() {
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
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.number, 4)
    }

    func testAllFiltersEnabledOnlyShowsCleanOpenPRs() {
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
        XCTAssertEqual(result.count, 1)
    }

    func testNoFiltersEnabledReturnsAllPRs() {
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
        XCTAssertEqual(result.count, 4)
    }

    func testEmptyInputReturnsEmpty() {
        let settings = FilterSettings()
        let result = settings.applyReviewFilters(to: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testAllPRsFilteredReturnsEmpty() {
        let settings = FilterSettings(hideDrafts: true)
        let prs = [
            PullRequest.fixture(number: 1, state: .draft),
            PullRequest.fixture(number: 2, state: .draft),
        ]
        let result = settings.applyReviewFilters(to: prs)
        XCTAssertTrue(result.isEmpty)
    }

    func testFilterPreservesOriginalOrder() {
        let settings = FilterSettings(hideDrafts: true)
        let prs = [
            PullRequest.fixture(number: 5, state: .open),
            PullRequest.fixture(number: 3, state: .draft),
            PullRequest.fixture(number: 1, state: .open),
            PullRequest.fixture(number: 4, state: .draft),
            PullRequest.fixture(number: 2, state: .open),
        ]
        let result = settings.applyReviewFilters(to: prs)
        XCTAssertEqual(result.map(\.number), [5, 1, 2])
    }

    func testPRMatchingMultipleFiltersIsHiddenOnce() {
        // A draft PR with failing CI and conflicts — should be hidden, not double-counted
        let settings = FilterSettings(
            hideDrafts: true,
            hideCIFailing: true,
            hideConflicting: true
        )
        let pr = PullRequest.fixture(state: .draft, ciStatus: .failure, mergeable: .conflicting)
        let result = settings.applyReviewFilters(to: [pr])
        XCTAssertTrue(result.isEmpty)
    }
}

// MARK: - FilterSettings Persistence

final class FilterSettingsPersistenceTests: XCTestCase {
    private let testKey = "filter_settings_test"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: testKey)
        super.tearDown()
    }

    func testPersistAndReloadViaUserDefaults() throws {
        let original = FilterSettings(
            hideDrafts: false,
            hideCIFailing: true,
            hideCIPending: true,
            hideConflicting: true,
            hideApproved: true
        )

        // Persist
        let data = try JSONEncoder().encode(original)
        UserDefaults.standard.set(data, forKey: testKey)

        // Reload
        let loaded = UserDefaults.standard.data(forKey: testKey)!
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: loaded)

        XCTAssertEqual(decoded, original)
    }

    func testMissingKeyReturnsNilData() {
        let data = UserDefaults.standard.data(forKey: "nonexistent_filter_key")
        XCTAssertNil(data)
    }

    func testCorruptedDataFallsBackGracefully() {
        UserDefaults.standard.set(Data("not json".utf8), forKey: testKey)
        let data = UserDefaults.standard.data(forKey: testKey)!
        let decoded = try? JSONDecoder().decode(FilterSettings.self, from: data)
        XCTAssertNil(decoded)
        // Callers should fall back to FilterSettings() when decode returns nil
    }
}
