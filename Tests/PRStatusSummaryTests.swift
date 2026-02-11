import XCTest
@testable import PRStatusWatcher

final class PRStatusSummaryTests: XCTestCase {

    // MARK: - overallStatusIcon

    func testOverallStatusIconEmptyReturnsDefault() {
        XCTAssertEqual(PRStatusSummary.overallStatusIcon(for: []), "arrow.triangle.pull")
    }

    func testOverallStatusIconWithFailure() {
        let prs = [PullRequest.fixture(ciStatus: .failure)]
        XCTAssertEqual(PRStatusSummary.overallStatusIcon(for: prs), "xmark.circle.fill")
    }

    func testOverallStatusIconWithPending() {
        let prs = [PullRequest.fixture(ciStatus: .pending)]
        XCTAssertEqual(PRStatusSummary.overallStatusIcon(for: prs), "clock.circle.fill")
    }

    func testOverallStatusIconFailureTakesPriorityOverPending() {
        let prs = [
            PullRequest.fixture(number: 1, ciStatus: .failure),
            PullRequest.fixture(number: 2, ciStatus: .pending),
        ]
        XCTAssertEqual(PRStatusSummary.overallStatusIcon(for: prs), "xmark.circle.fill")
    }

    func testOverallStatusIconAllMergedOrClosed() {
        let prs = [
            PullRequest.fixture(number: 1, state: .merged, ciStatus: .success),
            PullRequest.fixture(number: 2, state: .closed, ciStatus: .unknown),
        ]
        XCTAssertEqual(PRStatusSummary.overallStatusIcon(for: prs), "checkmark.circle")
    }

    func testOverallStatusIconAllSuccess() {
        let prs = [PullRequest.fixture(ciStatus: .success)]
        XCTAssertEqual(PRStatusSummary.overallStatusIcon(for: prs), "checkmark.circle.fill")
    }

    // MARK: - hasFailure

    func testHasFailureTrue() {
        let prs = [PullRequest.fixture(ciStatus: .failure)]
        XCTAssertTrue(PRStatusSummary.hasFailure(in: prs))
    }

    func testHasFailureFalse() {
        let prs = [PullRequest.fixture(ciStatus: .success)]
        XCTAssertFalse(PRStatusSummary.hasFailure(in: prs))
    }

    func testHasFailureEmpty() {
        XCTAssertFalse(PRStatusSummary.hasFailure(in: []))
    }

    // MARK: - Counts

    func testOpenCountExcludesMergeQueue() {
        let prs = [
            PullRequest.fixture(number: 1, state: .open, isInMergeQueue: false),
            PullRequest.fixture(number: 2, state: .open, isInMergeQueue: true),
        ]
        XCTAssertEqual(PRStatusSummary.openCount(in: prs), 1)
    }

    func testOpenCountExcludesDrafts() {
        let prs = [
            PullRequest.fixture(number: 1, state: .open),
            PullRequest.fixture(number: 2, state: .draft),
        ]
        XCTAssertEqual(PRStatusSummary.openCount(in: prs), 1)
    }

    func testDraftCount() {
        let prs = [
            PullRequest.fixture(number: 1, state: .draft),
            PullRequest.fixture(number: 2, state: .draft),
            PullRequest.fixture(number: 3, state: .open),
        ]
        XCTAssertEqual(PRStatusSummary.draftCount(in: prs), 2)
    }

    func testQueuedCount() {
        let prs = [
            PullRequest.fixture(number: 1, isInMergeQueue: true),
            PullRequest.fixture(number: 2, isInMergeQueue: false),
        ]
        XCTAssertEqual(PRStatusSummary.queuedCount(in: prs), 1)
    }

    // MARK: - statusBarSummary

    func testStatusBarSummaryEmptyReturnsEmpty() {
        XCTAssertEqual(PRStatusSummary.statusBarSummary(for: []), "")
    }

    func testStatusBarSummarySingleOpen() {
        let prs = [PullRequest.fixture(state: .open)]
        XCTAssertEqual(PRStatusSummary.statusBarSummary(for: prs), "1")
    }

    func testStatusBarSummaryAllThreeCategories() {
        let prs = [
            PullRequest.fixture(number: 1, state: .draft),
            PullRequest.fixture(number: 2, state: .open),
            PullRequest.fixture(number: 3, state: .open),
            PullRequest.fixture(number: 4, state: .open, isInMergeQueue: true),
        ]
        XCTAssertEqual(PRStatusSummary.statusBarSummary(for: prs), "1·2·1")
    }

    func testStatusBarSummaryOmitsZeroCategories() {
        let prs = [
            PullRequest.fixture(number: 1, state: .open),
            PullRequest.fixture(number: 2, state: .open),
        ]
        // No drafts, no queued — just "2"
        XCTAssertEqual(PRStatusSummary.statusBarSummary(for: prs), "2")
    }

    func testStatusBarSummaryDraftOnly() {
        let prs = [PullRequest.fixture(state: .draft)]
        XCTAssertEqual(PRStatusSummary.statusBarSummary(for: prs), "1")
    }

    // MARK: - refreshIntervalLabel

    func testRefreshIntervalLabelSeconds() {
        XCTAssertEqual(PRStatusSummary.refreshIntervalLabel(for: 30), "30s")
    }

    func testRefreshIntervalLabelOneMinute() {
        XCTAssertEqual(PRStatusSummary.refreshIntervalLabel(for: 60), "1 min")
    }

    func testRefreshIntervalLabelMultipleMinutes() {
        XCTAssertEqual(PRStatusSummary.refreshIntervalLabel(for: 120), "2 min")
        XCTAssertEqual(PRStatusSummary.refreshIntervalLabel(for: 300), "5 min")
    }

    func testRefreshIntervalLabelNonEvenMinutes() {
        XCTAssertEqual(PRStatusSummary.refreshIntervalLabel(for: 90), "90s")
    }

    func testRefreshIntervalLabelBoundary59() {
        XCTAssertEqual(PRStatusSummary.refreshIntervalLabel(for: 59), "59s")
    }
}
