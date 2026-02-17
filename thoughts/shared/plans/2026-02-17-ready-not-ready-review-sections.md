# Ready vs Not Ready Review Sections — Implementation Plan

## Overview

Restructure the Reviews tab from a flat repo-grouped list into two top-level readiness sections — **"Ready for Review"** and **"Not Ready for Review"** — with repository groups nested within each section (Option A from the research doc). Additionally, add a **required CI checks** configuration so users can specify individual check names (e.g., "Bazel-Pipeline-PR") that must pass for a PR to be considered ready.

## Current State Analysis

The Reviews tab currently shows all review-requested PRs in a flat list grouped by repository:

```
Reviews Tab
├── org/repo-a (2)
│   ├── PR #123 - Fix login        [Open] [CI ✓]
│   └── PR #789 - WIP feature      [Draft] [CI ✗]
└── org/repo-b (1)
    └── PR #456 - Add tests        [Open] [CI ✓]
```

**Data flow:**
```
PRManager.reviewPRs
  → ContentView.filteredPRs (FilterSettings.applyReviewFilters)
    → ContentView.groupedPRs (PRGrouping.grouped)
      → ForEach repoSection → PRRowView
```

**Key code locations:**
- `Models.swift:6-117` — `PullRequest` struct, enums, `CheckInfo`
- `Models.swift:122-165` — `FilterSettings` with `applyReviewFilters()`
- `ContentView.swift:22-29` — `filteredPRs` and `groupedPRs` computed properties
- `ContentView.swift:90-146` — `prList` and `repoSection()` rendering
- `GitHubService.swift:333-367` — `tallyCheckContexts()` processes individual check nodes
- `PRGrouping.swift:16-38` — repo grouping and sort logic
- `SettingsView.swift:85-103` — "Review Filters" settings section
- `SettingsStore.swift:43-63` — FilterSettings persistence (JSON via UserDefaults)
- `PRManager.swift:21-37` — `collapsedRepos` and `filterSettings` with `didSet` persistence

**Key discovery:** The GraphQL query already fetches per-check details (`name`, `status`, `conclusion`, `detailsUrl`) via `statusCheckRollup.contexts`. Currently only **failed** check names are stored as `failedChecks: [CheckInfo]`. We need to store **all** check results to evaluate required-check readiness.

## Desired End State

After implementation:

1. The Reviews tab shows two collapsible top-level sections:
   - **"Ready for Review (N)"** — expanded by default, green checkmark icon
   - **"Not Ready (N)"** — collapsed by default, clock icon, secondary color
2. Each section contains familiar repo-grouped subsections with collapsible headers
3. The existing `FilterSettings` hide toggles still work — they remove PRs entirely before the readiness split
4. A new "Review Readiness" section in Settings lets the user specify required CI check names
5. When required checks are configured, only those checks determine CI readiness (other failures are ignored; checks not present on a PR are also ignored)
6. When no required checks are configured, the overall `ciStatus` rollup is used (current behavior)
7. Settings offers autocomplete for check names based on recently-seen checks across all fetched PRs

**Verification:**
```
Reviews Tab
├── ✅ Ready for Review (3)
│   ├── org/repo-a (1)
│   │   └── PR #123 - Fix login        [Open] [CI ✓] [Review Required]
│   └── org/repo-b (2)
│       ├── PR #456 - Add tests        [Open] [CI ✓] [Approved]
│       └── PR #457 - Fix flaky test   [Open] [CI ✓] [Review Required]
│
└── ⏳ Not Ready for Review (2)          ← collapsed by default
    ├── org/repo-a (1)
    │   └── PR #789 - WIP feature      [Draft]
    └── org/repo-c (1)
        └── PR #101 - New endpoint      [CI: Bazel-Pipeline-PR pending]
```

## What We're NOT Doing

- **Per-repo required checks** — Required check names are global, not per-repository. If a configured check name doesn't exist on a PR (because that repo's CI pipeline doesn't include it), the check is **ignored** (assumed passing). This makes a single global list work naturally across heterogeneous repos — e.g., configuring "Bazel-Pipeline-PR" won't block Android PRs that don't have that job.
- **Readiness sections on the "My PRs" tab** — Only the Reviews tab gets readiness sections. My PRs keeps its current flat repo-grouped layout.
- **Custom "not ready reason" UI** — The existing `PRRowView` badges (Draft, CI status, Conflicts) already communicate why a PR isn't ready. We won't add a separate reason label.
- **Readiness-aware notifications** — Notifications remain based on CI status changes for authored PRs, not readiness transitions. However, this is a valuable future enhancement — see [Future Enhancements](#future-enhancements) below.

## Design Principle: Honest Information, Semantic Grouping

The readiness sections are a **semantic grouping recommendation** — they help the reviewer answer "what can I act on right now?" by sorting PRs into two buckets. However, the actual CI status badges, failed checks list, review badges, and all other information on each PR row (`PRRowView`) continue to display the **true, unfiltered status**.

Concretely: if a user configures "Bazel-Pipeline-PR" as the only required check, and a PR has Bazel passing but lint failing, that PR lands in "Ready for Review" — but its CI badge still honestly shows "1 failed" with the expandable failure list. We don't hide or alter CI information based on the readiness configuration. The readiness sections are an organizational layer on top of the existing, truthful data display.

---

## Implementation Approach

Four phases, each independently testable:

1. **Phase 1:** Data model changes — `CheckResult`, `checkResults` on `PullRequest`, `requiredCheckNames` on `FilterSettings`, `isReady()` predicate, and updated `tallyCheckContexts()` parsing.
2. **Phase 2:** Persistence and state — collapsed readiness sections state on `PRManager`, aggregated check names for autocomplete.
3. **Phase 3:** Reviews tab UI — readiness sections in `ContentView`, collapsible headers, edge cases.
4. **Phase 4:** Required checks settings UI — editor in `SettingsView` with add/remove and autocomplete.

---

## Phase 1: Data Model, Parsing & Readiness Logic

### Overview

Add the data structures needed to store all individual check results, configure required check names, and compute readiness. Update `GitHubService` to populate the new fields.

### Changes Required

#### 1. New types and fields on `PullRequest`

**File:** `Sources/Models.swift`

Add `CheckStatus` enum and `CheckResult` struct inside `PullRequest` (alongside existing `CheckInfo`):

```swift
// Inside PullRequest, after CheckInfo:

enum CheckStatus: String, Codable {
    case passed
    case failed
    case pending
}

struct CheckResult: Codable, Equatable {
    let name: String
    let status: CheckStatus
    let detailsUrl: URL?
}
```

Add a new stored property on `PullRequest`:

```swift
var checkResults: [CheckResult]
```

Add it after `failedChecks` (line 28), keeping the existing `failedChecks` property intact for backward compatibility with `PRRowView`.

Add readiness methods on `PullRequest`:

```swift
// After the existing computed properties (after line 68):

/// Whether this PR is ready for review given the user's required-check configuration.
func isReady(requiredChecks: [String]) -> Bool {
    guard state != .draft else { return false }
    guard mergeable != .conflicting else { return false }

    if requiredChecks.isEmpty {
        // No specific checks configured — use overall CI rollup
        return ciStatus != .failure && ciStatus != .pending
    }

    // Only evaluate the named required checks.
    // If a required check name isn't present on this PR (e.g., the repo
    // doesn't have that CI job), it's ignored — assumed passing.
    for name in requiredChecks {
        guard let check = checkResults.first(where: { $0.name == name }) else {
            continue // check doesn't exist on this PR's repo — ignore it
        }
        if check.status != .passed { return false }
    }
    return true
}
```

#### 2. Add `requiredCheckNames` to `FilterSettings`

**File:** `Sources/Models.swift`

Add to `FilterSettings`:

```swift
var requiredCheckNames: [String]
```

Update `init`:

```swift
init(
    hideDrafts: Bool = true,
    hideCIFailing: Bool = false,
    hideCIPending: Bool = false,
    hideConflicting: Bool = false,
    hideApproved: Bool = false,
    requiredCheckNames: [String] = []
) {
    self.hideDrafts = hideDrafts
    self.hideCIFailing = hideCIFailing
    self.hideCIPending = hideCIPending
    self.hideConflicting = hideConflicting
    self.hideApproved = hideApproved
    self.requiredCheckNames = requiredCheckNames
}
```

Update the custom `init(from:)` decoder:

```swift
requiredCheckNames = try container.decodeIfPresent([String].self, forKey: .requiredCheckNames) ?? []
```

#### 3. Update `GitHubService` to populate all check results

**File:** `Sources/GitHubService.swift`

Update `CheckCounts` (line 326) to include all check results:

```swift
struct CheckCounts {
    var passed: Int
    var failed: Int
    var pending: Int
    var failedChecks: [PullRequest.CheckInfo]
    var allChecks: [PullRequest.CheckResult]  // NEW
}
```

Update `tallyCheckContexts()` (line 333) — initialize `allChecks` and append to it alongside the existing counting logic:

```swift
func tallyCheckContexts(_ contexts: [PRNode.CheckContext]) -> CheckCounts {
    var counts = CheckCounts(passed: 0, failed: 0, pending: 0, failedChecks: [], allChecks: [])

    for ctx in contexts {
        if let contextName = ctx.context {
            // StatusContext node
            switch ctx.state ?? "" {
            case "SUCCESS":
                counts.passed += 1
                counts.allChecks.append(PullRequest.CheckResult(
                    name: contextName, status: .passed,
                    detailsUrl: ctx.targetUrl.flatMap { URL(string: $0) }
                ))
            case "FAILURE", "ERROR":
                counts.failed += 1
                let targetUrl = ctx.targetUrl.flatMap { URL(string: $0) }
                counts.failedChecks.append(PullRequest.CheckInfo(name: contextName, detailsUrl: targetUrl))
                counts.allChecks.append(PullRequest.CheckResult(
                    name: contextName, status: .failed, detailsUrl: targetUrl
                ))
            case "PENDING", "EXPECTED":
                counts.pending += 1
                counts.allChecks.append(PullRequest.CheckResult(
                    name: contextName, status: .pending,
                    detailsUrl: ctx.targetUrl.flatMap { URL(string: $0) }
                ))
            default:
                counts.pending += 1
                counts.allChecks.append(PullRequest.CheckResult(
                    name: contextName, status: .pending,
                    detailsUrl: ctx.targetUrl.flatMap { URL(string: $0) }
                ))
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
                if let name = ctx.name {
                    counts.allChecks.append(PullRequest.CheckResult(
                        name: name, status: .pending,
                        detailsUrl: ctx.detailsUrl.flatMap { URL(string: $0) }
                    ))
                }
            }
        }
    }

    return counts
}
```

Update `classifyCompletedCheckContext()` (line 369) to also append to `allChecks`:

```swift
func classifyCompletedCheckContext(
    _ ctx: PRNode.CheckContext,
    conclusion: String,
    counts: inout CheckCounts
) {
    let detailsUrl = ctx.detailsUrl.flatMap { URL(string: $0) }
    switch conclusion {
    case "SUCCESS", "SKIPPED", "NEUTRAL":
        counts.passed += 1
        if let name = ctx.name {
            counts.allChecks.append(PullRequest.CheckResult(
                name: name, status: .passed, detailsUrl: detailsUrl
            ))
        }
    default:
        counts.failed += 1
        if let name = ctx.name {
            counts.failedChecks.append(PullRequest.CheckInfo(name: name, detailsUrl: detailsUrl))
            counts.allChecks.append(PullRequest.CheckResult(
                name: name, status: .failed, detailsUrl: detailsUrl
            ))
        }
    }
}
```

Update `CIResult` (line 272) to carry `checkResults`:

```swift
struct CIResult {
    let status: PullRequest.CIStatus
    let total: Int
    let passed: Int
    let failed: Int
    let failedChecks: [PullRequest.CheckInfo]
    let checkResults: [PullRequest.CheckResult]  // NEW
}
```

Update `parseCheckStatus()` (line 288) to pass through:

```swift
func parseCheckStatus(from node: PRNode) -> CIResult {
    guard let rollupData = extractRollupData(from: node) else {
        return CIResult(status: .unknown, total: 0, passed: 0, failed: 0,
                        failedChecks: [], checkResults: [])
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
        failedChecks: counts.failedChecks,
        checkResults: counts.allChecks
    )
}
```

Update `convertNode()` (line 197) to pass `checkResults` to the `PullRequest` initializer:

```swift
return PullRequest(
    // ... existing fields ...
    failedChecks: checkResult.failedChecks,
    checkResults: checkResult.checkResults  // NEW
)
```

#### 4. Update test fixtures

**File:** `Tests/FilterSettingsTests.swift`

Update `PullRequest.fixture()` to include `checkResults`:

```swift
static func fixture(
    // ... existing parameters ...
    failedChecks: [CheckInfo] = [],
    checkResults: [CheckResult] = []  // NEW
) -> PullRequest {
    PullRequest(
        // ... existing fields ...
        failedChecks: failedChecks,
        checkResults: checkResults  // NEW
    )
}
```

**File:** `Tests/GitHubServiceParsingTests.swift`

Add tests for `allChecks` population in `tallyCheckContexts`:

```swift
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
```

#### 5. Add readiness predicate tests

**File:** `Tests/PullRequestTests.swift` (or new `Tests/ReadinessTests.swift`)

```swift
@Suite struct ReadinessTests {
    // Default mode (no required checks)

    @Test func openPRWithPassingCIIsReady() {
        let pr = PullRequest.fixture(state: .open, ciStatus: .success, mergeable: .mergeable)
        #expect(pr.isReady(requiredChecks: []))
    }

    @Test func draftPRIsNotReady() {
        let pr = PullRequest.fixture(state: .draft, ciStatus: .success)
        #expect(!pr.isReady(requiredChecks: []))
    }

    @Test func conflictingPRIsNotReady() {
        let pr = PullRequest.fixture(state: .open, ciStatus: .success, mergeable: .conflicting)
        #expect(!pr.isReady(requiredChecks: []))
    }

    @Test func failingCIIsNotReadyInDefaultMode() {
        let pr = PullRequest.fixture(state: .open, ciStatus: .failure)
        #expect(!pr.isReady(requiredChecks: []))
    }

    @Test func pendingCIIsNotReadyInDefaultMode() {
        let pr = PullRequest.fixture(state: .open, ciStatus: .pending)
        #expect(!pr.isReady(requiredChecks: []))
    }

    @Test func unknownCIIsReadyInDefaultMode() {
        let pr = PullRequest.fixture(state: .open, ciStatus: .unknown)
        #expect(pr.isReady(requiredChecks: []))
    }

    // Required checks mode

    @Test func requiredCheckPassingIsReady() {
        let pr = PullRequest.fixture(
            state: .open, ciStatus: .failure, // overall CI failing
            checkResults: [
                .init(name: "Bazel-Pipeline-PR", status: .passed, detailsUrl: nil),
                .init(name: "lint", status: .failed, detailsUrl: nil), // non-required
            ]
        )
        #expect(pr.isReady(requiredChecks: ["Bazel-Pipeline-PR"]))
    }

    @Test func requiredCheckFailingIsNotReady() {
        let pr = PullRequest.fixture(
            state: .open,
            checkResults: [
                .init(name: "Bazel-Pipeline-PR", status: .failed, detailsUrl: nil),
            ]
        )
        #expect(!pr.isReady(requiredChecks: ["Bazel-Pipeline-PR"]))
    }

    @Test func requiredCheckMissingIsIgnored() {
        // PR from a repo that doesn't have "Bazel-Pipeline-PR" at all —
        // the missing check is ignored (assumed passing), so the PR is ready.
        let pr = PullRequest.fixture(state: .open, checkResults: [])
        #expect(pr.isReady(requiredChecks: ["Bazel-Pipeline-PR"]))
    }

    @Test func requiredCheckMissingWithOtherCheckPresent() {
        // Android repo: has "android-build" (passing) but not "Bazel-Pipeline-PR".
        // Both are in requiredChecks. Missing one is ignored, present one passes → ready.
        let pr = PullRequest.fixture(
            state: .open,
            checkResults: [
                .init(name: "android-build", status: .passed, detailsUrl: nil),
            ]
        )
        #expect(pr.isReady(requiredChecks: ["Bazel-Pipeline-PR", "android-build"]))
    }

    @Test func requiredCheckPresentButFailingIsNotReady() {
        // The check exists on this repo but is failing — not ready.
        let pr = PullRequest.fixture(
            state: .open,
            checkResults: [
                .init(name: "Bazel-Pipeline-PR", status: .failed, detailsUrl: nil),
                .init(name: "android-build", status: .passed, detailsUrl: nil),
            ]
        )
        #expect(!pr.isReady(requiredChecks: ["Bazel-Pipeline-PR", "android-build"]))
    }

    @Test func allRequiredChecksMissingIsReady() {
        // Edge case: all required checks are missing (none of them exist on this repo).
        // All are ignored → falls through to "ready" (draft/conflict guards already passed).
        let pr = PullRequest.fixture(state: .open, checkResults: [
            .init(name: "unrelated-check", status: .passed, detailsUrl: nil),
        ])
        #expect(pr.isReady(requiredChecks: ["Bazel-Pipeline-PR", "ios-lint"]))
    }

    @Test func multipleRequiredChecksAllMustPass() {
        let pr = PullRequest.fixture(
            state: .open,
            checkResults: [
                .init(name: "build", status: .passed, detailsUrl: nil),
                .init(name: "lint", status: .pending, detailsUrl: nil),
            ]
        )
        #expect(!pr.isReady(requiredChecks: ["build", "lint"]))
    }

    @Test func requiredChecksDontOverrideDraftStatus() {
        let pr = PullRequest.fixture(
            state: .draft,
            checkResults: [
                .init(name: "build", status: .passed, detailsUrl: nil),
            ]
        )
        #expect(!pr.isReady(requiredChecks: ["build"]))
    }

    @Test func requiredChecksDontOverrideConflicts() {
        let pr = PullRequest.fixture(
            state: .open, mergeable: .conflicting,
            checkResults: [
                .init(name: "build", status: .passed, detailsUrl: nil),
            ]
        )
        #expect(!pr.isReady(requiredChecks: ["build"]))
    }
}
```

#### 6. Update `FilterSettings` tests

**File:** `Tests/FilterSettingsTests.swift`

Add tests for `requiredCheckNames` serialization:

```swift
@Test func codableRoundTripWithRequiredCheckNames() throws {
    let original = FilterSettings(requiredCheckNames: ["build", "lint"])
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(FilterSettings.self, from: data)
    #expect(decoded.requiredCheckNames == ["build", "lint"])
}

@Test func decodingWithoutRequiredCheckNamesDefaultsToEmpty() throws {
    let json = #"{"hideDrafts": true}"#.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(FilterSettings.self, from: json)
    #expect(decoded.requiredCheckNames.isEmpty)
}
```

### Success Criteria

#### Automated Verification:
- [ ] Build succeeds: `swift build`
- [ ] All existing tests pass: `swift test`
- [ ] New readiness predicate tests pass
- [ ] New FilterSettings serialization tests pass
- [ ] New `tallyCheckContexts` allChecks tests pass

#### Manual Verification:
- [ ] N/A — no UI changes in this phase

**Implementation Note:** After completing this phase and all automated verification passes, proceed to Phase 2.

---

## Phase 2: Persistence & State Management

### Overview

Add persistence for the collapsed readiness sections state and expose aggregated check names on `PRManager` for the settings autocomplete feature.

### Changes Required

#### 1. Add collapsed readiness sections to `SettingsStoreProtocol`

**File:** `Sources/SettingsStoreProtocol.swift`

```swift
protocol SettingsStoreProtocol {
    // ... existing methods ...
    func loadCollapsedReadinessSections() -> Set<String>
    func saveCollapsedReadinessSections(_ value: Set<String>)
}
```

#### 2. Implement in `SettingsStore`

**File:** `Sources/SettingsStore.swift`

Add a new key constant:

```swift
static let collapsedReadinessSectionsKey = AppConstants.DefaultsKey.collapsedReadinessSections
```

Add load/save methods:

```swift
func loadCollapsedReadinessSections() -> Set<String> {
    guard let array = defaults.stringArray(forKey: Self.collapsedReadinessSectionsKey) else {
        // First launch: "Not Ready" collapsed by default
        return ["notReady"]
    }
    let result = Set(array)
    logger.debug("loadCollapsedReadinessSections: \(result.count) sections")
    return result
}

func saveCollapsedReadinessSections(_ value: Set<String>) {
    defaults.set(Array(value), forKey: Self.collapsedReadinessSectionsKey)
    logger.debug("saveCollapsedReadinessSections: \(value.count) sections")
}
```

#### 3. Add AppConstants key

**File:** `Sources/AppConstants.swift` (or wherever `DefaultsKey` is defined)

Add:

```swift
static let collapsedReadinessSections = "collapsedReadinessSections"
```

#### 4. Add state to `PRManager`

**File:** `Sources/PRManager.swift`

Add published property (after `collapsedRepos`):

```swift
@Published var collapsedReadinessSections: Set<String> = [] {
    didSet { settingsStore.saveCollapsedReadinessSections(collapsedReadinessSections) }
}

func toggleReadinessSectionCollapsed(_ section: String) {
    if collapsedReadinessSections.contains(section) {
        collapsedReadinessSections.remove(section)
    } else {
        collapsedReadinessSections.insert(section)
    }
}
```

Load in `init`:

```swift
self.collapsedReadinessSections = settingsStore.loadCollapsedReadinessSections()
```

#### 5. Add aggregated check names for autocomplete

**File:** `Sources/PRManager.swift`

Add a computed property that aggregates all unique check names across fetched review PRs:

```swift
/// All unique check names seen across review PRs, sorted alphabetically.
/// Used for autocomplete in the required-checks settings UI.
var availableCheckNames: [String] {
    let names = Set(reviewPRs.flatMap { $0.checkResults.map(\.name) })
    return names.sorted()
}
```

#### 6. Update mock/test `SettingsStoreProtocol` conformances

Any test mocks that conform to `SettingsStoreProtocol` need stubs for the new methods:

**File:** `Tests/PRManagerTests.swift` (or wherever `MockSettingsStore` lives)

```swift
var savedCollapsedReadinessSections: Set<String> = ["notReady"]

func loadCollapsedReadinessSections() -> Set<String> {
    savedCollapsedReadinessSections
}

func saveCollapsedReadinessSections(_ value: Set<String>) {
    savedCollapsedReadinessSections = value
}
```

### Success Criteria

#### Automated Verification:
- [ ] Build succeeds: `swift build`
- [ ] All tests pass: `swift test`
- [ ] Collapsed readiness sections persist across load/save cycle (add unit test to `SettingsStoreTests`)

#### Manual Verification:
- [ ] N/A — no UI changes in this phase

**Implementation Note:** After completing this phase and all automated verification passes, proceed to Phase 3.

---

## Phase 3: Reviews Tab UI — Readiness Sections

### Overview

The core UI change. Replace the flat repo-grouped list on the Reviews tab with two top-level readiness sections, each containing repo groups. "Not Ready" is collapsed by default.

### Changes Required

#### 1. Add readiness strings

**File:** `Sources/Strings.swift`

Add a new `Readiness` section:

```swift
enum Readiness {
    static func readyForReview(_ count: Int) -> String {
        "Ready for Review (\(count))"
    }
    static func notReady(_ count: Int) -> String {
        "Not Ready (\(count))"
    }
}
```

#### 2. Partition PRs and group by readiness in `ContentView`

**File:** `Sources/ContentView.swift`

Add computed properties for the readiness-split grouping (after `groupedPRs`):

```swift
// MARK: - Readiness Partitioning (Reviews tab only)

private var readyPRs: [PullRequest] {
    filteredPRs.filter { $0.isReady(requiredChecks: manager.filterSettings.requiredCheckNames) }
}

private var notReadyPRs: [PullRequest] {
    filteredPRs.filter { !$0.isReady(requiredChecks: manager.filterSettings.requiredCheckNames) }
}

private var groupedReadyPRs: [(repo: String, prs: [PullRequest])] {
    PRGrouping.grouped(prs: readyPRs, isReviews: true)
}

private var groupedNotReadyPRs: [(repo: String, prs: [PullRequest])] {
    PRGrouping.grouped(prs: notReadyPRs, isReviews: true)
}
```

#### 3. Update `prList` to render readiness sections on the Reviews tab

**File:** `Sources/ContentView.swift`

Replace the `prList` content (lines 90-110) so that when `selectedTab == .reviews`, it renders readiness sections instead of the flat grouped list:

```swift
private var prList: some View {
    Group {
        if activePRs.isEmpty && !manager.hasCompletedInitialLoad {
            loadingState
        } else if activePRs.isEmpty {
            emptyState
        } else if filteredPRs.isEmpty {
            filteredEmptyState
        } else if selectedTab == .reviews {
            reviewsReadinessList
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(groupedPRs, id: \.repo) { group in
                        repoSection(repo: group.repo, prs: group.prs)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
    .frame(maxHeight: .infinity)
}
```

#### 4. Add `reviewsReadinessList` view

**File:** `Sources/ContentView.swift`

```swift
private var reviewsReadinessList: some View {
    ScrollView {
        LazyVStack(spacing: 0) {
            if !readyPRs.isEmpty {
                readinessSection(
                    key: "ready",
                    title: Strings.Readiness.readyForReview(readyPRs.count),
                    icon: "checkmark.circle.fill",
                    color: .green,
                    groups: groupedReadyPRs
                )
            }
            if !notReadyPRs.isEmpty {
                readinessSection(
                    key: "notReady",
                    title: Strings.Readiness.notReady(notReadyPRs.count),
                    icon: "clock.fill",
                    color: .secondary,
                    groups: groupedNotReadyPRs
                )
            }
        }
        .padding(.vertical, 4)
    }
}
```

#### 5. Add `readinessSection` and `readinessSectionHeader` views

**File:** `Sources/ContentView.swift`

```swift
// MARK: - Readiness Section

private func readinessSection(
    key: String,
    title: String,
    icon: String,
    color: Color,
    groups: [(repo: String, prs: [PullRequest])]
) -> some View {
    let isCollapsed = manager.collapsedReadinessSections.contains(key)

    return VStack(spacing: 0) {
        readinessSectionHeader(
            key: key,
            title: title,
            icon: icon,
            color: color,
            isCollapsed: isCollapsed,
            prs: groups.flatMap(\.prs)
        )

        if !isCollapsed {
            ForEach(groups, id: \.repo) { group in
                repoSection(repo: group.repo, prs: group.prs)
            }
        }
    }
}

private func readinessSectionHeader(
    key: String,
    title: String,
    icon: String,
    color: Color,
    isCollapsed: Bool,
    prs: [PullRequest]
) -> some View {
    Button {
        withAnimation(.easeInOut(duration: 0.2)) {
            manager.toggleReadinessSectionCollapsed(key)
        }
    } label: {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundColor(color)
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))

            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundColor(color)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(color)

            Spacer()

            if isCollapsed {
                HStack(spacing: 3) {
                    ForEach(prs) { pullRequest in
                        Circle()
                            .fill(pullRequest.statusColor)
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(Color.secondary.opacity(0.08))
    .accessibilityLabel("\(title), \(isCollapsed ? "collapsed" : "expanded")")
    .accessibilityHint("Double-tap to \(isCollapsed ? "expand" : "collapse")")
}
```

#### 6. Handle edge cases

When all PRs are ready (no "Not Ready" section appears) or all are not ready (no "Ready" section appears), the UI naturally handles this because we only render non-empty sections. However, we should also handle the case where filters hide all PRs:

The existing `filteredEmptyState` already handles this — if `filteredPRs.isEmpty` after filtering, we show "All review requests hidden." No additional changes needed.

### Success Criteria

#### Automated Verification:
- [ ] Build succeeds: `swift build`
- [ ] All tests pass: `swift test`

#### Manual Verification:
- [ ] Reviews tab shows "Ready for Review" and "Not Ready" sections
- [ ] "Not Ready" section is collapsed by default on first launch
- [ ] Clicking a readiness section header toggles collapse/expand with animation
- [ ] Collapsed readiness section shows status dot summary (like collapsed repos)
- [ ] Repo groups within each section have collapsible headers (existing behavior preserved)
- [ ] PR row click, context menu, and failed checks expansion all work within sections
- [ ] Existing filter toggles (hide drafts, etc.) still remove PRs entirely before the readiness split
- [ ] "My PRs" tab is unaffected — still shows flat repo-grouped list
- [ ] When all PRs are ready, only "Ready for Review" section appears (no empty "Not Ready")
- [ ] When all PRs are not ready, only "Not Ready" section appears
- [ ] Collapse state persists across app restarts

**Implementation Note:** After completing this phase and all manual verification passes, proceed to Phase 4.

---

## Phase 4: Required Checks Settings UI

### Overview

Add a "Review Readiness" section to `SettingsView` where the user can manage required CI check names. Includes autocomplete from recently-seen check names.

### Changes Required

#### 1. Add readiness settings strings

**File:** `Sources/Strings.swift`

Extend the `Readiness` enum:

```swift
enum Readiness {
    // ... existing ...
    static let settingsTitle = "Review Readiness"
    static let settingsDescription = "PRs won't appear as \"Ready for Review\" until these checks pass."
    static let addCheckPlaceholder = "Add check name..."
    static let noChecksSuggestion = "No check names seen yet. Check names appear after PRs are fetched."
    static let requiredChecksLabel = "Required CI Checks"
    static let tipText = "Check names must match the exact name shown in GitHub CI. Checks not present on a PR are ignored."
}
```

#### 2. Add required checks editor to `SettingsView`

**File:** `Sources/SettingsView.swift`

Add a new `@State` for the text field:

```swift
@State private var newCheckName = ""
```

Add a new section after the "Review Filters" section (after line 103):

```swift
Divider()

// Review Readiness Section
VStack(alignment: .leading, spacing: 8) {
    Text(Strings.Readiness.settingsTitle)
        .font(.headline)

    Text(Strings.Readiness.settingsDescription)
        .font(.caption)
        .foregroundColor(.secondary)

    // Current required checks list
    if !manager.filterSettings.requiredCheckNames.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(manager.filterSettings.requiredCheckNames, id: \.self) { name in
                HStack {
                    Text(name)
                        .font(.system(.caption, design: .monospaced))
                    Spacer()
                    Button {
                        manager.filterSettings.requiredCheckNames.removeAll { $0 == name }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(name)")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(4)
            }
        }
    }

    // Add new check name
    HStack(spacing: 6) {
        checkNameTextField
        Button {
            addRequiredCheck()
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.body)
        }
        .buttonStyle(.borderless)
        .disabled(newCheckName.trimmingCharacters(in: .whitespaces).isEmpty)
        .accessibilityLabel("Add check name")
    }

    // Autocomplete suggestions
    let suggestions = checkNameSuggestions
    if !suggestions.isEmpty && !newCheckName.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) {
                        newCheckName = suggestion
                        addRequiredCheck()
                    }
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundColor(.accentColor)
                    .cornerRadius(4)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    Text(Strings.Readiness.tipText)
        .font(.caption2)
        .foregroundColor(.secondary.opacity(0.7))
}
```

#### 3. Add helper methods on `SettingsView`

**File:** `Sources/SettingsView.swift`

```swift
private var checkNameTextField: some View {
    TextField(Strings.Readiness.addCheckPlaceholder, text: $newCheckName)
        .textFieldStyle(.roundedBorder)
        .font(.system(.caption, design: .monospaced))
        .onSubmit { addRequiredCheck() }
}

private func addRequiredCheck() {
    let trimmed = newCheckName.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty,
          !manager.filterSettings.requiredCheckNames.contains(trimmed) else { return }
    manager.filterSettings.requiredCheckNames.append(trimmed)
    newCheckName = ""
}

/// Autocomplete suggestions: check names seen in recent PRs that aren't already required,
/// filtered by current text field input.
private var checkNameSuggestions: [String] {
    let existing = Set(manager.filterSettings.requiredCheckNames)
    let query = newCheckName.lowercased()
    return manager.availableCheckNames
        .filter { !existing.contains($0) && $0.lowercased().contains(query) }
}
```

### Success Criteria

#### Automated Verification:
- [ ] Build succeeds: `swift build`
- [ ] All tests pass: `swift test`

#### Manual Verification:
- [ ] Settings shows "Review Readiness" section with title and description
- [ ] Adding a check name via text field + enter/button works
- [ ] Duplicate check names are prevented
- [ ] Removing a check name via X button works
- [ ] Autocomplete suggestions appear while typing (filtered from available check names)
- [ ] Clicking a suggestion adds it and clears the text field
- [ ] Added required check names persist across app restart
- [ ] With required checks configured, a PR with those checks passing appears in "Ready" even if other checks fail
- [ ] With required checks configured, a PR where a required check is failing/pending appears in "Not Ready"
- [ ] With required checks configured, a PR from a repo that doesn't have the configured check at all still appears in "Ready" (missing check is ignored)
- [ ] Removing all required checks reverts to default behavior (overall CI status)

**Implementation Note:** After completing this phase and all manual verification passes, the feature is complete.

---

## Testing Strategy

### Unit Tests (automated, per phase)

**Phase 1:**
- `ReadinessTests` — readiness predicate for all combinations: draft, conflicts, CI failing, CI pending, CI unknown, required checks passing/failing/pending, missing checks ignored (cross-repo), multiple required checks, all required checks missing
- `FilterSettingsCodableTests` — round-trip with `requiredCheckNames`, backward-compatible decoding
- `GitHubServiceParsingTests` — `allChecks` populated correctly for CheckRun and StatusContext nodes

**Phase 2:**
- `SettingsStoreTests` — collapsed readiness sections load/save, default-to-notReady-collapsed on first load

### Manual Testing Steps

1. Launch app with no saved settings → Reviews tab shows "Not Ready" collapsed
2. Open "Not Ready" section → expand, close app, reopen → section stays expanded
3. Configure required checks: "build" → PR with "build" passing but "lint" failing shows in "Ready"
4. Configure a check name that only exists on some repos (e.g., "Bazel-Pipeline-PR") → PRs from repos without that job still appear in "Ready" (the missing check is ignored)
5. Remove required checks → reverts to overall CI status for readiness
6. Enable "Hide drafts" filter → draft PRs don't appear in either section
7. Disable "Hide drafts" → drafts appear in "Not Ready" section
8. All PRs ready → only "Ready for Review" section visible
9. No PRs at all → empty state shown
10. Verify CI badges on PR rows still show honest status (e.g., "1 failed") even when the PR is in "Ready" due to required-check config

---

## Performance Considerations

- Readiness computation is O(n * m) where n = number of PRs and m = number of required check names. Both are small (typically n < 50, m < 5), so no optimization needed.
- The `availableCheckNames` computed property on `PRManager` iterates all review PRs and their check results on every access. For autocomplete, this is fine since it only runs when the settings UI is open. If performance becomes a concern, it could be cached and invalidated on refresh.
- The additional `checkResults` array on each `PullRequest` increases memory slightly, but check counts are typically < 100 per PR.

---

## Migration Notes

- **No breaking changes to persisted data.** `FilterSettings` uses `decodeIfPresent` for all new fields, so existing saved JSON decodes cleanly with new defaults (`requiredCheckNames: []`).
- **Collapsed readiness sections** use a new UserDefaults key. First launch defaults to `["notReady"]` (not-ready collapsed). No migration needed.
- **`PullRequest.checkResults`** is populated on the next fetch cycle. No stored PR data needs migration — all PR data is fetched fresh from GitHub on each refresh.

---

## Future Enhancements

Ideas that are out of scope for this plan but worth tracking for future implementation:

1. **Readiness-aware notifications** — Notify the reviewer when a PR transitions from "Not Ready" to "Ready for Review" (e.g., CI passes, conflicts resolved, or draft published). This would be valuable for reviewers monitoring PRs that aren't yet actionable — they could be notified exactly when a PR becomes reviewable instead of polling the app. Implementation would involve tracking previous readiness state per-PR (similar to the existing `previousCIStates` diff in `PRManager`) and sending a notification on ready-transition.

2. **Per-repo required checks** — If users want different required checks per repository (rather than the global "missing = ignored" approach), this could be added as an advanced configuration option. The current global-with-ignore approach should cover most workflows.

---

## References

- Research doc: `thoughts/shared/research/2026-02-17-ready-not-ready-review-sections.md`
- Related research: `thoughts/shared/research/2026-02-10-reviewability-filter-controls.md`
- Architecture: `thoughts/shared/research/2026-02-10-architecture-and-design-patterns.md`
