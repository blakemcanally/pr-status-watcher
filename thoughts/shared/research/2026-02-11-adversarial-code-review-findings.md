---
date: 2026-02-11T14:35:57+0000
researcher: Blake McAnally
git_commit: 1ef6c9d6928fb6b97e4eda3f57195801967d2299
branch: main
repository: pr-status-watcher
topic: "Adversarial Code Review: Maintainability, Test Coverage, Performance, and Error Handling"
tags: [research, code-review, maintainability, testing, performance, error-handling, refactoring]
status: complete
last_updated: 2026-02-11
last_updated_by: Blake McAnally
---

# Research: Adversarial Code Review Findings

**Date**: 2026-02-11T14:35:57+0000
**Researcher**: Blake McAnally
**Git Commit**: 1ef6c9d6928fb6b97e4eda3f57195801967d2299
**Branch**: main
**Repository**: pr-status-watcher

## Research Question

Comprehensive adversarial code review of the entire PR Status Watcher codebase, identifying fixable issues across four dimensions: maintainability, test coverage, performance, and error handling/logging.

## Summary

The codebase is a ~2,362-line Swift/SwiftUI macOS menu bar app with 8 source files and 2 test files. It works well as a personal tool but has structural issues that will compound as features are added. The review identified **1 critical**, **10 high**, **20 medium**, and **16 low** severity issues across all four review dimensions.

The highest-leverage improvements are: (1) introducing protocols for dependency injection and testability, (2) breaking up the `PRManager` god object, (3) adding a process timeout to `GitHubService`, and (4) propagating all error states to the user.

## Codebase Overview

| File | Lines | Role |
|------|-------|------|
| `Sources/App.swift` | 55 | App entry point, AppDelegate, notification handling |
| `Sources/AuthStatusView.swift` | 85 | Auth status display (compact + detailed) |
| `Sources/ContentView.swift` | 352 | Main PR list view, grouping, sorting, tabs |
| `Sources/GitHubService.swift` | 423 | GitHub GraphQL API via `gh` CLI |
| `Sources/Models.swift` | 165 | `PullRequest` model + `FilterSettings` |
| `Sources/PRManager.swift` | 334 | Main ViewModel: fetch, poll, notify, state |
| `Sources/PRRowView.swift` | 243 | Individual PR row rendering |
| `Sources/SettingsView.swift` | 119 | Settings window UI |
| `Tests/FilterSettingsTests.swift` | 383 | Filter logic + persistence tests |
| `Tests/GitHubServiceParsingTests.swift` | 203 | GraphQL response parsing tests |
| **Total** | **2,362** | |

---

## Part 1: Maintainability Problems

### 1.1 PRManager God Object — HIGH

**Location**: `Sources/PRManager.swift` (entire file, 334 lines)

`PRManager` handles too many unrelated concerns in one class:
- Data fetching orchestration (lines 192-248)
- Polling lifecycle (lines 252-264)
- UserDefaults persistence (lines 22-64)
- Menu bar image composition (lines 128-168)
- Status summary computation (lines 84-125)
- Notification dispatch (lines 272-333)
- Auth state management (lines 15, 68-79)

Every new feature must touch this file. It currently sits at 334 lines (the SwiftLint warning threshold is 400). It will hit that limit with the next feature addition.

**Fix**: Extract into focused types:
- `PollingScheduler` — timer lifecycle
- `NotificationService` — permission + dispatch
- `SettingsStore` — UserDefaults abstraction
- `MenuBarState` — icon and summary derived from PR data

### 1.2 No Protocols / No Dependency Injection — CRITICAL

**Location**: `Sources/PRManager.swift:17`

```swift
let service = GitHubService()
```

`PRManager` instantiates `GitHubService` directly as a stored property. There is no protocol, no injection point, and no way to substitute a mock. This makes `PRManager` — the most important class in the app — completely untestable in isolation.

The same pattern applies to `UserDefaults.standard` (lines 23, 29, 35, 57-64) and `UNUserNotificationCenter.current()` (lines 274, 332).

**Fix**: Define `GitHubServiceProtocol`, `SettingsStorageProtocol`, and inject via init.

### 1.3 Business Logic Embedded in Views — MEDIUM

**Location**: `Sources/ContentView.swift:28-47`

```swift
private var groupedPRs: [(repo: String, prs: [PullRequest])] {
    let dict = Dictionary(grouping: filteredPRs, by: \.repoFullName)
    let isReviews = selectedTab == .reviews
    return dict.keys.sorted().map { key in
        (repo: key, prs: (dict[key] ?? []).sorted { ... })
    }
}
```

PR grouping and sorting is domain logic living inside a SwiftUI computed property. It cannot be unit tested, is recomputed on every body evaluation, and mixes concerns.

Additional instances:
- `ContentView.swift:164-173` — direct mutation of `manager.collapsedRepos`
- `ContentView.swift:139-149` — `NSWorkspace`, `NSPasteboard` system calls
- `PRRowView.swift:9` — `NSWorkspace.shared.open` in button action

**Fix**: Move grouping/sorting into `PRManager` or a dedicated view model. Expose `toggleRepoCollapsed(_:)` method instead of public `Set<String>`.

### 1.4 GitHubService Monolith — MEDIUM

**Location**: `Sources/GitHubService.swift` (423 lines)

One class handles five distinct concerns:
1. `gh` binary resolution (lines 11-20)
2. GraphQL query construction (lines 59-108)
3. Process execution (lines 364-402)
4. JSON parsing entry (lines 118-133)
5. Parse helpers (lines 137-354)

Adding new GraphQL fields requires changes across query string, `parsePRNode`, and potentially other helper methods.

**Fix**: Split into `GHCliRunner`, `GraphQLQueryBuilder`, `PRResponseParser`.

### 1.5 Mixed Domain Models — LOW

**Location**: `Sources/Models.swift`

`PullRequest` (domain entity, lines 6-117) and `FilterSettings` (user preferences, lines 122-165) live in the same file. They represent different layers and change for different reasons.

**Fix**: Move `FilterSettings` to a settings-related file.

### 1.6 @unchecked Sendable — HIGH ✅ RESOLVED

**Location**: `Sources/GitHubService.swift:7`

```swift
final class GitHubService: @unchecked Sendable {
```

This bypasses Swift concurrency safety checks. `Process` and `Pipe` operations in `run()` (lines 364-402) are not inherently thread-safe. The compiler trusts this annotation, but concurrent calls to `run()` could produce undefined behavior.

**Fix**: Either make `GitHubService` an `actor`, or add proper synchronization primitives around `run()`.

**Resolution**: Removed `@unchecked` — the class only has `let ghPath: String` (immutable, `Sendable`). The `run()` method creates only local variables. Added doc comment explaining the `Sendable` conformance rationale.

### 1.7 Hardcoded Configuration — MEDIUM

| Value | Location | Issue |
|-------|----------|-------|
| `gh` paths: 3 hardcoded candidates | `GitHubService.swift:13-17` | Nix, asdf, custom installs missed |
| `first: 100` pagination cap | `GitHubService.swift:63, 84` | Users with >100 PRs or checks see truncated data |
| `"polling_interval"`, `"collapsed_repos"`, `"filter_settings"` | `PRManager.swift:18-20` | String literals; typos cause silent bugs |
| `"url"` notification key | `App.swift:20`, `PRManager.swift:324` | Duplicated magic string |
| Frame sizes: 400, 460, 560, 180, 20x16 | `ContentView.swift:58-60`, `PRManager.swift:143` | Scattered, no central layout config |

**Fix**: Use constants/enums for keys, make pagination configurable, search PATH for `gh`.

### 1.8 README Outdated — LOW

**Location**: `README.md:94-124`

README mentions "zero tests" (false — there are 2 test files with 586 lines), lists improvements that are already implemented, and references error types that don't exist in the current code.

---

## Part 2: Missing Test Coverage

### 2.1 Current Coverage Audit

**What IS tested:**
- `FilterSettings` defaults, Codable round-trips, individual predicates, combinations, persistence, edge cases — **well covered** (383 lines, 24 test methods)
- `GitHubService` parsing: `parsePRState`, `parseReviewDecision`, `parseMergeableState`, `tallyCheckContexts` (CheckRun nodes), `resolveOverallStatus`, `parsePRNode` — **moderately covered** (203 lines, 18 test methods)

**What is NOT tested:** Everything else.

### 2.2 PRManager — Zero Tests — CRITICAL

**Location**: `Sources/PRManager.swift` (entire file)

The central ViewModel has **zero test coverage**. Every path listed below is untested:

| Method/Property | Lines | Risk |
|----------------|-------|------|
| `refreshAll()` — success, failure, nil user, refresh guard | 172-248 | Core data flow |
| `checkForStatusChanges()` — notification decisions | 277-314 | Incorrect notifications |
| `overallStatusIcon` — icon selection logic | 84-98 | Wrong menu bar icon |
| `statusBarSummary` — count formatting | 118-125 | Display errors |
| `openCount`, `draftCount`, `queuedCount` — filtering | 104-114 | Incorrect counts |
| `refreshIntervalLabel` — boundary formatting | 39-44 | Edge cases (59s, 60s, 90s) |
| `menuBarImage` — image composition | 128-168 | Visual bugs |
| `startPolling()` / cancellation | 252-264 | Timer leaks |

**Suggested test cases (requires protocol-based DI first):**
- `refreshAll` with mock service returning success
- `refreshAll` with mock service returning failure for my PRs
- `refreshAll` with mock service returning failure for review PRs (currently silent)
- `refreshAll` when `ghUser` is nil
- `refreshAll` guard against concurrent refresh
- `checkForStatusChanges` when CI goes pending → failure
- `checkForStatusChanges` when CI goes pending → success
- `checkForStatusChanges` when PR disappears
- `checkForStatusChanges` on first load (should not notify)
- `overallStatusIcon` with empty PRs, with failures, with all merged
- `statusBarSummary` formatting for various combinations
- `refreshIntervalLabel` for 30, 59, 60, 90, 120, 300

### 2.3 GitHubService Untested Paths — HIGH

| Function | Lines | Gap |
|----------|-------|-----|
| `escapeForGraphQL` | 52-56 | Not tested. Injection risk: newlines, control chars not escaped. |
| `run()` | 364-402 | Process execution entirely untested. |
| `fetchPRs()` | 59-133 | Only parsing is tested; actual fetch flow untested. |
| `currentUser()` | 25-37 | Not tested. |
| Error paths: `cliNotFound`, `apiError`, `invalidJSON` | 407-423 | Zero coverage. |
| `extractRollupData()` | 256-268 | Not tested. |
| `parseCheckStatus()` | 226-248 | Not tested (only its sub-functions are). |
| `StatusContext` node handling in `tallyCheckContexts` | 281-295 | Only `CheckRun` nodes tested. |

### 2.4 Model Computed Properties — HIGH

| Property | Lines | Gap |
|----------|-------|-----|
| `PullRequest.sortPriority` | Models.swift:34-42 | Used in `ContentView` sorting. Zero tests. |
| `PullRequest.reviewSortPriority` | Models.swift:46-52 | Used in Reviews tab sorting. Zero tests. |
| `PullRequest.statusColor` | Models.swift:55-69 | Drives UI. Zero tests. |
| `PullRequest.id` (computed) | Models.swift:7 | Assumed unique. Not verified. |

### 2.5 View Logic — MEDIUM

| Logic | Location | Gap |
|-------|----------|-----|
| `groupedPRs` sorting | ContentView.swift:28-47 | Cannot test without extracting from view. |
| `ciText` formatting | PRRowView.swift:203-212 | String formatting logic untested. |
| `stateText` display | PRRowView.swift:121-138 | Merge queue position display untested. |
| `filteredPRs` | ContentView.swift:22-25 | Filter application to tab untested. |

### 2.6 Test Quality Notes

**Good patterns observed:**
- Test fixture with sensible defaults (`PullRequest.fixture(...)`) reduces boilerplate
- Tests are well-organized by concern (defaults, Codable, predicates, combinations, persistence)
- Edge cases covered: empty input, all filtered, corrupted data, order preservation

**Anti-patterns:**
- `GitHubServiceParsingTests` instantiates a real `GitHubService()` (line 5). If `GitHubService.init()` gains side effects, tests become integration tests.
- No test for `StatusContext` nodes despite being a separate code path in `tallyCheckContexts`.

---

## Part 3: Performance Issues

### 3.1 Process Spawning Overhead — HIGH

**Location**: `GitHubService.swift:364-402`, called from `PRManager.swift:194-210`

Each refresh cycle spawns **2 separate `gh` CLI processes** per refresh, plus 1 at init:
1. `gh api user --jq .login` (**one-time at init**, not per-refresh)
2. `gh api graphql` for authored PRs (per refresh)
3. `gh api graphql` for review-requested PRs (per refresh)

At the default 60-second interval, that's 2 × (86400/60) = 2,880 process spawns per day (plus 1 at startup). Each spawn involves:
- `Process()` allocation
- Two `Pipe()` allocations
- `DispatchGroup` + two `DispatchQueue.global().async` blocks
- `waitUntilExit()` blocking

**Fix**: Replace `gh` CLI with `URLSession` + `gh auth token` for API calls. Or at minimum, combine the two GraphQL queries into a single aliased query:

```graphql
query {
  myPRs: search(query: "author:user ...", type: ISSUE, first: 100) { ... }
  reviews: search(query: "review-requested:user ...", type: ISSUE, first: 100) { ... }
}
```

### 3.2 Menu Bar Image Recreated on Every State Change — HIGH ✅ RESOLVED

**Location**: `Sources/PRManager.swift:128-168`

`menuBarImage` is a computed property that creates a new `NSImage` on every access. It is read from `App.swift:41`:

```swift
Image(nsImage: manager.menuBarImage)
```

Because `PRManager` is `@ObservableObject`, any `@Published` property change (including unrelated ones like `isRefreshing`) triggers a SwiftUI body evaluation, which calls `menuBarImage`, which allocates a new `NSImage` with drawing operations.

**Resolution**: Converted `menuBarImage` to a `@Published` stored property. Added `updateMenuBarImageIfNeeded()` which only rebuilds when `overallStatusIcon` or `hasFailure` changes. Called at the end of `refreshAll()`. Tests verify image identity stability across refreshes with unchanged status.

### 3.3 groupedPRs Recomputed in SwiftUI Body — MEDIUM

**Location**: `Sources/ContentView.swift:28-47`

`groupedPRs` is a computed property on the view. It performs:
1. `Dictionary(grouping:by:)` — O(n)
2. `dict.keys.sorted()` — O(k log k) where k = unique repos
3. Per-repo sort — O(m log m) per repo

This runs on **every** body evaluation. For a menu bar app that refreshes every 60s, this is fine now, but becomes wasteful as PR count grows.

**Fix**: Move to `PRManager` as a cached `@Published` property, updated only when `pullRequests` or `reviewPRs` change.

### 3.4 Three Separate Count Passes — LOW

**Location**: `Sources/PRManager.swift:104-114`

```swift
var openCount: Int {
    pullRequests.filter { $0.state == .open && !$0.isInMergeQueue }.count
}
var draftCount: Int {
    pullRequests.filter { $0.state == .draft }.count
}
var queuedCount: Int {
    pullRequests.filter { $0.isInMergeQueue }.count
}
```

Three separate `filter` passes over the same array. For small arrays (<100) this is negligible, but could be combined into a single pass.

### 3.5 Fixed Polling Regardless of App State — MEDIUM

**Location**: `Sources/PRManager.swift:252-260`

```swift
private func startPolling() {
    pollingTask?.cancel()
    pollingTask = Task {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(refreshInterval) * 1_000_000_000)
            await refreshAll()
        }
    }
}
```

Polling runs at the same rate regardless of whether:
- The Mac is asleep
- The menu bar popover is closed
- There are zero PRs to track
- The previous fetch failed (and is likely to fail again)

For a 24/7 menu bar app, smarter polling (exponential backoff on errors, pause when sleeping) would reduce wasted resources.

### 3.6 JSON Parsed as Untyped Dictionaries — MEDIUM

**Location**: `Sources/GitHubService.swift:118-126`

```swift
let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
```

The entire GraphQL response is parsed into `[String: Any]` dictionaries, then manually traversed with conditional casts throughout `parsePRNode` and helpers. Codable structs would be more efficient (no `Any` boxing) and provide compile-time safety.

### 3.7 No GraphQL Pagination — HIGH ✅ RESOLVED

**Location**: `Sources/GitHubService.swift:63, 84`

```swift
search(query: "...", type: ISSUE, first: 100)
contexts(first: 100)
```

Hard cap of 100 results. Users with >100 open PRs (common in large orgs) or >100 check contexts silently see truncated data. There is no cursor-based pagination, no `hasNextPage` check, and no user-facing indication of truncation.

**Resolution**: Added cursor-based pagination with `pageInfo { hasNextPage endCursor }` and a loop with `after:` cursor. Safety limit of 10 pages (1000 PRs max). Check context truncation is now logged as a warning.

---

## Part 4: Error Handling & Logging

### 4.1 Review PR Fetch Failure Not Shown to User — HIGH

**Location**: `Sources/PRManager.swift:237-244`

```swift
case .failure(let error):
    logger.error("refreshAll: review PRs fetch failed: \(error.localizedDescription, privacy: .public)")
    // Keep existing reviewPRs in place — don't blank the UI
    break  // <-- lastError is NOT set
```

Compare with the "my PRs" failure handling (line 233):
```swift
lastError = error.localizedDescription
```

If authored PRs succeed but review PRs fail, the user sees no error. The Reviews tab silently shows stale data.

**Fix**: Set `lastError` for both failure paths, potentially combining messages.

> **Status**: Fixed in P0 bugfix plan (`thoughts/shared/plans/2026-02-11-p0-bugfixes.md`, Phase 1). `lastError` is now set on review-PR failure, with combined messaging when both fetches fail.

### 4.2 No Timeout on `gh` Process — HIGH

**Location**: `Sources/GitHubService.swift:364-402`

The `run()` method calls `process.waitUntilExit()` (line 396) with no timeout. If `gh` hangs (DNS resolution, network timeout, broken pipe), the entire app blocks indefinitely. Since `run()` is called from `Task.detached`, this blocks a cooperative thread pool thread.

**Fix**: Add a deadline using `DispatchWorkItem` or a timer that terminates the process:

```swift
let deadline = DispatchTime.now() + .seconds(30)
DispatchQueue.global().asyncAfter(deadline: deadline) {
    if process.isRunning { process.terminate() }
}
```

> **Status**: Fixed in P0 bugfix plan (`thoughts/shared/plans/2026-02-11-p0-bugfixes.md`, Phase 2). `run()` now uses `DispatchSemaphore` + `terminationHandler` with a 30-second timeout and `GHError.timeout`.

### 4.3 `try? Task.sleep` Masks Cancellation — MEDIUM

**Location**: `Sources/PRManager.swift:256`

```swift
try? await Task.sleep(nanoseconds: UInt64(refreshInterval) * 1_000_000_000)
```

`Task.sleep` throws `CancellationError` when the task is cancelled. Swallowing it with `try?` causes the loop to immediately proceed to `refreshAll()` instead of exiting. On cancellation, the polling loop runs one more unnecessary refresh, then continues looping (checking `Task.isCancelled` only at the top).

**Fix**:
```swift
do {
    try await Task.sleep(nanoseconds: UInt64(refreshInterval) * 1_000_000_000)
} catch {
    return  // Exit on cancellation
}
```

> **Status**: Already fixed during PRManager decomposition (`PollingScheduler.swift`). The extracted `PollingScheduler` uses `do-catch` with explicit `return` on cancellation instead of `try?`.

### 4.4 currentUser() Treats All Errors as "CLI Failed" — MEDIUM ✅ RESOLVED

**Location**: `Sources/GitHubService.swift:27`

```swift
guard let (out, stderr, exit) = try? run(["api", "user", "--jq", ".login"]) else {
    logger.error("currentUser: gh cli failed to launch")
    return nil
}
```

`try?` discards the actual error type. Authentication failures, network errors, and permission errors all produce the same "gh cli failed to launch" log message.

**Fix**: Use `do-catch` to log the actual error:
```swift
do {
    let (out, stderr, exit) = try run(["api", "user", "--jq", ".login"])
    ...
} catch GHError.cliNotFound {
    logger.error("currentUser: gh CLI not found")
} catch {
    logger.error("currentUser: \(error.localizedDescription, privacy: .public)")
}
```

### 4.5 Malformed PR Nodes Silently Dropped — MEDIUM ✅ RESOLVED

**Location**: `Sources/GitHubService.swift:128-132`

```swift
let prs = nodes.compactMap { node -> PullRequest? in
    parsePRNode(node)
}
```

If `parsePRNode` returns `nil` (malformed data, missing required fields), the node is silently filtered out. No log, no metric, no indication that data was lost.

**Fix**: Log when a node fails to parse:
```swift
let prs = nodes.compactMap { node -> PullRequest? in
    guard let pr = parsePRNode(node) else {
        logger.debug("parsePRNode: skipping malformed node")
        return nil
    }
    return pr
}
```

### 4.6 GraphQL `errors` Field Ignored — MEDIUM ✅ RESOLVED

**Location**: `Sources/GitHubService.swift:118-126`

The code only checks for `json["data"]`. GitHub GraphQL can return `{"errors": [...], "data": null}` for partial failures, rate limits, or schema errors. These are thrown away as `GHError.invalidJSON` without surfacing the actual error message.

**Fix**: Inspect the `errors` field before throwing:
```swift
if let errors = json["errors"] as? [[String: Any]],
   let first = errors.first,
   let msg = first["message"] as? String {
    throw GHError.apiError(msg)
}
```

### 4.7 Notification Permission & Delivery Unverified — MEDIUM

**Location**: `Sources/PRManager.swift:274, 332`

```swift
// Permission request — result discarded
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

// Notification delivery — no completion handler
UNUserNotificationCenter.current().add(request)
```

Both the permission result and delivery result are discarded. If notification permission is denied or delivery fails, there is no log, no retry, and no user indication.

### 4.8 process.run() Error Overwritten — MEDIUM ✅ RESOLVED

**Location**: `Sources/GitHubService.swift:374-377`

```swift
do {
    try process.run()
} catch {
    throw GHError.cliNotFound
}
```

Any `Process.run()` error (permission denied, file not found, resource exhaustion) is mapped to `GHError.cliNotFound`. The actual error is discarded.

**Fix**: Either preserve the underlying error or add a new case:
```swift
} catch {
    logger.error("gh process launch failed: \(error.localizedDescription, privacy: .public)")
    throw GHError.cliNotFound  // or: throw GHError.processLaunchFailed(error)
}
```

### 4.9 FileHandle.readDataToEndOfFile Can Throw — MEDIUM ✅ RESOLVED

**Location**: `Sources/GitHubService.swift:386-393`

```swift
DispatchQueue.global().async {
    outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    group.leave()
}
```

`readDataToEndOfFile()` can throw (e.g., if the pipe breaks or the file descriptor is invalid). In a non-throwing `async` closure, an unhandled throw would be a runtime error.

**Fix**: Wrap in do-catch.

### 4.10 Silent Persistence Failures — LOW

**Location**: `Sources/PRManager.swift:28-31, 61-64`

```swift
// Save — failure swallowed
if let data = try? JSONEncoder().encode(filterSettings) {
    UserDefaults.standard.set(data, forKey: Self.filterSettingsKey)
}

// Load — failure swallowed
if let data = UserDefaults.standard.data(forKey: Self.filterSettingsKey),
   let saved = try? JSONDecoder().decode(FilterSettings.self, from: data) {
    self.filterSettings = saved
}
```

Both encode and decode failures are silently swallowed. User settings could be lost without any indication.

### 4.11 Missing Logging for Key Operations — LOW

Operations with no logging:
- App launch and lifecycle events (`App.swift`)
- Notification tap handling (`App.swift:15-25`)
- UserDefaults reads/writes (`PRManager.swift:23, 29, 35`)
- `gh` binary path resolution result (`GitHubService.swift:18-19`)
- Notification scheduling (`PRManager.swift:331-332`)
- Pasteboard and URL-open results (`ContentView.swift:139-149`)

### 4.12 No Request Correlation — LOW

There are no request IDs to correlate logs across a single refresh cycle. When debugging "why did this PR disappear?", there's no way to trace a specific `refreshAll()` invocation through `fetchPRs()`, parsing, and notification decisions.

---

## Issue Summary

### By Severity

| Severity | Count | Key Examples |
|----------|-------|-------------|
| CRITICAL | 1 | No protocols / no dependency injection |
| HIGH | 10 | God object, unchecked Sendable, no PRManager tests, no process timeout, no pagination, process spawning overhead, menu bar image, review PR error suppression |
| MEDIUM | 20 | Business logic in views, monolithic service, fixed polling, untyped JSON, various error handling gaps |
| LOW | 16 | Mixed models, duplicated empty states, scattered magic values, missing logs, README outdated |

### By Category

| Category | CRITICAL | HIGH | MEDIUM | LOW | Total |
|----------|----------|------|--------|-----|-------|
| Maintainability | 1 | 3 | 3 | 2 | 9 |
| Test Coverage | 0 | 3 | 2 | 0 | 5 |
| Performance | 0 | 3 | 3 | 1 | 7 |
| Error Handling | 0 | 2 | 7 | 3 | 12 |

---

## Recommended Fix Order

The fixes below are ordered by impact and dependency. Each step is atomic and involves fewer than 20 files.

### Phase 1: Foundation (Unblocks Everything Else)

**Step 1: Introduce `GitHubServiceProtocol`**
- **Task**: Extract a protocol from `GitHubService`, inject conforming instance into `PRManager` via init
- **Files**: `GitHubService.swift`, `PRManager.swift`, `App.swift`
- **Why first**: Unblocks all `PRManager` testing. Highest leverage change.
- **Issues addressed**: 1.2 (CRITICAL), 2.2 (CRITICAL)

**Step 2: Add process timeout to `GitHubService.run()`** ✅ Done
- **Task**: Add a 30-second deadline that terminates the `gh` process if exceeded
- **Files**: `GitHubService.swift`
- **Why**: Prevents the app from hanging indefinitely on network issues
- **Issues addressed**: 4.2 (HIGH)

### Phase 2: Error Handling (Quick Wins)

**Step 3: Propagate review PR errors** ✅ Done
- **Task**: Set `lastError` when review PR fetch fails; surface both error paths to user
- **Files**: `PRManager.swift`
- **Issues addressed**: 4.1 (HIGH)

**Step 4: Fix `Task.sleep` cancellation** ✅ Done (fixed during PRManager decomposition)
- **Task**: Replace `try?` with `do-catch`, exit loop on `CancellationError`
- **Files**: `PRManager.swift`
- **Issues addressed**: 4.3 (MEDIUM)

**Step 5: Improve error specificity** ✅ Done (P1 high-impact fixes)
- **Task**: Replace `try?` in `currentUser()` with `do-catch`; preserve process launch errors; inspect GraphQL `errors` field; close pipe write fds
- **Files**: `GitHubService.swift`
- **Issues addressed**: 4.4, 4.6, 4.8, 4.9 (MEDIUM)

**Step 6: Add missing logging** ✅ Done (P1 high-impact fixes)
- **Task**: Log dropped PR nodes, persistence failures, notification results, `gh` path resolution
- **Files**: `GitHubService.swift`, `PRManager.swift`
- **Issues addressed**: 4.5, 4.7, 4.10, 4.11 (MEDIUM/LOW)

### Phase 3: Testing

**Step 7: Add `PRManager` unit tests**
- **Task**: Using the protocol from Step 1, test `refreshAll()`, `checkForStatusChanges()`, computed properties
- **Files**: New `Tests/PRManagerTests.swift`
- **Issues addressed**: 2.2 (CRITICAL)

**Step 8: Add `GitHubService` parsing gap tests**
- **Task**: Test `escapeForGraphQL`, `StatusContext` nodes, `extractRollupData`, `parseCheckStatus`, error paths
- **Files**: `Tests/GitHubServiceParsingTests.swift`
- **Issues addressed**: 2.3 (HIGH)

**Step 9: Add model property tests**
- **Task**: Test `sortPriority`, `reviewSortPriority`, `statusColor`
- **Files**: New `Tests/PullRequestTests.swift`
- **Issues addressed**: 2.4 (HIGH)

### Phase 4: Architecture

**Step 10: Break up `PRManager`**
- **Task**: Extract `NotificationService`, `PollingScheduler`, `SettingsStore` from `PRManager`
- **Files**: `PRManager.swift` + 3 new files + `App.swift`
- **Issues addressed**: 1.1 (HIGH)

**Step 11: Move business logic out of views**
- **Task**: Extract `groupedPRs` to ViewModel, add `toggleRepoCollapsed()`, extract `ciText`
- **Files**: `ContentView.swift`, `PRRowView.swift`, `PRManager.swift`
- **Issues addressed**: 1.3 (MEDIUM)

**Step 12: Remove `@unchecked Sendable`** ✅ Done (P1 high-impact fixes)
- **Task**: Removed `@unchecked` — class is genuinely `Sendable` (only `let` stored properties). Added doc comment explaining why.
- **Files**: `GitHubService.swift`
- **Issues addressed**: 1.6 (HIGH)

### Phase 5: Performance

**Step 13: Cache `menuBarImage`** ✅ Done (P1 high-impact fixes)
- **Task**: Converted to `@Published` stored property; only regenerated when `overallStatusIcon` or `hasFailure` changes
- **Files**: `PRManager.swift`
- **Issues addressed**: 3.2 (HIGH)

**Step 14: Combine GraphQL queries**
- **Task**: Merge "my PRs" and "review PRs" into a single aliased GraphQL query
- **Files**: `GitHubService.swift`, `PRManager.swift`
- **Issues addressed**: 3.1 (HIGH)

**Step 15: Smart polling**
- **Task**: Back off on errors, pause when system is asleep, reduce frequency when no PRs
- **Files**: `PRManager.swift` (or extracted `PollingScheduler`)
- **Issues addressed**: 3.5 (MEDIUM)

---

## Code References

- `Sources/PRManager.swift:17` — Direct `GitHubService` instantiation (no protocol)
- `Sources/PRManager.swift:128-168` — `menuBarImage` computed property (no caching)
- `Sources/PRManager.swift:237-244` — Review PR error suppressed
- `Sources/PRManager.swift:256` — `try? Task.sleep` masking cancellation
- `Sources/GitHubService.swift:7` — `@unchecked Sendable`
- `Sources/GitHubService.swift:63,84` — `first: 100` pagination cap
- `Sources/GitHubService.swift:118-126` — GraphQL `errors` field ignored
- `Sources/GitHubService.swift:364-402` — `run()` with no timeout
- `Sources/GitHubService.swift:374-377` — Process launch error overwritten
- `Sources/ContentView.swift:28-47` — Business logic in view
- `Sources/ContentView.swift:164-173` — Direct mutation of manager state
- `Sources/Models.swift:34-52` — `sortPriority` and `reviewSortPriority` (untested)

## Related Research

- `thoughts/shared/research/2026-02-10-architecture-and-design-patterns.md` — Architecture documentation
- `thoughts/shared/research/2026-02-10-dry-refactoring-opportunities.md` — DRY analysis
- `thoughts/shared/plans/2026-02-10-dry-cleanup.md` — DRY cleanup plan
- `thoughts/shared/research/2026-02-10-reviewability-filter-controls.md` — Filter controls research

## Open Questions

1. **URLSession migration**: Should `gh` CLI be replaced with direct `URLSession` calls using `gh auth token`? This would eliminate process spawning overhead entirely but introduces a new dependency on token management.
2. **GraphQL pagination**: Is the 100-item cap actually hit by any current users? Should we add cursor-based pagination or just raise the limit?
3. **Notification reliability**: Should we track notification permission state and display a persistent UI indicator when denied?
4. **Concurrency model**: Is `actor` the right choice for `GitHubService`, or should it remain a class with explicit synchronization?
