import Testing
import Foundation
@testable import PRStatusWatcher

@Suite struct GitHubServiceParsingTests {
    let service = GitHubService()

    // MARK: - parsePRState (signature unchanged)

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

    // MARK: - parseReviewDecision (now takes String?)

    @Test(arguments: [
        ("APPROVED" as String?, PullRequest.ReviewDecision.approved),
        ("CHANGES_REQUESTED" as String?, PullRequest.ReviewDecision.changesRequested),
        ("REVIEW_REQUIRED" as String?, PullRequest.ReviewDecision.reviewRequired),
        (nil as String?, PullRequest.ReviewDecision.none),
        ("" as String?, PullRequest.ReviewDecision.none),
    ])
    func parseReviewDecision(raw: String?, expected: PullRequest.ReviewDecision) {
        #expect(service.parseReviewDecision(raw: raw) == expected)
    }

    // MARK: - parseMergeableState (now takes String?)

    @Test(arguments: [
        ("MERGEABLE" as String?, PullRequest.MergeableState.mergeable),
        ("CONFLICTING" as String?, PullRequest.MergeableState.conflicting),
        ("UNKNOWN" as String?, PullRequest.MergeableState.unknown),
        (nil as String?, PullRequest.MergeableState.unknown),
    ])
    func parseMergeableState(raw: String?, expected: PullRequest.MergeableState) {
        #expect(service.parseMergeableState(raw: raw) == expected)
    }

    // MARK: - tallyCheckContexts (now takes [PRNode.CheckContext])

    @Test func tallyAllPassing() {
        let contexts: [PRNode.CheckContext] = [
            .fixture(name: "build", status: "COMPLETED", conclusion: "SUCCESS"),
            .fixture(name: "test", status: "COMPLETED", conclusion: "SUCCESS"),
        ]
        let counts = service.tallyCheckContexts(contexts)
        #expect(counts.passed == 2)
        #expect(counts.failed == 0)
        #expect(counts.pending == 0)
    }

    @Test func tallyMixed() {
        let contexts: [PRNode.CheckContext] = [
            .fixture(name: "build", status: "COMPLETED", conclusion: "SUCCESS"),
            .fixture(name: "lint", status: "COMPLETED", conclusion: "FAILURE"),
            .fixture(name: "test", status: "IN_PROGRESS", conclusion: ""),
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
        let contexts: [PRNode.CheckContext] = [
            .fixture(name: "optional", status: "COMPLETED", conclusion: "SKIPPED"),
            .fixture(name: "info", status: "COMPLETED", conclusion: "NEUTRAL"),
        ]
        let counts = service.tallyCheckContexts(contexts)
        #expect(counts.passed == 2)
        #expect(counts.failed == 0)
    }

    @Test func tallyEmptyNodes() {
        let contexts: [PRNode.CheckContext] = [
            PRNode.CheckContext(name: nil, status: nil, conclusion: nil, detailsUrl: nil, context: nil, state: nil, targetUrl: nil),
            .fixture(name: nil, status: "", conclusion: ""),
        ]
        let counts = service.tallyCheckContexts(contexts)
        #expect(counts.passed == 0)
        #expect(counts.failed == 0)
        #expect(counts.pending == 0)
    }

    // NEW: StatusContext node handling (previously untested)

    @Test func tallyStatusContextSuccess() {
        let contexts: [PRNode.CheckContext] = [
            .statusContextFixture(context: "ci/circleci", state: "SUCCESS"),
        ]
        let counts = service.tallyCheckContexts(contexts)
        #expect(counts.passed == 1)
        #expect(counts.failed == 0)
        #expect(counts.pending == 0)
    }

    @Test func tallyStatusContextFailure() {
        let contexts: [PRNode.CheckContext] = [
            .statusContextFixture(context: "ci/circleci", state: "FAILURE", targetUrl: "https://ci.example.com/123"),
        ]
        let counts = service.tallyCheckContexts(contexts)
        #expect(counts.failed == 1)
        #expect(counts.failedChecks.count == 1)
        #expect(counts.failedChecks.first?.name == "ci/circleci")
        #expect(counts.failedChecks.first?.detailsUrl?.absoluteString == "https://ci.example.com/123")
    }

    @Test func tallyStatusContextPending() {
        let contexts: [PRNode.CheckContext] = [
            .statusContextFixture(context: "ci/check", state: "PENDING"),
        ]
        let counts = service.tallyCheckContexts(contexts)
        #expect(counts.pending == 1)
    }

    @Test func tallyMixedCheckRunAndStatusContext() {
        let contexts: [PRNode.CheckContext] = [
            .fixture(name: "build", status: "COMPLETED", conclusion: "SUCCESS"),
            .statusContextFixture(context: "ci/external", state: "FAILURE"),
        ]
        let counts = service.tallyCheckContexts(contexts)
        #expect(counts.passed == 1)
        #expect(counts.failed == 1)
    }

    // MARK: - allChecks population

    @Test func tallyPopulatesAllChecks() {
        let contexts: [PRNode.CheckContext] = [
            .fixture(name: "build", status: "COMPLETED", conclusion: "SUCCESS"),
            .fixture(name: "lint", status: "COMPLETED", conclusion: "FAILURE"),
            .fixture(name: "test", status: "IN_PROGRESS", conclusion: ""),
        ]
        let counts = service.tallyCheckContexts(contexts)
        #expect(counts.allChecks.count == 3)
        #expect(counts.allChecks.first(where: { $0.name == "build" })?.status == .passed)
        #expect(counts.allChecks.first(where: { $0.name == "lint" })?.status == .failed)
        #expect(counts.allChecks.first(where: { $0.name == "test" })?.status == .pending)
    }

    @Test func tallyStatusContextPopulatesAllChecks() {
        let contexts: [PRNode.CheckContext] = [
            .statusContextFixture(context: "ci/circleci", state: "SUCCESS"),
            .statusContextFixture(context: "ci/external", state: "FAILURE"),
        ]
        let counts = service.tallyCheckContexts(contexts)
        #expect(counts.allChecks.count == 2)
        #expect(counts.allChecks.first(where: { $0.name == "ci/circleci" })?.status == .passed)
        #expect(counts.allChecks.first(where: { $0.name == "ci/external" })?.status == .failed)
    }

    // MARK: - Edge cases: pending CheckRun with name, completed failure with name

    @Test func tallyPendingCheckRunWithNamePopulatesAllChecks() {
        let contexts: [PRNode.CheckContext] = [
            .fixture(name: "deploy", status: "QUEUED", conclusion: ""),
        ]
        let counts = service.tallyCheckContexts(contexts)
        #expect(counts.pending == 1)
        #expect(counts.allChecks.count == 1)
        #expect(counts.allChecks.first?.name == "deploy")
        #expect(counts.allChecks.first?.status == .pending)
    }

    @Test func tallyCompletedFailureWithNamePopulatesAllChecks() {
        let contexts: [PRNode.CheckContext] = [
            .fixture(name: "e2e", status: "COMPLETED", conclusion: "FAILURE",
                     detailsUrl: "https://ci.example.com/456"),
        ]
        let counts = service.tallyCheckContexts(contexts)
        #expect(counts.failed == 1)
        #expect(counts.failedChecks.count == 1)
        #expect(counts.failedChecks.first?.name == "e2e")
        #expect(counts.allChecks.count == 1)
        #expect(counts.allChecks.first?.name == "e2e")
        #expect(counts.allChecks.first?.status == .failed)
        #expect(counts.allChecks.first?.detailsUrl?.absoluteString == "https://ci.example.com/456")
    }

    @Test func tallyStatusContextErrorCountsAsFailure() {
        let contexts: [PRNode.CheckContext] = [
            .statusContextFixture(context: "ci/broken", state: "ERROR"),
        ]
        let counts = service.tallyCheckContexts(contexts)
        #expect(counts.failed == 1)
        #expect(counts.failedChecks.first?.name == "ci/broken")
        #expect(counts.allChecks.first?.status == .failed)
    }

    // MARK: - extractRollupData: truncated contexts path

    @Test func extractRollupDataTruncatedContextsStillReturnsData() {
        let node = PRNode.fixture(
            commits: PRNode.CommitConnection(nodes: [
                PRNode.CommitNode(commit: PRNode.CommitRef(
                    statusCheckRollup: PRNode.StatusCheckRollup(
                        state: "PENDING",
                        contexts: PRNode.CheckContextConnection(
                            totalCount: 150,
                            nodes: [
                                .fixture(name: "build", status: "COMPLETED", conclusion: "SUCCESS"),
                            ]
                        )
                    )
                ))
            ])
        )
        let result = service.extractRollupData(from: node)
        #expect(result != nil)
        #expect(result?.totalCount == 150)
        #expect(result?.contextNodes.count == 1)
    }

    // MARK: - parseCheckStatus: no rollup data returns unknown

    @Test func parseCheckStatusNoRollupReturnsUnknown() {
        let node = PRNode.fixture()
        let result = service.parseCheckStatus(from: node)
        #expect(result.status == .unknown)
        #expect(result.total == 0)
        #expect(result.checkResults.isEmpty)
    }

    // MARK: - resolveOverallStatus: additional rollup fallback paths

    @Test func resolveOverallStatusFallbackToRollupPending() {
        let result = service.resolveOverallStatus(
            totalCount: 2, passed: 0, failed: 0, pending: 0, rollupState: "PENDING"
        )
        #expect(result == .pending)
    }

    @Test func resolveOverallStatusFallbackToRollupUnknown() {
        let result = service.resolveOverallStatus(
            totalCount: 2, passed: 0, failed: 0, pending: 0, rollupState: "SOMETHING_ELSE"
        )
        #expect(result == .unknown)
    }

    @Test func resolveOverallStatusFallbackToRollupError() {
        let result = service.resolveOverallStatus(
            totalCount: 2, passed: 0, failed: 0, pending: 0, rollupState: "ERROR"
        )
        #expect(result == .failure)
    }

    // MARK: - resolveOverallStatus (now takes String? instead of [String: Any])

    @Test func resolveOverallStatusEmpty() {
        let result = service.resolveOverallStatus(totalCount: 0, passed: 0, failed: 0, pending: 0, rollupState: nil)
        #expect(result == .unknown)
    }

    @Test func resolveOverallStatusAllPassed() {
        let result = service.resolveOverallStatus(totalCount: 3, passed: 3, failed: 0, pending: 0, rollupState: nil)
        #expect(result == .success)
    }

    @Test func resolveOverallStatusHasFailure() {
        let result = service.resolveOverallStatus(totalCount: 3, passed: 1, failed: 1, pending: 1, rollupState: nil)
        #expect(result == .failure)
    }

    @Test func resolveOverallStatusHasPending() {
        let result = service.resolveOverallStatus(totalCount: 3, passed: 2, failed: 0, pending: 1, rollupState: nil)
        #expect(result == .pending)
    }

    @Test func resolveOverallStatusFallbackToRollup() {
        let result = service.resolveOverallStatus(totalCount: 2, passed: 0, failed: 0, pending: 0, rollupState: "SUCCESS")
        #expect(result == .success)
    }

    @Test func resolveOverallStatusFallbackToRollupFailure() {
        let result = service.resolveOverallStatus(totalCount: 2, passed: 0, failed: 0, pending: 0, rollupState: "FAILURE")
        #expect(result == .failure)
    }

    // MARK: - convertNode (replaces parsePRNode)

    @Test func convertNodeValid() {
        let node = PRNode.fixture(
            number: 42,
            title: "Test PR",
            url: "https://github.com/test/repo/pull/42",
            nameWithOwner: "test/repo",
            authorLogin: "testuser",
            isDraft: false,
            state: "OPEN",
            reviewDecision: "APPROVED",
            mergeable: "MERGEABLE",
            approvalCount: 1
        )
        let pr = service.convertNode(node, viewerUsername: "testuser")
        #expect(pr != nil)
        #expect(pr?.number == 42)
        #expect(pr?.title == "Test PR")
        #expect(pr?.author == "testuser")
        #expect(pr?.state == .open)
        #expect(pr?.owner == "test")
        #expect(pr?.repo == "repo")
        #expect(pr?.reviewDecision == .approved)
        #expect(pr?.mergeable == .mergeable)
    }

    @Test func convertNodeMissingNumber() {
        let node = PRNode.fixture(number: nil, title: "No Number")
        #expect(service.convertNode(node, viewerUsername: "testuser") == nil)
    }

    @Test func convertNodeMissingTitle() {
        let node = PRNode.fixture(title: nil)
        #expect(service.convertNode(node, viewerUsername: "testuser") == nil)
    }

    @Test func convertNodeMissingURL() {
        let node = PRNode.fixture(url: nil)
        #expect(service.convertNode(node, viewerUsername: "testuser") == nil)
    }

    @Test func convertNodeEmptyURL() {
        let node = PRNode.fixture(url: "")
        #expect(service.convertNode(node, viewerUsername: "testuser") == nil)
    }

    @Test func convertNodeMissingRepository() {
        let node = PRNode.fixture(nameWithOwner: nil)
        #expect(service.convertNode(node, viewerUsername: "testuser") == nil)
    }

    @Test func convertNodeSingleSegmentRepo() {
        let node = PRNode.fixture(nameWithOwner: "noslash")
        #expect(service.convertNode(node, viewerUsername: "testuser") == nil)
    }

    @Test func convertNodeThreeSegmentRepo() {
        let node = PRNode.fixture(nameWithOwner: "too/many/segments")
        #expect(service.convertNode(node, viewerUsername: "testuser") == nil)
    }

    @Test func convertNodeDraft() {
        let node = PRNode.fixture(isDraft: true, state: "OPEN")
        let pr = service.convertNode(node, viewerUsername: "testuser")
        #expect(pr?.state == .draft)
    }

    @Test func convertNodeDefaultsForOptionalFields() {
        // Minimal valid node — only required fields
        let node = PRNode.fixture()
        let pr = service.convertNode(node, viewerUsername: "testuser")
        #expect(pr != nil)
        #expect(pr?.author == "unknown")
        #expect(pr?.state == .open)
        #expect(pr?.headRefName == "")
    }

    // MARK: - convertNode: viewerHasApproved via latestReviews

    @Test func convertNodeSetsViewerHasApprovedWhenViewerApproved() {
        let node = PRNode.fixture(
            latestReviews: PRNode.LatestReviewsConnection(nodes: [
                PRNode.LatestReviewNode(author: PRNode.AuthorRef(login: "viewer"), state: "APPROVED"),
                PRNode.LatestReviewNode(author: PRNode.AuthorRef(login: "other"), state: "CHANGES_REQUESTED"),
            ])
        )
        let pr = service.convertNode(node, viewerUsername: "viewer")
        #expect(pr?.viewerHasApproved == true)
    }

    @Test func convertNodeSetsViewerHasApprovedFalseWhenViewerRequestedChanges() {
        let node = PRNode.fixture(
            latestReviews: PRNode.LatestReviewsConnection(nodes: [
                PRNode.LatestReviewNode(author: PRNode.AuthorRef(login: "viewer"), state: "CHANGES_REQUESTED"),
            ])
        )
        let pr = service.convertNode(node, viewerUsername: "viewer")
        #expect(pr?.viewerHasApproved == false)
    }

    @Test func convertNodeSetsViewerHasApprovedFalseWhenViewerNotInReviews() {
        let node = PRNode.fixture(
            latestReviews: PRNode.LatestReviewsConnection(nodes: [
                PRNode.LatestReviewNode(author: PRNode.AuthorRef(login: "other"), state: "APPROVED"),
            ])
        )
        let pr = service.convertNode(node, viewerUsername: "viewer")
        #expect(pr?.viewerHasApproved == false)
    }

    @Test func convertNodeSetsViewerHasApprovedFalseWhenNoLatestReviews() {
        let node = PRNode.fixture(latestReviews: nil)
        let pr = service.convertNode(node, viewerUsername: "viewer")
        #expect(pr?.viewerHasApproved == false)
    }

    @Test func convertNodeViewerMatchIsCaseInsensitive() {
        let node = PRNode.fixture(
            latestReviews: PRNode.LatestReviewsConnection(nodes: [
                PRNode.LatestReviewNode(author: PRNode.AuthorRef(login: "Viewer"), state: "APPROVED"),
            ])
        )
        let pr = service.convertNode(node, viewerUsername: "viewer")
        #expect(pr?.viewerHasApproved == true)
    }

    @Test func convertNodeCommentedReviewIsNotApproved() {
        let node = PRNode.fixture(
            latestReviews: PRNode.LatestReviewsConnection(nodes: [
                PRNode.LatestReviewNode(author: PRNode.AuthorRef(login: "viewer"), state: "COMMENTED"),
            ])
        )
        let pr = service.convertNode(node, viewerUsername: "viewer")
        #expect(pr?.viewerHasApproved == false)
    }

    @Test func convertNodeNilAuthorInLatestReviewIsNotApproved() {
        let node = PRNode.fixture(
            latestReviews: PRNode.LatestReviewsConnection(nodes: [
                PRNode.LatestReviewNode(author: nil, state: "APPROVED"),
            ])
        )
        let pr = service.convertNode(node, viewerUsername: "viewer")
        #expect(pr?.viewerHasApproved == false)
    }

    @Test func convertNodeNilStateInLatestReviewIsNotApproved() {
        let node = PRNode.fixture(
            latestReviews: PRNode.LatestReviewsConnection(nodes: [
                PRNode.LatestReviewNode(author: PRNode.AuthorRef(login: "viewer"), state: nil),
            ])
        )
        let pr = service.convertNode(node, viewerUsername: "viewer")
        #expect(pr?.viewerHasApproved == false)
    }

    @Test func convertNodeEmptyLatestReviewsNodesIsNotApproved() {
        let node = PRNode.fixture(
            latestReviews: PRNode.LatestReviewsConnection(nodes: [])
        )
        let pr = service.convertNode(node, viewerUsername: "viewer")
        #expect(pr?.viewerHasApproved == false)
    }

    // MARK: - GraphQLResponse Decoding

    @Test func decodeFullGraphQLResponse() throws {
        let json = """
        {
          "data": {
            "search": {
              "nodes": [
                {
                  "number": 42,
                  "title": "Test PR",
                  "url": "https://github.com/test/repo/pull/42",
                  "repository": {"nameWithOwner": "test/repo"},
                  "author": {"login": "testuser"},
                  "isDraft": false,
                  "state": "OPEN"
                }
              ]
            }
          }
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(GraphQLResponse.self, from: data)
        #expect(response.data?.search.nodes.count == 1)
        #expect(response.data?.search.nodes.first?.number == 42)
        #expect(response.errors == nil)
    }

    @Test func decodeGraphQLResponseWithErrors() throws {
        let json = """
        {
          "errors": [{"message": "API rate limit exceeded", "type": "RATE_LIMITED"}],
          "data": null
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(GraphQLResponse.self, from: data)
        #expect(response.data == nil)
        #expect(response.errors?.count == 1)
        #expect(response.errors?.first?.message == "API rate limit exceeded")
    }

    @Test func decodeGraphQLResponseWithEmptyNodes() throws {
        let json = """
        {
          "data": {
            "search": {
              "nodes": [{}]
            }
          }
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(GraphQLResponse.self, from: data)
        #expect(response.data?.search.nodes.count == 1)
        // Empty node — all fields nil
        let node = response.data!.search.nodes[0]
        #expect(node.number == nil)
        #expect(node.title == nil)
    }
}

// MARK: - Test Fixtures

extension PRNode {
    /// Minimal valid PRNode for testing. Override individual fields as needed.
    static func fixture(
        number: Int? = 1,
        title: String? = "Test PR",
        url: String? = "https://github.com/test/repo/pull/1",
        nameWithOwner: String? = "test/repo",
        authorLogin: String? = nil,
        isDraft: Bool? = false,
        state: String? = "OPEN",
        reviewDecision: String? = nil,
        mergeable: String? = nil,
        mergeQueuePosition: Int?? = nil,
        approvalCount: Int? = nil,
        headRefOid: String? = nil,
        headRefName: String? = nil,
        commits: PRNode.CommitConnection? = nil,
        latestReviews: PRNode.LatestReviewsConnection? = nil
    ) -> PRNode {
        PRNode(
            number: number,
            title: title,
            url: url,
            repository: nameWithOwner.map { PRNode.RepositoryRef(nameWithOwner: $0) },
            author: authorLogin.map { PRNode.AuthorRef(login: $0) },
            isDraft: isDraft,
            state: state,
            reviewDecision: reviewDecision,
            mergeable: mergeable,
            mergeQueueEntry: mergeQueuePosition.map { PRNode.MergeQueueEntryRef(position: $0) } ?? nil,
            reviews: approvalCount.map { PRNode.ReviewsRef(totalCount: $0) },
            latestReviews: latestReviews,
            headRefOid: headRefOid,
            headRefName: headRefName,
            commits: commits
        )
    }
}

extension PRNode.CheckContext {
    /// CheckRun-style fixture.
    static func fixture(
        name: String? = nil,
        status: String? = nil,
        conclusion: String? = nil,
        detailsUrl: String? = nil
    ) -> PRNode.CheckContext {
        PRNode.CheckContext(
            name: name, status: status, conclusion: conclusion, detailsUrl: detailsUrl,
            context: nil, state: nil, targetUrl: nil
        )
    }

    /// StatusContext-style fixture.
    static func statusContextFixture(
        context: String,
        state: String,
        targetUrl: String? = nil
    ) -> PRNode.CheckContext {
        PRNode.CheckContext(
            name: nil, status: nil, conclusion: nil, detailsUrl: nil,
            context: context, state: state, targetUrl: targetUrl
        )
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

    @Test func processLaunchFailedDescription() {
        let error = GHError.processLaunchFailed("Permission denied")
        #expect(error.errorDescription == Strings.Error.ghProcessLaunchFailed("Permission denied"))
        #expect(error.errorDescription?.contains("Permission denied") == true)
        #expect(error.errorDescription?.contains("Failed to launch") == true)
    }
}

// MARK: - extractRollupData

@Suite struct ExtractRollupDataTests {
    let service = GitHubService()

    @Test func extractRollupDataValid() {
        let node = PRNode.fixture(
            commits: PRNode.CommitConnection(nodes: [
                PRNode.CommitNode(commit: PRNode.CommitRef(
                    statusCheckRollup: PRNode.StatusCheckRollup(
                        state: "SUCCESS",
                        contexts: PRNode.CheckContextConnection(
                            totalCount: 2,
                            nodes: [
                                .fixture(name: "build", status: "COMPLETED", conclusion: "SUCCESS"),
                                .fixture(name: "test", status: "COMPLETED", conclusion: "SUCCESS"),
                            ]
                        )
                    )
                ))
            ])
        )
        let result = service.extractRollupData(from: node)
        #expect(result != nil)
        #expect(result?.totalCount == 2)
        #expect(result?.contextNodes.count == 2)
    }

    @Test func extractRollupDataMissingRollup() {
        let node = PRNode.fixture(
            commits: PRNode.CommitConnection(nodes: [
                PRNode.CommitNode(commit: PRNode.CommitRef(statusCheckRollup: nil))
            ])
        )
        #expect(service.extractRollupData(from: node) == nil)
    }

    @Test func extractRollupDataEmptyCommits() {
        let node = PRNode.fixture(
            commits: PRNode.CommitConnection(nodes: nil)
        )
        #expect(service.extractRollupData(from: node) == nil)
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
