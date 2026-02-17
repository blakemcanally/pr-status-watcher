# P1 High-Impact Fixes Implementation Plan

## Overview

Five P1 issues from the adversarial code review (`thoughts/shared/research/2026-02-11-adversarial-code-review-findings.md`) require fixes to improve concurrency safety, performance, data completeness, and error handling in `GitHubService` and `PRManager`.

| # | Issue | File(s) | Severity |
|---|-------|---------|----------|
| 1 | `@unchecked Sendable` bypasses concurrency checks | `GitHubService.swift:7` | P1 |
| 2 | Menu bar image regenerated on every `@Published` change | `PRManager.swift:108-148` | P1 |
| 3 | No GraphQL pagination — hard `first: 100` cap | `GitHubService.swift:63, 84` | P1 |
| 4 | GraphQL `errors` field ignored — rate limits/schema errors lost | `GitHubService.swift:118-126` | P1 |
| 5 | Poor error handling: `currentUser()`, `process.run()`, pipe reads | `GitHubService.swift:25-37, 379-383, 391-398` | P1 |

## Current State Analysis

### Issue 1: `@unchecked Sendable`

```swift
// Sources/GitHubService.swift:7
final class GitHubService: GitHubServiceProtocol, @unchecked Sendable {
```

`GitHubService` has a single stored property: `private let ghPath: String`. Since `String` is `Sendable` and the property is `let`, the class is *genuinely* `Sendable` — the `@unchecked` annotation is unnecessary. The `run()` method only creates local variables (`Process`, `Pipe`, `DispatchGroup`, `DispatchSemaphore`); there is no shared mutable state between concurrent calls.

The `@unchecked` annotation is dangerous because it permanently opts the class out of compiler verification. If mutable state is added in the future, the compiler won't warn.

### Issue 2: Menu Bar Image Recomputation

```swift
// Sources/PRManager.swift:108-148
var menuBarImage: NSImage {
    let symbolName = overallStatusIcon
    // ... creates new NSImage every access
}
```

`menuBarImage` is a computed property accessed from `App.swift:45`:
```swift
Image(nsImage: manager.menuBarImage)
```

Because `PRManager` is `@ObservableObject`, *any* `@Published` property change triggers SwiftUI body re-evaluation, which calls `menuBarImage`, which allocates a new `NSImage` with drawing operations. Changes to `isRefreshing`, `lastError`, `filterSettings`, etc. all cause unnecessary image regeneration even when the icon inputs (`overallStatusIcon` and `hasFailure`) haven't changed.

### Issue 3: No GraphQL Pagination

```swift
// Sources/GitHubService.swift:63
search(query: "\(escapedQuery)", type: ISSUE, first: 100) {
```

Hard cap of 100 results with no `pageInfo` or cursor handling. Users in large orgs with >100 open PRs get silently truncated data. Similarly, `contexts(first: 100)` on line 84 caps check contexts with no truncation warning.

### Issue 4: GraphQL `errors` Field Ignored

```swift
// Sources/GitHubService.swift:118-126
guard let data = stdout.data(using: .utf8),
      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let dataDict = json["data"] as? [String: Any],
      let search = dataDict["search"] as? [String: Any],
      let nodes = search["nodes"] as? [[String: Any]]
else {
    throw GHError.invalidJSON
}
```

GitHub GraphQL responses can include `{"errors": [...], "data": null}` for rate limits, authentication failures, and schema errors. The current code falls through to `GHError.invalidJSON` and the actual error message is lost.

### Issue 5: Poor Error Handling in `GitHubService`

**5a. `currentUser()` (line 27):**
```swift
guard let (out, stderr, exit) = try? run(["api", "user", "--jq", ".login"]) else {
    logger.error("currentUser: gh cli failed to launch")
    return nil
}
```
`try?` discards the actual error. Authentication failures, timeouts, and network errors all produce the same "cli failed to launch" log.

**5b. `process.run()` catch (line 379-383):**
```swift
do {
    try process.run()
} catch {
    throw GHError.cliNotFound
}
```
All `Process.run()` errors (permission denied, resource exhaustion, file not found) are mapped to `cliNotFound`. The actual error is discarded.

**5c. `readDataToEndOfFile` pipe safety (line 391-398):**
The write ends of the pipes are not closed in the parent process after `process.run()`. While this works in practice, leaving the parent's write fds open means `readDataToEndOfFile()` could hang if the child process crashes before writing (the parent still holds a reference to the write end, preventing EOF).

### Key Discoveries

- `GitHubService` has *zero* mutable stored state — `ghPath` is `let`. Removing `@unchecked Sendable` is a safe one-line change.
- `menuBarImage` inputs are `overallStatusIcon` (derived from `pullRequests`) and `hasFailure` (also derived from `pullRequests`). They only change when `pullRequests` changes — not on `isRefreshing`, `lastError`, etc.
- The `MockGitHubService` in tests also uses `@unchecked Sendable` (line 4). It has mutable state, so `@unchecked` is actually needed there.
- The `GitHubServiceProtocol` requires `Sendable` conformance, so any conforming type must be Sendable.
- Pagination requires adding `pageInfo { hasNextPage endCursor }` to the GraphQL query and looping with an `after:` cursor.
- The `fetchPRs()` method is `private`, so pagination can be added without changing the public API.

## Desired End State

1. **`@unchecked Sendable` removed** from `GitHubService`. The compiler verifies Sendability statically.
2. **Menu bar image cached** as a `@Published` stored property, only regenerated when `overallStatusIcon` or `hasFailure` actually changes.
3. **GraphQL responses paginated** with cursor-based fetching. Users with >100 PRs see all of them. Check context truncation is logged.
4. **GraphQL `errors` field inspected** before parsing `data`. Rate limits and schema errors surface as `GHError.apiError` with the actual message.
5. **Error handling improved**: `currentUser()` logs specific errors; `process.run()` preserves error details via a new `GHError.processLaunchFailed` case; pipe write fds closed after process launch.
6. **Comprehensive test coverage** for all changes.

## What We're NOT Doing

- Not converting `GitHubService` to an actor (unnecessary — no mutable state)
- Not replacing `gh` CLI with `URLSession` (separate performance initiative)
- Not combining the two GraphQL queries into one (separate optimization)
- Not adding retry logic or exponential backoff
- Not changing the `GitHubServiceProtocol` API surface (pagination is internal to `fetchPRs`)

---

## Phase 1: GitHubService Error Handling Hardening

**Goal:** Surface real error information instead of discarding it. Add a new error case for process launch failures. Close pipe fds properly.

### 1.1 Add `GHError.processLaunchFailed` case

**File:** `Sources/GitHubService.swift`

Add a new case to `GHError` that preserves the underlying error message:

```swift
enum GHError: LocalizedError {
    case cliNotFound
    case apiError(String)
    case invalidJSON
    case timeout
    case processLaunchFailed(String)  // NEW

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            return "GitHub CLI (gh) not found — install it with: brew install gh"
        case .apiError(let msg):
            let trimmed = msg.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "GitHub API error" : trimmed
        case .invalidJSON:
            return "Invalid response from GitHub API"
        case .timeout:
            return "GitHub CLI timed out — check your network connection"
        case .processLaunchFailed(let detail):
            return "Failed to launch GitHub CLI: \(detail)"
        }
    }
}
```

### 1.2 Surface GraphQL `errors` field in `fetchPRs()`

**File:** `Sources/GitHubService.swift`, `fetchPRs()` method (lines 118-126)

Replace the single `guard` chain with two steps — first parse the JSON and check for errors, then extract the data:

```swift
guard let data = stdout.data(using: .utf8),
      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
else {
    logger.error("fetchPRs: failed to parse JSON response")
    throw GHError.invalidJSON
}

// Surface GraphQL errors (rate limits, schema errors, auth failures)
if let errors = json["errors"] as? [[String: Any]],
   let firstError = errors.first,
   let message = firstError["message"] as? String {
    logger.error("fetchPRs: GraphQL error: \(message, privacy: .public)")
    throw GHError.apiError(message)
}

guard let dataDict = json["data"] as? [String: Any],
      let search = dataDict["search"] as? [String: Any],
      let nodes = search["nodes"] as? [[String: Any]]
else {
    logger.error("fetchPRs: unexpected JSON structure")
    throw GHError.invalidJSON
}
```

### 1.3 Fix `currentUser()` to log specific errors

**File:** `Sources/GitHubService.swift`, `currentUser()` method (lines 25-37)

Replace `try?` with a `do-catch` that logs the actual error:

```swift
func currentUser() -> String? {
    logger.info("currentUser: resolving via gh api user")
    let out: String
    let stderr: String
    let exit: Int32
    do {
        (out, stderr, exit) = try run(["api", "user", "--jq", ".login"])
    } catch let error as GHError {
        logger.error("currentUser: \(error.localizedDescription, privacy: .public)")
        return nil
    } catch {
        logger.error("currentUser: unexpected error: \(error.localizedDescription, privacy: .public)")
        return nil
    }
    if exit != 0 {
        logger.error("currentUser: exit=\(exit), stderr=\(stderr.prefix(200), privacy: .public)")
    }
    guard exit == 0 else { return nil }
    let username = out.trimmingCharacters(in: .whitespacesAndNewlines)
    return username.isEmpty ? nil : username
}
```

### 1.4 Preserve `process.run()` error details

**File:** `Sources/GitHubService.swift`, `run()` method (lines 379-383)

Replace the generic `cliNotFound` with the new `processLaunchFailed` case:

```swift
do {
    try process.run()
} catch {
    logger.error("run: process launch failed: \(error.localizedDescription, privacy: .public)")
    throw GHError.processLaunchFailed(error.localizedDescription)
}
```

### 1.5 Close pipe write ends after process launch

**File:** `Sources/GitHubService.swift`, `run()` method, immediately after `try process.run()`

Close the parent process's write ends of the pipes to ensure proper EOF signaling:

```swift
do {
    try process.run()
} catch {
    logger.error("run: process launch failed: \(error.localizedDescription, privacy: .public)")
    throw GHError.processLaunchFailed(error.localizedDescription)
}

// Close write ends in parent to ensure EOF when child exits
outPipe.fileHandleForWriting.closeFile()
errPipe.fileHandleForWriting.closeFile()
```

### 1.6 Log dropped PR nodes

**File:** `Sources/GitHubService.swift`, `fetchPRs()` method (lines 128-130)

Add a debug log when a node fails to parse:

```swift
let prs = nodes.compactMap { node -> PullRequest? in
    guard let pr = parsePRNode(node) else {
        logger.debug("fetchPRs: skipping malformed PR node: \(String(describing: node["number"]))")
        return nil
    }
    return pr
}
```

### 1.7 Add test coverage

**File:** `Tests/GitHubServiceParsingTests.swift`

Add tests for the new error case and GraphQL error surfacing. Since `fetchPRs()` is private, we test through the public methods via `PRManagerTests` and directly test the new `GHError` case:

| Test | Setup | Expected |
|------|-------|----------|
| `processLaunchFailedErrorDescription` | Create `GHError.processLaunchFailed("Permission denied")` | `errorDescription` contains "Permission denied" |
| `graphQLErrorSurfacedToUser` | Mock throws `GHError.apiError("API rate limit exceeded")` | `lastError` contains "API rate limit exceeded" |
| `invalidJSONErrorSurfacedToUser` | Mock throws `GHError.invalidJSON` | `lastError` contains "Invalid response" |
| `processLaunchFailedSurfacedToUser` | Mock throws `GHError.processLaunchFailed("Not found")` | `lastError` contains "Failed to launch" |

**File:** `Tests/GitHubServiceParsingTests.swift` — new section for `GHError` descriptions:

```swift
// MARK: - GHError Descriptions

@Suite struct GHErrorTests {
    @Test func cliNotFoundDescription() {
        let error = GHError.cliNotFound
        #expect(error.errorDescription?.contains("not found") == true)
    }

    @Test func apiErrorDescription() {
        let error = GHError.apiError("rate limit exceeded")
        #expect(error.errorDescription?.contains("rate limit exceeded") == true)
    }

    @Test func apiErrorEmptyMessageFallback() {
        let error = GHError.apiError("  ")
        #expect(error.errorDescription == "GitHub API error")
    }

    @Test func invalidJSONDescription() {
        let error = GHError.invalidJSON
        #expect(error.errorDescription?.contains("Invalid response") == true)
    }

    @Test func timeoutDescription() {
        let error = GHError.timeout
        #expect(error.errorDescription?.contains("timed out") == true)
    }

    @Test func processLaunchFailedDescription() {
        let error = GHError.processLaunchFailed("Permission denied")
        #expect(error.errorDescription?.contains("Permission denied") == true)
        #expect(error.errorDescription?.contains("Failed to launch") == true)
    }
}
```

**File:** `Tests/PRManagerTests.swift` — new section for error propagation:

```swift
// MARK: - Error Type Propagation

@Test func graphQLApiErrorSurfaced() async {
    mockService.myPRsResult = .failure(GHError.apiError("API rate limit exceeded"))
    mockService.reviewPRsResult = .success([])

    let manager = makeManager()
    manager.ghUser = "testuser"
    await manager.refreshAll()

    #expect(manager.lastError?.contains("rate limit exceeded") == true)
}

@Test func processLaunchFailedSurfaced() async {
    mockService.myPRsResult = .failure(GHError.processLaunchFailed("Permission denied"))
    mockService.reviewPRsResult = .success([])

    let manager = makeManager()
    manager.ghUser = "testuser"
    await manager.refreshAll()

    #expect(manager.lastError?.contains("Failed to launch") == true)
}

@Test func invalidJSONErrorSurfaced() async {
    mockService.myPRsResult = .failure(GHError.invalidJSON)
    mockService.reviewPRsResult = .success([])

    let manager = makeManager()
    manager.ghUser = "testuser"
    await manager.refreshAll()

    #expect(manager.lastError?.contains("Invalid response") == true)
}
```

### Success Criteria

#### Automated Verification:
- [x] Build succeeds: `swift build 2>&1 | tail -5`
- [x] All tests pass: `swift test 2>&1 | tail -20`
- [x] SwiftLint passes: `swiftlint lint --strict` (pre-existing violations only)

#### Manual Verification:
- [ ] Normal refresh cycle still works with the new error handling
- [ ] Disconnect network, trigger refresh → error message shows the actual error, not just "Invalid response"

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 2: Remove `@unchecked Sendable`

**Goal:** Remove the `@unchecked` annotation from `GitHubService` so the compiler statically verifies Sendability. Leave `MockGitHubService` as `@unchecked Sendable` (it has mutable state by design).

### 2.1 Remove `@unchecked` from `GitHubService`

**File:** `Sources/GitHubService.swift:7`

Change:
```swift
final class GitHubService: GitHubServiceProtocol, @unchecked Sendable {
```
To:
```swift
final class GitHubService: GitHubServiceProtocol, Sendable {
```

**Why this works:** `GitHubService` is `final` with a single stored property `let ghPath: String`. `String` is `Sendable`, the property is immutable, and the class is final (no subclasses can add mutable state). The Swift compiler can statically verify this.

### 2.2 Verify MockGitHubService stays `@unchecked`

**File:** `Tests/Mocks/MockGitHubService.swift:4`

`MockGitHubService` has mutable `var` properties (`currentUserResult`, `myPRsResult`, etc.) and call counters. It *requires* `@unchecked Sendable` because it's intentionally mutable for test configuration. No change needed — just verify it still compiles.

### 2.3 Add a code comment explaining the Sendable conformance

**File:** `Sources/GitHubService.swift:7`

```swift
/// Thread-safe: all stored properties are `let` and `Sendable`.
/// If mutable state is ever added, convert to `actor` instead of using `@unchecked`.
final class GitHubService: GitHubServiceProtocol, Sendable {
```

### Success Criteria

#### Automated Verification:
- [x] Build succeeds with no Sendable warnings: `swift build 2>&1 | grep -i sendable` (should show no warnings)
- [x] All tests pass: `swift test 2>&1 | tail -20`

#### Manual Verification:
- [ ] App launches and refreshes normally

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 3: GraphQL Pagination

**Goal:** Replace the hard `first: 100` cap with cursor-based pagination that fetches all pages. Log when check contexts are truncated.

### 3.1 Add `pageInfo` to the GraphQL query and loop until all pages are fetched

**File:** `Sources/GitHubService.swift`, `fetchPRs()` method

Restructure `fetchPRs()` to loop with a cursor:

```swift
private func fetchPRs(searchQuery: String) throws -> [PullRequest] {
    let escapedQuery = escapeForGraphQL(searchQuery)
    var allPRs: [PullRequest] = []
    var cursor: String? = nil
    let pageSize = 100

    repeat {
        let afterClause = cursor.map { #", after: "\#($0)""# } ?? ""
        let query = """
        query {
          search(query: "\(escapedQuery)", type: ISSUE, first: \(pageSize)\(afterClause)) {
            pageInfo {
              hasNextPage
              endCursor
            }
            nodes {
              ... on PullRequest {
                number
                title
                author { login }
                isDraft
                state
                url
                repository { nameWithOwner }
                reviewDecision
                mergeable
                mergeQueueEntry { position }
                reviews(states: APPROVED, first: 0) { totalCount }
                headRefOid
                headRefName
                commits(last: 1) {
                  nodes {
                    commit {
                      statusCheckRollup {
                        state
                        contexts(first: 100) {
                          totalCount
                          nodes {
                            ... on CheckRun {
                              name
                              status
                              conclusion
                              detailsUrl
                            }
                            ... on StatusContext {
                              context
                              state
                              targetUrl
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        """

        logger.info("fetchPRs: query=\(searchQuery.prefix(80), privacy: .public), cursor=\(cursor ?? "nil", privacy: .public)")
        let (stdout, stderr, exit) = try run(["api", "graphql", "-f", "query=\(query)"])

        guard exit == 0 else {
            logger.error("fetchPRs: exit=\(exit), stderr=\(stderr.prefix(500), privacy: .public)")
            throw GHError.apiError(stderr.isEmpty ? stdout : stderr)
        }

        guard let data = stdout.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            logger.error("fetchPRs: failed to parse JSON response")
            throw GHError.invalidJSON
        }

        // Surface GraphQL errors (rate limits, schema errors, auth failures)
        if let errors = json["errors"] as? [[String: Any]],
           let firstError = errors.first,
           let message = firstError["message"] as? String {
            logger.error("fetchPRs: GraphQL error: \(message, privacy: .public)")
            throw GHError.apiError(message)
        }

        guard let dataDict = json["data"] as? [String: Any],
              let search = dataDict["search"] as? [String: Any],
              let nodes = search["nodes"] as? [[String: Any]]
        else {
            logger.error("fetchPRs: unexpected JSON structure")
            throw GHError.invalidJSON
        }

        let prs = nodes.compactMap { node -> PullRequest? in
            guard let pr = parsePRNode(node) else {
                logger.debug("fetchPRs: skipping malformed PR node: \(String(describing: node["number"]))")
                return nil
            }
            return pr
        }
        allPRs.append(contentsOf: prs)

        logger.info("fetchPRs: parsed \(prs.count) PRs from \(nodes.count) nodes (page total: \(allPRs.count))")

        // Check for more pages
        let pageInfo = search["pageInfo"] as? [String: Any]
        let hasNextPage = pageInfo?["hasNextPage"] as? Bool ?? false
        cursor = hasNextPage ? (pageInfo?["endCursor"] as? String) : nil
    } while cursor != nil

    return allPRs
}
```

### 3.2 Log check context truncation

**File:** `Sources/GitHubService.swift`, `extractRollupData()` method

After extracting `totalCount` and `contextNodes`, log when truncation occurs:

```swift
func extractRollupData(from node: [String: Any]) -> RollupData? {
    guard let commits = node["commits"] as? [String: Any],
          let commitNodes = commits["nodes"] as? [[String: Any]],
          let firstCommit = commitNodes.first,
          let commit = firstCommit["commit"] as? [String: Any],
          let rollup = commit["statusCheckRollup"] as? [String: Any],
          let contexts = rollup["contexts"] as? [String: Any],
          let totalCount = contexts["totalCount"] as? Int,
          let contextNodes = contexts["nodes"] as? [[String: Any]]
    else { return nil }

    if totalCount > contextNodes.count {
        logger.warning("extractRollupData: check contexts truncated — \(contextNodes.count)/\(totalCount) fetched")
    }

    return RollupData(rollup: rollup, totalCount: totalCount, contextNodes: contextNodes)
}
```

### 3.3 Add pagination safety limit

To prevent runaway pagination (e.g., a user with thousands of PRs causing dozens of API calls), add a maximum page count:

```swift
private static let maxPages = 10  // 1000 PRs max
```

And in the loop:
```swift
var pageCount = 0
repeat {
    pageCount += 1
    if pageCount > Self.maxPages {
        logger.warning("fetchPRs: reached max page limit (\(Self.maxPages)), stopping pagination")
        break
    }
    // ... existing loop body
} while cursor != nil
```

### 3.4 Add test coverage

Testing pagination requires testing through `PRManager` since `fetchPRs()` is private. We simulate paginated results by having the mock return large result sets:

**File:** `Tests/PRManagerTests.swift` — new section:

```swift
// MARK: - Large Result Sets

@Test func refreshAllHandlesLargeResultSet() async {
    // Simulate a user with >100 PRs (post-pagination, all results returned)
    let prs = (1...150).map { PullRequest.fixture(number: $0) }
    mockService.myPRsResult = .success(prs)
    mockService.reviewPRsResult = .success([])

    let manager = makeManager()
    manager.ghUser = "testuser"
    await manager.refreshAll()

    #expect(manager.pullRequests.count == 150)
    #expect(manager.lastError == nil)
}
```

**File:** `Tests/GitHubServiceParsingTests.swift` — test `extractRollupData` truncation detection:

```swift
// MARK: - extractRollupData

@Test func extractRollupDataValid() {
    let node: [String: Any] = [
        "commits": [
            "nodes": [[
                "commit": [
                    "statusCheckRollup": [
                        "state": "SUCCESS",
                        "contexts": [
                            "totalCount": 2,
                            "nodes": [
                                ["status": "COMPLETED", "conclusion": "SUCCESS", "name": "build"],
                                ["status": "COMPLETED", "conclusion": "SUCCESS", "name": "test"],
                            ]
                        ]
                    ]
                ]
            ]]
        ]
    ]
    let result = service.extractRollupData(from: node)
    #expect(result != nil)
    #expect(result?.totalCount == 2)
    #expect(result?.contextNodes.count == 2)
}

@Test func extractRollupDataMissingRollup() {
    let node: [String: Any] = [
        "commits": ["nodes": [["commit": [:]]]]
    ]
    #expect(service.extractRollupData(from: node) == nil)
}

@Test func extractRollupDataEmptyCommits() {
    let node: [String: Any] = ["commits": ["nodes": []]]
    #expect(service.extractRollupData(from: node) == nil)
}
```

### Success Criteria

#### Automated Verification:
- [x] Build succeeds: `swift build 2>&1 | tail -5`
- [x] All tests pass: `swift test 2>&1 | tail -20`
- [x] SwiftLint passes: `swiftlint lint --strict` (pre-existing violations only)

#### Manual Verification:
- [ ] Refresh works normally for accounts with <100 PRs (single page, no behavior change)
- [ ] If testing with an account with >100 PRs, verify all PRs appear
- [ ] Check Console.app for pagination log messages during refresh

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 4: Menu Bar Image Caching

**Goal:** Cache the menu bar `NSImage` and only regenerate it when the visual inputs (`overallStatusIcon`, `hasFailure`) actually change. Eliminate unnecessary `NSImage` allocations triggered by unrelated `@Published` changes.

### 4.1 Convert `menuBarImage` from computed to cached `@Published`

**File:** `Sources/PRManager.swift`

Replace the computed property with a cached `@Published` property and a private rebuild method:

```swift
// MARK: - Menu Bar Icon

/// Cached menu bar image — only regenerated when visual inputs change.
@Published private(set) var menuBarImage: NSImage = NSImage(
    systemSymbolName: "arrow.triangle.pull",
    accessibilityDescription: "PR Status"
) ?? NSImage()

/// Tracks the last inputs used to build the cached image, to avoid redundant rebuilds.
private var lastMenuBarIcon: String = ""
private var lastMenuBarHasFailure: Bool = false

/// Rebuild the menu bar image if the visual inputs have changed.
private func updateMenuBarImageIfNeeded() {
    let icon = overallStatusIcon
    let failure = hasFailure
    guard icon != lastMenuBarIcon || failure != lastMenuBarHasFailure else { return }
    lastMenuBarIcon = icon
    lastMenuBarHasFailure = failure
    menuBarImage = buildMenuBarImage(icon: icon, hasFailure: failure)
}

/// Build the menu bar NSImage for a given icon and failure state.
private func buildMenuBarImage(icon: String, hasFailure: Bool) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
    let base = NSImage(systemSymbolName: icon, accessibilityDescription: "PR Status")?
        .withSymbolConfiguration(config) ?? NSImage()

    guard hasFailure else {
        if let img = base.copy() as? NSImage {
            img.isTemplate = true
            return img
        }
        return base
    }

    // Composite the icon with a red badge dot
    let size = NSSize(width: 20, height: 16)
    let image = NSImage(size: size, flipped: false) { rect in
        let iconSize = base.size
        let iconOrigin = NSPoint(
            x: 0,
            y: (rect.height - iconSize.height) / 2
        )
        base.draw(at: iconOrigin, from: .zero, operation: .sourceOver, fraction: 1.0)

        let dotSize: CGFloat = 5
        let dotRect = NSRect(
            x: iconSize.width - 2,
            y: rect.height - dotSize - 1,
            width: dotSize,
            height: dotSize
        )
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        return true
    }
    image.isTemplate = false
    return image
}
```

### 4.2 Call `updateMenuBarImageIfNeeded()` after data changes

**File:** `Sources/PRManager.swift`, `refreshAll()` method

Add a call to `updateMenuBarImageIfNeeded()` at the end of `refreshAll()`, just before or after `hasCompletedInitialLoad = true`:

```swift
// At the end of refreshAll(), after processing both myPRs and revPRs:
updateMenuBarImageIfNeeded()
hasCompletedInitialLoad = true
```

Also call it during init, after the initial image default is set but before `refreshAll()` returns. Since the initial `pullRequests` is empty, the default image will use `"arrow.triangle.pull"` which matches our initial state.

### 4.3 No change needed in `App.swift`

`App.swift:45` already reads:
```swift
Image(nsImage: manager.menuBarImage)
```

Since `menuBarImage` is now a `@Published` property, SwiftUI will automatically re-render when it changes. The change is fully backward-compatible.

### 4.4 Add test coverage

**File:** `Tests/PRManagerTests.swift` — new section:

```swift
// MARK: - Menu Bar Image Caching

@Test func menuBarImageUpdatesOnPullRequestsChange() async {
    let manager = makeManager()
    manager.ghUser = "testuser"

    // Initial state: no PRs
    let initialImage = manager.menuBarImage

    // Add a failing PR
    mockService.myPRsResult = .success([
        PullRequest.fixture(number: 1, ciStatus: .failure),
    ])
    mockService.reviewPRsResult = .success([])
    await manager.refreshAll()

    // Image should have changed (now has failure badge)
    #expect(manager.menuBarImage !== initialImage)
}

@Test func menuBarImageStableWhenStatusUnchanged() async {
    let manager = makeManager()
    manager.ghUser = "testuser"

    // First refresh with success PRs
    mockService.myPRsResult = .success([
        PullRequest.fixture(number: 1, ciStatus: .success),
    ])
    mockService.reviewPRsResult = .success([])
    await manager.refreshAll()

    let imageAfterFirst = manager.menuBarImage

    // Second refresh with same status
    await manager.refreshAll()

    // Image should be the same object (not regenerated)
    #expect(manager.menuBarImage === imageAfterFirst)
}
```

### Success Criteria

#### Automated Verification:
- [x] Build succeeds: `swift build 2>&1 | tail -5`
- [x] All tests pass: `swift test 2>&1 | tail -20`
- [x] SwiftLint passes: `swiftlint lint --strict` (pre-existing violations only)

#### Manual Verification:
- [ ] Menu bar icon displays correctly with no PRs (pull arrow)
- [ ] Menu bar icon updates when CI fails (red dot badge appears)
- [ ] Menu bar icon updates when all checks pass (green checkmark)
- [ ] Icon does NOT flicker during refresh (no unnecessary rebuilds when clicking refresh)

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 5: Update Documentation

### 5.1 Update README `Future Improvements` section

**File:** `README.md`

Remove items that are now addressed by this plan and the P0 plan. Mark completed items:

- Remove "Escape GraphQL query parameters" (already done)
- Remove "Handle StatusContext nodes in check parsing" (already done)
- Remove "Store and cancel the polling task" (already done — `PollingScheduler`)
- Update Architecture section to reflect extracted types (`PollingScheduler`, `StatusChangeDetector`, `PRStatusSummary`, etc.)

### 5.2 Update adversarial code review findings

**File:** `thoughts/shared/research/2026-02-11-adversarial-code-review-findings.md`

Add status notes to the resolved issues:

- Section 1.6 (`@unchecked Sendable`): Mark as resolved
- Section 3.2 (menu bar image): Mark as resolved
- Section 3.7 (no pagination): Mark as resolved
- Section 4.4 (`currentUser()` error handling): Mark as resolved
- Section 4.6 (GraphQL errors ignored): Mark as resolved
- Section 4.8 (`process.run()` error overwritten): Mark as resolved
- Section 4.9 (`FileHandle` pipe safety): Mark as resolved
- Section 4.5 (malformed PR nodes dropped): Mark as resolved

Update the Recommended Fix Order to mark Steps 5, 6, 12, 13 as done.

### Success Criteria

#### Automated Verification:
- [x] No broken markdown links or formatting

#### Manual Verification:
- [ ] README accurately reflects current state
- [ ] Research doc status notes are accurate

---

## Implementation Order

| Step | Phase | Est. Lines Changed | Risk |
|------|-------|--------------------|------|
| 1 | 1.1 — `GHError.processLaunchFailed` | ~8 | Low — additive |
| 2 | 1.2 — GraphQL errors field | ~15 | Low — existing code path |
| 3 | 1.3 — `currentUser()` do-catch | ~12 | Low — same behavior, better logging |
| 4 | 1.4 — `process.run()` error details | ~3 | Low — isolated |
| 5 | 1.5 — Pipe write fd cleanup | ~4 | Low — standard practice |
| 6 | 1.6 — Log dropped PR nodes | ~5 | Low — additive |
| 7 | 1.7 — Tests | ~50 | Low |
| 8 | 2.1-2.3 — Remove `@unchecked Sendable` | ~3 | Low — verified by compiler |
| 9 | 3.1 — Pagination loop | ~30 | Medium — changes fetch logic |
| 10 | 3.2 — Context truncation logging | ~3 | Low — additive |
| 11 | 3.3 — Pagination safety limit | ~6 | Low — safety guard |
| 12 | 3.4 — Pagination tests | ~40 | Low |
| 13 | 4.1 — Image caching | ~50 | Medium — replaces computed property |
| 14 | 4.2 — Call site | ~2 | Low |
| 15 | 4.4 — Image caching tests | ~30 | Low |
| 16 | 5.1-5.2 — Documentation | ~30 | Low — docs only |

**Total estimated:** ~290 lines changed/added across source, tests, and docs.

---

## Testing Strategy

### Unit Tests (new, per phase):

**Phase 1:**
- `GHError.processLaunchFailed` error description
- All `GHError` case descriptions (comprehensive)
- GraphQL API error propagation through `PRManager`
- Process launch failure propagation through `PRManager`
- Invalid JSON error propagation through `PRManager`

**Phase 2:**
- Compilation is the test — compiler verifies Sendable conformance

**Phase 3:**
- `extractRollupData` valid input
- `extractRollupData` missing rollup
- `extractRollupData` empty commits
- Large result set handling (150+ PRs)

**Phase 4:**
- Image changes when status changes (failure → success)
- Image is stable (same object) when status unchanged
- Image correct on init (default icon)

### Existing Tests (must still pass):
- `FilterSettingsTests` (24 tests)
- `GitHubServiceParsingTests` (18 tests)
- `PRManagerTests` (17 tests)
- `PRStatusSummaryTests` (17 tests)
- `PullRequestTests` (13 tests)
- `SettingsStoreTests` (13 tests)
- `StatusChangeDetectorTests` (14 tests)

### Manual Testing Steps:
1. Launch app, verify menu bar icon shows correctly
2. Wait for refresh, verify PRs load
3. Check Console.app for improved error messages
4. Disconnect network, verify error surfaces with specific message
5. Reconnect, verify recovery
6. Verify icon doesn't flicker during refresh cycle

## Performance Considerations

- **Pagination adds latency** for users with >100 PRs (multiple API calls per refresh). The safety limit of 10 pages (1000 PRs) prevents runaway requests. Most users will see zero change (single page).
- **Image caching eliminates** ~4-6 unnecessary `NSImage` allocations per refresh cycle (one for each `@Published` property change that triggers SwiftUI re-evaluation).
- **Pipe fd cleanup** has negligible performance impact but prevents a theoretical hang condition.

## References

- Adversarial code review: `thoughts/shared/research/2026-02-11-adversarial-code-review-findings.md`
- P0 bugfix plan (predecessor): `thoughts/shared/plans/2026-02-11-p0-bugfixes.md`
- Architecture research: `thoughts/shared/research/2026-02-10-architecture-and-design-patterns.md`
- PRManager decomposition plan: `thoughts/shared/plans/2026-02-11-prmanager-decomposition.md`
