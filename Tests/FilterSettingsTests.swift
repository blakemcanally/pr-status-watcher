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
        failedChecks: [CheckInfo] = [],
        checkResults: [CheckResult] = []
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
            failedChecks: failedChecks,
            checkResults: checkResults
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
