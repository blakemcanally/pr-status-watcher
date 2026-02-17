# P2 Medium Impact Fixes — Implementation Plan

## Overview

Address 7 P2 issues from the adversarial code review, implementing with parallel subagent streams where file boundaries allow. Each stream is independent — no shared files — so they can execute concurrently without merge conflicts.

## Current State Analysis

| # | Issue | File(s) | Current Status |
|---|-------|---------|---------------|
| 1 | Malformed PR nodes silently dropped | `GitHubService.swift:128-130` | `compactMap` with no logging when `parsePRNode` returns `nil` |
| 2 | Notification permission & delivery unverified | `NotificationDispatcher.swift:15-17, 35` | `requestAuthorization` ignores granted/error; `add(request)` has no completion handler |
| 3 | `try? Task.sleep` masks cancellation | `PollingScheduler.swift:25-28` | **Already fixed** — uses `do-catch` with `return` on error |
| 4 | Business logic in views | `ContentView.swift:28-48, 164-173` | `groupedPRs` sorting/grouping computed in view; `collapsedRepos` mutated directly |
| 5 | 3 separate `gh` processes per refresh | `GitHubService.swift`, `PRManager.swift` | **Actually 2 per refresh** (my PRs + review PRs). `currentUser()` runs once at init. Research doc overstates this. |
| 6 | `groupedPRs` recomputed in SwiftUI body | `ContentView.swift:28-48` | O(n) computed property evaluated every body pass |
| 7 | JSON parsed as untyped dictionaries | `GitHubService.swift:118-126, 137-354` | Uses `JSONSerialization` → `[String: Any]` throughout |

### Key Discoveries:
- Issue 3 is **already fixed** in `PollingScheduler.swift` (extracted during PRManager decomposition). Only documentation updates needed.
- Issue 5 is **mischaracterized** — the app spawns 2 processes per refresh, not 3. The `currentUser()` call is one-time at init. Keeping separate processes is intentional for fault isolation (one query can fail without losing the other). Only documentation needs correction.
- Issues 4 and 6 overlap — extracting `groupedPRs` to a testable pure function addresses both.
- Issue 7 (Codable migration) is the largest change but is entirely contained within `GitHubService.swift` and its tests. The `GitHubServiceProtocol` signatures (`throws -> [PullRequest]`) don't change.
- All 137 tests already use Swift Testing. New tests follow the same conventions.

## Desired End State

1. **Malformed PR nodes are logged** with identifying information (number, title prefix) when `parsePRNode`/`convertNode` returns nil
2. **Notification permission results are logged** (granted/denied/error); delivery failures are logged
3. **`try? Task.sleep` fix is documented** in research findings (already fixed in code)
4. **Grouping/sorting logic is extracted** to a testable `PRGrouping` enum; `toggleRepoCollapsed(_:)` replaces direct Set mutation
5. **Documentation corrected** — "3 processes" → "2 processes per refresh (+ 1 at init)"
6. **`groupedPRs`** calls the extracted pure function (same semantics, now testable)
7. **GraphQL response uses Codable** structs instead of `[String: Any]`; GraphQL `errors` field is inspected
8. **~25 new tests** bring the total from 137 to ~162

### Verification:
```bash
swift build 2>&1 | tail -5    # Zero errors, zero warnings
swift test  2>&1 | tail -20   # All tests pass (existing + new)
```

## What We're NOT Doing

- Not combining the two GraphQL queries into one — separate processes provide fault isolation (one can fail without losing the other)
- Not changing `GitHubServiceProtocol` — the Codable migration is internal to `GitHubService`
- Not adding retry logic or exponential backoff (separate concern)
- Not moving `selectedTab` to `PRManager` — it's view-level state
- Not caching `groupedPRs` in `PRManager` — for <100 PRs, O(n) on body eval is acceptable; the pure function extraction provides testability now, and caching can be added later if needed
- Not changing `GitHubService` to an actor (separate P1 issue)

## Implementation Approach

Four parallel streams that touch non-overlapping file sets:

| Stream | Files Modified | Files Created | New Tests |
|--------|---------------|---------------|-----------|
| **A: Codable + Parse Logging** | `GitHubService.swift`, `GitHubServiceParsingTests.swift` | `GraphQLResponse.swift` | ~15 |
| **B: Notification Verification** | `NotificationDispatcher.swift`, `NotificationServiceProtocol.swift`, `MockNotificationService.swift` | `NotificationDispatcherTests.swift` | ~5 |
| **C: View Logic Extraction** | `ContentView.swift`, `PRManager.swift`, `PRManagerTests.swift` | `PRGrouping.swift`, `PRGroupingTests.swift` | ~10 |
| **D: Documentation** | `README.md`, research doc | — | 0 |

**Zero file overlap between streams A, B, C, and D.** All four can execute concurrently.

---

## Stream A: Codable Migration + Parse Node Logging

### Overview
Replace `JSONSerialization` → `[String: Any]` with `Codable` structs. Add logging when PR nodes fail to convert. Inspect the GraphQL `errors` field. Update all parsing tests for the new types.

**Files modified:** `Sources/GitHubService.swift`, `Tests/GitHubServiceParsingTests.swift`
**Files created:** `Sources/GraphQLResponse.swift`

### Changes Required:

#### A.1 Create Codable response types

**File:** `Sources/GraphQLResponse.swift` (new)

```swift
import Foundation

// MARK: - GitHub GraphQL API Response Types

/// Top-level response from `gh api graphql`.
struct GraphQLResponse: Codable {
    let data: GraphQLData?
    let errors: [GraphQLError]?
}

struct GraphQLError: Codable {
    let message: String
    let type: String?
}

struct GraphQLData: Codable {
    let search: SearchResult
}

struct SearchResult: Codable {
    let nodes: [PRNode]
}

/// A PR node from the GraphQL search results.
/// All fields are optional to handle partial/malformed responses from
/// inline fragments gracefully — the conversion to `PullRequest` validates
/// required fields.
struct PRNode: Codable {
    let number: Int?
    let title: String?
    let url: String?
    let repository: RepositoryRef?
    let author: AuthorRef?
    let isDraft: Bool?
    let state: String?
    let reviewDecision: String?
    let mergeable: String?
    let mergeQueueEntry: MergeQueueEntryRef?
    let reviews: ReviewsRef?
    let headRefOid: String?
    let headRefName: String?
    let commits: CommitConnection?

    struct RepositoryRef: Codable {
        let nameWithOwner: String
    }

    struct AuthorRef: Codable {
        let login: String
    }

    struct MergeQueueEntryRef: Codable {
        let position: Int?
    }

    struct ReviewsRef: Codable {
        let totalCount: Int
    }

    struct CommitConnection: Codable {
        let nodes: [CommitNode]?
    }

    struct CommitNode: Codable {
        let commit: CommitRef
    }

    struct CommitRef: Codable {
        let statusCheckRollup: StatusCheckRollup?
    }

    struct StatusCheckRollup: Codable {
        let state: String?
        let contexts: CheckContextConnection?
    }

    struct CheckContextConnection: Codable {
        let totalCount: Int
        let nodes: [CheckContext]
    }

    /// Represents either a CheckRun or a StatusContext.
    /// Both inline fragment types decode into one struct with optional fields.
    struct CheckContext: Codable {
        // CheckRun fields
        let name: String?
        let status: String?
        let conclusion: String?
        let detailsUrl: String?
        // StatusContext fields
        let context: String?
        let state: String?
        let targetUrl: String?
    }
}
```

#### A.2 Rewrite `fetchPRs` to use `JSONDecoder`

**File:** `Sources/GitHubService.swift`

Replace lines 108–133 (everything after the query string through the return). The query construction (lines 59–108) is unchanged.

```swift
    // ... query string unchanged above ...

    logger.info("fetchPRs: query=\(searchQuery.prefix(80), privacy: .public)")
    let (stdout, stderr, exit) = try run(["api", "graphql", "-f", "query=\(query)"])

    guard exit == 0 else {
        logger.error("fetchPRs: exit=\(exit), stderr=\(stderr.prefix(500), privacy: .public)")
        throw GHError.apiError(stderr.isEmpty ? stdout : stderr)
    }

    guard let data = stdout.data(using: .utf8) else {
        logger.error("fetchPRs: failed to convert stdout to Data")
        throw GHError.invalidJSON
    }

    let response: GraphQLResponse
    do {
        response = try JSONDecoder().decode(GraphQLResponse.self, from: data)
    } catch {
        logger.error("fetchPRs: JSON decode failed: \(error.localizedDescription, privacy: .public)")
        throw GHError.invalidJSON
    }

    // Surface GraphQL errors (rate limits, schema errors, partial failures)
    if let errors = response.errors, let first = errors.first {
        logger.error("fetchPRs: GraphQL error: \(first.message, privacy: .public)")
        throw GHError.apiError(first.message)
    }

    guard let nodes = response.data?.search.nodes else {
        logger.error("fetchPRs: missing data.search.nodes in response")
        throw GHError.invalidJSON
    }

    var skippedCount = 0
    let prs = nodes.compactMap { node -> PullRequest? in
        guard let pr = convertNode(node) else {
            skippedCount += 1
            logger.warning(
                "fetchPRs: skipping malformed node"
                + " (number=\(node.number.map(String.init) ?? "nil")"
                + ", title=\"\(node.title?.prefix(50) ?? "nil")\")"
            )
            return nil
        }
        return pr
    }

    if skippedCount > 0 {
        logger.warning("fetchPRs: skipped \(skippedCount) malformed nodes out of \(nodes.count)")
    }
    logger.info("fetchPRs: parsed \(prs.count) PRs from \(nodes.count) nodes")
    return prs
}
```

#### A.3 Rewrite parsing methods for typed input

**File:** `Sources/GitHubService.swift`

Replace `parsePRNode(_ node: [String: Any])` with `convertNode(_ node: PRNode)`:

```swift
// MARK: - Node Conversion (Codable → PullRequest)

func convertNode(_ node: PRNode) -> PullRequest? {
    guard let number = node.number,
          let title = node.title,
          let urlString = node.url,
          let url = URL(string: urlString),
          let nameWithOwner = node.repository?.nameWithOwner
    else { return nil }

    let repoParts = nameWithOwner.split(separator: "/")
    guard repoParts.count == 2 else { return nil }
    let owner = String(repoParts[0])
    let repo = String(repoParts[1])

    let author = node.author?.login ?? "unknown"
    let isDraft = node.isDraft ?? false
    let rawState = node.state ?? "OPEN"
    let headSHA = node.headRefOid ?? ""
    let headRefName = node.headRefName ?? ""
    let queuePosition = node.mergeQueueEntry?.position
    let approvalCount = node.reviews?.totalCount ?? 0

    let reviewDecision = parseReviewDecision(raw: node.reviewDecision)
    let mergeable = parseMergeableState(raw: node.mergeable)
    let state = parsePRState(rawState: rawState, isDraft: isDraft)
    let checkResult = parseCheckStatus(from: node)

    return PullRequest(
        owner: owner,
        repo: repo,
        number: number,
        title: title,
        author: author,
        state: state,
        ciStatus: checkResult.status,
        isInMergeQueue: node.mergeQueueEntry != nil,
        checksTotal: checkResult.total,
        checksPassed: checkResult.passed,
        checksFailed: checkResult.failed,
        url: url,
        headSHA: String(headSHA.prefix(7)),
        headRefName: headRefName,
        lastFetched: Date(),
        reviewDecision: reviewDecision,
        mergeable: mergeable,
        queuePosition: queuePosition,
        approvalCount: approvalCount,
        failedChecks: checkResult.failedChecks
    )
}
```

Replace `parseReviewDecision(from: [String: Any])` with `parseReviewDecision(raw: String?)`:

```swift
func parseReviewDecision(raw: String?) -> PullRequest.ReviewDecision {
    switch raw ?? "" {
    case "APPROVED": return .approved
    case "CHANGES_REQUESTED": return .changesRequested
    case "REVIEW_REQUIRED": return .reviewRequired
    default: return .none
    }
}
```

Replace `parseMergeableState(from: [String: Any])` with `parseMergeableState(raw: String?)`:

```swift
func parseMergeableState(raw: String?) -> PullRequest.MergeableState {
    switch raw ?? "" {
    case "MERGEABLE": return .mergeable
    case "CONFLICTING": return .conflicting
    default: return .unknown
    }
}
```

`parsePRState(rawState:isDraft:)` — **signature unchanged**, no modifications needed.

Replace `parseCheckStatus`, `extractRollupData`, `tallyCheckContexts` to use typed structs:

```swift
// MARK: - Check Status Parsing (typed)

struct TypedRollupData {
    let rollupState: String?
    let totalCount: Int
    let contextNodes: [PRNode.CheckContext]
}

func parseCheckStatus(from node: PRNode) -> CIResult {
    guard let rollupData = extractRollupData(from: node) else {
        return CIResult(status: .unknown, total: 0, passed: 0, failed: 0, failedChecks: [])
    }

    let counts = tallyCheckContexts(rollupData.contextNodes)

    let ciStatus = resolveOverallStatus(
        totalCount: rollupData.totalCount,
        passed: counts.passed,
        failed: counts.failed,
        pending: counts.pending,
        rollupState: rollupData.rollupState
    )

    return CIResult(
        status: ciStatus,
        total: rollupData.totalCount,
        passed: counts.passed,
        failed: counts.failed,
        failedChecks: counts.failedChecks
    )
}

func extractRollupData(from node: PRNode) -> TypedRollupData? {
    guard let commits = node.commits?.nodes,
          let firstCommit = commits.first,
          let rollup = firstCommit.commit.statusCheckRollup,
          let contexts = rollup.contexts
    else { return nil }

    return TypedRollupData(
        rollupState: rollup.state,
        totalCount: contexts.totalCount,
        contextNodes: contexts.nodes
    )
}

func tallyCheckContexts(_ contexts: [PRNode.CheckContext]) -> CheckCounts {
    var counts = CheckCounts(passed: 0, failed: 0, pending: 0, failedChecks: [])

    for ctx in contexts {
        if let contextName = ctx.context {
            // StatusContext node
            switch ctx.state ?? "" {
            case "SUCCESS":
                counts.passed += 1
            case "FAILURE", "ERROR":
                counts.failed += 1
                let targetUrl = ctx.targetUrl.flatMap { URL(string: $0) }
                counts.failedChecks.append(PullRequest.CheckInfo(name: contextName, detailsUrl: targetUrl))
            case "PENDING", "EXPECTED":
                counts.pending += 1
            default:
                counts.pending += 1
            }
        } else {
            // CheckRun node
            let status = ctx.status ?? ""
            let conclusion = ctx.conclusion ?? ""

            if status.isEmpty && conclusion.isEmpty { continue }

            if status == "COMPLETED" {
                classifyCompletedCheckContext(ctx, conclusion: conclusion, counts: &counts)
            } else {
                counts.pending += 1
            }
        }
    }

    return counts
}

func classifyCompletedCheckContext(
    _ ctx: PRNode.CheckContext,
    conclusion: String,
    counts: inout CheckCounts
) {
    switch conclusion {
    case "SUCCESS", "SKIPPED", "NEUTRAL":
        counts.passed += 1
    default:
        counts.failed += 1
        if let name = ctx.name {
            let detailsUrl = ctx.detailsUrl.flatMap { URL(string: $0) }
            counts.failedChecks.append(PullRequest.CheckInfo(name: name, detailsUrl: detailsUrl))
        }
    }
}

func resolveOverallStatus(
    totalCount: Int,
    passed: Int,
    failed: Int,
    pending: Int,
    rollupState: String?
) -> PullRequest.CIStatus {
    if totalCount == 0 { return .unknown }
    if failed > 0 { return .failure }
    if pending > 0 { return .pending }

    // All nodes were empty StatusContexts — fall back to rollup state
    if passed == 0 {
        switch rollupState ?? "" {
        case "SUCCESS": return .success
        case "FAILURE", "ERROR": return .failure
        case "PENDING": return .pending
        default: return .unknown
        }
    }

    return .success
}
```

**Delete these types** (replaced by `TypedRollupData`):
- `struct RollupData` (lines 250-254)

**Delete these methods** (replaced by typed versions):
- `parsePRNode(_ node: [String: Any])` (lines 137-189)
- `parseReviewDecision(from node: [String: Any])` (lines 191-199)
- `parseMergeableState(from node: [String: Any])` (lines 201-208)
- `parseCheckStatus(from node: [String: Any])` (lines 226-248)
- `extractRollupData(from node: [String: Any])` (lines 256-268)
- `tallyCheckContexts(_ contextNodes: [[String: Any]])` (lines 277-312)
- `classifyCompletedCheck(_ ctx: [String: Any], ...)` (lines 314-329)
- `resolveOverallStatus(..., rollup: [String: Any])` (lines 331-354)

#### A.4 Update parsing tests

**File:** `Tests/GitHubServiceParsingTests.swift`

Complete rewrite. Tests now construct `PRNode`, `PRNode.CheckContext`, etc. instead of `[String: Any]` dictionaries. All existing test cases are preserved; new ones added.

```swift
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
        let pr = service.convertNode(node)
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
        #expect(service.convertNode(node) == nil)
    }

    @Test func convertNodeMissingTitle() {
        let node = PRNode.fixture(title: nil)
        #expect(service.convertNode(node) == nil)
    }

    @Test func convertNodeMissingURL() {
        let node = PRNode.fixture(url: nil)
        #expect(service.convertNode(node) == nil)
    }

    @Test func convertNodeInvalidURL() {
        let node = PRNode.fixture(url: "not a url with spaces")
        #expect(service.convertNode(node) == nil)
    }

    @Test func convertNodeMissingRepository() {
        let node = PRNode.fixture(nameWithOwner: nil)
        #expect(service.convertNode(node) == nil)
    }

    @Test func convertNodeSingleSegmentRepo() {
        let node = PRNode.fixture(nameWithOwner: "noslash")
        #expect(service.convertNode(node) == nil)
    }

    @Test func convertNodeDraft() {
        let node = PRNode.fixture(isDraft: true, state: "OPEN")
        let pr = service.convertNode(node)
        #expect(pr?.state == .draft)
    }

    @Test func convertNodeDefaultsForOptionalFields() {
        // Minimal valid node — only required fields
        let node = PRNode.fixture()
        let pr = service.convertNode(node)
        #expect(pr != nil)
        #expect(pr?.author == "unknown")
        #expect(pr?.isDraft == false)  // via state
        #expect(pr?.headRefName == "")
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
        commits: PRNode.CommitConnection? = nil
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
            mergeQueueEntry: mergeQueuePosition.map { pos in pos.map { PRNode.MergeQueueEntryRef(position: $0) } } ?? nil,
            reviews: approvalCount.map { PRNode.ReviewsRef(totalCount: $0) },
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
```

### Success Criteria:

#### Automated Verification:
- [x] `swift build` succeeds with zero errors
- [x] `swift test` passes — all existing + new tests green
- [x] `Sources/GraphQLResponse.swift` exists with all Codable types
- [x] `GitHubService.swift` contains zero references to `JSONSerialization`
- [x] `GitHubService.swift` contains zero references to `[String: Any]` (except in `escapeForGraphQL` which returns `String`)
- [x] `GitHubServiceParsingTests.swift` contains zero `[String: Any]` test data
- [x] New tests for StatusContext nodes, GraphQL error handling, and convertNode edge cases all pass

---

## Stream B: Notification Permission & Delivery Verification

### Overview
Add logging to `NotificationDispatcher` for permission and delivery results. Update the protocol with a `permissionGranted` property. Add tests verifying the protocol contract.

**Files modified:** `Sources/NotificationDispatcher.swift`, `Sources/NotificationServiceProtocol.swift`, `Tests/Mocks/MockNotificationService.swift`
**Files created:** `Tests/NotificationServiceTests.swift`

### Changes Required:

#### B.1 Update protocol with permission state

**File:** `Sources/NotificationServiceProtocol.swift`

```swift
import Foundation

/// Abstraction over UNUserNotificationCenter for local notification delivery.
protocol NotificationServiceProtocol {
    var isAvailable: Bool { get }

    /// Whether the user has granted notification permission.
    /// Returns `false` until permission is explicitly granted.
    var permissionGranted: Bool { get }

    func requestPermission()
    func send(title: String, body: String, url: URL?)
}
```

#### B.2 Update `NotificationDispatcher` with logging

**File:** `Sources/NotificationDispatcher.swift`

```swift
import Foundation
import UserNotifications
import os

private let logger = Logger(subsystem: "PRStatusWatcher", category: "NotificationDispatcher")

// MARK: - Notification Dispatcher

/// Delivers local notifications via UNUserNotificationCenter.
/// Conforms to NotificationServiceProtocol for mock injection.
final class NotificationDispatcher: NotificationServiceProtocol {
    private(set) var permissionGranted: Bool = false

    var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    func requestPermission() {
        guard isAvailable else {
            logger.info("requestPermission: skipped — no bundle identifier")
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { [weak self] granted, error in
            self?.permissionGranted = granted
            if let error {
                logger.error("requestPermission: failed — \(error.localizedDescription, privacy: .public)")
            } else {
                logger.info("requestPermission: \(granted ? "granted" : "denied")")
            }
        }
    }

    func send(title: String, body: String, url: URL?) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let url {
            content.userInfo = ["url": url.absoluteString]
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.error("send: delivery failed — \(error.localizedDescription, privacy: .public)")
            } else {
                logger.debug("send: delivered '\(title)' notification")
            }
        }
    }
}
```

#### B.3 Update mock to match protocol

**File:** `Tests/Mocks/MockNotificationService.swift`

```swift
import Foundation
@testable import PRStatusWatcher

final class MockNotificationService: NotificationServiceProtocol {
    var isAvailable: Bool = true
    var permissionGranted: Bool = true
    var sentNotifications: [(title: String, body: String, url: URL?)] = []
    var permissionRequested = false

    func requestPermission() { permissionRequested = true }
    func send(title: String, body: String, url: URL?) {
        sentNotifications.append((title, body, url))
    }
}
```

#### B.4 Add notification service tests

**File:** `Tests/NotificationServiceTests.swift` (new)

Tests verify the protocol contract through the mock and the concrete `NotificationDispatcher`'s observable state.

```swift
import Testing
import Foundation
@testable import PRStatusWatcher

@Suite struct NotificationServiceProtocolTests {

    // MARK: - Mock behavior

    @Test func mockDefaultsToPermissionGranted() {
        let mock = MockNotificationService()
        #expect(mock.permissionGranted)
    }

    @Test func mockTracksPermissionRequest() {
        let mock = MockNotificationService()
        #expect(!mock.permissionRequested)
        mock.requestPermission()
        #expect(mock.permissionRequested)
    }

    @Test func mockRecordsSentNotifications() {
        let mock = MockNotificationService()
        let url = URL(string: "https://github.com/test/repo/pull/1")!
        mock.send(title: "CI Failed", body: "test/repo #1: Fix the thing", url: url)

        #expect(mock.sentNotifications.count == 1)
        #expect(mock.sentNotifications.first?.title == "CI Failed")
        #expect(mock.sentNotifications.first?.url == url)
    }

    @Test func mockPermissionDeniedSimulation() {
        let mock = MockNotificationService()
        mock.permissionGranted = false
        #expect(!mock.permissionGranted)
    }

    // MARK: - Concrete dispatcher observable state

    @Test func dispatcherDefaultsToPermissionNotGranted() {
        let dispatcher = NotificationDispatcher()
        #expect(!dispatcher.permissionGranted)
    }
}
```

### Success Criteria:

#### Automated Verification:
- [x] `swift build` succeeds with zero errors
- [x] `swift test` passes — all existing + new tests green
- [x] `NotificationServiceProtocol` includes `permissionGranted` property
- [x] `NotificationDispatcher` has a logger and logs permission/delivery results
- [x] `MockNotificationService` has a `permissionGranted` property
- [x] `Tests/NotificationServiceTests.swift` exists with 5 test methods

---

## Stream C: Extract Business Logic from Views

### Overview
Extract PR grouping/sorting from `ContentView` into a testable `PRGrouping` utility. Add `toggleRepoCollapsed(_:)` to `PRManager` to replace direct Set mutation from the view. Add comprehensive tests.

**Files modified:** `Sources/ContentView.swift`, `Sources/PRManager.swift`, `Tests/PRManagerTests.swift`
**Files created:** `Sources/PRGrouping.swift`, `Tests/PRGroupingTests.swift`

### Changes Required:

#### C.1 Create `PRGrouping` utility

**File:** `Sources/PRGrouping.swift` (new)

```swift
import Foundation

// MARK: - PR Grouping (Pure Logic)

/// Pure functions for grouping and sorting PRs by repository.
/// Extracted from ContentView for testability.
enum PRGrouping {

    /// Group PRs by repository, sorting repos alphabetically and PRs within
    /// each repo by the tab-appropriate priority.
    ///
    /// - Parameters:
    ///   - prs: The PRs to group (already filtered).
    ///   - isReviews: If true, sorts by review priority first.
    /// - Returns: Array of (repo name, sorted PRs) tuples, sorted by repo name.
    static func grouped(
        prs: [PullRequest],
        isReviews: Bool
    ) -> [(repo: String, prs: [PullRequest])] {
        let dict = Dictionary(grouping: prs, by: \.repoFullName)
        return dict.keys.sorted().map { key in
            (repo: key, prs: (dict[key] ?? []).sorted {
                if isReviews {
                    // Reviews tab: needs-review first, then fewest approvals, then state, then number
                    if $0.reviewSortPriority != $1.reviewSortPriority {
                        return $0.reviewSortPriority < $1.reviewSortPriority
                    }
                    if $0.approvalCount != $1.approvalCount {
                        return $0.approvalCount < $1.approvalCount
                    }
                }
                let lhsPriority = $0.sortPriority
                let rhsPriority = $1.sortPriority
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                return $0.number < $1.number
            })
        }
    }
}
```

#### C.2 Add `toggleRepoCollapsed(_:)` to PRManager

**File:** `Sources/PRManager.swift`

Add after the `collapsedRepos` property (line 23):

```swift
/// Toggle a repo's collapsed state. Call from views instead of mutating
/// `collapsedRepos` directly, to keep mutation logic in the ViewModel.
func toggleRepoCollapsed(_ repo: String) {
    if collapsedRepos.contains(repo) {
        collapsedRepos.remove(repo)
    } else {
        collapsedRepos.insert(repo)
    }
}
```

#### C.3 Update ContentView to use extracted logic

**File:** `Sources/ContentView.swift`

Replace the `groupedPRs` computed property (lines 28-48):

```swift
/// Active PRs grouped by repo, sorted by repo name. Sort within each repo depends on tab.
private var groupedPRs: [(repo: String, prs: [PullRequest])] {
    PRGrouping.grouped(prs: filteredPRs, isReviews: selectedTab == .reviews)
}
```

Replace the `repoHeader` button action (lines 163-174):

```swift
private func repoHeader(repo: String, prs: [PullRequest], isCollapsed: Bool) -> some View {
    Button {
        withAnimation(.easeInOut(duration: 0.2)) {
            manager.toggleRepoCollapsed(repo)
        }
    } label: {
        // ... label unchanged ...
    }
    // ... modifiers unchanged ...
}
```

#### C.4 Add PRGrouping tests

**File:** `Tests/PRGroupingTests.swift` (new)

```swift
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
```

#### C.5 Add toggleRepoCollapsed tests

**File:** `Tests/PRManagerTests.swift`

Add to the existing `PRManagerTests` suite:

```swift
// MARK: - toggleRepoCollapsed

@Test func toggleRepoCollapsedAddsRepo() {
    let manager = makeManager()
    #expect(!manager.collapsedRepos.contains("org/repo"))

    manager.toggleRepoCollapsed("org/repo")

    #expect(manager.collapsedRepos.contains("org/repo"))
}

@Test func toggleRepoCollapsedRemovesRepo() {
    let manager = makeManager()
    manager.collapsedRepos = ["org/repo"]

    manager.toggleRepoCollapsed("org/repo")

    #expect(!manager.collapsedRepos.contains("org/repo"))
}

@Test func toggleRepoCollapsedSavesToStore() {
    let manager = makeManager()
    let initialCount = mockSettings.saveCollapsedReposCallCount

    manager.toggleRepoCollapsed("org/repo")

    #expect(mockSettings.saveCollapsedReposCallCount == initialCount + 1)
}
```

### Success Criteria:

#### Automated Verification:
- [x] `swift build` succeeds with zero errors
- [x] `swift test` passes — all existing + new tests green
- [x] `Sources/PRGrouping.swift` exists with `grouped(prs:isReviews:)` static method
- [x] `ContentView.swift:groupedPRs` body is a single-line call to `PRGrouping.grouped`
- [x] `ContentView.swift` no longer directly mutates `manager.collapsedRepos`
- [x] `PRManager.swift` has a `toggleRepoCollapsed(_:)` method
- [x] `Tests/PRGroupingTests.swift` exists with 9 test methods
- [x] `Tests/PRManagerTests.swift` has 3 new toggle tests (21 total)

---

## Stream D: Documentation Corrections

### Overview
Correct factual errors in the research document and README. Mark already-fixed issues. This stream has zero code changes.

**Files modified:** `thoughts/shared/research/2026-02-11-adversarial-code-review-findings.md`, `README.md`

### Changes Required:

#### D.1 Correct process count in research doc

**File:** `thoughts/shared/research/2026-02-11-adversarial-code-review-findings.md`

**Section 3.1** (line ~253): Change "3 separate `gh` CLI processes" to "2 separate `gh` CLI processes per refresh, plus 1 at init for `currentUser()`". Update the daily calculation: 2 × (86400/60) = 2,880 → correct (the math was already right for 3, change to reflect 2 + note init).

**Section 4.3** (line ~422): Add resolution note:

```markdown
> **Status**: Already fixed during PRManager decomposition (`PollingScheduler.swift`). The extracted `PollingScheduler` uses `do-catch` with explicit `return` on cancellation instead of `try?`.
```

**Step 4 in Recommended Fix Order** (line ~638): Mark as done:

```markdown
**Step 4: Fix `Task.sleep` cancellation** ✅ Done (fixed during PRManager decomposition)
```

#### D.2 Update README Future Improvements

**File:** `README.md`

Remove these items from "Future Improvements > Code Correctness" (they are already done):
- "Store and cancel the polling task" — done during PRManager decomposition (PollingScheduler)
- "Escape GraphQL query parameters" — already implemented (`escapeForGraphQL` at GitHubService.swift:52-56)
- "Handle StatusContext nodes in check parsing" — already implemented (GitHubService.swift:281-295)

Remove these items from "Future Improvements > Code Quality" (they are already done):
- "Add `Codable` conformance to PullRequest" — already has `Codable` (Models.swift:6)
- "Add `Equatable` conformance to PullRequest" — already has `Equatable` (Models.swift:6)
- "Persist collapsed repo state" in UX section — already persisted via SettingsStore

### Success Criteria:

#### Automated Verification:
- [x] No code files changed — documentation only
- [x] Research doc accurately reflects current state
- [x] README Future Improvements lists only genuinely unimplemented items

---

## Parallelization Map

```
┌──────────────────────────────────────────────────────────────────┐
│                    Phase 1: Parallel Execution                   │
│                                                                  │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────┐  ┌──────────┐ │
│  │  Stream A    │  │  Stream B     │  │ Stream C │  │ Stream D │ │
│  │  Codable +   │  │  Notification │  │ View     │  │ Docs     │ │
│  │  Parse Log   │  │  Verification │  │ Extract  │  │ Fixes    │ │
│  │             │  │              │  │          │  │          │ │
│  │ GitHubSvc   │  │ NotifDisp    │  │ Content  │  │ README   │ │
│  │ GHSvcTests  │  │ NotifProto   │  │ PRMgr    │  │ Research │ │
│  │ GQLResp     │  │ MockNotif    │  │ PRMgrTest│  │          │ │
│  │ (new)       │  │ NotifTests   │  │ Grouping │  │          │ │
│  │             │  │ (new)        │  │ (new)    │  │          │ │
│  │             │  │              │  │ GrpTests │  │          │ │
│  │             │  │              │  │ (new)    │  │          │ │
│  └─────────────┘  └──────────────┘  └──────────┘  └──────────┘ │
│  ~15 new tests     ~5 new tests     ~12 new tests   0 tests    │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│                 Phase 2: Integration Verification                │
│                                                                  │
│  swift build          # Zero errors                              │
│  swift test           # All ~162 tests pass                      │
│  swiftlint lint       # No new violations                        │
│  Manual smoke test    # App works correctly                      │
└──────────────────────────────────────────────────────────────────┘
```

**File conflict matrix** (✓ = stream touches file):

| File | A | B | C | D |
|------|---|---|---|---|
| `Sources/GitHubService.swift` | ✓ | | | |
| `Sources/GraphQLResponse.swift` (new) | ✓ | | | |
| `Tests/GitHubServiceParsingTests.swift` | ✓ | | | |
| `Sources/NotificationDispatcher.swift` | | ✓ | | |
| `Sources/NotificationServiceProtocol.swift` | | ✓ | | |
| `Tests/Mocks/MockNotificationService.swift` | | ✓ | | |
| `Tests/NotificationServiceTests.swift` (new) | | ✓ | | |
| `Sources/ContentView.swift` | | | ✓ | |
| `Sources/PRManager.swift` | | | ✓ | |
| `Tests/PRManagerTests.swift` | | | ✓ | |
| `Sources/PRGrouping.swift` (new) | | | ✓ | |
| `Tests/PRGroupingTests.swift` (new) | | | ✓ | |
| `README.md` | | | | ✓ |
| Research doc | | | | ✓ |

**Zero overlapping cells.** All streams are safe to run concurrently.

---

## Test Summary

| Stream | New Tests | Updated Tests | Files |
|--------|-----------|---------------|-------|
| A: Codable + Parse Logging | 15 (StatusContext, GraphQL decode, convertNode edge cases) | 16 (rewritten for typed structs) | `GitHubServiceParsingTests.swift` |
| B: Notification Verification | 5 (protocol contract, mock behavior, dispatcher state) | 0 | `NotificationServiceTests.swift` (new) |
| C: View Logic Extraction | 12 (grouping, sorting, toggle) | 0 | `PRGroupingTests.swift` (new), `PRManagerTests.swift` |
| **Total** | **~32** | **16** | |

**Before:** 137 tests across 7 files
**After:** ~169 tests across 9 files

---

## References

- Original findings: `thoughts/shared/research/2026-02-11-adversarial-code-review-findings.md`
- P0 bugfixes (done): `thoughts/shared/plans/2026-02-11-p0-bugfixes.md`
- PRManager decomposition (done): `thoughts/shared/plans/2026-02-11-prmanager-decomposition.md`
- Swift Testing migration (done): `thoughts/shared/plans/2026-02-11-swift-testing-migration.md`
