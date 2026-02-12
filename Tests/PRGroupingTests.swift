import Testing
@testable import PRStatusWatcher

@Suite struct PRGroupingTests {

    // MARK: - Basic Grouping

    @Test func emptyInputReturnsEmpty() {
        let result = PRGrouping.grouped(prs: [], isReviews: false)
        #expect(result.isEmpty)
    }

    @Test func singleRepoGroupedCorrectly() {
        let prs = [
            PullRequest.fixture(number: 1),
            PullRequest.fixture(number: 2),
        ]
        let result = PRGrouping.grouped(prs: prs, isReviews: false)
        #expect(result.count == 1)
        #expect(result.first?.repo == "test/repo")
        #expect(result.first?.prs.count == 2)
    }

    @Test func multipleReposSortedAlphabetically() {
        let prs = [
            PullRequest.fixture(owner: "z-org", repo: "z-repo", number: 1),
            PullRequest.fixture(owner: "a-org", repo: "a-repo", number: 2),
            PullRequest.fixture(owner: "m-org", repo: "m-repo", number: 3),
        ]
        let result = PRGrouping.grouped(prs: prs, isReviews: false)
        #expect(result.map(\.repo) == ["a-org/a-repo", "m-org/m-repo", "z-org/z-repo"])
    }

    // MARK: - My PRs Sort Order

    @Test func myPRsSortedByStateThenNumber() {
        let prs = [
            PullRequest.fixture(number: 3, state: .draft),
            PullRequest.fixture(number: 1, state: .open),
            PullRequest.fixture(number: 2, state: .open),
        ]
        let result = PRGrouping.grouped(prs: prs, isReviews: false)
        let numbers = result.first?.prs.map(\.number)
        // Open (priority 0) before Draft (priority 1), then by number
        #expect(numbers == [1, 2, 3])
    }

    @Test func myPRsQueuedAfterDraft() {
        let prs = [
            PullRequest.fixture(number: 1, state: .open, isInMergeQueue: true),
            PullRequest.fixture(number: 2, state: .draft),
            PullRequest.fixture(number: 3, state: .open),
        ]
        let result = PRGrouping.grouped(prs: prs, isReviews: false)
        let numbers = result.first?.prs.map(\.number)
        // Open=0, Draft=1, Queued=2
        #expect(numbers == [3, 2, 1])
    }

    // MARK: - Reviews Sort Order

    @Test func reviewsSortedByReviewPriorityFirst() {
        let prs = [
            PullRequest.fixture(number: 1, reviewDecision: .approved),
            PullRequest.fixture(number: 2, reviewDecision: .reviewRequired),
            PullRequest.fixture(number: 3, reviewDecision: .changesRequested),
        ]
        let result = PRGrouping.grouped(prs: prs, isReviews: true)
        let numbers = result.first?.prs.map(\.number)
        // reviewRequired=0, changesRequested=1, approved=2
        #expect(numbers == [2, 3, 1])
    }

    @Test func reviewsSortedByApprovalCountWithinSamePriority() {
        let prs = [
            PullRequest.fixture(number: 1, reviewDecision: .reviewRequired, approvalCount: 2),
            PullRequest.fixture(number: 2, reviewDecision: .reviewRequired, approvalCount: 0),
            PullRequest.fixture(number: 3, reviewDecision: .reviewRequired, approvalCount: 1),
        ]
        let result = PRGrouping.grouped(prs: prs, isReviews: true)
        let numbers = result.first?.prs.map(\.number)
        // Same review priority → sorted by approval count ascending
        #expect(numbers == [2, 3, 1])
    }

    @Test func reviewsFallsThroughToStatePriority() {
        let prs = [
            PullRequest.fixture(number: 1, state: .draft, reviewDecision: .reviewRequired, approvalCount: 0),
            PullRequest.fixture(number: 2, state: .open, reviewDecision: .reviewRequired, approvalCount: 0),
        ]
        let result = PRGrouping.grouped(prs: prs, isReviews: true)
        let numbers = result.first?.prs.map(\.number)
        // Same review priority, same approval count → sort by state priority (open=0 < draft=1)
        #expect(numbers == [2, 1])
    }

    // MARK: - Edge Cases

    @Test func sameStateAndNumberPreservesStableOrder() {
        // Two PRs from different repos with same state/number
        let prs = [
            PullRequest.fixture(owner: "b-org", repo: "b-repo", number: 1),
            PullRequest.fixture(owner: "a-org", repo: "a-repo", number: 1),
        ]
        let result = PRGrouping.grouped(prs: prs, isReviews: false)
        #expect(result.count == 2)
        #expect(result[0].repo == "a-org/a-repo")
        #expect(result[1].repo == "b-org/b-repo")
    }
}
