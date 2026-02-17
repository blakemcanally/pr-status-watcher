---
date: 2026-02-17T15:25:16Z
researcher: Blake McAnally
git_commit: 16769aa6ffb382c2b87712a3404256525845cd32
branch: main
repository: blakemcanally/pr-status-watcher
topic: "Ignored CI Checks — the contrapositive of required checks allowlisting"
tags: [research, codebase, ci-checks, ignore-list, readiness, filter-settings, check-status-parsing]
status: complete
last_updated: 2026-02-17
last_updated_by: Blake McAnally
last_updated_note: "Resolved all open questions — Option 2 confirmed, mutual exclusion validation, reviews-only scope, distinct settings sections, refresh on change"
---

# Research: Ignored CI Checks — Contrapositive of Required Checks

**Date**: 2026-02-17T15:25:16Z
**Researcher**: Blake McAnally
**Git Commit**: 16769aa6ffb382c2b87712a3404256525845cd32
**Branch**: main
**Repository**: blakemcanally/pr-status-watcher

## Research Question

The existing "Review Readiness" feature uses an allowlist (`requiredCheckNames`) — you specify which CI checks **must** pass for a PR to be considered ready. The user wants the **contrapositive**: an ignore list where you specify CI checks to **completely disregard** because they're flaky, managed elsewhere (e.g., Graphite stack management), or otherwise irrelevant. What code paths are involved, what are the design trade-offs, and how would this integrate with the existing architecture?

## Summary

The ignored-checks feature touches **six distinct code areas**: the `FilterSettings` model (persistence), the `isReady()` readiness predicate, the CI status tallying pipeline (`tallyCheckContexts` → `resolveOverallStatus`), the PR row display (`PRRowView`), the readiness sections in `ContentView`, and the settings UI in `SettingsView`. The deepest design question is **where in the pipeline** to filter out ignored checks — during data ingestion (in `tallyCheckContexts`) or post-ingestion (via computed properties or view-layer filtering). The recommended approach is **post-tally filtering on `PullRequest`** with "effective" computed properties, which preserves raw data integrity while giving every downstream consumer access to filtered results.

---

## How the Current System Works

### The Allowlist: `requiredCheckNames`

The existing feature is defined in `FilterSettings` (`Sources/Models.swift:161-178`):

```swift
struct FilterSettings: Codable, Equatable {
    var hideDrafts: Bool
    var requiredCheckNames: [String]  // ← the allowlist
}
```

It's consumed by `PullRequest.isReady(requiredChecks:)` (`Sources/Models.swift:136-155`):

```swift
func isReady(requiredChecks: [String]) -> Bool {
    guard state != .draft else { return false }
    guard mergeable != .conflicting else { return false }

    if requiredChecks.isEmpty {
        // Default mode: use overall ciStatus rollup
        return ciStatus != .failure && ciStatus != .pending
    }

    // Allowlist mode: only evaluate named checks
    for name in requiredChecks {
        guard let check = checkResults.first(where: { $0.name == name }) else {
            continue  // missing = ignored
        }
        if check.status != .passed { return false }
    }
    return true
}
```

**Behavior**: When the allowlist is non-empty, **only** listed checks matter. Everything else — passing or failing — is irrelevant to readiness. When the allowlist is empty, the overall `ciStatus` rollup determines readiness.

### The Contrapositive: What an Ignore List Means

| Feature | Semantics | Effect |
|---------|-----------|--------|
| **Allowlist** (`requiredCheckNames`) | "Only these matter" | Everything else is noise |
| **Ignore list** (`ignoredCheckNames`) | "These don't matter" | Everything else still matters |

An ignore list says: "Pretend these checks don't exist." A PR with 10 checks where 9 pass and 1 flaky check fails — if that flaky check is on the ignore list, the PR should appear as 9/9 passed, CI green, ready for review.

---

## Full Data Flow: Where Checks Touch the System

The following trace shows every code location that processes or displays check data. Each is a potential integration point for the ignore list.

### Step 1: GraphQL Fetch

Individual check details are fetched via `statusCheckRollup.contexts` in the GraphQL query (`Sources/GitHubService.swift:116-137`). This returns `CheckRun` and `StatusContext` nodes with `name`, `status`, `conclusion`, `detailsUrl`, etc.

### Step 2: Tallying (`tallyCheckContexts`)

**File**: `Sources/GitHubService+CheckStatusParsing.swift:79-126`

Iterates each check context node and produces `CheckCounts`:

```swift
struct CheckCounts {
    var passed: Int
    var failed: Int
    var pending: Int
    var failedChecks: [PullRequest.CheckInfo]   // names + URLs of failed checks
    var allChecks: [PullRequest.CheckResult]     // all checks with name + status + URL
}
```

For **StatusContext** nodes: classifies by `state` (SUCCESS → passed, FAILURE/ERROR → failed, else → pending).
For **CheckRun** nodes: if `status == "COMPLETED"`, delegates to `classifyCompletedCheckContext()` (`line 128-151`), which maps conclusion (SUCCESS/SKIPPED/NEUTRAL → passed, else → failed). Non-completed runs are counted as pending.

**Key detail**: Both `failedChecks` and `allChecks` are populated here. The `failedChecks` array only contains failed checks; `allChecks` contains everything.

### Step 3: Overall Status Resolution

**File**: `Sources/GitHubService+CheckStatusParsing.swift:153-176`

```swift
func resolveOverallStatus(totalCount:, passed:, failed:, pending:, rollupState:) -> CIStatus
```

Logic: `totalCount == 0` → unknown; `failed > 0` → failure; `pending > 0` → pending; otherwise success (with fallback to rollupState if no nodes were classified).

**Critical**: This function operates on **aggregate counts**. If ignored checks are filtered out before tallying, the counts change and `ciStatus` automatically reflects the filtered state.

### Step 4: CIResult Assembly

**File**: `Sources/GitHubService+CheckStatusParsing.swift:25-49`

`parseCheckStatus()` calls `tallyCheckContexts` and `resolveOverallStatus`, producing:

```swift
struct CIResult {
    let status: PullRequest.CIStatus
    let total: Int
    let passed: Int
    let failed: Int
    let failedChecks: [PullRequest.CheckInfo]
    let checkResults: [PullRequest.CheckResult]
}
```

### Step 5: PullRequest Construction

**File**: `Sources/GitHubService+NodeConversion.swift:33-56`

`convertNode()` maps `CIResult` into `PullRequest` fields:

```swift
return PullRequest(
    ...
    ciStatus: checkResult.status,
    checksTotal: checkResult.total,
    checksPassed: checkResult.passed,
    checksFailed: checkResult.failed,
    failedChecks: checkResult.failedChecks,
    checkResults: checkResult.checkResults
)
```

### Step 6: Readiness Evaluation

**File**: `Sources/ContentView.swift:34-48`

```swift
private var readyPRs: [PullRequest] {
    filteredPRs.filter { $0.isReady(requiredChecks: manager.filterSettings.requiredCheckNames) }
}
private var notReadyPRs: [PullRequest] {
    filteredPRs.filter { !$0.isReady(requiredChecks: manager.filterSettings.requiredCheckNames) }
}
```

### Step 7: PR Row Display

**File**: `Sources/PRRowView.swift`

The following PR row elements use check data:

| Element | Property Used | Lines |
|---------|--------------|-------|
| Status dot color | `pullRequest.statusColor` → `ciStatus` | 13-15 |
| Review badge visibility | `pullRequest.ciStatus == .success \|\| .unknown` | 43-44 |
| CI badge visibility | `pullRequest.checksTotal > 0` | 169 |
| CI badge color | `pullRequest.ciStatus.color` | 180 |
| CI badge icon | `pullRequest.ciStatus` | 194-200 |
| CI badge text | `checksFailed`, `checksPassed`, `checksTotal` | 203-211 |
| Expand chevron | `!pullRequest.failedChecks.isEmpty` | 171, 182 |
| Failed checks list | `pullRequest.failedChecks` (ForEach) | 56-83 |

### Step 8: Menu Bar & Status Bar

**File**: `Sources/PRManager.swift:112-134`

- `overallStatusIcon` and `hasFailure` use `pullRequests` (authored PRs, not reviews)
- `statusBarSummary` applies review filters before counting

These use `ciStatus` indirectly through `PRStatusSummary` helpers, not individual check data.

---

## The Design Question: Where to Filter

### Option 1: Filter During Tallying (Layer 1 — Data Ingestion)

**How**: Pass `ignoredCheckNames` into `tallyCheckContexts()` and skip any context whose name matches.

**Pros**:
- Cleanest downstream effect — `ciStatus`, `failedChecks`, counts, and everything derived from them automatically exclude ignored checks
- No changes needed to PRRowView, readiness logic, or ContentView — they all "just work" because the data is already filtered
- Ignored checks never even enter `failedChecks` or `allChecks`

**Cons**:
- `tallyCheckContexts` is on `GitHubService`, which currently has no access to user settings — settings would need to be threaded through
- Raw check data is lost — you can't later show "these checks were ignored" in the UI
- Harder to test in isolation since filtering is mixed with parsing
- Breaks the current separation between "data fetching" and "user preferences"

**Files changed**: `GitHubService+CheckStatusParsing.swift` (add parameter), `GitHubService+NodeConversion.swift` (pass settings), `GitHubService.swift` or `PRManager.swift` (thread settings to service)

### Option 2: Filter After Construction (Layer 2 — Post-Processing)

**How**: Store all checks on `PullRequest` (as today), but add computed properties or methods that produce "effective" values excluding ignored checks.

**Pros**:
- Raw data preserved — the full truth is always accessible
- Clean separation: data layer fetches everything, presentation layer filters
- Easy to implement "show ignored checks differently" UI in the future
- Testable in isolation — the effective methods are pure functions
- Consistent with the existing architecture (settings don't leak into service layer)

**Cons**:
- More touchpoints to update — every consumer of `ciStatus`, `failedChecks`, `checksTotal`, etc. needs to use the "effective" version
- Potential for bugs if a consumer accidentally uses the raw value instead of the effective one

**Files changed**: `Models.swift` (add effective methods + `ignoredCheckNames` to FilterSettings), `PRRowView.swift` (use effective properties), `ContentView.swift` (pass ignore list to readiness), `SettingsView.swift` (UI), `PRManager.swift` (pass-through)

### Option 3: Hybrid — Filter in PRManager After Fetch

**How**: In `PRManager.refreshAll()`, after receiving `[PullRequest]` from the service, post-process each PR to strip out ignored checks and recompute `ciStatus`, `checksTotal`, etc. The `PullRequest` objects stored in `reviewPRs` and `pullRequests` are already filtered.

**Pros**:
- Single filter point — happens once per refresh, not on every view render
- All downstream consumers see filtered data automatically (like Option 1)
- Doesn't require changing the service layer
- Raw data is only briefly available during the refresh cycle

**Cons**:
- `PullRequest` needs a mutating method or factory to recompute CI fields from filtered checks
- The recomputation duplicates some of `resolveOverallStatus`'s logic
- Less transparent than Option 2's explicit effective methods

**Files changed**: `PRManager.swift` (add post-processing), `Models.swift` (add recompute method + `ignoredCheckNames`), `SettingsView.swift` (UI)

### Recommendation: Option 2 (Post-Processing with Effective Properties)

Option 2 is the most architecturally consistent choice for this codebase. It follows the same pattern as the existing readiness feature: raw data on the model, user preferences consumed at the point of use, truthful display with semantic overlays.

However, if the goal is to fully hide ignored checks from all UI (not just readiness), **Option 3 is the pragmatic choice** — it gives the same effect as Option 1 without coupling settings to the service layer.

---

## Interaction Between Allowlist and Ignore List

When both `requiredCheckNames` and `ignoredCheckNames` are configured, there are three possible semantics:

### Semantic A: Ignore List Applies First (Recommended)

1. Remove ignored checks from `checkResults`
2. Evaluate readiness using filtered results

This means if a check is in both lists, it's ignored (removed before evaluation). The allowlist never sees it.

**Rationale**: If a user explicitly says "ignore this check," that should override all other settings. This prevents a scenario where a flaky check is in the required list and blocks readiness even though the user wants to ignore it.

### Semantic B: Required List Takes Precedence

If a check is in both lists, the required-list wins — the check is still required.

**Rationale**: Prevents accidental misconfiguration where someone ignores a check that's actually required.

**Problem**: Defeats the purpose. If a required check becomes flaky, the user wants to temporarily ignore it without removing it from the required list. Semantic B forces them to modify two lists.

### Semantic C: Mutually Exclusive (Validation Error)

The UI prevents a check from being in both lists.

**Rationale**: Simplest mental model — no ambiguity.

**Problem**: Adds UI complexity for minimal benefit. The user must remove from one list before adding to the other.

**Recommendation**: Semantic A. The ignore list is a "nuclear option" — if you want a check gone, it's gone, regardless of other settings.

---

## Specific Code Changes Required

### 1. `FilterSettings` — Add `ignoredCheckNames`

**File**: `Sources/Models.swift`

Add a new property alongside `requiredCheckNames`:

```swift
struct FilterSettings: Codable, Equatable {
    var hideDrafts: Bool
    var requiredCheckNames: [String]
    var ignoredCheckNames: [String]   // NEW
}
```

Update `init`, `init(from decoder:)` with `decodeIfPresent` defaulting to `[]`. This follows the exact same pattern as `requiredCheckNames` was added — backward-compatible deserialization.

### 2. `PullRequest` — Add Effective Properties (Option 2) or Recompute Method (Option 3)

**File**: `Sources/Models.swift`

#### Option 2 approach — add computed methods:

```swift
extension PullRequest {
    /// Check results excluding ignored check names.
    func effectiveCheckResults(ignoredChecks: [String]) -> [CheckResult] {
        guard !ignoredChecks.isEmpty else { return checkResults }
        let ignored = Set(ignoredChecks)
        return checkResults.filter { !ignored.contains($0.name) }
    }

    /// Failed checks excluding ignored check names.
    func effectiveFailedChecks(ignoredChecks: [String]) -> [CheckInfo] {
        guard !ignoredChecks.isEmpty else { return failedChecks }
        let ignored = Set(ignoredChecks)
        return failedChecks.filter { !ignored.contains($0.name) }
    }

    /// Recomputed CI status excluding ignored checks.
    func effectiveCIStatus(ignoredChecks: [String]) -> CIStatus {
        guard !ignoredChecks.isEmpty else { return ciStatus }
        let effective = effectiveCheckResults(ignoredChecks: ignoredChecks)
        if effective.isEmpty { return .unknown }
        if effective.contains(where: { $0.status == .failed }) { return .failure }
        if effective.contains(where: { $0.status == .pending }) { return .pending }
        return .success
    }

    /// Recomputed check counts excluding ignored checks.
    func effectiveCheckCounts(ignoredChecks: [String]) -> (total: Int, passed: Int, failed: Int) {
        let effective = effectiveCheckResults(ignoredChecks: ignoredChecks)
        let passed = effective.filter { $0.status == .passed }.count
        let failed = effective.filter { $0.status == .failed }.count
        return (total: effective.count, passed: passed, failed: failed)
    }
}
```

#### Option 3 approach — mutating recompute after fetch:

```swift
extension PullRequest {
    /// Strips ignored checks and recomputes all derived CI fields.
    mutating func applyIgnoredChecks(_ ignoredNames: Set<String>) {
        guard !ignoredNames.isEmpty else { return }
        checkResults = checkResults.filter { !ignoredNames.contains($0.name) }
        failedChecks = failedChecks.filter { !ignoredNames.contains($0.name) }
        let passed = checkResults.filter { $0.status == .passed }.count
        let failed = checkResults.filter { $0.status == .failed }.count
        let pending = checkResults.filter { $0.status == .pending }.count
        checksPassed = passed
        checksFailed = failed
        checksTotal = checkResults.count
        if checksTotal == 0 { ciStatus = .unknown }
        else if failed > 0 { ciStatus = .failure }
        else if pending > 0 { ciStatus = .pending }
        else { ciStatus = .success }
    }
}
```

### 3. `isReady()` — Accept Ignored Checks

**File**: `Sources/Models.swift`

The readiness predicate needs to account for ignored checks. Under Semantic A (ignore first):

```swift
func isReady(requiredChecks: [String], ignoredChecks: [String] = []) -> Bool {
    guard state != .draft else { return false }
    guard mergeable != .conflicting else { return false }

    let ignored = Set(ignoredChecks)
    let effectiveResults = checkResults.filter { !ignored.contains($0.name) }

    if requiredChecks.isEmpty {
        // Default mode: use effective CI status
        let effectiveStatus = Self.computeStatus(from: effectiveResults)
        return effectiveStatus != .failure && effectiveStatus != .pending
    }

    // Required-checks mode: evaluate only required checks (minus ignored)
    let activeRequired = requiredChecks.filter { !ignored.contains($0) }
    for name in activeRequired {
        guard let check = effectiveResults.first(where: { $0.name == name }) else {
            continue  // missing = ignored
        }
        if check.status != .passed { return false }
    }
    return true
}
```

### 4. `PRRowView` — Use Effective Values

**File**: `Sources/PRRowView.swift`

PRRowView currently reads `pullRequest.ciStatus`, `pullRequest.failedChecks`, `pullRequest.checksFailed`, `pullRequest.checksPassed`, `pullRequest.checksTotal` directly.

**Option 2**: PRRowView would need access to `ignoredCheckNames` (via `@EnvironmentObject` or passed as a parameter) and call the effective methods.

**Option 3**: No PRRowView changes needed — the data is already filtered on the model.

This is the strongest argument for Option 3 if the intent is to completely hide ignored checks from all UI, as it avoids threading settings through every view.

### 5. `ContentView` — Pass Ignore List to Readiness

**File**: `Sources/ContentView.swift`

Update the readiness computed properties:

```swift
private var readyPRs: [PullRequest] {
    filteredPRs.filter {
        $0.isReady(
            requiredChecks: manager.filterSettings.requiredCheckNames,
            ignoredChecks: manager.filterSettings.ignoredCheckNames
        )
    }
}
```

### 6. `SettingsView` — UI for Ignored Check Names

**File**: `Sources/SettingsView.swift`

Mirror the existing `requiredCheckNames` UI pattern: a list of current ignored checks with remove buttons, a text field with autocomplete from `availableCheckNames`, and an add button. Place it in the "Review Readiness" section, either alongside or below the required checks list.

### 7. `Strings.swift` — Add Ignore List Strings

**File**: `Sources/Strings.swift`

```swift
enum Readiness {
    // ... existing ...
    static let ignoredChecksDescription = "These CI checks are completely hidden — they won't affect readiness or appear in the CI badge."
    static let addIgnoredCheckPlaceholder = "Add check to ignore..."
    static let ignoredChecksLabel = "Ignored CI Checks"
}
```

### 8. `PRManager` — Option 3 Post-Processing

**File**: `Sources/PRManager.swift`

If using Option 3, add post-processing in `refreshAll()`:

```swift
// After setting reviewPRs = prs:
let ignored = Set(filterSettings.ignoredCheckNames)
if !ignored.isEmpty {
    reviewPRs = reviewPRs.map { var pr = $0; pr.applyIgnoredChecks(ignored); return pr }
    pullRequests = pullRequests.map { var pr = $0; pr.applyIgnoredChecks(ignored); return pr }
}
```

**Caveat**: This means changing `ignoredCheckNames` in settings requires a re-fetch (or re-process) to take effect. To handle settings changes without re-fetching, `filterSettings.didSet` could trigger reprocessing from cached raw data.

---

## Design Trade-Off: "Honest Information" Principle

The existing plan doc established the **"Honest Information, Semantic Grouping"** principle: readiness sections are organizational, but PR row badges always show the true, unfiltered CI status.

An ignore list creates a tension with this principle. Two philosophies:

### Philosophy A: Ignore = Remove From Display Entirely

Ignored checks are stripped from all displays — CI badge counts, failed checks list, status color. The PR row looks like those checks don't exist.

**Best for**: Truly irrelevant checks (Graphite stack management, infrastructure-only checks that never affect code quality). The user's stated use cases — "flaky, managed elsewhere, or any other reason" — strongly suggest this intent.

### Philosophy B: Ignore = Show But Don't Block Readiness

Ignored checks still appear in the CI badge and failed checks list, but don't affect the Ready/Not Ready classification.

**Best for**: Checks that are informational but shouldn't block workflow. Preserves the "honest information" principle.

### Assessment

Given the user's stated use cases (flaky checks, Graphite stack), **Philosophy A** is the right default. When a check is "managed elsewhere," showing it is pure noise. The user is explicitly saying "this check is not meaningful in this context."

This is also why **Option 3** (filter after fetch, before storage) is pragmatically attractive — it removes the check from the model entirely, so every downstream consumer automatically ignores it.

---

## Complete File Impact Summary

| File | Change | Option 2 | Option 3 |
|------|--------|----------|----------|
| `Sources/Models.swift` | Add `ignoredCheckNames` to `FilterSettings` | Yes | Yes |
| `Sources/Models.swift` | Add effective methods / recompute method | Effective methods | Mutating method |
| `Sources/Models.swift` | Update `isReady()` signature | Yes | Yes (simpler) |
| `Sources/Models.swift` | Update `init(from decoder:)` | Yes | Yes |
| `Sources/PRManager.swift` | Post-process after fetch | No | Yes |
| `Sources/PRManager.swift` | Re-process on settings change | No | Yes |
| `Sources/PRRowView.swift` | Use effective values | Yes (many changes) | No changes |
| `Sources/ContentView.swift` | Pass ignore list to readiness | Yes | Minor |
| `Sources/SettingsView.swift` | Ignored checks UI section | Yes | Yes |
| `Sources/Strings.swift` | Add ignore list strings | Yes | Yes |
| `Sources/SettingsStoreProtocol.swift` | No change (FilterSettings covers it) | — | — |
| `Sources/SettingsStore.swift` | No change (FilterSettings JSON covers it) | — | — |
| `Tests/FilterSettingsTests.swift` | Codable tests for `ignoredCheckNames` | Yes | Yes |
| `Tests/PullRequestTests.swift` | Readiness tests with ignored checks | Yes | Yes |
| `Tests/PRManagerTests.swift` | Post-processing tests | No | Yes |

---

## Autocomplete Reuse

The existing `availableCheckNames` computed property on `PRManager` (`Sources/PRManager.swift:49-52`) aggregates all unique check names from `reviewPRs`. This same data source serves autocomplete for both `requiredCheckNames` and `ignoredCheckNames`. The settings UI just needs to filter out names already in the respective list.

---

## Code References

- `Sources/Models.swift:6-29` — `PullRequest` struct with all CI fields
- `Sources/Models.swift:55-70` — `statusColor` computed property (uses `ciStatus`)
- `Sources/Models.swift:81-95` — `CIStatus` enum with `color` property
- `Sources/Models.swift:114-131` — `CheckInfo`, `CheckStatus`, `CheckResult` types
- `Sources/Models.swift:136-155` — `isReady(requiredChecks:)` predicate
- `Sources/Models.swift:161-188` — `FilterSettings` with `requiredCheckNames`
- `Sources/GitHubService+CheckStatusParsing.swift:71-77` — `CheckCounts` struct
- `Sources/GitHubService+CheckStatusParsing.swift:79-126` — `tallyCheckContexts()`
- `Sources/GitHubService+CheckStatusParsing.swift:128-151` — `classifyCompletedCheckContext()`
- `Sources/GitHubService+CheckStatusParsing.swift:153-176` — `resolveOverallStatus()`
- `Sources/GitHubService+NodeConversion.swift:33-56` — `convertNode()` maps CIResult to PullRequest
- `Sources/PRManager.swift:49-52` — `availableCheckNames` for autocomplete
- `Sources/PRManager.swift:54-56` — `filterSettings` with `didSet` persistence
- `Sources/PRRowView.swift:55-83` — Expandable failed checks list
- `Sources/PRRowView.swift:167-191` — CI badge with expand toggle
- `Sources/PRRowView.swift:203-211` — `ciText` using check counts
- `Sources/ContentView.swift:34-48` — Readiness partitioning
- `Sources/SettingsView.swift:86-162` — Review Readiness settings section
- `Sources/Strings.swift:141-153` — Readiness strings

## Related Research

- `thoughts/shared/research/2026-02-17-ready-not-ready-review-sections.md` — Ready/Not Ready sections research
- `thoughts/shared/plans/2026-02-17-ready-not-ready-review-sections.md` — Implementation plan for readiness sections
- `thoughts/shared/research/2026-02-10-reviewability-filter-controls.md` — Filter controls research
- `thoughts/shared/research/2026-02-10-architecture-and-design-patterns.md` — Architecture documentation

## Resolved Questions

1. **Option 2 (Effective Properties) chosen over Option 3.** There is value in showing "these checks were ignored" in the UI in the future — raw data must be preserved. This rules out Option 3's lossy post-processing. Option 2's computed "effective" methods keep the full truth on the model while giving every consumer access to filtered results.

2. **Semantic C: Mutually exclusive lists with validation.** The UI should validate and block a check from being added to `ignoredCheckNames` if it already exists in `requiredCheckNames` (and vice versa). This prevents ambiguous configurations entirely. The settings UI should warn the user when they attempt this.

3. **Reviews tab only.** The ignore list applies exclusively to the Reviews tab — readiness partitioning, CI badge display, and failed-checks list on review PRs. The "My PRs" tab continues to show the full, unfiltered CI status.

4. **Visually distinct settings sections.** "Required CI Checks" and "Ignored CI Checks" should be separate, clearly labeled sections in Settings with their own descriptions, not grouped under a shared umbrella.

5. **Trigger a refresh on settings change.** Changing the ignore list (or required checks list) should immediately trigger a `refreshAll()` call, so the user sees up-to-date data reflecting their new configuration. Since Option 2 uses computed properties rather than mutating model data, a refresh ensures the views re-evaluate with the latest settings. Investigate whether the existing `filterSettings.didSet` on `PRManager` can also kick off a refresh.

## Revised Design Implications

These decisions refine the implementation approach:

- **Option 2 is confirmed**: Add `effectiveCIStatus(ignoredChecks:)`, `effectiveFailedChecks(ignoredChecks:)`, `effectiveCheckCounts(ignoredChecks:)` as methods on `PullRequest`. Raw `ciStatus`, `failedChecks`, and counts remain untouched.
- **PRRowView must be updated**: Since raw data is preserved, `PRRowView` needs to call the effective methods when rendering review PRs. This means PRRowView needs access to the ignore list — either via `@EnvironmentObject` (PRManager) or as an explicit parameter. A new `ignoredCheckNames` parameter (or a wrapper view that provides it) is the cleanest approach.
- **Scope is limited to Reviews tab**: The effective methods are only called when `selectedTab == .reviews`. On the "My PRs" tab, PRRowView uses raw values as-is. This could be handled by passing an empty `ignoredChecks` list for the My PRs tab.
- **Validation in SettingsView**: The `addRequiredCheck()` and (new) `addIgnoredCheck()` methods must cross-check the other list and show an inline warning or prevent the addition.
- **Refresh on change**: The `filterSettings.didSet` in PRManager already saves to UserDefaults. It can additionally call `Task { await refreshAll() }` to immediately re-fetch, ensuring the UI reflects the new configuration.
