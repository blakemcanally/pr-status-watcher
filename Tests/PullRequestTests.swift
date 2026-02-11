import Testing
import SwiftUI
@testable import PRStatusWatcher

@Suite struct PullRequestSortPriorityTests {
    @Test(arguments: [
        (PullRequest.PRState.open, false, 0),
        (PullRequest.PRState.draft, false, 1),
        (PullRequest.PRState.open, true, 2),    // isInMergeQueue
        (PullRequest.PRState.merged, false, 3),
        (PullRequest.PRState.closed, false, 3),
    ])
    func sortPriority(state: PullRequest.PRState, isInMergeQueue: Bool, expected: Int) {
        #expect(PullRequest.fixture(state: state, isInMergeQueue: isInMergeQueue).sortPriority == expected)
    }
}

@Suite struct PullRequestReviewSortPriorityTests {
    @Test(arguments: [
        (PullRequest.ReviewDecision.reviewRequired, 0),
        (PullRequest.ReviewDecision.none, 0),
        (PullRequest.ReviewDecision.changesRequested, 1),
        (PullRequest.ReviewDecision.approved, 2),
    ])
    func reviewSortPriority(decision: PullRequest.ReviewDecision, expected: Int) {
        #expect(PullRequest.fixture(reviewDecision: decision).reviewSortPriority == expected)
    }
}

@Suite struct PullRequestStatusColorTests {
    @Test(arguments: [
        (PullRequest.PRState.merged, PullRequest.CIStatus.success, false, Color.purple),
        (PullRequest.PRState.closed, PullRequest.CIStatus.success, false, Color.gray),
        (PullRequest.PRState.draft, PullRequest.CIStatus.success, false, Color.gray),
        (PullRequest.PRState.open, PullRequest.CIStatus.success, true, Color.purple),   // queued
        (PullRequest.PRState.open, PullRequest.CIStatus.success, false, Color.green),
        (PullRequest.PRState.open, PullRequest.CIStatus.failure, false, Color.red),
        (PullRequest.PRState.open, PullRequest.CIStatus.pending, false, Color.orange),
        (PullRequest.PRState.open, PullRequest.CIStatus.unknown, false, Color.gray),
    ])
    func statusColor(state: PullRequest.PRState, ciStatus: PullRequest.CIStatus, isInMergeQueue: Bool, expected: Color) {
        #expect(
            PullRequest.fixture(state: state, ciStatus: ciStatus, isInMergeQueue: isInMergeQueue)
                .statusColor == expected
        )
    }
}

@Suite struct PullRequestIdentityTests {
    @Test func idFormat() {
        let pr = PullRequest.fixture(owner: "myorg", repo: "myrepo", number: 42)
        #expect(pr.id == "myorg/myrepo#42")
    }

    @Test func repoFullName() {
        let pr = PullRequest.fixture(owner: "acme", repo: "widget")
        #expect(pr.repoFullName == "acme/widget")
    }

    @Test func displayNumber() {
        let pr = PullRequest.fixture(number: 99)
        #expect(pr.displayNumber == "#99")
    }
}
