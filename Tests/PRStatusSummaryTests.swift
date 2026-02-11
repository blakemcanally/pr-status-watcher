import Testing
@testable import PRStatusWatcher

@Suite struct PRStatusSummaryTests {

    // MARK: - overallStatusIcon

    @Test func overallStatusIconEmptyReturnsDefault() {
        #expect(PRStatusSummary.overallStatusIcon(for: []) == "arrow.triangle.pull")
    }

    @Test func overallStatusIconWithFailure() {
        let prs = [PullRequest.fixture(ciStatus: .failure)]
        #expect(PRStatusSummary.overallStatusIcon(for: prs) == "xmark.circle.fill")
    }

    @Test func overallStatusIconWithPending() {
        let prs = [PullRequest.fixture(ciStatus: .pending)]
        #expect(PRStatusSummary.overallStatusIcon(for: prs) == "clock.circle.fill")
    }

    @Test func overallStatusIconFailureTakesPriorityOverPending() {
        let prs = [
            PullRequest.fixture(number: 1, ciStatus: .failure),
            PullRequest.fixture(number: 2, ciStatus: .pending),
        ]
        #expect(PRStatusSummary.overallStatusIcon(for: prs) == "xmark.circle.fill")
    }

    @Test func overallStatusIconAllMergedOrClosed() {
        let prs = [
            PullRequest.fixture(number: 1, state: .merged, ciStatus: .success),
            PullRequest.fixture(number: 2, state: .closed, ciStatus: .unknown),
        ]
        #expect(PRStatusSummary.overallStatusIcon(for: prs) == "checkmark.circle")
    }

    @Test func overallStatusIconAllSuccess() {
        let prs = [PullRequest.fixture(ciStatus: .success)]
        #expect(PRStatusSummary.overallStatusIcon(for: prs) == "checkmark.circle.fill")
    }

    // MARK: - hasFailure

    @Test func hasFailureTrue() {
        let prs = [PullRequest.fixture(ciStatus: .failure)]
        #expect(PRStatusSummary.hasFailure(in: prs))
    }

    @Test func hasFailureFalse() {
        let prs = [PullRequest.fixture(ciStatus: .success)]
        #expect(!PRStatusSummary.hasFailure(in: prs))
    }

    @Test func hasFailureEmpty() {
        #expect(!PRStatusSummary.hasFailure(in: []))
    }

    // MARK: - Counts

    @Test func openCountExcludesMergeQueue() {
        let prs = [
            PullRequest.fixture(number: 1, state: .open, isInMergeQueue: false),
            PullRequest.fixture(number: 2, state: .open, isInMergeQueue: true),
        ]
        #expect(PRStatusSummary.openCount(in: prs) == 1)
    }

    @Test func openCountExcludesDrafts() {
        let prs = [
            PullRequest.fixture(number: 1, state: .open),
            PullRequest.fixture(number: 2, state: .draft),
        ]
        #expect(PRStatusSummary.openCount(in: prs) == 1)
    }

    @Test func draftCount() {
        let prs = [
            PullRequest.fixture(number: 1, state: .draft),
            PullRequest.fixture(number: 2, state: .draft),
            PullRequest.fixture(number: 3, state: .open),
        ]
        #expect(PRStatusSummary.draftCount(in: prs) == 2)
    }

    @Test func queuedCount() {
        let prs = [
            PullRequest.fixture(number: 1, isInMergeQueue: true),
            PullRequest.fixture(number: 2, isInMergeQueue: false),
        ]
        #expect(PRStatusSummary.queuedCount(in: prs) == 1)
    }

    // MARK: - statusBarSummary

    @Test func statusBarSummaryEmptyReturnsEmpty() {
        #expect(PRStatusSummary.statusBarSummary(for: []) == "")
    }

    @Test func statusBarSummarySingleOpen() {
        let prs = [PullRequest.fixture(state: .open)]
        #expect(PRStatusSummary.statusBarSummary(for: prs) == "1")
    }

    @Test func statusBarSummaryAllThreeCategories() {
        let prs = [
            PullRequest.fixture(number: 1, state: .draft),
            PullRequest.fixture(number: 2, state: .open),
            PullRequest.fixture(number: 3, state: .open),
            PullRequest.fixture(number: 4, state: .open, isInMergeQueue: true),
        ]
        #expect(PRStatusSummary.statusBarSummary(for: prs) == "1·2·1")
    }

    @Test func statusBarSummaryOmitsZeroCategories() {
        let prs = [
            PullRequest.fixture(number: 1, state: .open),
            PullRequest.fixture(number: 2, state: .open),
        ]
        #expect(PRStatusSummary.statusBarSummary(for: prs) == "2")
    }

    @Test func statusBarSummaryDraftOnly() {
        let prs = [PullRequest.fixture(state: .draft)]
        #expect(PRStatusSummary.statusBarSummary(for: prs) == "1")
    }

    // MARK: - refreshIntervalLabel

    @Test(arguments: [
        (30, "30s"),
        (59, "59s"),
        (60, "1 min"),
        (90, "90s"),
        (120, "2 min"),
        (300, "5 min"),
    ])
    func refreshIntervalLabel(seconds: Int, expected: String) {
        #expect(PRStatusSummary.refreshIntervalLabel(for: seconds) == expected)
    }
}
