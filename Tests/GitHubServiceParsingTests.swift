import XCTest
@testable import PRStatusWatcher

final class GitHubServiceParsingTests: XCTestCase {
    let service = GitHubService()

    // MARK: - parsePRState

    func testParsePRStateMerged() {
        XCTAssertEqual(service.parsePRState(rawState: "MERGED", isDraft: false), .merged)
    }

    func testParsePRStateClosed() {
        XCTAssertEqual(service.parsePRState(rawState: "CLOSED", isDraft: false), .closed)
    }

    func testParsePRStateOpenNotDraft() {
        XCTAssertEqual(service.parsePRState(rawState: "OPEN", isDraft: false), .open)
    }

    func testParsePRStateOpenDraft() {
        XCTAssertEqual(service.parsePRState(rawState: "OPEN", isDraft: true), .draft)
    }

    func testParsePRStateUnknownDefault() {
        XCTAssertEqual(service.parsePRState(rawState: "SOMETHING", isDraft: false), .open)
    }

    // MARK: - parseReviewDecision

    func testParseReviewDecisionApproved() {
        let node: [String: Any] = ["reviewDecision": "APPROVED"]
        XCTAssertEqual(service.parseReviewDecision(from: node), .approved)
    }

    func testParseReviewDecisionChangesRequested() {
        let node: [String: Any] = ["reviewDecision": "CHANGES_REQUESTED"]
        XCTAssertEqual(service.parseReviewDecision(from: node), .changesRequested)
    }

    func testParseReviewDecisionReviewRequired() {
        let node: [String: Any] = ["reviewDecision": "REVIEW_REQUIRED"]
        XCTAssertEqual(service.parseReviewDecision(from: node), .reviewRequired)
    }

    func testParseReviewDecisionMissing() {
        let node: [String: Any] = [:]
        XCTAssertEqual(service.parseReviewDecision(from: node), .none)
    }

    // MARK: - parseMergeableState

    func testParseMergeableStateMergeable() {
        let node: [String: Any] = ["mergeable": "MERGEABLE"]
        XCTAssertEqual(service.parseMergeableState(from: node), .mergeable)
    }

    func testParseMergeableStateConflicting() {
        let node: [String: Any] = ["mergeable": "CONFLICTING"]
        XCTAssertEqual(service.parseMergeableState(from: node), .conflicting)
    }

    func testParseMergeableStateUnknown() {
        let node: [String: Any] = ["mergeable": "UNKNOWN"]
        XCTAssertEqual(service.parseMergeableState(from: node), .unknown)
    }

    // MARK: - tallyCheckContexts

    func testTallyAllPassing() {
        let contexts: [[String: Any]] = [
            ["status": "COMPLETED", "conclusion": "SUCCESS", "name": "build"],
            ["status": "COMPLETED", "conclusion": "SUCCESS", "name": "test"],
        ]
        let counts = service.tallyCheckContexts(contexts)
        XCTAssertEqual(counts.passed, 2)
        XCTAssertEqual(counts.failed, 0)
        XCTAssertEqual(counts.pending, 0)
    }

    func testTallyMixed() {
        let contexts: [[String: Any]] = [
            ["status": "COMPLETED", "conclusion": "SUCCESS", "name": "build"],
            ["status": "COMPLETED", "conclusion": "FAILURE", "name": "lint"],
            ["status": "IN_PROGRESS", "conclusion": "", "name": "test"],
        ]
        let counts = service.tallyCheckContexts(contexts)
        XCTAssertEqual(counts.passed, 1)
        XCTAssertEqual(counts.failed, 1)
        XCTAssertEqual(counts.pending, 1)
        XCTAssertEqual(counts.failedChecks.count, 1)
        XCTAssertEqual(counts.failedChecks.first?.name, "lint")
    }

    func testTallyEmpty() {
        let counts = service.tallyCheckContexts([])
        XCTAssertEqual(counts.passed, 0)
        XCTAssertEqual(counts.failed, 0)
        XCTAssertEqual(counts.pending, 0)
    }

    func testTallySkippedAndNeutral() {
        let contexts: [[String: Any]] = [
            ["status": "COMPLETED", "conclusion": "SKIPPED", "name": "optional"],
            ["status": "COMPLETED", "conclusion": "NEUTRAL", "name": "info"],
        ]
        let counts = service.tallyCheckContexts(contexts)
        XCTAssertEqual(counts.passed, 2)
        XCTAssertEqual(counts.failed, 0)
    }

    func testTallyEmptyNodes() {
        // StatusContext nodes that have no status/conclusion (empty)
        let contexts: [[String: Any]] = [
            [:],
            ["status": "", "conclusion": ""],
        ]
        let counts = service.tallyCheckContexts(contexts)
        XCTAssertEqual(counts.passed, 0)
        XCTAssertEqual(counts.failed, 0)
        XCTAssertEqual(counts.pending, 0)
    }

    // MARK: - resolveOverallStatus

    func testResolveOverallStatusEmpty() {
        let result = service.resolveOverallStatus(totalCount: 0, passed: 0, failed: 0, pending: 0, rollup: [:])
        XCTAssertEqual(result, .unknown)
    }

    func testResolveOverallStatusAllPassed() {
        let result = service.resolveOverallStatus(totalCount: 3, passed: 3, failed: 0, pending: 0, rollup: [:])
        XCTAssertEqual(result, .success)
    }

    func testResolveOverallStatusHasFailure() {
        let result = service.resolveOverallStatus(totalCount: 3, passed: 1, failed: 1, pending: 1, rollup: [:])
        XCTAssertEqual(result, .failure)
    }

    func testResolveOverallStatusHasPending() {
        let result = service.resolveOverallStatus(totalCount: 3, passed: 2, failed: 0, pending: 1, rollup: [:])
        XCTAssertEqual(result, .pending)
    }

    func testResolveOverallStatusFallbackToRollup() {
        let rollup: [String: Any] = ["state": "SUCCESS"]
        let result = service.resolveOverallStatus(totalCount: 2, passed: 0, failed: 0, pending: 0, rollup: rollup)
        XCTAssertEqual(result, .success)
    }

    func testResolveOverallStatusFallbackToRollupFailure() {
        let rollup: [String: Any] = ["state": "FAILURE"]
        let result = service.resolveOverallStatus(totalCount: 2, passed: 0, failed: 0, pending: 0, rollup: rollup)
        XCTAssertEqual(result, .failure)
    }

    // MARK: - parsePRNode

    func testParsePRNodeValid() {
        let node: [String: Any] = [
            "number": 42,
            "title": "Test PR",
            "url": "https://github.com/test/repo/pull/42",
            "repository": ["nameWithOwner": "test/repo"],
            "author": ["login": "testuser"],
            "isDraft": false,
            "state": "OPEN",
            "headRefOid": "abc1234567890",
            "headRefName": "feature-branch",
            "reviewDecision": "APPROVED",
            "mergeable": "MERGEABLE",
            "reviews": ["totalCount": 1],
        ]
        let pr = service.parsePRNode(node)
        XCTAssertNotNil(pr)
        XCTAssertEqual(pr?.number, 42)
        XCTAssertEqual(pr?.title, "Test PR")
        XCTAssertEqual(pr?.author, "testuser")
        XCTAssertEqual(pr?.state, .open)
        XCTAssertEqual(pr?.owner, "test")
        XCTAssertEqual(pr?.repo, "repo")
    }

    func testParsePRNodeMissingRequiredFields() {
        let node: [String: Any] = ["title": "Incomplete"]
        let pr = service.parsePRNode(node)
        XCTAssertNil(pr)
    }

    func testParsePRNodeDraft() {
        let node: [String: Any] = [
            "number": 1,
            "title": "Draft PR",
            "url": "https://github.com/test/repo/pull/1",
            "repository": ["nameWithOwner": "test/repo"],
            "isDraft": true,
            "state": "OPEN",
        ]
        let pr = service.parsePRNode(node)
        XCTAssertEqual(pr?.state, .draft)
    }
}
