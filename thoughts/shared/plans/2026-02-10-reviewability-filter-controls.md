# Reviewability Filter Controls — Implementation Plan

## Overview

Add configurable filters to the Reviews tab that hide PRs not ready for review. Filters are configured in Settings (set-it-and-forget-it) and apply only to the Reviews tab — the My PRs tab remains an unfiltered at-a-glance dashboard. The core filter predicate is extracted as a pure function on a `FilterSettings` struct for maximum unit test coverage.

## Current State Analysis

- The `PullRequest` model already contains all four data signals needed: `state` (draft), `ciStatus` (CI pass/fail/pending), `mergeable` (conflicts), and `reviewDecision` (approved/changes/required).
- No GraphQL or API changes are needed.
- There is no filtering layer between the `@Published` PR arrays and the UI — `ContentView.activePRs` is a direct tab switch, and `groupedPRs` only groups and sorts.
- The test target exists (`Tests/`) with 26 passing tests in `GitHubServiceParsingTests.swift`.
- SwiftLint only lints `Sources/` (not `Tests/`).

### Key Discoveries:
- `ContentView.swift:14-19` — `activePRs` is the natural interception point for filtering
- `ContentView.swift:22-42` — `groupedPRs` consumes `activePRs` and must be rewired to consume `filteredPRs`
- `PRManager.swift:16-17` — Existing UserDefaults persistence pattern (key constants + `didSet`)
- `PRManager.swift:42-45` — Init loads persisted values (same pattern for filter settings)
- `SettingsView.swift:64-80` — Existing section pattern (headline + description + control group)
- `Models.swift:6-117` — Current model file at 117 lines (room for FilterSettings)

## Desired End State

The Reviews tab hides PRs based on user-configured filters. Five toggle settings control visibility: hide drafts (on by default), hide CI-failing, hide CI-pending, hide conflicting, and hide already-approved PRs. Settings are persisted across launches. The My PRs tab is unaffected.

### Verification:
1. `swift build` succeeds with zero warnings
2. `swift test` passes with all existing tests plus ~25 new filter tests
3. Settings window shows "Review Filters" section with five toggles
4. Toggling "Hide draft PRs" off in Settings → draft PRs appear on Reviews tab
5. All filters off → Reviews tab shows all PRs (same as before)
6. All PRs filtered out → Reviews tab shows "All review requests hidden by filters" message

## What We're NOT Doing

- No filter bar in ContentView — filters are settings-only, not inline toggles
- No filters on the My PRs tab — it's an unfiltered personal dashboard
- No merged PR audit tab (deferred)
- No repo-specific required check filtering (requires admin, deferred)
- No label-based filtering (Phase 2, requires GraphQL change)
- No changes to notification logic — notifications fire on the unfiltered data
- No changes to menu bar icon/badge — it reflects My PRs (unfiltered)

## Implementation Approach

The filter predicate is implemented as a pure function `applyReviewFilters(to:)` on the `FilterSettings` struct, making it fully testable without SwiftUI. `ContentView` calls this function and feeds the result into `groupedPRs`. `FilterSettings` is persisted as a JSON blob in UserDefaults using the same `didSet` pattern as `refreshInterval`.

Four phases, each independently buildable and verifiable:
1. Model + filter logic + tests (pure logic, zero UI)
2. PRManager integration + persistence (ViewModel wiring)
3. ContentView wiring (display layer)
4. SettingsView UI (configuration layer)

---

## Phase 1: FilterSettings Model + Filter Predicate + Unit Tests

### Overview
Define the `FilterSettings` struct with a `Codable` custom decoder (for forward compatibility), implement the filter predicate as a pure testable function, create a `PullRequest` test fixture helper, and write comprehensive unit tests.

### Changes Required:

#### 1. Add `FilterSettings` struct to Models.swift
**File**: `Sources/Models.swift`
**Where**: After the closing `}` of the `PullRequest` struct (after line 117)

```swift
// MARK: - Review Filter Settings

/// User preferences for hiding PRs on the Reviews tab that aren't ready for review.
struct FilterSettings: Codable, Equatable {
    var hideDrafts: Bool
    var hideCIFailing: Bool
    var hideCIPending: Bool
    var hideConflicting: Bool
    var hideApproved: Bool

    init(
        hideDrafts: Bool = true,
        hideCIFailing: Bool = false,
        hideCIPending: Bool = false,
        hideConflicting: Bool = false,
        hideApproved: Bool = false
    ) {
        self.hideDrafts = hideDrafts
        self.hideCIFailing = hideCIFailing
        self.hideCIPending = hideCIPending
        self.hideConflicting = hideConflicting
        self.hideApproved = hideApproved
    }

    // Custom decoder: use decodeIfPresent so that adding new filter
    // properties in the future doesn't break previously-saved JSON.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hideDrafts = try container.decodeIfPresent(Bool.self, forKey: .hideDrafts) ?? true
        hideCIFailing = try container.decodeIfPresent(Bool.self, forKey: .hideCIFailing) ?? false
        hideCIPending = try container.decodeIfPresent(Bool.self, forKey: .hideCIPending) ?? false
        hideConflicting = try container.decodeIfPresent(Bool.self, forKey: .hideConflicting) ?? false
        hideApproved = try container.decodeIfPresent(Bool.self, forKey: .hideApproved) ?? false
    }

    /// Filter a list of PRs for the Reviews tab, removing PRs that match enabled filters.
    func applyReviewFilters(to prs: [PullRequest]) -> [PullRequest] {
        prs.filter { pr in
            if hideDrafts && pr.state == .draft { return false }
            if hideCIFailing && pr.ciStatus == .failure { return false }
            if hideCIPending && pr.ciStatus == .pending { return false }
            if hideConflicting && pr.mergeable == .conflicting { return false }
            if hideApproved && pr.reviewDecision == .approved { return false }
            return true
        }
    }
}
```

#### 2. Create test file with fixture helper and comprehensive tests
**File**: `Tests/FilterSettingsTests.swift` (new file)

```swift
import XCTest
@testable import PRStatusWatcher

// MARK: - PullRequest Test Fixture

extension PullRequest {
    /// Create a PullRequest with sensible defaults for testing.
    /// Override only the properties relevant to each test case.
    static func fixture(
        owner: String = "test",
        repo: String = "repo",
        number: Int = 1,
        title: String = "Test PR",
        author: String = "testuser",
        state: PRState = .open,
        ciStatus: CIStatus = .success,
        isInMergeQueue: Bool = false,
        checksTotal: Int = 1,
        checksPassed: Int = 1,
        checksFailed: Int = 0,
        url: URL = URL(string: "https://github.com/test/repo/pull/1")!,
        headSHA: String = "abc1234",
        headRefName: String = "feature",
        lastFetched: Date = Date(),
        reviewDecision: ReviewDecision = .reviewRequired,
        mergeable: MergeableState = .mergeable,
        queuePosition: Int? = nil,
        approvalCount: Int = 0,
        failedChecks: [CheckInfo] = []
    ) -> PullRequest {
        PullRequest(
            owner: owner,
            repo: repo,
            number: number,
            title: title,
            author: author,
            state: state,
            ciStatus: ciStatus,
            isInMergeQueue: isInMergeQueue,
            checksTotal: checksTotal,
            checksPassed: checksPassed,
            checksFailed: checksFailed,
            url: url,
            headSHA: headSHA,
            headRefName: headRefName,
            lastFetched: lastFetched,
            reviewDecision: reviewDecision,
            mergeable: mergeable,
            queuePosition: queuePosition,
            approvalCount: approvalCount,
            failedChecks: failedChecks
        )
    }
}

// MARK: - FilterSettings Default Values

final class FilterSettingsDefaultsTests: XCTestCase {
    func testDefaultHideDraftsIsTrue() {
        XCTAssertTrue(FilterSettings().hideDrafts)
    }

    func testDefaultHideCIFailingIsFalse() {
        XCTAssertFalse(FilterSettings().hideCIFailing)
    }

    func testDefaultHideCIPendingIsFalse() {
        XCTAssertFalse(FilterSettings().hideCIPending)
    }

    func testDefaultHideConflictingIsFalse() {
        XCTAssertFalse(FilterSettings().hideConflicting)
    }

    func testDefaultHideApprovedIsFalse() {
        XCTAssertFalse(FilterSettings().hideApproved)
    }
}

// MARK: - FilterSettings Codable

final class FilterSettingsCodableTests: XCTestCase {
    func testCodableRoundTripDefaultValues() throws {
        let original = FilterSettings()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testCodableRoundTripCustomValues() throws {
        let original = FilterSettings(
            hideDrafts: false,
            hideCIFailing: true,
            hideCIPending: true,
            hideConflicting: true,
            hideApproved: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testDecodingEmptyJSONUsesDefaults() throws {
        let json = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: json)
        XCTAssertEqual(decoded, FilterSettings())
    }

    func testDecodingPartialJSONUsesDefaultsForMissingKeys() throws {
        let json = #"{"hideDrafts": false}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: json)
        XCTAssertFalse(decoded.hideDrafts)
        // All other properties should have their defaults
        XCTAssertFalse(decoded.hideCIFailing)
        XCTAssertFalse(decoded.hideCIPending)
        XCTAssertFalse(decoded.hideConflicting)
        XCTAssertFalse(decoded.hideApproved)
    }
}

// MARK: - Filter Predicate: Individual Filters

final class FilterPredicateTests: XCTestCase {
    // MARK: hideDrafts

    func testDefaultSettingsHideDraftPRs() {
        let prs = [
            PullRequest.fixture(number: 1, state: .draft),
            PullRequest.fixture(number: 2, state: .open),
        ]
        let result = FilterSettings().applyReviewFilters(to: prs)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.number, 2)
    }

    func testHideDraftsDisabledShowsDraftPRs() {
        let settings = FilterSettings(hideDrafts: false)
        let prs = [PullRequest.fixture(state: .draft)]
        let result = settings.applyReviewFilters(to: prs)
        XCTAssertEqual(result.count, 1)
    }

    func testHideDraftsDoesNotAffectOpenPRs() {
        let prs = [PullRequest.fixture(state: .open)]
        let result = FilterSettings().applyReviewFilters(to: prs)
        XCTAssertEqual(result.count, 1)
    }

    // MARK: hideCIFailing

    func testHideCIFailingFiltersFailingPRs() {
        let settings = FilterSettings(hideDrafts: false, hideCIFailing: true)
        let prs = [
            PullRequest.fixture(number: 1, ciStatus: .failure),
            PullRequest.fixture(number: 2, ciStatus: .success),
        ]
        let result = settings.applyReviewFilters(to: prs)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.number, 2)
    }

    func testHideCIFailingDoesNotAffectPendingOrSuccess() {
        let settings = FilterSettings(hideDrafts: false, hideCIFailing: true)
        let prs = [
            PullRequest.fixture(number: 1, ciStatus: .pending),
            PullRequest.fixture(number: 2, ciStatus: .success),
            PullRequest.fixture(number: 3, ciStatus: .unknown),
        ]
        let result = settings.applyReviewFilters(to: prs)
        XCTAssertEqual(result.count, 3)
    }

    // MARK: hideCIPending

    func testHideCIPendingFiltersPendingPRs() {
        let settings = FilterSettings(hideDrafts: false, hideCIPending: true)
        let prs = [
            PullRequest.fixture(number: 1, ciStatus: .pending),
            PullRequest.fixture(number: 2, ciStatus: .success),
        ]
        let result = settings.applyReviewFilters(to: prs)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.number, 2)
    }

    func testHideCIPendingDoesNotAffectFailureOrSuccess() {
        let settings = FilterSettings(hideDrafts: false, hideCIPending: true)
        let prs = [
            PullRequest.fixture(number: 1, ciStatus: .failure),
            PullRequest.fixture(number: 2, ciStatus: .success),
        ]
        let result = settings.applyReviewFilters(to: prs)
        XCTAssertEqual(result.count, 2)
    }

    // MARK: hideConflicting

    func testHideConflictingFiltersConflictingPRs() {
        let settings = FilterSettings(hideDrafts: false, hideConflicting: true)
        let prs = [
            PullRequest.fixture(number: 1, mergeable: .conflicting),
            PullRequest.fixture(number: 2, mergeable: .mergeable),
        ]
        let result = settings.applyReviewFilters(to: prs)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.number, 2)
    }

    func testHideConflictingDoesNotFilterUnknownMergeable() {
        let settings = FilterSettings(hideDrafts: false, hideConflicting: true)
        let prs = [PullRequest.fixture(mergeable: .unknown)]
        let result = settings.applyReviewFilters(to: prs)
        XCTAssertEqual(result.count, 1)
    }

    // MARK: hideApproved

    func testHideApprovedFiltersApprovedPRs() {
        let settings = FilterSettings(hideDrafts: false, hideApproved: true)
        let prs = [
            PullRequest.fixture(number: 1, reviewDecision: .approved),
            PullRequest.fixture(number: 2, reviewDecision: .reviewRequired),
        ]
        let result = settings.applyReviewFilters(to: prs)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.number, 2)
    }

    func testHideApprovedDoesNotAffectOtherDecisions() {
        let settings = FilterSettings(hideDrafts: false, hideApproved: true)
        let prs = [
            PullRequest.fixture(number: 1, reviewDecision: .reviewRequired),
            PullRequest.fixture(number: 2, reviewDecision: .changesRequested),
            PullRequest.fixture(number: 3, reviewDecision: .none),
        ]
        let result = settings.applyReviewFilters(to: prs)
        XCTAssertEqual(result.count, 3)
    }
}

// MARK: - Filter Predicate: Combinations & Edge Cases

final class FilterCombinationTests: XCTestCase {
    func testMultipleFiltersApplySimultaneously() {
        let settings = FilterSettings(
            hideDrafts: true,
            hideCIFailing: true,
            hideConflicting: true
        )
        let prs = [
            PullRequest.fixture(number: 1, state: .draft),                           // hidden: draft
            PullRequest.fixture(number: 2, ciStatus: .failure),                       // hidden: CI failing
            PullRequest.fixture(number: 3, mergeable: .conflicting),                  // hidden: conflicts
            PullRequest.fixture(number: 4, state: .open, ciStatus: .success),         // visible
        ]
        let result = settings.applyReviewFilters(to: prs)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.number, 4)
    }

    func testAllFiltersEnabledOnlyShowsCleanOpenPRs() {
        let settings = FilterSettings(
            hideDrafts: true,
            hideCIFailing: true,
            hideCIPending: true,
            hideConflicting: true,
            hideApproved: true
        )
        // This PR is: open, CI success, mergeable, review required — passes all filters
        let clean = PullRequest.fixture(
            number: 1,
            state: .open,
            ciStatus: .success,
            reviewDecision: .reviewRequired,
            mergeable: .mergeable
        )
        let result = settings.applyReviewFilters(to: [clean])
        XCTAssertEqual(result.count, 1)
    }

    func testNoFiltersEnabledReturnsAllPRs() {
        let settings = FilterSettings(
            hideDrafts: false,
            hideCIFailing: false,
            hideCIPending: false,
            hideConflicting: false,
            hideApproved: false
        )
        let prs = [
            PullRequest.fixture(number: 1, state: .draft),
            PullRequest.fixture(number: 2, ciStatus: .failure),
            PullRequest.fixture(number: 3, mergeable: .conflicting),
            PullRequest.fixture(number: 4, reviewDecision: .approved),
        ]
        let result = settings.applyReviewFilters(to: prs)
        XCTAssertEqual(result.count, 4)
    }

    func testEmptyInputReturnsEmpty() {
        let settings = FilterSettings()
        let result = settings.applyReviewFilters(to: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testAllPRsFilteredReturnsEmpty() {
        let settings = FilterSettings(hideDrafts: true)
        let prs = [
            PullRequest.fixture(number: 1, state: .draft),
            PullRequest.fixture(number: 2, state: .draft),
        ]
        let result = settings.applyReviewFilters(to: prs)
        XCTAssertTrue(result.isEmpty)
    }

    func testFilterPreservesOriginalOrder() {
        let settings = FilterSettings(hideDrafts: true)
        let prs = [
            PullRequest.fixture(number: 5, state: .open),
            PullRequest.fixture(number: 3, state: .draft),
            PullRequest.fixture(number: 1, state: .open),
            PullRequest.fixture(number: 4, state: .draft),
            PullRequest.fixture(number: 2, state: .open),
        ]
        let result = settings.applyReviewFilters(to: prs)
        XCTAssertEqual(result.map(\.number), [5, 1, 2])
    }

    func testPRMatchingMultipleFiltersIsHiddenOnce() {
        // A draft PR with failing CI and conflicts — should be hidden, not double-counted
        let settings = FilterSettings(
            hideDrafts: true,
            hideCIFailing: true,
            hideConflicting: true
        )
        let pr = PullRequest.fixture(state: .draft, ciStatus: .failure, mergeable: .conflicting)
        let result = settings.applyReviewFilters(to: [pr])
        XCTAssertTrue(result.isEmpty)
    }
}
```

### Success Criteria:

#### Automated Verification:
- [x] `swift build` succeeds with zero warnings/errors
- [x] `swift test` passes — all 26 existing tests plus ~27 new tests (53+ total)
- [x] No references to `FilterSettings` appear in any View or ViewModel yet (this phase is model-only)

#### Manual Verification:
- [x] None — this phase is pure logic with full automated coverage

---

## Phase 2: PRManager Integration + Persistence

### Overview
Add `@Published filterSettings` to `PRManager` with UserDefaults persistence, following the existing `refreshInterval` / `collapsedRepos` patterns.

### Changes Required:

#### 1. Add filterSettings property and persistence
**File**: `Sources/PRManager.swift`

**Add UserDefaults key** (after `collapsedReposKey` on line 17):
```swift
private static let filterSettingsKey = "filter_settings"
```

**Add published property** (after `collapsedRepos` on line 21):
```swift
@Published var filterSettings: FilterSettings = FilterSettings() {
    didSet {
        if let data = try? JSONEncoder().encode(filterSettings) {
            UserDefaults.standard.set(data, forKey: Self.filterSettingsKey)
        }
    }
}
```

**Load saved value in init** (after the `collapsedRepos` load on line 45, before `requestNotificationPermission()`):
```swift
if let data = UserDefaults.standard.data(forKey: Self.filterSettingsKey),
   let saved = try? JSONDecoder().decode(FilterSettings.self, from: data) {
    self.filterSettings = saved
}
```

**Important**: The `didSet` will NOT fire during init assignment (Swift behavior: `didSet` doesn't fire for assignments in the type's own `init`), so the load-then-assign pattern is safe — it won't write back to UserDefaults unnecessarily.

#### 2. Add persistence test
**File**: `Tests/FilterSettingsTests.swift`

Add a new test class at the bottom:

```swift
// MARK: - FilterSettings Persistence

final class FilterSettingsPersistenceTests: XCTestCase {
    private let testKey = "filter_settings_test"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: testKey)
        super.tearDown()
    }

    func testPersistAndReloadViaUserDefaults() throws {
        let original = FilterSettings(
            hideDrafts: false,
            hideCIFailing: true,
            hideCIPending: true,
            hideConflicting: true,
            hideApproved: true
        )

        // Persist
        let data = try JSONEncoder().encode(original)
        UserDefaults.standard.set(data, forKey: testKey)

        // Reload
        let loaded = UserDefaults.standard.data(forKey: testKey)!
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: loaded)

        XCTAssertEqual(decoded, original)
    }

    func testMissingKeyReturnsNilData() {
        let data = UserDefaults.standard.data(forKey: "nonexistent_filter_key")
        XCTAssertNil(data)
    }

    func testCorruptedDataFallsBackGracefully() {
        UserDefaults.standard.set(Data("not json".utf8), forKey: testKey)
        let data = UserDefaults.standard.data(forKey: testKey)!
        let decoded = try? JSONDecoder().decode(FilterSettings.self, from: data)
        XCTAssertNil(decoded)
        // Callers should fall back to FilterSettings() when decode returns nil
    }
}
```

### Success Criteria:

#### Automated Verification:
- [x] `swift build` succeeds with zero warnings/errors
- [x] `swift test` passes — all previous tests plus 3 new persistence tests
- [x] `PRManager` has a `filterSettings` property that persists via UserDefaults

#### Manual Verification:
- [x] None — persistence is covered by automated tests

---

## Phase 3: ContentView Wiring + Empty State

### Overview
Insert `filteredPRs` between `activePRs` and `groupedPRs`. Add a "filtered empty" state that distinguishes "no PRs at all" from "all PRs hidden by filters." Update `prList` to use the new computed properties.

### Changes Required:

#### 1. Add `filteredPRs` computed property
**File**: `Sources/ContentView.swift`
**Where**: After `activePRs` (after line 19), before `groupedPRs`

```swift
/// Active PRs after applying per-tab review filters.
private var filteredPRs: [PullRequest] {
    guard selectedTab == .reviews else { return activePRs }
    return manager.filterSettings.applyReviewFilters(to: activePRs)
}
```

#### 2. Rewire `groupedPRs` to consume `filteredPRs`
**File**: `Sources/ContentView.swift`
**Change**: Line 23 — replace `activePRs` with `filteredPRs`

Before:
```swift
let dict = Dictionary(grouping: activePRs, by: \.repoFullName)
```

After:
```swift
let dict = Dictionary(grouping: filteredPRs, by: \.repoFullName)
```

#### 3. Update `prList` to handle the filtered-empty case
**File**: `Sources/ContentView.swift`
**Change**: The `prList` computed property (lines 98-114)

Before:
```swift
private var prList: some View {
    Group {
        if activePRs.isEmpty {
            emptyState
        } else {
            ScrollView {
```

After:
```swift
private var prList: some View {
    Group {
        if activePRs.isEmpty {
            emptyState
        } else if filteredPRs.isEmpty {
            filteredEmptyState
        } else {
            ScrollView {
```

#### 4. Add `filteredEmptyState` view
**File**: `Sources/ContentView.swift`
**Where**: After the existing `emptyState` (after line 248)

```swift
private var filteredEmptyState: some View {
    VStack(spacing: 10) {
        Spacer()
        Image(systemName: "line.3.horizontal.decrease.circle")
            .font(.system(size: 32))
            .foregroundColor(.secondary)
        Text("All review requests hidden")
            .font(.title3)
            .foregroundColor(.secondary)
        Text("Adjust your review filters in Settings to see more PRs")
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        Spacer()
    }
    .frame(maxWidth: .infinity)
    .accessibilityLabel("All review requests hidden by filters")
}
```

### Success Criteria:

#### Automated Verification:
- [x] `swift build` succeeds with zero warnings/errors
- [x] `swift test` passes — all tests still pass (no regressions)

#### Manual Verification:
- [ ] With default settings (hide drafts on): open the Reviews tab. Draft PRs should not appear.
- [ ] Toggle all filters off in Settings → all PRs appear on Reviews tab.
- [ ] My PRs tab is completely unaffected — always shows all PRs regardless of filter settings.
- [ ] When all review PRs are hidden by filters → "All review requests hidden" empty state appears.
- [ ] When there are genuinely no review-requested PRs → original "No review requests" empty state appears.

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 4: SettingsView UI

### Overview
Add a "Review Filters" section to SettingsView with five toggles, following the existing section pattern. Update the window frame to accommodate the new section.

### Changes Required:

#### 1. Add filter binding helper
**File**: `Sources/SettingsView.swift`
**Where**: After `body` closing brace, before the struct's closing brace

```swift
private func filterBinding(_ keyPath: WritableKeyPath<FilterSettings, Bool>) -> Binding<Bool> {
    Binding(
        get: { manager.filterSettings[keyPath: keyPath] },
        set: { manager.filterSettings[keyPath: keyPath] = $0 }
    )
}
```

#### 2. Add Review Filters section
**File**: `Sources/SettingsView.swift`
**Where**: After the Polling Interval section's closing `}` (after line 80), before `Spacer()`

```swift
Divider()

// Review Filters Section
VStack(alignment: .leading, spacing: 8) {
    Text("Review Filters")
        .font(.headline)

    Text("Hide PRs on the Reviews tab that aren't ready for your review.")
        .font(.caption)
        .foregroundColor(.secondary)

    VStack(alignment: .leading, spacing: 6) {
        Toggle("Hide draft PRs", isOn: filterBinding(\.hideDrafts))
        Toggle("Hide PRs with failing CI", isOn: filterBinding(\.hideCIFailing))
        Toggle("Hide PRs with pending CI", isOn: filterBinding(\.hideCIPending))
        Toggle("Hide PRs with merge conflicts", isOn: filterBinding(\.hideConflicting))
        Toggle("Hide already-approved PRs", isOn: filterBinding(\.hideApproved))
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Review filter toggles")
}
```

#### 3. Update window frame to accommodate new section
**File**: `Sources/SettingsView.swift`
**Change**: Line 85-88 — the `.frame(...)` modifier

Before:
```swift
.frame(
    minWidth: 320, idealWidth: 360, maxWidth: 480,
    minHeight: 380, idealHeight: 430, maxHeight: 600
)
```

After:
```swift
.frame(
    minWidth: 320, idealWidth: 360, maxWidth: 480,
    minHeight: 480, idealHeight: 560, maxHeight: 700
)
```

### Success Criteria:

#### Automated Verification:
- [x] `swift build` succeeds with zero warnings/errors
- [x] `swift test` passes — all tests still pass (no regressions)

#### Manual Verification:
- [ ] Settings window shows "Review Filters" section below "Refresh Interval"
- [ ] Section has headline, description text, and five toggles
- [ ] "Hide draft PRs" is checked by default; all others unchecked
- [ ] Toggling a filter immediately affects the Reviews tab (close and reopen menu bar)
- [ ] Filter settings persist across app restart (quit and relaunch)
- [ ] Settings window scrolls if needed on smaller displays

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding.

---

## Testing Strategy

### Unit Tests (automated — `swift test`):

**FilterSettings defaults (5 tests)**:
- Each of the five properties has the correct default value

**FilterSettings Codable (4 tests)**:
- Round-trip with default values
- Round-trip with all-custom values
- Decoding from empty JSON `{}` falls back to defaults (forward compatibility)
- Decoding from partial JSON fills in defaults for missing keys

**Filter predicate — individual filters (10 tests)**:
- `hideDrafts` filters draft PRs (default on)
- `hideDrafts` disabled shows draft PRs
- `hideDrafts` does not affect open PRs
- `hideCIFailing` filters failing PRs
- `hideCIFailing` does not affect pending/success
- `hideCIPending` filters pending PRs
- `hideCIPending` does not affect failure/success
- `hideConflicting` filters conflicting PRs
- `hideConflicting` does NOT filter `.unknown` mergeable state
- `hideApproved` filters approved PRs
- `hideApproved` does not affect other review decisions

**Filter predicate — combinations & edge cases (7 tests)**:
- Multiple filters active simultaneously
- All filters enabled — only clean/open/passing/required PRs survive
- No filters enabled — all PRs pass through
- Empty input → empty output
- All PRs filtered → empty output
- Filter preserves original array order
- PR matching multiple filter criteria is hidden once (not double-counted)

**Persistence (3 tests)**:
- Persist and reload via UserDefaults round-trip
- Missing key returns nil data
- Corrupted data fails gracefully (caller falls back to defaults)

**Total new tests: ~30**
**Total tests after implementation: ~56**

### Manual Testing Steps:
1. Launch app → open Settings → verify "Review Filters" section appears with correct defaults
2. Open Reviews tab → verify draft PRs are hidden (default behavior)
3. Uncheck "Hide draft PRs" → verify drafts reappear on Reviews tab
4. Check "Hide PRs with failing CI" → verify CI-failing PRs disappear from Reviews tab
5. Switch to My PRs tab → verify all PRs still visible (filters don't apply)
6. Enable all filters → verify "All review requests hidden" empty state on Reviews tab
7. Quit and relaunch → verify filter settings persisted
8. Disable all filters → verify full PR list restored

---

## References

- Research: `thoughts/shared/research/2026-02-10-reviewability-filter-controls.md`
- Architecture: `thoughts/shared/research/2026-02-10-architecture-and-design-patterns.md`
- DRY plan: `thoughts/shared/plans/2026-02-10-dry-cleanup.md`
- Existing tests: `Tests/GitHubServiceParsingTests.swift`
