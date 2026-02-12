import Testing
@testable import PRStatusWatcher

@Suite struct GitHubServiceParsingTests {
    let service = GitHubService()

    // MARK: - parsePRState

    @Test(arguments: [
        ("MERGED", false, PullRequest.PRState.merged),
        ("CLOSED", false, PullRequest.PRState.closed),
        ("OPEN", false, PullRequest.PRState.open),
        ("OPEN", true, PullRequest.PRState.draft),
        ("SOMETHING", false, PullRequest.PRState.open),
    ])
    func parsePRState(rawState: String, isDraft: Bool, expected: PullRequest.PRState) {
        #expect(service.parsePRState(rawState: rawState, isDraft: isDraft) == expected)
    }

    // MARK: - parseReviewDecision

    @Test func parseReviewDecisionApproved() {
        let node: [String: Any] = ["reviewDecision": "APPROVED"]
        #expect(service.parseReviewDecision(from: node) == .approved)
    }

    @Test func parseReviewDecisionChangesRequested() {
        let node: [String: Any] = ["reviewDecision": "CHANGES_REQUESTED"]
        #expect(service.parseReviewDecision(from: node) == .changesRequested)
    }

    @Test func parseReviewDecisionReviewRequired() {
        let node: [String: Any] = ["reviewDecision": "REVIEW_REQUIRED"]
        #expect(service.parseReviewDecision(from: node) == .reviewRequired)
    }

    @Test func parseReviewDecisionMissing() {
        let node: [String: Any] = [:]
        #expect(service.parseReviewDecision(from: node) == .none)
    }

    // MARK: - parseMergeableState

    @Test func parseMergeableStateMergeable() {
        let node: [String: Any] = ["mergeable": "MERGEABLE"]
        #expect(service.parseMergeableState(from: node) == .mergeable)
    }

    @Test func parseMergeableStateConflicting() {
        let node: [String: Any] = ["mergeable": "CONFLICTING"]
        #expect(service.parseMergeableState(from: node) == .conflicting)
    }

    @Test func parseMergeableStateUnknown() {
        let node: [String: Any] = ["mergeable": "UNKNOWN"]
        #expect(service.parseMergeableState(from: node) == .unknown)
    }

    // MARK: - tallyCheckContexts

    @Test func tallyAllPassing() {
        let contexts: [[String: Any]] = [
            ["status": "COMPLETED", "conclusion": "SUCCESS", "name": "build"],
            ["status": "COMPLETED", "conclusion": "SUCCESS", "name": "test"],
        ]
        let counts = service.tallyCheckContexts(contexts)
        #expect(counts.passed == 2)
        #expect(counts.failed == 0)
        #expect(counts.pending == 0)
    }

    @Test func tallyMixed() {
        let contexts: [[String: Any]] = [
            ["status": "COMPLETED", "conclusion": "SUCCESS", "name": "build"],
            ["status": "COMPLETED", "conclusion": "FAILURE", "name": "lint"],
            ["status": "IN_PROGRESS", "conclusion": "", "name": "test"],
        ]
        let counts = service.tallyCheckContexts(contexts)
        #expect(counts.passed == 1)
        #expect(counts.failed == 1)
        #expect(counts.pending == 1)
        #expect(counts.failedChecks.count == 1)
        #expect(counts.failedChecks.first?.name == "lint")
    }

    @Test func tallyEmpty() {
        let counts = service.tallyCheckContexts([])
        #expect(counts.passed == 0)
        #expect(counts.failed == 0)
        #expect(counts.pending == 0)
    }

    @Test func tallySkippedAndNeutral() {
        let contexts: [[String: Any]] = [
            ["status": "COMPLETED", "conclusion": "SKIPPED", "name": "optional"],
            ["status": "COMPLETED", "conclusion": "NEUTRAL", "name": "info"],
        ]
        let counts = service.tallyCheckContexts(contexts)
        #expect(counts.passed == 2)
        #expect(counts.failed == 0)
    }

    @Test func tallyEmptyNodes() {
        let contexts: [[String: Any]] = [
            [:],
            ["status": "", "conclusion": ""],
        ]
        let counts = service.tallyCheckContexts(contexts)
        #expect(counts.passed == 0)
        #expect(counts.failed == 0)
        #expect(counts.pending == 0)
    }

    // MARK: - resolveOverallStatus

    @Test func resolveOverallStatusEmpty() {
        let result = service.resolveOverallStatus(totalCount: 0, passed: 0, failed: 0, pending: 0, rollup: [:])
        #expect(result == .unknown)
    }

    @Test func resolveOverallStatusAllPassed() {
        let result = service.resolveOverallStatus(totalCount: 3, passed: 3, failed: 0, pending: 0, rollup: [:])
        #expect(result == .success)
    }

    @Test func resolveOverallStatusHasFailure() {
        let result = service.resolveOverallStatus(totalCount: 3, passed: 1, failed: 1, pending: 1, rollup: [:])
        #expect(result == .failure)
    }

    @Test func resolveOverallStatusHasPending() {
        let result = service.resolveOverallStatus(totalCount: 3, passed: 2, failed: 0, pending: 1, rollup: [:])
        #expect(result == .pending)
    }

    @Test func resolveOverallStatusFallbackToRollup() {
        let rollup: [String: Any] = ["state": "SUCCESS"]
        let result = service.resolveOverallStatus(totalCount: 2, passed: 0, failed: 0, pending: 0, rollup: rollup)
        #expect(result == .success)
    }

    @Test func resolveOverallStatusFallbackToRollupFailure() {
        let rollup: [String: Any] = ["state": "FAILURE"]
        let result = service.resolveOverallStatus(totalCount: 2, passed: 0, failed: 0, pending: 0, rollup: rollup)
        #expect(result == .failure)
    }

    // MARK: - parsePRNode

    @Test func parsePRNodeValid() {
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
        #expect(pr != nil)
        #expect(pr?.number == 42)
        #expect(pr?.title == "Test PR")
        #expect(pr?.author == "testuser")
        #expect(pr?.state == .open)
        #expect(pr?.owner == "test")
        #expect(pr?.repo == "repo")
    }

    @Test func parsePRNodeMissingRequiredFields() {
        let node: [String: Any] = ["title": "Incomplete"]
        let pr = service.parsePRNode(node)
        #expect(pr == nil)
    }

    @Test func parsePRNodeDraft() {
        let node: [String: Any] = [
            "number": 1,
            "title": "Draft PR",
            "url": "https://github.com/test/repo/pull/1",
            "repository": ["nameWithOwner": "test/repo"],
            "isDraft": true,
            "state": "OPEN",
        ]
        let pr = service.parsePRNode(node)
        #expect(pr?.state == .draft)
    }
}

// MARK: - GHError Description Tests

@Suite struct GHErrorDescriptionTests {
    @Test func cliNotFoundUsesStringsConstant() {
        #expect(GHError.cliNotFound.errorDescription == Strings.Error.ghCliNotFound)
    }

    @Test func timeoutUsesStringsConstant() {
        #expect(GHError.timeout.errorDescription == Strings.Error.ghTimeout)
    }

    @Test func invalidJSONUsesStringsConstant() {
        #expect(GHError.invalidJSON.errorDescription == Strings.Error.ghInvalidJSON)
    }

    @Test func apiErrorReturnsCustomMessage() {
        let error = GHError.apiError("rate limit exceeded")
        #expect(error.errorDescription == "rate limit exceeded")
    }

    @Test func apiErrorEmptyReturnsFallback() {
        let error = GHError.apiError("")
        #expect(error.errorDescription == Strings.Error.ghApiErrorFallback)
    }

    @Test func apiErrorWhitespaceReturnsFallback() {
        let error = GHError.apiError("  \n  ")
        #expect(error.errorDescription == Strings.Error.ghApiErrorFallback)
    }
}

// MARK: - PATH Resolution Tests

@Suite struct GitHubServicePATHResolutionTests {
    @Test func resolveFromPATHFindsCommonBinary() {
        // "ls" is universally available on macOS
        let result = GitHubService.resolveFromPATH("ls")
        #expect(result != nil)
        #expect(result?.hasSuffix("/ls") == true)
    }

    @Test func resolveFromPATHReturnsNilForNonexistent() {
        let result = GitHubService.resolveFromPATH("definitely_not_a_binary_xyz_123")
        #expect(result == nil)
    }
}
