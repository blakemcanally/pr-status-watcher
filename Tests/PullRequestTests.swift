import XCTest
import SwiftUI
@testable import PRStatusWatcher

final class PullRequestSortPriorityTests: XCTestCase {
    func testOpenPriorityIsZero() {
        XCTAssertEqual(PullRequest.fixture(state: .open).sortPriority, 0)
    }

    func testDraftPriorityIsOne() {
        XCTAssertEqual(PullRequest.fixture(state: .draft).sortPriority, 1)
    }

    func testQueuedPriorityIsTwo() {
        XCTAssertEqual(PullRequest.fixture(state: .open, isInMergeQueue: true).sortPriority, 2)
    }

    func testMergedPriorityIsThree() {
        XCTAssertEqual(PullRequest.fixture(state: .merged).sortPriority, 3)
    }

    func testClosedPriorityIsThree() {
        XCTAssertEqual(PullRequest.fixture(state: .closed).sortPriority, 3)
    }

    func testQueuedTakesPriorityOverOpenState() {
        // A PR that is state: .open but isInMergeQueue should sort as queued (2), not open (0)
        let pr = PullRequest.fixture(state: .open, isInMergeQueue: true)
        XCTAssertEqual(pr.sortPriority, 2)
    }
}

final class PullRequestReviewSortPriorityTests: XCTestCase {
    func testReviewRequiredIsZero() {
        XCTAssertEqual(
            PullRequest.fixture(reviewDecision: .reviewRequired).reviewSortPriority, 0
        )
    }

    func testNoneIsZero() {
        XCTAssertEqual(
            PullRequest.fixture(reviewDecision: .none).reviewSortPriority, 0
        )
    }

    func testChangesRequestedIsOne() {
        XCTAssertEqual(
            PullRequest.fixture(reviewDecision: .changesRequested).reviewSortPriority, 1
        )
    }

    func testApprovedIsTwo() {
        XCTAssertEqual(
            PullRequest.fixture(reviewDecision: .approved).reviewSortPriority, 2
        )
    }
}

final class PullRequestStatusColorTests: XCTestCase {
    func testMergedIsPurple() {
        XCTAssertEqual(PullRequest.fixture(state: .merged).statusColor, .purple)
    }

    func testClosedIsGray() {
        XCTAssertEqual(PullRequest.fixture(state: .closed).statusColor, .gray)
    }

    func testDraftIsGray() {
        XCTAssertEqual(PullRequest.fixture(state: .draft).statusColor, .gray)
    }

    func testOpenQueuedIsPurple() {
        XCTAssertEqual(
            PullRequest.fixture(state: .open, isInMergeQueue: true).statusColor, .purple
        )
    }

    func testOpenSuccessIsGreen() {
        XCTAssertEqual(
            PullRequest.fixture(state: .open, ciStatus: .success).statusColor, .green
        )
    }

    func testOpenFailureIsRed() {
        XCTAssertEqual(
            PullRequest.fixture(state: .open, ciStatus: .failure).statusColor, .red
        )
    }

    func testOpenPendingIsOrange() {
        XCTAssertEqual(
            PullRequest.fixture(state: .open, ciStatus: .pending).statusColor, .orange
        )
    }

    func testOpenUnknownIsGray() {
        XCTAssertEqual(
            PullRequest.fixture(state: .open, ciStatus: .unknown).statusColor, .gray
        )
    }
}

final class PullRequestIdentityTests: XCTestCase {
    func testIdFormat() {
        let pr = PullRequest.fixture(owner: "myorg", repo: "myrepo", number: 42)
        XCTAssertEqual(pr.id, "myorg/myrepo#42")
    }

    func testRepoFullName() {
        let pr = PullRequest.fixture(owner: "acme", repo: "widget")
        XCTAssertEqual(pr.repoFullName, "acme/widget")
    }

    func testDisplayNumber() {
        let pr = PullRequest.fixture(number: 99)
        XCTAssertEqual(pr.displayNumber, "#99")
    }
}
