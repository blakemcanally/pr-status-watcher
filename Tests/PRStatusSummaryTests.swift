import Testing
import Foundation
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

    @Test func statusBarSummaryBothEmptyReturnsEmpty() {
        #expect(PRStatusSummary.statusBarSummary(for: [], reviewPRs: []) == "")
    }

    @Test func statusBarSummaryMyPRsOnlyShowsBothCounts() {
        let myPRs = [
            PullRequest.fixture(number: 1, state: .open),
            PullRequest.fixture(number: 2, state: .draft),
            PullRequest.fixture(number: 3, state: .open),
        ]
        #expect(PRStatusSummary.statusBarSummary(for: myPRs, reviewPRs: []) == "3 | 0")
    }

    @Test func statusBarSummaryReviewsOnlyShowsBothCounts() {
        let reviews = [
            PullRequest.fixture(number: 10, state: .open),
            PullRequest.fixture(number: 11, state: .open),
        ]
        #expect(PRStatusSummary.statusBarSummary(for: [], reviewPRs: reviews) == "0 | 2")
    }

    @Test func statusBarSummaryBothTabsPopulated() {
        let myPRs = [
            PullRequest.fixture(number: 1, state: .open),
            PullRequest.fixture(number: 2, state: .draft),
            PullRequest.fixture(number: 3, state: .open, isInMergeQueue: true),
            PullRequest.fixture(number: 4, state: .open),
        ]
        let reviews = [
            PullRequest.fixture(number: 10, state: .open),
            PullRequest.fixture(number: 11, state: .open),
        ]
        #expect(PRStatusSummary.statusBarSummary(for: myPRs, reviewPRs: reviews) == "4 | 2")
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

    // MARK: - countdownLabel

    @Test func countdownLabelNilWhenPast() {
        let now = Date.now
        let target = now.addingTimeInterval(-5)
        #expect(PRStatusSummary.countdownLabel(until: target, now: now) == nil)
    }

    @Test func countdownLabelNilWhenUnderTenSeconds() {
        let now = Date.now
        #expect(PRStatusSummary.countdownLabel(until: now.addingTimeInterval(0), now: now) == nil)
        #expect(PRStatusSummary.countdownLabel(until: now.addingTimeInterval(5), now: now) == nil)
        #expect(PRStatusSummary.countdownLabel(until: now.addingTimeInterval(9), now: now) == nil)
    }

    @Test(arguments: [
        (10, "~10s"),
        (14, "~10s"),
        (15, "~20s"),
        (20, "~20s"),
        (24, "~20s"),
        (25, "~30s"),
        (35, "~40s"),
        (50, "~50s"),
        (54, "~50s"),
        (55, "~1 min"),
        (59, "~1 min"),
    ])
    func countdownLabelSeconds(remaining: Int, expected: String) {
        let now = Date.now
        let target = now.addingTimeInterval(TimeInterval(remaining))
        #expect(PRStatusSummary.countdownLabel(until: target, now: now) == expected)
    }

    @Test(arguments: [
        (60, "~1 min"),
        (89, "~1 min"),
        (90, "~2 min"),
        (119, "~2 min"),
        (120, "~2 min"),
        (149, "~2 min"),
        (150, "~3 min"),
        (179, "~3 min"),
        (300, "~5 min"),
    ])
    func countdownLabelMinutes(remaining: Int, expected: String) {
        let now = Date.now
        let target = now.addingTimeInterval(TimeInterval(remaining))
        #expect(PRStatusSummary.countdownLabel(until: target, now: now) == expected)
    }
}
