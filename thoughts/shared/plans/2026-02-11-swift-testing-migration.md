# Swift Testing Migration Implementation Plan

## Overview

Migrate all 140 unit tests across 7 test files from XCTest to Swift Testing, introduce parameterized tests where patterns repeat, add code coverage tooling, and update the README with testing conventions.

## Current State Analysis

### Test Inventory (7 files, ~16 XCTestCase classes, 140 tests)

| File | Classes | Tests | setUp/tearDown | async | Notes |
|------|---------|-------|----------------|-------|-------|
| `PRManagerTests.swift` | 1 | 13 | `setUp()` | Yes | `@MainActor`, uses all 3 mocks |
| `PullRequestTests.swift` | 4 | 21 | None | No | Sort priority, colors, identity |
| `PRStatusSummaryTests.swift` | 1 | 17 | None | No | Static method tests |
| `StatusChangeDetectorTests.swift` | 1 | 14 | None | No | `let detector` instance property |
| `SettingsStoreTests.swift` | 1 | 13 | Both | No | UserDefaults with UUID suite |
| `FilterSettingsTests.swift` | 6 | 48 | `tearDown` (1 class) | No | Includes fixture extension |
| `GitHubServiceParsingTests.swift` | 1 | 16 | None | No | `let service` instance property |

### Supporting Files (unchanged)
- `Tests/Mocks/MockGitHubService.swift` — not a test class, no changes needed
- `Tests/Mocks/MockNotificationService.swift` — not a test class, no changes needed
- `Tests/Mocks/MockSettingsStore.swift` — not a test class, no changes needed

### Toolchain
- **Swift 6.2.3** installed — Swift Testing fully supported
- **`swift-tools-version: 5.9`** — Swift Testing available via toolchain without bumping to 6.0
- **SwiftLint** only lints `Sources/`, not `Tests/` — no config changes needed

### Key Discoveries
- All 140 tests pass on current `main` (verified via `swift test`)
- `swift test` already shows the Swift Testing runner executing (0 tests) alongside XCTest
- The README "Testing" section is outdated — says "Zero tests exist today"
- No code coverage tooling exists

## Desired End State

After this plan is complete:

1. All tests use `import Testing` instead of `import XCTest`
2. Test containers are `@Suite struct` (or `@Suite final class` where `deinit` cleanup is needed)
3. Assertions use `#expect()` and `#require()` macros
4. Repeated input→output patterns use `@Test(arguments:)` parameterized tests
5. `test` prefix is dropped from function names (`@Test` attribute replaces it)
6. A `coverage.sh` script runs tests with coverage and prints a per-file summary
7. README documents testing conventions, how to run tests, and how to check coverage

### Verification
- `swift test` passes with 140+ test cases and 0 failures
- `swift test` output shows **only** the Swift Testing runner (no XCTest runner)
- `./coverage.sh` prints a per-file coverage table
- README has a complete "Testing" section

## What We're NOT Doing

- **Not bumping `swift-tools-version` to 6.0** — avoids enabling strict concurrency checking, which is a separate concern
- **Not adding CI** — coverage tracking is local-first; CI integration can come later
- **Not refactoring production code** — test logic is migrated 1:1 (except where parameterized tests consolidate repetitive patterns)
- **Not changing mock files** — they're protocol conformances, not test classes

## Implementation Approach

Migrate file-by-file, running `swift test` after each file to catch issues immediately. Start with the simplest files (no setUp/tearDown), then stateful files, then add parameterized tests as a refinement pass. Add coverage tooling last since it's independent.

---

## Phase 1: Migrate Simple Test Files

These four files have no `setUp()`/`tearDown()` — they're pure assertion tests, making them the easiest to convert.

### Overview
Convert `PullRequestTests.swift`, `PRStatusSummaryTests.swift`, `StatusChangeDetectorTests.swift`, and `GitHubServiceParsingTests.swift` from XCTest to Swift Testing.

### Translation Reference

| XCTest | Swift Testing |
|--------|--------------|
| `import XCTest` | `import Testing` |
| `final class Foo: XCTestCase` | `@Suite struct Foo` |
| `func testSomething()` | `@Test func something()` |
| `XCTAssertEqual(a, b)` | `#expect(a == b)` |
| `XCTAssertTrue(a)` | `#expect(a)` |
| `XCTAssertFalse(a)` | `#expect(!a)` |
| `XCTAssertNil(a)` | `#expect(a == nil)` |
| `XCTAssertNotNil(a)` | `#expect(a != nil)` |
| `let x = try XCTUnwrap(a)` | `let x = try #require(a)` |

### Changes Required

#### 1. `Tests/PullRequestTests.swift`

Replace the entire file. Key changes:
- `import XCTest` → `import Testing`
- `import SwiftUI` stays (needed for `Color` comparisons)
- 4 `XCTestCase` classes → 4 `@Suite struct`s
- Drop `test` prefix from all function names
- `XCTAssertEqual(a, b)` → `#expect(a == b)`

```swift
import Testing
import SwiftUI
@testable import PRStatusWatcher

@Suite struct PullRequestSortPriorityTests {
    @Test func openPriorityIsZero() {
        #expect(PullRequest.fixture(state: .open).sortPriority == 0)
    }

    @Test func draftPriorityIsOne() {
        #expect(PullRequest.fixture(state: .draft).sortPriority == 1)
    }

    @Test func queuedPriorityIsTwo() {
        #expect(PullRequest.fixture(state: .open, isInMergeQueue: true).sortPriority == 2)
    }

    @Test func mergedPriorityIsThree() {
        #expect(PullRequest.fixture(state: .merged).sortPriority == 3)
    }

    @Test func closedPriorityIsThree() {
        #expect(PullRequest.fixture(state: .closed).sortPriority == 3)
    }

    @Test func queuedTakesPriorityOverOpenState() {
        let pr = PullRequest.fixture(state: .open, isInMergeQueue: true)
        #expect(pr.sortPriority == 2)
    }
}

@Suite struct PullRequestReviewSortPriorityTests {
    @Test func reviewRequiredIsZero() {
        #expect(PullRequest.fixture(reviewDecision: .reviewRequired).reviewSortPriority == 0)
    }

    @Test func noneIsZero() {
        #expect(PullRequest.fixture(reviewDecision: .none).reviewSortPriority == 0)
    }

    @Test func changesRequestedIsOne() {
        #expect(PullRequest.fixture(reviewDecision: .changesRequested).reviewSortPriority == 1)
    }

    @Test func approvedIsTwo() {
        #expect(PullRequest.fixture(reviewDecision: .approved).reviewSortPriority == 2)
    }
}

@Suite struct PullRequestStatusColorTests {
    @Test func mergedIsPurple() {
        #expect(PullRequest.fixture(state: .merged).statusColor == .purple)
    }

    @Test func closedIsGray() {
        #expect(PullRequest.fixture(state: .closed).statusColor == .gray)
    }

    @Test func draftIsGray() {
        #expect(PullRequest.fixture(state: .draft).statusColor == .gray)
    }

    @Test func openQueuedIsPurple() {
        #expect(PullRequest.fixture(state: .open, isInMergeQueue: true).statusColor == .purple)
    }

    @Test func openSuccessIsGreen() {
        #expect(PullRequest.fixture(state: .open, ciStatus: .success).statusColor == .green)
    }

    @Test func openFailureIsRed() {
        #expect(PullRequest.fixture(state: .open, ciStatus: .failure).statusColor == .red)
    }

    @Test func openPendingIsOrange() {
        #expect(PullRequest.fixture(state: .open, ciStatus: .pending).statusColor == .orange)
    }

    @Test func openUnknownIsGray() {
        #expect(PullRequest.fixture(state: .open, ciStatus: .unknown).statusColor == .gray)
    }
}

@Suite struct PullRequestIdentityTests {
    @Test func idFormat() {
        let pr = PullRequest.fixture(owner: "myorg", repo: "myrepo", number: 42)
        #expect(pr.id == "myorg/myrepo#42")
    }

    @Test func repoFullName() {
        let pr = PullRequest.fixture(owner: "acme", repo: "widget")
        #expect(pr.repoFullName == "acme/widget")
    }

    @Test func displayNumber() {
        let pr = PullRequest.fixture(number: 99)
        #expect(pr.displayNumber == "#99")
    }
}
```

#### 2. `Tests/PRStatusSummaryTests.swift`

Same pattern — replace `XCTestCase` class with `@Suite struct`, swap all assertions.

```swift
import Testing
@testable import PRStatusWatcher

@Suite struct PRStatusSummaryTests {

    // MARK: - overallStatusIcon

    @Test func overallStatusIconEmptyReturnsDefault() {
        #expect(PRStatusSummary.overallStatusIcon(for: []) == "arrow.triangle.pull")
    }

    @Test func overallStatusIconWithFailure() {
        let prs = [PullRequest.fixture(ciStatus: .failure)]
        #expect(PRStatusSummary.overallStatusIcon(for: prs) == "xmark.circle.fill")
    }

    // ... (all 17 tests follow the same pattern: XCTAssertEqual → #expect(==))

    // MARK: - refreshIntervalLabel

    @Test func refreshIntervalLabelSeconds() {
        #expect(PRStatusSummary.refreshIntervalLabel(for: 30) == "30s")
    }

    @Test func refreshIntervalLabelOneMinute() {
        #expect(PRStatusSummary.refreshIntervalLabel(for: 60) == "1 min")
    }

    @Test func refreshIntervalLabelMultipleMinutes() {
        #expect(PRStatusSummary.refreshIntervalLabel(for: 120) == "2 min")
        #expect(PRStatusSummary.refreshIntervalLabel(for: 300) == "5 min")
    }

    @Test func refreshIntervalLabelNonEvenMinutes() {
        #expect(PRStatusSummary.refreshIntervalLabel(for: 90) == "90s")
    }

    @Test func refreshIntervalLabelBoundary59() {
        #expect(PRStatusSummary.refreshIntervalLabel(for: 59) == "59s")
    }
}
```

#### 3. `Tests/StatusChangeDetectorTests.swift`

The `let detector = StatusChangeDetector()` instance property becomes a struct property initialized inline.

```swift
import Testing
@testable import PRStatusWatcher

@Suite struct StatusChangeDetectorTests {
    let detector = StatusChangeDetector()

    // MARK: - CI Transitions

    @Test func pendingToFailureSendsCIFailed() {
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .pending]
        let prevIds: Set<String> = ["test/repo#1"]
        let newPRs = [PullRequest.fixture(number: 1, ciStatus: .failure)]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        #expect(result.count == 1)
        #expect(result.first?.title == "CI Failed")
    }

    // ... (all 14 tests follow same pattern)
    // XCTAssertTrue(result.isEmpty) → #expect(result.isEmpty)
    // XCTAssertTrue(result.first?.body.contains("x") ?? false) → #expect(result.first?.body.contains("x") == true)
    // XCTAssertTrue(result.allSatisfy { ... }) → #expect(result.allSatisfy { ... })
}
```

#### 4. `Tests/GitHubServiceParsingTests.swift`

Same pattern. The `let service = GitHubService()` property stays as-is.

```swift
import Testing
@testable import PRStatusWatcher

@Suite struct GitHubServiceParsingTests {
    let service = GitHubService()

    // MARK: - parsePRState

    @Test func parsePRStateMerged() {
        #expect(service.parsePRState(rawState: "MERGED", isDraft: false) == .merged)
    }

    // ... (all 16 tests follow same pattern)
}
```

### Success Criteria

#### Automated Verification:
- [x] `swift test` passes with 0 failures
- [x] No `import XCTest` remains in the four migrated files
- [x] Swift Testing runner reports tests from these files (no XCTest runner for them)

---

## Phase 2: Migrate Stateful Test Files

These three files use `setUp()` and/or `tearDown()`, requiring slightly different migration patterns.

### Overview
Convert `PRManagerTests.swift`, `SettingsStoreTests.swift`, and `FilterSettingsTests.swift`. Handle setUp→init conversion and tearDown→deinit where needed.

### Changes Required

#### 1. `Tests/PRManagerTests.swift`

**Key challenge:** Uses `setUp()` to create mocks, `@MainActor`, and `async` tests.

**Migration strategy:** Convert to `@Suite struct` with `init()`. The `@MainActor` annotation moves to the struct level. Mock properties become `let` constants initialized in `init()`.

```swift
import Testing
@testable import PRStatusWatcher

@MainActor
@Suite struct PRManagerTests {
    let mockService: MockGitHubService
    let mockSettings: MockSettingsStore
    let mockNotifications: MockNotificationService

    init() {
        mockService = MockGitHubService()
        mockSettings = MockSettingsStore()
        mockNotifications = MockNotificationService()
    }

    private func makeManager() -> PRManager {
        PRManager(
            service: mockService,
            settingsStore: mockSettings,
            notificationService: mockNotifications
        )
    }

    // MARK: - Init

    @Test func initLoadsSettingsFromStore() {
        mockSettings.refreshInterval = 120
        mockSettings.collapsedRepos = ["a/b"]
        mockSettings.filterSettings = FilterSettings(hideDrafts: false)

        let manager = makeManager()

        #expect(manager.refreshInterval == 120)
        #expect(manager.collapsedRepos == ["a/b"])
        #expect(manager.filterSettings == FilterSettings(hideDrafts: false))
    }

    @Test func initRequestsNotificationPermission() {
        _ = makeManager()
        #expect(mockNotifications.permissionRequested)
    }

    // MARK: - refreshAll

    @Test func refreshAllSuccessUpdatesPullRequests() async {
        let prs = [PullRequest.fixture(number: 1), PullRequest.fixture(number: 2)]
        mockService.myPRsResult = .success(prs)
        mockService.reviewPRsResult = .success([])

        let manager = makeManager()
        manager.ghUser = "testuser"
        await manager.refreshAll()

        #expect(manager.pullRequests.count == 2)
        #expect(manager.lastError == nil)
        #expect(manager.hasCompletedInitialLoad)
    }

    // ... (all 13 tests follow same pattern)
}
```

**Note:** `MockGitHubService`, `MockSettingsStore`, and `MockNotificationService` are reference types (classes), so mutating their properties through `let` bindings on a struct is fine.

#### 2. `Tests/SettingsStoreTests.swift`

**Key challenge:** Uses `setUp()` to create a unique UserDefaults suite and `tearDown()` to clean it up.

**Migration strategy:** Use `@Suite final class` (not struct) so we can use `deinit` for cleanup. This is the idiomatic Swift Testing approach when resource cleanup is needed.

```swift
import Testing
import Foundation
@testable import PRStatusWatcher

@Suite final class SettingsStoreTests {
    private let suiteName: String
    private let defaults: UserDefaults
    private let store: SettingsStore

    init() {
        suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = SettingsStore(defaults: defaults)
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Refresh Interval

    @Test func loadRefreshIntervalDefaultIs60() {
        #expect(store.loadRefreshInterval() == 60)
    }

    @Test func loadRefreshIntervalReturnsSavedValue() {
        defaults.set(120, forKey: SettingsStore.pollingKey)
        #expect(store.loadRefreshInterval() == 120)
    }

    // ... (all 13 tests)

    // `throws` tests use #expect(throws:) or just stay as throwing functions:
    @Test func loadFilterSettingsReturnsSavedValue() throws {
        let custom = FilterSettings(hideDrafts: false, hideCIFailing: true)
        let data = try JSONEncoder().encode(custom)
        defaults.set(data, forKey: SettingsStore.filterSettingsKey)
        #expect(store.loadFilterSettings() == custom)
    }

    @Test func saveFilterSettingsPersists() throws {
        let custom = FilterSettings(hideDrafts: false, hideCIPending: true, hideApproved: true)
        store.saveFilterSettings(custom)
        let data = try #require(defaults.data(forKey: SettingsStore.filterSettingsKey))
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: data)
        #expect(decoded == custom)
    }
}
```

#### 3. `Tests/FilterSettingsTests.swift`

**Key challenge:** Contains 6 XCTestCase classes plus the `PullRequest.fixture` extension. One class (`FilterSettingsPersistenceTests`) has `tearDown`.

**Migration strategy:**
- The `PullRequest.fixture` extension stays unchanged (it's not a test class)
- 5 classes without tearDown → `@Suite struct`
- `FilterSettingsPersistenceTests` with tearDown → `@Suite final class` with `deinit`

```swift
import Testing
import Foundation
@testable import PRStatusWatcher

// MARK: - PullRequest Test Fixture (unchanged — not a test class)

extension PullRequest {
    static func fixture(
        owner: String = "test",
        // ... (identical to current)
    ) -> PullRequest { /* ... */ }
}

// MARK: - FilterSettings Default Values

@Suite struct FilterSettingsDefaultsTests {
    @Test func defaultHideDraftsIsTrue() {
        #expect(FilterSettings().hideDrafts)
    }

    @Test func defaultHideCIFailingIsFalse() {
        #expect(!FilterSettings().hideCIFailing)
    }

    // ... (all 5 tests)
}

// MARK: - FilterSettings Codable

@Suite struct FilterSettingsCodableTests {
    @Test func codableRoundTripDefaultValues() throws {
        let original = FilterSettings()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: data)
        #expect(decoded == original)
    }

    // ... (all 4 tests)
}

// MARK: - Filter Predicate: Individual Filters

@Suite struct FilterPredicateTests {
    @Test func defaultSettingsHideDraftPRs() {
        let prs = [
            PullRequest.fixture(number: 1, state: .draft),
            PullRequest.fixture(number: 2, state: .open),
        ]
        let result = FilterSettings().applyReviewFilters(to: prs)
        #expect(result.count == 1)
        #expect(result.first?.number == 2)
    }

    // ... (all 11 tests)
}

// MARK: - Filter Predicate: Combinations & Edge Cases

@Suite struct FilterCombinationTests {
    // ... (all 7 tests, same pattern)

    @Test func filterPreservesOriginalOrder() {
        let settings = FilterSettings(hideDrafts: true)
        let prs = [
            PullRequest.fixture(number: 5, state: .open),
            PullRequest.fixture(number: 3, state: .draft),
            PullRequest.fixture(number: 1, state: .open),
            PullRequest.fixture(number: 4, state: .draft),
            PullRequest.fixture(number: 2, state: .open),
        ]
        let result = settings.applyReviewFilters(to: prs)
        #expect(result.map(\.number) == [5, 1, 2])
    }
}

// MARK: - FilterSettings Persistence

@Suite final class FilterSettingsPersistenceTests {
    private let testKey: String

    init() {
        testKey = "filter_settings_test_\(UUID().uuidString)"
    }

    deinit {
        UserDefaults.standard.removeObject(forKey: testKey)
    }

    @Test func persistAndReloadViaUserDefaults() throws {
        let original = FilterSettings(
            hideDrafts: false, hideCIFailing: true, hideCIPending: true,
            hideConflicting: true, hideApproved: true
        )
        let data = try JSONEncoder().encode(original)
        UserDefaults.standard.set(data, forKey: testKey)

        let loaded = try #require(UserDefaults.standard.data(forKey: testKey))
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: loaded)
        #expect(decoded == original)
    }

    @Test func missingKeyReturnsNilData() {
        let data = UserDefaults.standard.data(forKey: "nonexistent_filter_key_\(UUID().uuidString)")
        #expect(data == nil)
    }

    @Test func corruptedDataFallsBackGracefully() {
        UserDefaults.standard.set(Data("not json".utf8), forKey: testKey)
        let data = UserDefaults.standard.data(forKey: testKey)!
        let decoded = try? JSONDecoder().decode(FilterSettings.self, from: data)
        #expect(decoded == nil)
    }
}
```

### Success Criteria

#### Automated Verification:
- [x] `swift test` passes with 0 failures
- [x] No `import XCTest` remains in any test file
- [x] `swift test` output shows only the Swift Testing runner (no XCTest suite output)
- [x] All `@MainActor` async tests still execute correctly

---

## Phase 3: Introduce Parameterized Tests

### Overview
Refactor repetitive input→output test patterns into `@Test(arguments:)` parameterized tests. This reduces boilerplate while keeping every test case explicit. Each argument tuple still counts as a separate test case in the runner.

### Changes Required

#### 1. `Tests/PullRequestTests.swift` — Sort Priority

Replace 6 individual `sortPriority` tests with one parameterized test:

```swift
@Suite struct PullRequestSortPriorityTests {
    @Test(arguments: [
        (PRState.open, false, 0),
        (PRState.draft, false, 1),
        (PRState.open, true, 2),    // isInMergeQueue
        (PRState.merged, false, 3),
        (PRState.closed, false, 3),
    ])
    func sortPriority(state: PRState, isInMergeQueue: Bool, expected: Int) {
        #expect(PullRequest.fixture(state: state, isInMergeQueue: isInMergeQueue).sortPriority == expected)
    }
}
```

#### 2. `Tests/PullRequestTests.swift` — Review Sort Priority

```swift
@Suite struct PullRequestReviewSortPriorityTests {
    @Test(arguments: [
        (ReviewDecision.reviewRequired, 0),
        (ReviewDecision.none, 0),
        (ReviewDecision.changesRequested, 1),
        (ReviewDecision.approved, 2),
    ])
    func reviewSortPriority(decision: ReviewDecision, expected: Int) {
        #expect(PullRequest.fixture(reviewDecision: decision).reviewSortPriority == expected)
    }
}
```

**Note:** This requires `ReviewDecision` to conform to `Sendable`. If it's an enum (likely), it already does implicitly. If not, we may need to add the conformance.

#### 3. `Tests/PullRequestTests.swift` — Status Color

```swift
@Suite struct PullRequestStatusColorTests {
    @Test(arguments: [
        (PRState.merged, CIStatus.success, false, Color.purple),
        (PRState.closed, CIStatus.success, false, Color.gray),
        (PRState.draft, CIStatus.success, false, Color.gray),
        (PRState.open, CIStatus.success, true, Color.purple),   // queued
        (PRState.open, CIStatus.success, false, Color.green),
        (PRState.open, CIStatus.failure, false, Color.red),
        (PRState.open, CIStatus.pending, false, Color.orange),
        (PRState.open, CIStatus.unknown, false, Color.gray),
    ])
    func statusColor(state: PRState, ciStatus: CIStatus, isInMergeQueue: Bool, expected: Color) {
        #expect(
            PullRequest.fixture(state: state, ciStatus: ciStatus, isInMergeQueue: isInMergeQueue)
                .statusColor == expected
        )
    }
}
```

**Note:** `Color` must conform to `Sendable` for parameterized tests. SwiftUI's `Color` is `Sendable` in Swift 6. If this causes issues, keep the individual tests from Phase 1 instead.

#### 4. `Tests/GitHubServiceParsingTests.swift` — parsePRState

```swift
@Test(arguments: [
    ("MERGED", false, PRState.merged),
    ("CLOSED", false, PRState.closed),
    ("OPEN", false, PRState.open),
    ("OPEN", true, PRState.draft),
    ("SOMETHING", false, PRState.open),
])
func parsePRState(rawState: String, isDraft: Bool, expected: PRState) {
    #expect(service.parsePRState(rawState: rawState, isDraft: isDraft) == expected)
}
```

#### 5. `Tests/PRStatusSummaryTests.swift` — refreshIntervalLabel

```swift
@Test(arguments: [
    (30, "30s"),
    (59, "59s"),
    (60, "1 min"),
    (90, "90s"),
    (120, "2 min"),
    (300, "5 min"),
])
func refreshIntervalLabel(seconds: Int, expected: String) {
    #expect(PRStatusSummary.refreshIntervalLabel(for: seconds) == expected)
}
```

### Conformance Requirements

For `@Test(arguments:)`, each argument type must conform to `Sendable`. Check these enums and add conformances if not already present:

| Type | Expected Status | File |
|------|----------------|------|
| `PRState` | Likely already `Sendable` (enum) | `Sources/Models.swift` |
| `CIStatus` | Likely already `Sendable` (enum) | `Sources/Models.swift` |
| `ReviewDecision` | Likely already `Sendable` (enum) | `Sources/Models.swift` |
| `MergeableState` | Likely already `Sendable` (enum) | `Sources/Models.swift` |
| `Color` (SwiftUI) | `Sendable` in Swift 6 | N/A |

If any enum is missing `Sendable`, add it:
```swift
enum PRState: Sendable { /* ... */ }
```

### Success Criteria

#### Automated Verification:
- [x] `swift test` passes with 0 failures
- [x] Parameterized tests appear as individual test cases in runner output (same or higher test count)
- [x] No compiler warnings about `Sendable` conformance

---

## Phase 4: Code Coverage Tooling

### Overview
Add a `coverage.sh` script that runs tests with LLVM code coverage enabled and prints a per-file summary. Optionally generates an HTML report for line-by-line inspection.

### Changes Required

#### 1. `coverage.sh` (new file, project root)

```bash
#!/usr/bin/env bash
set -euo pipefail

# ─── Run tests with code coverage ───
echo "==> Running tests with code coverage…"
swift test --enable-code-coverage --quiet 2>&1

# ─── Locate build artifacts ───
BIN_PATH=$(swift build --show-bin-path)
PROFDATA="$BIN_PATH/codecov/default.profdata"
# The test binary name matches the test target name
TEST_BIN="$BIN_PATH/PRStatusWatcherPackageTests"

# On macOS, SPM test binaries may be inside an .xctest bundle
if [ -d "$TEST_BIN.xctest" ]; then
    TEST_BIN="$TEST_BIN.xctest/Contents/MacOS/PRStatusWatcherPackageTests"
fi

if [ ! -f "$PROFDATA" ]; then
    echo "Error: Coverage data not found at $PROFDATA"
    echo "Make sure 'swift test --enable-code-coverage' succeeded."
    exit 1
fi

# ─── Print per-file summary ───
echo ""
echo "==> Coverage Summary (Sources/ only)"
echo ""
xcrun llvm-cov report "$TEST_BIN" \
    --instr-profile="$PROFDATA" \
    --sources Sources/

# ─── Optional: HTML report ───
if [[ "${1:-}" == "--html" ]]; then
    OUTPUT_DIR=".build/coverage-html"
    echo ""
    echo "==> Generating HTML report at $OUTPUT_DIR"
    xcrun llvm-cov show "$TEST_BIN" \
        --instr-profile="$PROFDATA" \
        --sources Sources/ \
        --format=html \
        --output-dir="$OUTPUT_DIR"
    echo "    Open with: open $OUTPUT_DIR/index.html"
fi

# ─── Optional: Export lcov for CI ───
if [[ "${1:-}" == "--lcov" ]]; then
    LCOV_FILE=".build/coverage.lcov"
    echo ""
    echo "==> Exporting lcov to $LCOV_FILE"
    xcrun llvm-cov export "$TEST_BIN" \
        --instr-profile="$PROFDATA" \
        --sources Sources/ \
        --format=lcov > "$LCOV_FILE"
    echo "    File: $LCOV_FILE"
fi
```

#### 2. `.gitignore` — add coverage artifacts

Add to `.gitignore`:
```
# Coverage
.build/coverage-html/
.build/coverage.lcov
```

### Success Criteria

#### Automated Verification:
- [x] `chmod +x coverage.sh && ./coverage.sh` exits 0 and prints a coverage table
- [x] `./coverage.sh --html` generates `.build/coverage-html/index.html`
- [x] Coverage artifacts are gitignored

#### Manual Verification:
- [ ] Coverage table shows per-file line/function percentages for `Sources/` files
- [ ] HTML report is navigable and shows line-by-line coverage highlighting

---

## Phase 5: Update README

### Overview
Replace the outdated "Testing" bullet in the README (which says "Zero tests exist today") with a comprehensive Testing section documenting how to run tests, check coverage, and the conventions for writing new tests.

### Changes Required

#### 1. `README.md` — Remove outdated testing bullet

Remove from the "Future Improvements > Testing" section:
```markdown
- [ ] **Add a test target and parsing tests** -- Zero tests exist today. ...
```

#### 2. `README.md` — Add Testing section (after "Architecture", before "Future Improvements")

```markdown
## Testing

### Run tests

```bash
swift test
```

### Code coverage

```bash
# Print per-file coverage summary
./coverage.sh

# Generate HTML report for line-by-line inspection
./coverage.sh --html
open .build/coverage-html/index.html

# Export lcov for CI integration
./coverage.sh --lcov
```

### Conventions

This project uses **[Swift Testing](https://developer.apple.com/documentation/testing)** (not XCTest). Follow these conventions when adding or modifying tests:

- **Import**: `import Testing` (never `import XCTest`)
- **Test containers**: Use `@Suite struct` by default. Use `@Suite final class` only when `deinit` cleanup is needed (e.g., UserDefaults teardown).
- **Test functions**: Mark with `@Test`. Drop the `test` prefix — write `@Test func refreshUpdatesState()`, not `@Test func testRefreshUpdatesState()`.
- **Assertions**: Use `#expect()` for all checks and `#require()` for force-unwrapping.

  | Instead of (XCTest) | Use (Swift Testing) |
  |---------------------|---------------------|
  | `XCTAssertEqual(a, b)` | `#expect(a == b)` |
  | `XCTAssertTrue(a)` | `#expect(a)` |
  | `XCTAssertFalse(a)` | `#expect(!a)` |
  | `XCTAssertNil(a)` | `#expect(a == nil)` |
  | `XCTAssertNotNil(a)` | `#expect(a != nil)` |
  | `try XCTUnwrap(a)` | `try #require(a)` |

- **Parameterized tests**: When multiple tests share the same logic with different inputs, use `@Test(arguments:)` instead of writing separate functions.
- **setUp → init**: Use `init()` for per-test setup. Swift Testing creates a fresh instance for each `@Test` method automatically.
- **tearDown → deinit**: When cleanup is needed, use `@Suite final class` with `deinit`.
- **Mocks**: Place in `Tests/Mocks/`. Mocks are plain classes conforming to protocols — they don't use any test framework.
- **Fixtures**: Use `PullRequest.fixture(...)` with keyword overrides for test data (defined in `Tests/FilterSettingsTests.swift`).

### Test file structure

```
Tests/
├── FilterSettingsTests.swift          # Filter defaults, codable, predicates, persistence
├── GitHubServiceParsingTests.swift    # GraphQL response parsing
├── Mocks/
│   ├── MockGitHubService.swift
│   ├── MockNotificationService.swift
│   └── MockSettingsStore.swift
├── PRManagerTests.swift               # ViewModel integration tests
├── PRStatusSummaryTests.swift         # Status icon/bar logic
├── PullRequestTests.swift             # Model computed properties
├── SettingsStoreTests.swift           # UserDefaults persistence
└── StatusChangeDetectorTests.swift    # Notification change detection
```
```

### Success Criteria

#### Automated Verification:
- [x] No references to "Zero tests exist today" remain in README
- [x] README contains a "Testing" section with run/coverage/conventions subsections

#### Manual Verification:
- [ ] Testing section reads clearly and covers all conventions used in the migrated tests
- [ ] Coverage commands in README match actual `coverage.sh` behavior

---

## Testing Strategy

### Automated Test Suite
- Run `swift test` after each phase to verify no regressions
- Final test count should be >= 140 (parameterized tests may increase the count)
- Zero XCTest references should remain in any test file

### Manual Verification Checkpoints
- **After Phase 2**: Verify that `swift test` output no longer shows the XCTest runner (only Swift Testing runner)
- **After Phase 4**: Run `./coverage.sh` and spot-check the HTML report
- **After Phase 5**: Read the final README "Testing" section for clarity

## Performance Considerations

- Swift Testing runs tests in parallel by default (unlike XCTest's serial execution). All tests in this project are already isolated, so no ordering issues are expected.
- `SettingsStoreTests` and `FilterSettingsPersistenceTests` use unique UserDefaults suite names per instance, ensuring parallel-safe execution.
- `PRManagerTests` uses `@MainActor` which serializes those tests — this is correct and intentional since `PRManager` is a `@MainActor`-isolated `ObservableObject`.

## References

- [Swift Testing documentation](https://developer.apple.com/documentation/testing)
- [Migrating from XCTest](https://developer.apple.com/documentation/testing/migratingfromxctest)
- [Parameterized testing](https://developer.apple.com/documentation/testing/parameterizedtesting)
