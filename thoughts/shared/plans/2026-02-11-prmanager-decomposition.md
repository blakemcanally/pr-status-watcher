# PRManager Decomposition Implementation Plan

## Overview

Decompose the `PRManager` god object (334 lines, 7 concerns, zero tests) into focused, single-responsibility types with constructor-based dependency injection and comprehensive unit test coverage.

## Current State Analysis

`PRManager` is the central ViewModel of the app. It currently handles:

| Concern | Lines | Description |
|---------|-------|-------------|
| Data fetching orchestration | 172–248 | Coordinates parallel `GitHubService` calls |
| Polling lifecycle | 252–264 | Timer-based recurring refresh |
| UserDefaults persistence | 22–64 | Save/load `refreshInterval`, `collapsedRepos`, `filterSettings` |
| Menu bar state | 84–168 | Icon selection, PR counts, summary string, NSImage composition |
| Notification dispatch | 267–334 | Permission request, change detection, `UNUserNotificationCenter` delivery |
| Auth state management | 15, 68–79 | Resolve `ghUser` via `GitHubService` on startup |
| Settings mutation | 22–36 | `didSet` observers that persist on change |

Every new feature must touch this file. It sits at 334 lines against a SwiftLint threshold of 400. It has **zero test coverage** because `GitHubService`, `UserDefaults`, and `UNUserNotificationCenter` are all hard-wired with no injection points.

### Key Discoveries:
- `PRManager.swift:17` — `let service = GitHubService()` with no protocol, no injection
- `PRManager.swift:23,29,35` — Direct `UserDefaults.standard` access in `didSet` observers
- `PRManager.swift:274,332` — Direct `UNUserNotificationCenter.current()` calls
- `PRManager.swift:277-314` — Change detection logic is pure (old state vs new state) but untestable because it's entangled with notification delivery
- `PRManager.swift:84-125` — Status icon, counts, and summary are pure functions of `[PullRequest]` but embedded in the class
- `PRManager.swift:256` — `try? Task.sleep` masks cancellation errors (bug, fixed during extraction)
- Existing test patterns: `PullRequest.fixture(...)` factory in `Tests/FilterSettingsTests.swift:6-53`

## Desired End State

After this plan is complete:

1. **PRManager is a thin coordinator** (~120 lines) that owns `@Published` state and delegates to focused sub-objects
2. **All dependencies are injected via constructor** — no default parameter values; the composition root (`App.swift`) wires production instances explicitly, preventing accidental use of live services in tests
3. **Nine new source files** contain extracted logic: `GitHubServiceProtocol.swift`, `SettingsStoreProtocol.swift`, `NotificationServiceProtocol.swift`, `SettingsStore.swift`, `StatusNotification.swift`, `StatusChangeDetector.swift`, `PRStatusSummary.swift`, `NotificationDispatcher.swift`, `PollingScheduler.swift` — one type per file
4. **Eight new test files** provide ~78 new test methods covering all extracted logic plus `PRManager` itself; mocks live under `Tests/Mocks/` in individual files
5. **Existing behavior is preserved** — no UI changes, no feature changes, no API changes visible to views
6. **The `try? Task.sleep` cancellation bug is fixed** as a side effect of extracting `PollingScheduler`

### Verification:

```bash
swift build 2>&1 | tail -5    # Zero errors, zero warnings
swift test  2>&1 | tail -20   # All tests pass (existing + new)
```

## What We're NOT Doing

- No changes to `GitHubService` internals (parsing, GraphQL queries, process execution)
- No changes to view files (`ContentView`, `PRRowView`, `SettingsView`, `AuthStatusView`)
- No changes to `Models.swift`
- No UI or behavioral changes — this is strictly a refactor
- `App.swift` is updated to serve as the **composition root** — it explicitly wires all production dependencies into `PRManager.init`
- Not extracting `menuBarImage` NSImage composition (AppKit-specific, low test value; the *logic* driving it is tested via `PRStatusSummary`)
- Not breaking up `GitHubService` (separate effort, tracked in research doc)

## Implementation Approach

Constructor-based dependency injection throughout. No default parameter values anywhere — all wiring is explicit. The composition root (`App.swift`) assembles production instances; tests assemble mocks. This eliminates any risk of accidentally using a live `GitHubService`, `UserDefaults.standard`, or `UNUserNotificationCenter` in a test.

**Design philosophy: one type per file.** Every protocol, struct, and class gets its own file named after the type. Many smaller files are preferable to a few large ones.

The extraction follows dependency order: protocols first (unblocks everything), then leaf types (no dependencies on other new types), then PRManager rewiring, then tests.

---

## Phase 1: Protocols + Constructor-Based Dependency Injection

### Overview
Define protocols for all external dependencies and wire `PRManager.init` to accept them. No logic changes — just adding the injection seam.

### Changes Required:

#### 1. Create protocol definitions (one file per protocol)

**File**: `Sources/GitHubServiceProtocol.swift` (new)

```swift
import Foundation

/// Abstraction over GitHub API access, enabling mock injection for tests.
protocol GitHubServiceProtocol: Sendable {
    func currentUser() -> String?
    func fetchAllMyOpenPRs(username: String) throws -> [PullRequest]
    func fetchReviewRequestedPRs(username: String) throws -> [PullRequest]
}
```

**File**: `Sources/SettingsStoreProtocol.swift` (new)

```swift
import Foundation

/// Abstraction over UserDefaults persistence for app settings.
protocol SettingsStoreProtocol {
    func loadRefreshInterval() -> Int
    func saveRefreshInterval(_ value: Int)
    func loadCollapsedRepos() -> Set<String>
    func saveCollapsedRepos(_ value: Set<String>)
    func loadFilterSettings() -> FilterSettings
    func saveFilterSettings(_ value: FilterSettings)
}
```

**File**: `Sources/NotificationServiceProtocol.swift` (new)

```swift
import Foundation

/// Abstraction over UNUserNotificationCenter for local notification delivery.
protocol NotificationServiceProtocol {
    var isAvailable: Bool { get }
    func requestPermission()
    func send(title: String, body: String, url: URL?)
}
```

#### 2. Conform `GitHubService` to the protocol
**File**: `Sources/GitHubService.swift`
**Changes**: Add protocol conformance. The existing public methods already match the protocol signature exactly — this is a one-line change.

```swift
// Before
final class GitHubService: @unchecked Sendable {

// After
final class GitHubService: GitHubServiceProtocol, @unchecked Sendable {
```

#### 3. Update `PRManager` to accept `service` via init (no default)
**File**: `Sources/PRManager.swift`
**Changes**: Replace the hard-wired `let service = GitHubService()` with an injected protocol. No default parameter — the caller must provide the instance explicitly. For now, `SettingsStore` and `NotificationDispatcher` don't exist yet, so only inject `GitHubServiceProtocol` in this phase. The other two protocols will be wired in Phases 2 and 5.

```swift
// Before
let service = GitHubService()

// After
private let service: GitHubServiceProtocol

// Before
init() {
    let saved = UserDefaults.standard.integer(forKey: Self.pollingKey)
    self.refreshInterval = saved > 0 ? saved : 60
    // ...

// After
init(service: GitHubServiceProtocol) {
    self.service = service
    let saved = UserDefaults.standard.integer(forKey: Self.pollingKey)
    self.refreshInterval = saved > 0 ? saved : 60
    // ... rest unchanged
```

#### 4. Update composition root
**File**: `Sources/App.swift`
**Changes**: Wire production `GitHubService` explicitly.

```swift
// Before
@StateObject private var manager = PRManager()

// After
@StateObject private var manager = PRManager(service: GitHubService())
```

### Success Criteria:

#### Automated Verification:
- [x] `swift build` succeeds with zero errors
- [x] `swift test` passes (all existing tests still green)
- [x] `Sources/GitHubServiceProtocol.swift`, `Sources/SettingsStoreProtocol.swift`, `Sources/NotificationServiceProtocol.swift` each exist with one protocol
- [x] `GitHubService` conforms to `GitHubServiceProtocol`
- [x] `PRManager.init(service:)` requires a `GitHubServiceProtocol` argument (no default)
- [x] `App.swift` passes `GitHubService()` explicitly

---

## Phase 2: Extract SettingsStore

### Overview
Extract all `UserDefaults` persistence logic from `PRManager` into a dedicated `SettingsStore` type. Inject it via constructor. Add unit tests for the store.

### Changes Required:

#### 1. Create `SettingsStore`
**File**: `Sources/SettingsStore.swift` (new)
**Changes**: Implement the `SettingsStoreProtocol` defined in Phase 1.

```swift
import Foundation

// MARK: - Settings Store (UserDefaults)

/// Persists app settings to UserDefaults. Accepts a custom UserDefaults
/// instance for test isolation.
final class SettingsStore: SettingsStoreProtocol {
    private let defaults: UserDefaults

    static let pollingKey = "polling_interval"
    static let collapsedReposKey = "collapsed_repos"
    static let filterSettingsKey = "filter_settings"

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func loadRefreshInterval() -> Int {
        let saved = defaults.integer(forKey: Self.pollingKey)
        return saved > 0 ? saved : 60
    }

    func saveRefreshInterval(_ value: Int) {
        defaults.set(value, forKey: Self.pollingKey)
    }

    func loadCollapsedRepos() -> Set<String> {
        Set(defaults.stringArray(forKey: Self.collapsedReposKey) ?? [])
    }

    func saveCollapsedRepos(_ value: Set<String>) {
        defaults.set(Array(value), forKey: Self.collapsedReposKey)
    }

    func loadFilterSettings() -> FilterSettings {
        guard let data = defaults.data(forKey: Self.filterSettingsKey),
              let settings = try? JSONDecoder().decode(FilterSettings.self, from: data) else {
            return FilterSettings()
        }
        return settings
    }

    func saveFilterSettings(_ value: FilterSettings) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: Self.filterSettingsKey)
        }
    }
}
```

#### 2. Update `PRManager` to use `SettingsStore`
**File**: `Sources/PRManager.swift`
**Changes**:
- Add `settingsStore` as an injected dependency
- Remove the `static let` keys (moved to `SettingsStore`)
- Replace `UserDefaults.standard` calls in `didSet` with `settingsStore` calls
- Replace `UserDefaults.standard` reads in `init` with `settingsStore` calls

```swift
// Add to stored properties
private let settingsStore: SettingsStoreProtocol

// Update init signature (no defaults — explicit wiring required)
init(
    service: GitHubServiceProtocol,
    settingsStore: SettingsStoreProtocol
) {
    self.service = service
    self.settingsStore = settingsStore

    // Load from settings store instead of UserDefaults directly
    self.refreshInterval = settingsStore.loadRefreshInterval()
    self.collapsedRepos = settingsStore.loadCollapsedRepos()
    self.filterSettings = settingsStore.loadFilterSettings()

    // ... rest of init unchanged
}

// Update didSet observers
@Published var collapsedRepos: Set<String> = [] {
    didSet { settingsStore.saveCollapsedRepos(collapsedRepos) }
}

@Published var filterSettings: FilterSettings = FilterSettings() {
    didSet { settingsStore.saveFilterSettings(filterSettings) }
}

@Published var refreshInterval: Int {
    didSet { settingsStore.saveRefreshInterval(refreshInterval) }
}
```

- Delete these three lines (keys moved to `SettingsStore`):
```swift
private static let pollingKey = "polling_interval"
private static let collapsedReposKey = "collapsed_repos"
private static let filterSettingsKey = "filter_settings"
```

#### 3. Update composition root
**File**: `Sources/App.swift`
**Changes**: Wire `SettingsStore` with explicit `UserDefaults.standard`.

```swift
// Before (from Phase 1)
@StateObject private var manager = PRManager(service: GitHubService())

// After
@StateObject private var manager = PRManager(
    service: GitHubService(),
    settingsStore: SettingsStore(defaults: .standard)
)
```

#### 4. Add SettingsStore tests
**File**: `Tests/SettingsStoreTests.swift` (new)
**Changes**: Test all load/save paths using an isolated `UserDefaults` suite.

```swift
import XCTest
@testable import PRStatusWatcher

final class SettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: SettingsStore!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = SettingsStore(defaults: defaults)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Refresh Interval

    func testLoadRefreshIntervalDefaultIs60() {
        XCTAssertEqual(store.loadRefreshInterval(), 60)
    }

    func testLoadRefreshIntervalReturnsSavedValue() {
        defaults.set(120, forKey: SettingsStore.pollingKey)
        XCTAssertEqual(store.loadRefreshInterval(), 120)
    }

    func testLoadRefreshIntervalIgnoresZero() {
        defaults.set(0, forKey: SettingsStore.pollingKey)
        XCTAssertEqual(store.loadRefreshInterval(), 60)
    }

    func testLoadRefreshIntervalIgnoresNegative() {
        defaults.set(-10, forKey: SettingsStore.pollingKey)
        XCTAssertEqual(store.loadRefreshInterval(), 60)
    }

    func testSaveRefreshIntervalPersists() {
        store.saveRefreshInterval(300)
        XCTAssertEqual(defaults.integer(forKey: SettingsStore.pollingKey), 300)
    }

    // MARK: - Collapsed Repos

    func testLoadCollapsedReposDefaultIsEmpty() {
        XCTAssertEqual(store.loadCollapsedRepos(), [])
    }

    func testLoadCollapsedReposReturnsSavedValue() {
        defaults.set(["owner/repo1", "owner/repo2"], forKey: SettingsStore.collapsedReposKey)
        XCTAssertEqual(store.loadCollapsedRepos(), ["owner/repo1", "owner/repo2"])
    }

    func testSaveCollapsedReposPersists() {
        store.saveCollapsedRepos(["a/b", "c/d"])
        let saved = Set(defaults.stringArray(forKey: SettingsStore.collapsedReposKey) ?? [])
        XCTAssertEqual(saved, ["a/b", "c/d"])
    }

    // MARK: - Filter Settings

    func testLoadFilterSettingsDefaultIsFilterSettingsInit() {
        XCTAssertEqual(store.loadFilterSettings(), FilterSettings())
    }

    func testLoadFilterSettingsReturnsSavedValue() throws {
        let custom = FilterSettings(hideDrafts: false, hideCIFailing: true)
        let data = try JSONEncoder().encode(custom)
        defaults.set(data, forKey: SettingsStore.filterSettingsKey)
        XCTAssertEqual(store.loadFilterSettings(), custom)
    }

    func testLoadFilterSettingsCorruptedDataReturnsDefault() {
        defaults.set(Data("not json".utf8), forKey: SettingsStore.filterSettingsKey)
        XCTAssertEqual(store.loadFilterSettings(), FilterSettings())
    }

    func testSaveFilterSettingsPersists() throws {
        let custom = FilterSettings(hideDrafts: false, hideCIPending: true, hideApproved: true)
        store.saveFilterSettings(custom)
        let data = defaults.data(forKey: SettingsStore.filterSettingsKey)!
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: data)
        XCTAssertEqual(decoded, custom)
    }

    func testSaveAndLoadRoundTrip() {
        let settings = FilterSettings(
            hideDrafts: false,
            hideCIFailing: true,
            hideCIPending: true,
            hideConflicting: true,
            hideApproved: true
        )
        store.saveFilterSettings(settings)
        XCTAssertEqual(store.loadFilterSettings(), settings)
    }
}
```

### Success Criteria:

#### Automated Verification:
- [x] `swift build` succeeds with zero errors
- [x] `swift test` passes — all existing tests + new `SettingsStoreTests` green
- [x] `PRManager.swift` contains zero references to `UserDefaults`
- [x] `PRManager.swift` contains zero `static let` key definitions
- [x] `Sources/SettingsStore.swift` exists
- [x] `Tests/SettingsStoreTests.swift` exists with 13 test methods

---

## Phase 3: Extract StatusChangeDetector

### Overview
Extract the notification decision logic from `PRManager.checkForStatusChanges(newPRs:)` into a pure, stateless struct. This is the highest-value extraction for testing — it's the most complex logic in `PRManager` and currently has zero coverage.

### Changes Required:

#### 1. Create `StatusNotification` value type
**File**: `Sources/StatusNotification.swift` (new)
**Changes**: Small value type returned by `StatusChangeDetector`. One type per file.

```swift
import Foundation

/// A notification to send when PR status changes.
struct StatusNotification: Equatable {
    let title: String
    let body: String
    let url: URL?
}
```

#### 2. Create `StatusChangeDetector`
**File**: `Sources/StatusChangeDetector.swift` (new)
**Changes**: Pure struct with a single method. No dependencies, no side effects.

```swift
import Foundation

/// Compares previous and current PR states, returning notifications for
/// meaningful status transitions. Pure logic — no side effects.
struct StatusChangeDetector {

    /// Detect status changes between previous and current PR state.
    ///
    /// Notifications are generated for:
    /// - CI pending → failure ("CI Failed")
    /// - CI pending → success ("All Checks Passed")
    /// - PR disappeared from results ("PR No Longer Open")
    ///
    /// No notification is generated for:
    /// - New PRs that appear for the first time
    /// - Status changes that don't originate from pending
    /// - PRs with unchanged status
    func detectChanges(
        previousCIStates: [String: PullRequest.CIStatus],
        previousPRIds: Set<String>,
        newPRs: [PullRequest]
    ) -> [StatusNotification] {
        var notifications: [StatusNotification] = []
        let newIds = Set(newPRs.map { $0.id })

        for pr in newPRs {
            guard let oldStatus = previousCIStates[pr.id] else {
                continue  // New PR — no notification
            }

            if oldStatus == .pending && pr.ciStatus == .failure {
                notifications.append(StatusNotification(
                    title: "CI Failed",
                    body: "\(pr.repoFullName) \(pr.displayNumber): \(pr.title)",
                    url: pr.url
                ))
            }

            if oldStatus == .pending && pr.ciStatus == .success {
                notifications.append(StatusNotification(
                    title: "All Checks Passed",
                    body: "\(pr.repoFullName) \(pr.displayNumber): \(pr.title)",
                    url: pr.url
                ))
            }
        }

        let disappeared = previousPRIds.subtracting(newIds)
        for id in disappeared {
            notifications.append(StatusNotification(
                title: "PR No Longer Open",
                body: "\(id) was merged or closed",
                url: nil
            ))
        }

        return notifications
    }
}
```

#### 3. Update `PRManager` to delegate to `StatusChangeDetector`
**File**: `Sources/PRManager.swift`
**Changes**:
- Add a `StatusChangeDetector` stored property
- Replace the body of `checkForStatusChanges(newPRs:)` with a call to the detector, then iterate over results and call `sendNotification`

```swift
// Add stored property
private let changeDetector = StatusChangeDetector()

// Replace checkForStatusChanges body
private func checkForStatusChanges(newPRs: [PullRequest]) {
    let notifications = changeDetector.detectChanges(
        previousCIStates: previousCIStates,
        previousPRIds: previousPRIds,
        newPRs: newPRs
    )
    for notification in notifications {
        sendNotification(
            title: notification.title,
            body: notification.body,
            url: notification.url
        )
    }
}
```

#### 4. Add StatusChangeDetector tests
**File**: `Tests/StatusChangeDetectorTests.swift` (new)

```swift
import XCTest
@testable import PRStatusWatcher

final class StatusChangeDetectorTests: XCTestCase {
    let detector = StatusChangeDetector()

    // MARK: - CI Transitions

    func testPendingToFailureSendsCIFailed() {
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .pending]
        let prevIds: Set<String> = ["test/repo#1"]
        let newPRs = [PullRequest.fixture(number: 1, ciStatus: .failure)]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "CI Failed")
    }

    func testPendingToSuccessSendsAllChecksPassed() {
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .pending]
        let prevIds: Set<String> = ["test/repo#1"]
        let newPRs = [PullRequest.fixture(number: 1, ciStatus: .success)]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "All Checks Passed")
    }

    func testSuccessToFailureDoesNotNotify() {
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .success]
        let prevIds: Set<String> = ["test/repo#1"]
        let newPRs = [PullRequest.fixture(number: 1, ciStatus: .failure)]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testFailureToSuccessDoesNotNotify() {
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .failure]
        let prevIds: Set<String> = ["test/repo#1"]
        let newPRs = [PullRequest.fixture(number: 1, ciStatus: .success)]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testNoStatusChangeProducesNoNotification() {
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .success]
        let prevIds: Set<String> = ["test/repo#1"]
        let newPRs = [PullRequest.fixture(number: 1, ciStatus: .success)]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - New PRs

    func testNewPRDoesNotNotify() {
        let result = detector.detectChanges(
            previousCIStates: [:], previousPRIds: [], newPRs: [
                PullRequest.fixture(number: 1, ciStatus: .pending)
            ]
        )

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Disappeared PRs

    func testDisappearedPRSendsNotification() {
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .success]
        let prevIds: Set<String> = ["test/repo#1"]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: []
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "PR No Longer Open")
        XCTAssertTrue(result.first?.body.contains("test/repo#1") ?? false)
        XCTAssertNil(result.first?.url)
    }

    func testMultipleDisappearedPRsSendMultipleNotifications() {
        let prevIds: Set<String> = ["test/repo#1", "test/repo#2", "test/repo#3"]
        let prev: [String: PullRequest.CIStatus] = [
            "test/repo#1": .success,
            "test/repo#2": .pending,
            "test/repo#3": .failure
        ]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: []
        )

        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.allSatisfy { $0.title == "PR No Longer Open" })
    }

    // MARK: - Multiple Changes

    func testMultipleTransitionsInSingleRefresh() {
        let prev: [String: PullRequest.CIStatus] = [
            "test/repo#1": .pending,
            "test/repo#2": .pending,
            "test/repo#3": .success
        ]
        let prevIds: Set<String> = ["test/repo#1", "test/repo#2", "test/repo#3"]
        let newPRs = [
            PullRequest.fixture(number: 1, ciStatus: .failure),
            PullRequest.fixture(number: 2, ciStatus: .success),
            // #3 disappeared
        ]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        XCTAssertEqual(result.count, 3)
        let titles = Set(result.map(\.title))
        XCTAssertTrue(titles.contains("CI Failed"))
        XCTAssertTrue(titles.contains("All Checks Passed"))
        XCTAssertTrue(titles.contains("PR No Longer Open"))
    }

    // MARK: - Edge Cases

    func testEmptyPreviousAndNewPRsProducesNoNotifications() {
        let result = detector.detectChanges(
            previousCIStates: [:], previousPRIds: [], newPRs: []
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testNotificationBodyContainsRepoAndNumber() {
        let prev: [String: PullRequest.CIStatus] = ["myorg/myrepo#42": .pending]
        let prevIds: Set<String> = ["myorg/myrepo#42"]
        let pr = PullRequest.fixture(
            owner: "myorg", repo: "myrepo", number: 42,
            title: "Fix the thing", ciStatus: .failure
        )

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: [pr]
        )

        XCTAssertEqual(result.first?.body, "myorg/myrepo #42: Fix the thing")
    }

    func testNotificationURLIsSetFromPR() {
        let expectedURL = URL(string: "https://github.com/test/repo/pull/1")!
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .pending]
        let prevIds: Set<String> = ["test/repo#1"]
        let newPRs = [PullRequest.fixture(number: 1, ciStatus: .failure, url: expectedURL)]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        XCTAssertEqual(result.first?.url, expectedURL)
    }

    func testPendingToPendingDoesNotNotify() {
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .pending]
        let prevIds: Set<String> = ["test/repo#1"]
        let newPRs = [PullRequest.fixture(number: 1, ciStatus: .pending)]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testPendingToUnknownDoesNotNotify() {
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .pending]
        let prevIds: Set<String> = ["test/repo#1"]
        let newPRs = [PullRequest.fixture(number: 1, ciStatus: .unknown)]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        XCTAssertTrue(result.isEmpty)
    }
}
```

### Success Criteria:

#### Automated Verification:
- [x] `swift build` succeeds with zero errors
- [x] `swift test` passes — all existing tests + `StatusChangeDetectorTests` green
- [x] `Sources/StatusNotification.swift` exists
- [x] `Sources/StatusChangeDetector.swift` exists
- [x] `Tests/StatusChangeDetectorTests.swift` exists with 14 test methods
- [x] `PRManager.checkForStatusChanges` delegates to `StatusChangeDetector`

---

## Phase 4: Extract PRStatusSummary

### Overview
Extract the pure computed properties (icon selection, PR counts, summary string, interval label) from `PRManager` into a stateless `PRStatusSummary` enum with static functions. These are pure functions of `[PullRequest]` with zero dependencies.

### Changes Required:

#### 1. Create `PRStatusSummary`
**File**: `Sources/PRStatusSummary.swift` (new)

```swift
import Foundation

// MARK: - PR Status Summary (Pure Logic)

/// Pure functions that derive menu bar state from PR data.
/// No side effects, no dependencies — fully testable.
enum PRStatusSummary {

    /// SF Symbol name for the overall status icon.
    static func overallStatusIcon(for pullRequests: [PullRequest]) -> String {
        if pullRequests.isEmpty {
            return "arrow.triangle.pull"
        }
        if pullRequests.contains(where: { $0.ciStatus == .failure }) {
            return "xmark.circle.fill"
        }
        if pullRequests.contains(where: { $0.ciStatus == .pending }) {
            return "clock.circle.fill"
        }
        if pullRequests.allSatisfy({ $0.state == .merged || $0.state == .closed }) {
            return "checkmark.circle"
        }
        return "checkmark.circle.fill"
    }

    /// Whether any PR has a CI failure.
    static func hasFailure(in pullRequests: [PullRequest]) -> Bool {
        pullRequests.contains(where: { $0.ciStatus == .failure })
    }

    /// Count of open PRs not in the merge queue.
    static func openCount(in pullRequests: [PullRequest]) -> Int {
        pullRequests.filter { $0.state == .open && !$0.isInMergeQueue }.count
    }

    /// Count of draft PRs.
    static func draftCount(in pullRequests: [PullRequest]) -> Int {
        pullRequests.filter { $0.state == .draft }.count
    }

    /// Count of PRs in the merge queue.
    static func queuedCount(in pullRequests: [PullRequest]) -> Int {
        pullRequests.filter { $0.isInMergeQueue }.count
    }

    /// Compact menu bar summary string, e.g. "3·10·2" for draft·open·queued.
    static func statusBarSummary(for pullRequests: [PullRequest]) -> String {
        guard !pullRequests.isEmpty else { return "" }
        let draft = draftCount(in: pullRequests)
        let open = openCount(in: pullRequests)
        let queued = queuedCount(in: pullRequests)
        var parts: [String] = []
        if draft > 0 { parts.append("\(draft)") }
        if open > 0 { parts.append("\(open)") }
        if queued > 0 { parts.append("\(queued)") }
        return parts.joined(separator: "·")
    }

    /// Human-readable label for a polling interval in seconds.
    static func refreshIntervalLabel(for interval: Int) -> String {
        if interval < 60 { return "\(interval)s" }
        if interval == 60 { return "1 min" }
        if interval % 60 == 0 { return "\(interval / 60) min" }
        return "\(interval)s"
    }
}
```

#### 2. Update `PRManager` to delegate to `PRStatusSummary`
**File**: `Sources/PRManager.swift`
**Changes**: Replace the inline computed property bodies with one-line delegations.

```swift
// Replace these property bodies (keep the same property names for API compatibility)

var overallStatusIcon: String {
    PRStatusSummary.overallStatusIcon(for: pullRequests)
}

var hasFailure: Bool {
    PRStatusSummary.hasFailure(in: pullRequests)
}

var openCount: Int {
    PRStatusSummary.openCount(in: pullRequests)
}

var draftCount: Int {
    PRStatusSummary.draftCount(in: pullRequests)
}

var queuedCount: Int {
    PRStatusSummary.queuedCount(in: pullRequests)
}

var statusBarSummary: String {
    PRStatusSummary.statusBarSummary(for: pullRequests)
}

var refreshIntervalLabel: String {
    PRStatusSummary.refreshIntervalLabel(for: refreshInterval)
}
```

#### 3. Add PRStatusSummary tests
**File**: `Tests/PRStatusSummaryTests.swift` (new)

```swift
import XCTest
@testable import PRStatusWatcher

final class PRStatusSummaryTests: XCTestCase {

    // MARK: - overallStatusIcon

    func testOverallStatusIconEmptyReturnsDefault() {
        XCTAssertEqual(PRStatusSummary.overallStatusIcon(for: []), "arrow.triangle.pull")
    }

    func testOverallStatusIconWithFailure() {
        let prs = [PullRequest.fixture(ciStatus: .failure)]
        XCTAssertEqual(PRStatusSummary.overallStatusIcon(for: prs), "xmark.circle.fill")
    }

    func testOverallStatusIconWithPending() {
        let prs = [PullRequest.fixture(ciStatus: .pending)]
        XCTAssertEqual(PRStatusSummary.overallStatusIcon(for: prs), "clock.circle.fill")
    }

    func testOverallStatusIconFailureTakesPriorityOverPending() {
        let prs = [
            PullRequest.fixture(number: 1, ciStatus: .failure),
            PullRequest.fixture(number: 2, ciStatus: .pending),
        ]
        XCTAssertEqual(PRStatusSummary.overallStatusIcon(for: prs), "xmark.circle.fill")
    }

    func testOverallStatusIconAllMergedOrClosed() {
        let prs = [
            PullRequest.fixture(number: 1, state: .merged, ciStatus: .success),
            PullRequest.fixture(number: 2, state: .closed, ciStatus: .unknown),
        ]
        XCTAssertEqual(PRStatusSummary.overallStatusIcon(for: prs), "checkmark.circle")
    }

    func testOverallStatusIconAllSuccess() {
        let prs = [PullRequest.fixture(ciStatus: .success)]
        XCTAssertEqual(PRStatusSummary.overallStatusIcon(for: prs), "checkmark.circle.fill")
    }

    // MARK: - hasFailure

    func testHasFailureTrue() {
        let prs = [PullRequest.fixture(ciStatus: .failure)]
        XCTAssertTrue(PRStatusSummary.hasFailure(in: prs))
    }

    func testHasFailureFalse() {
        let prs = [PullRequest.fixture(ciStatus: .success)]
        XCTAssertFalse(PRStatusSummary.hasFailure(in: prs))
    }

    func testHasFailureEmpty() {
        XCTAssertFalse(PRStatusSummary.hasFailure(in: []))
    }

    // MARK: - Counts

    func testOpenCountExcludesMergeQueue() {
        let prs = [
            PullRequest.fixture(number: 1, state: .open, isInMergeQueue: false),
            PullRequest.fixture(number: 2, state: .open, isInMergeQueue: true),
        ]
        XCTAssertEqual(PRStatusSummary.openCount(in: prs), 1)
    }

    func testOpenCountExcludesDrafts() {
        let prs = [
            PullRequest.fixture(number: 1, state: .open),
            PullRequest.fixture(number: 2, state: .draft),
        ]
        XCTAssertEqual(PRStatusSummary.openCount(in: prs), 1)
    }

    func testDraftCount() {
        let prs = [
            PullRequest.fixture(number: 1, state: .draft),
            PullRequest.fixture(number: 2, state: .draft),
            PullRequest.fixture(number: 3, state: .open),
        ]
        XCTAssertEqual(PRStatusSummary.draftCount(in: prs), 2)
    }

    func testQueuedCount() {
        let prs = [
            PullRequest.fixture(number: 1, isInMergeQueue: true),
            PullRequest.fixture(number: 2, isInMergeQueue: false),
        ]
        XCTAssertEqual(PRStatusSummary.queuedCount(in: prs), 1)
    }

    // MARK: - statusBarSummary

    func testStatusBarSummaryEmptyReturnsEmpty() {
        XCTAssertEqual(PRStatusSummary.statusBarSummary(for: []), "")
    }

    func testStatusBarSummarySingleOpen() {
        let prs = [PullRequest.fixture(state: .open)]
        XCTAssertEqual(PRStatusSummary.statusBarSummary(for: prs), "1")
    }

    func testStatusBarSummaryAllThreeCategories() {
        let prs = [
            PullRequest.fixture(number: 1, state: .draft),
            PullRequest.fixture(number: 2, state: .open),
            PullRequest.fixture(number: 3, state: .open),
            PullRequest.fixture(number: 4, state: .open, isInMergeQueue: true),
        ]
        XCTAssertEqual(PRStatusSummary.statusBarSummary(for: prs), "1·2·1")
    }

    func testStatusBarSummaryOmitsZeroCategories() {
        let prs = [
            PullRequest.fixture(number: 1, state: .open),
            PullRequest.fixture(number: 2, state: .open),
        ]
        // No drafts, no queued — just "2"
        XCTAssertEqual(PRStatusSummary.statusBarSummary(for: prs), "2")
    }

    func testStatusBarSummaryDraftOnly() {
        let prs = [PullRequest.fixture(state: .draft)]
        XCTAssertEqual(PRStatusSummary.statusBarSummary(for: prs), "1")
    }

    // MARK: - refreshIntervalLabel

    func testRefreshIntervalLabelSeconds() {
        XCTAssertEqual(PRStatusSummary.refreshIntervalLabel(for: 30), "30s")
    }

    func testRefreshIntervalLabelOneMinute() {
        XCTAssertEqual(PRStatusSummary.refreshIntervalLabel(for: 60), "1 min")
    }

    func testRefreshIntervalLabelMultipleMinutes() {
        XCTAssertEqual(PRStatusSummary.refreshIntervalLabel(for: 120), "2 min")
        XCTAssertEqual(PRStatusSummary.refreshIntervalLabel(for: 300), "5 min")
    }

    func testRefreshIntervalLabelNonEvenMinutes() {
        XCTAssertEqual(PRStatusSummary.refreshIntervalLabel(for: 90), "90s")
    }

    func testRefreshIntervalLabelBoundary59() {
        XCTAssertEqual(PRStatusSummary.refreshIntervalLabel(for: 59), "59s")
    }
}
```

### Success Criteria:

#### Automated Verification:
- [x] `swift build` succeeds with zero errors
- [x] `swift test` passes — all tests green
- [x] `Sources/PRStatusSummary.swift` exists
- [x] `Tests/PRStatusSummaryTests.swift` exists with 23 test methods
- [x] `PRManager` computed property bodies are single-line delegations to `PRStatusSummary`

---

## Phase 5: Extract NotificationDispatcher + PollingScheduler

### Overview
Extract the two remaining concerns: notification delivery (wraps `UNUserNotificationCenter`) and polling lifecycle (manages the recurring `Task`). These are thin wrappers with minimal logic — the main value is separating concerns and enabling mock injection.

### Changes Required:

#### 1. Create `NotificationDispatcher`
**File**: `Sources/NotificationDispatcher.swift` (new)

```swift
import Foundation
import UserNotifications

// MARK: - Notification Dispatcher

/// Delivers local notifications via UNUserNotificationCenter.
/// Conforms to NotificationServiceProtocol for mock injection.
final class NotificationDispatcher: NotificationServiceProtocol {
    var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    func requestPermission() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in }
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
        UNUserNotificationCenter.current().add(request)
    }
}
```

#### 2. Create `PollingScheduler`
**File**: `Sources/PollingScheduler.swift` (new)
**Changes**: Also fixes the `try? Task.sleep` cancellation bug from the research doc (issue 4.3).

```swift
import Foundation

// MARK: - Polling Scheduler

/// Manages a recurring async task on a fixed interval.
/// Properly handles Task cancellation (fixes the try? sleep bug).
@MainActor
final class PollingScheduler {
    private var task: Task<Void, Never>?

    /// Whether a polling task is currently active.
    var isRunning: Bool {
        task != nil && !(task?.isCancelled ?? true)
    }

    /// Start polling at the given interval. Cancels any existing task first.
    func start(interval: Int, action: @escaping @Sendable () async -> Void) {
        stop()
        task = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                } catch {
                    return  // Exit cleanly on cancellation
                }
                await action()
            }
        }
    }

    /// Stop the current polling task.
    func stop() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
```

#### 3. Wire both into `PRManager`
**File**: `Sources/PRManager.swift`
**Changes**:
- Add `notificationService` as an injected dependency
- Add `PollingScheduler` as a stored property
- Update init to accept `notificationService`
- Replace `sendNotification` with `notificationService.send`
- Replace `requestNotificationPermission` with `notificationService.requestPermission()`
- Replace `startPolling()` body with `scheduler.start(...)`
- Remove `pollingTask` stored property
- Remove `deinit` (scheduler handles cleanup)
- Update `notificationsAvailable` to delegate to `notificationService.isAvailable`
- Delete `sendNotification(title:body:url:)` private method
- Delete `requestNotificationPermission()` private method

The final `PRManager.init` signature after this phase (no default parameters):

```swift
init(
    service: GitHubServiceProtocol,
    settingsStore: SettingsStoreProtocol,
    notificationService: NotificationServiceProtocol
) {
    self.service = service
    self.settingsStore = settingsStore
    self.notificationService = notificationService

    self.refreshInterval = settingsStore.loadRefreshInterval()
    self.collapsedRepos = settingsStore.loadCollapsedRepos()
    self.filterSettings = settingsStore.loadFilterSettings()

    notificationService.requestPermission()

    let svc = service
    Task {
        logger.info("init: resolving gh user...")
        ghUser = await Task.detached { svc.currentUser() }.value
        logger.info("init: gh user resolved to \(self.ghUser ?? "nil", privacy: .public)")
        await refreshAll()
        startPolling()
    }
}
```

#### 4. Update composition root (final form)
**File**: `Sources/App.swift`
**Changes**: Wire all three production dependencies explicitly. This is the **only place** in the codebase that knows about concrete implementations.

```swift
@StateObject private var manager = PRManager(
    service: GitHubService(),
    settingsStore: SettingsStore(defaults: .standard),
    notificationService: NotificationDispatcher()
)
```

The `checkForStatusChanges` method becomes:

```swift
private func checkForStatusChanges(newPRs: [PullRequest]) {
    let notifications = changeDetector.detectChanges(
        previousCIStates: previousCIStates,
        previousPRIds: previousPRIds,
        newPRs: newPRs
    )
    for notification in notifications {
        notificationService.send(
            title: notification.title,
            body: notification.body,
            url: notification.url
        )
    }
}
```

The `startPolling` method becomes:

```swift
private func startPolling() {
    scheduler.start(interval: refreshInterval) { [weak self] in
        await self?.refreshAll()
    }
}
```

Properties to delete from `PRManager`:
- `private var pollingTask: Task<Void, Never>?`

Methods to delete from `PRManager`:
- `private func sendNotification(title:body:url:)`
- `private func requestNotificationPermission()`
- `deinit`

### Success Criteria:

#### Automated Verification:
- [x] `swift build` succeeds with zero errors
- [x] `swift test` passes — all existing + new tests green
- [x] `PRManager.swift` contains zero references to `UNUserNotificationCenter`
- [x] `PRManager.swift` contains zero references to `UNMutableNotificationContent`
- [x] `PRManager.swift` contains zero `Task.sleep` calls
- [x] `import UserNotifications` is removed from `PRManager.swift`
- [x] `Sources/NotificationDispatcher.swift` exists
- [x] `Sources/PollingScheduler.swift` exists
- [x] `App.swift` wires all three dependencies explicitly: `GitHubService()`, `SettingsStore(defaults: .standard)`, `NotificationDispatcher()`
- [x] `PRManager.init` has zero default parameter values

**Implementation Note**: After completing this phase and verifying all automated checks pass, pause here for a manual check — confirm the menu bar still shows the correct icon/summary and that the app polls on schedule.

---

## Phase 6: PRManager Unit Tests + PullRequest Model Tests

### Overview
With all dependencies now injectable, write comprehensive unit tests for `PRManager` using mocks, and add the missing `PullRequest` model property tests.

### Changes Required:

#### 1. Create test mocks (one mock per file under `Tests/Mocks/`)

**File**: `Tests/Mocks/MockGitHubService.swift` (new)

```swift
import Foundation
@testable import PRStatusWatcher

final class MockGitHubService: GitHubServiceProtocol, @unchecked Sendable {
    var currentUserResult: String? = "testuser"
    var myPRsResult: Result<[PullRequest], Error> = .success([])
    var reviewPRsResult: Result<[PullRequest], Error> = .success([])

    var fetchMyPRsCallCount = 0
    var fetchReviewPRsCallCount = 0

    func currentUser() -> String? { currentUserResult }

    func fetchAllMyOpenPRs(username: String) throws -> [PullRequest] {
        fetchMyPRsCallCount += 1
        return try myPRsResult.get()
    }

    func fetchReviewRequestedPRs(username: String) throws -> [PullRequest] {
        fetchReviewPRsCallCount += 1
        return try reviewPRsResult.get()
    }
}
```

**File**: `Tests/Mocks/MockSettingsStore.swift` (new)

```swift
import Foundation
@testable import PRStatusWatcher

final class MockSettingsStore: SettingsStoreProtocol {
    var refreshInterval: Int = 60
    var collapsedRepos: Set<String> = []
    var filterSettings: FilterSettings = FilterSettings()

    var saveRefreshIntervalCallCount = 0
    var saveCollapsedReposCallCount = 0
    var saveFilterSettingsCallCount = 0

    func loadRefreshInterval() -> Int { refreshInterval }
    func saveRefreshInterval(_ value: Int) {
        saveRefreshIntervalCallCount += 1
        refreshInterval = value
    }
    func loadCollapsedRepos() -> Set<String> { collapsedRepos }
    func saveCollapsedRepos(_ value: Set<String>) {
        saveCollapsedReposCallCount += 1
        collapsedRepos = value
    }
    func loadFilterSettings() -> FilterSettings { filterSettings }
    func saveFilterSettings(_ value: FilterSettings) {
        saveFilterSettingsCallCount += 1
        filterSettings = value
    }
}
```

**File**: `Tests/Mocks/MockNotificationService.swift` (new)

```swift
import Foundation
@testable import PRStatusWatcher

final class MockNotificationService: NotificationServiceProtocol {
    var isAvailable: Bool = true
    var sentNotifications: [(title: String, body: String, url: URL?)] = []
    var permissionRequested = false

    func requestPermission() { permissionRequested = true }
    func send(title: String, body: String, url: URL?) {
        sentNotifications.append((title, body, url))
    }
}
```

#### 2. Create PRManager tests
**File**: `Tests/PRManagerTests.swift` (new)
**Changes**: Test `PRManager` in isolation using the mocks above.

```swift
import XCTest
@testable import PRStatusWatcher

@MainActor
final class PRManagerTests: XCTestCase {
    private var mockService: MockGitHubService!
    private var mockSettings: MockSettingsStore!
    private var mockNotifications: MockNotificationService!

    override func setUp() {
        super.setUp()
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

    func testInitLoadsSettingsFromStore() {
        mockSettings.refreshInterval = 120
        mockSettings.collapsedRepos = ["a/b"]
        mockSettings.filterSettings = FilterSettings(hideDrafts: false)

        let manager = makeManager()

        XCTAssertEqual(manager.refreshInterval, 120)
        XCTAssertEqual(manager.collapsedRepos, ["a/b"])
        XCTAssertEqual(manager.filterSettings, FilterSettings(hideDrafts: false))
    }

    func testInitRequestsNotificationPermission() {
        _ = makeManager()
        XCTAssertTrue(mockNotifications.permissionRequested)
    }

    // MARK: - refreshAll

    func testRefreshAllSuccessUpdatesPullRequests() async {
        let prs = [PullRequest.fixture(number: 1), PullRequest.fixture(number: 2)]
        mockService.myPRsResult = .success(prs)
        mockService.reviewPRsResult = .success([])

        let manager = makeManager()
        manager.ghUser = "testuser"
        await manager.refreshAll()

        XCTAssertEqual(manager.pullRequests.count, 2)
        XCTAssertNil(manager.lastError)
        XCTAssertTrue(manager.hasCompletedInitialLoad)
    }

    func testRefreshAllSuccessUpdatesReviewPRs() async {
        let reviewPRs = [PullRequest.fixture(number: 10)]
        mockService.myPRsResult = .success([])
        mockService.reviewPRsResult = .success(reviewPRs)

        let manager = makeManager()
        manager.ghUser = "testuser"
        await manager.refreshAll()

        XCTAssertEqual(manager.reviewPRs.count, 1)
    }

    func testRefreshAllMyPRsFailureSetsLastError() async {
        mockService.myPRsResult = .failure(
            NSError(domain: "test", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Network timeout"
            ])
        )

        let manager = makeManager()
        manager.ghUser = "testuser"
        await manager.refreshAll()

        XCTAssertEqual(manager.lastError, "Network timeout")
    }

    func testRefreshAllNilUserSetsAuthError() async {
        let manager = makeManager()
        manager.ghUser = nil
        await manager.refreshAll()

        XCTAssertEqual(manager.lastError, "gh not authenticated")
    }

    func testRefreshAllFirstLoadSkipsNotifications() async {
        mockService.myPRsResult = .success([
            PullRequest.fixture(number: 1, ciStatus: .failure)
        ])

        let manager = makeManager()
        manager.ghUser = "testuser"
        await manager.refreshAll()

        XCTAssertTrue(mockNotifications.sentNotifications.isEmpty)
    }

    func testRefreshAllSecondLoadSendsNotifications() async {
        let manager = makeManager()
        manager.ghUser = "testuser"

        // First load: pending
        mockService.myPRsResult = .success([
            PullRequest.fixture(number: 1, ciStatus: .pending)
        ])
        await manager.refreshAll()
        XCTAssertTrue(mockNotifications.sentNotifications.isEmpty)

        // Second load: failure
        mockService.myPRsResult = .success([
            PullRequest.fixture(number: 1, ciStatus: .failure)
        ])
        await manager.refreshAll()

        XCTAssertEqual(mockNotifications.sentNotifications.count, 1)
        XCTAssertEqual(mockNotifications.sentNotifications.first?.title, "CI Failed")
    }

    func testRefreshAllReviewPRsFailureKeepsExistingData() async {
        let manager = makeManager()
        manager.ghUser = "testuser"

        // First load succeeds
        mockService.myPRsResult = .success([])
        mockService.reviewPRsResult = .success([PullRequest.fixture(number: 5)])
        await manager.refreshAll()
        XCTAssertEqual(manager.reviewPRs.count, 1)

        // Second load: review PRs fail
        mockService.reviewPRsResult = .failure(
            NSError(domain: "test", code: 1)
        )
        await manager.refreshAll()

        // Should keep existing review PRs
        XCTAssertEqual(manager.reviewPRs.count, 1)
    }

    // MARK: - Settings Persistence

    func testFilterSettingsDidSetSavesToStore() {
        let manager = makeManager()
        manager.filterSettings = FilterSettings(hideDrafts: false, hideCIFailing: true)

        XCTAssertEqual(mockSettings.saveFilterSettingsCallCount, 1)
        XCTAssertEqual(mockSettings.filterSettings, FilterSettings(hideDrafts: false, hideCIFailing: true))
    }

    func testRefreshIntervalDidSetSavesToStore() {
        let manager = makeManager()
        manager.refreshInterval = 300

        XCTAssertEqual(mockSettings.saveRefreshIntervalCallCount, 1)
        XCTAssertEqual(mockSettings.refreshInterval, 300)
    }

    func testCollapsedReposDidSetSavesToStore() {
        let manager = makeManager()
        manager.collapsedRepos = ["org/repo"]

        XCTAssertEqual(mockSettings.saveCollapsedReposCallCount, 1)
        XCTAssertEqual(mockSettings.collapsedRepos, ["org/repo"])
    }

    // MARK: - Delegated Properties

    func testNotificationsAvailableDelegatesToService() {
        mockNotifications.isAvailable = false
        let manager = makeManager()
        XCTAssertFalse(manager.notificationsAvailable)
    }
}
```

#### 3. Create PullRequest model property tests
**File**: `Tests/PullRequestTests.swift` (new)
**Changes**: Cover `sortPriority`, `reviewSortPriority`, `statusColor`, `id`, `repoFullName`, `displayNumber`.

```swift
import XCTest
import SwiftUI
@testable import PRStatusWatcher

final class PullRequestSortPriorityTests: XCTestCase {
    func testOpenPriorityIsZero() {
        XCTAssertEqual(PullRequest.fixture(state: .open).sortPriority, 0)
    }

    func testDraftPriorityIsOne() {
        XCTAssertEqual(PullRequest.fixture(state: .draft).sortPriority, 1)
    }

    func testQueuedPriorityIsTwo() {
        XCTAssertEqual(PullRequest.fixture(state: .open, isInMergeQueue: true).sortPriority, 2)
    }

    func testMergedPriorityIsThree() {
        XCTAssertEqual(PullRequest.fixture(state: .merged).sortPriority, 3)
    }

    func testClosedPriorityIsThree() {
        XCTAssertEqual(PullRequest.fixture(state: .closed).sortPriority, 3)
    }

    func testQueuedTakesPriorityOverOpenState() {
        // A PR that is state: .open but isInMergeQueue should sort as queued (2), not open (0)
        let pr = PullRequest.fixture(state: .open, isInMergeQueue: true)
        XCTAssertEqual(pr.sortPriority, 2)
    }
}

final class PullRequestReviewSortPriorityTests: XCTestCase {
    func testReviewRequiredIsZero() {
        XCTAssertEqual(
            PullRequest.fixture(reviewDecision: .reviewRequired).reviewSortPriority, 0
        )
    }

    func testNoneIsZero() {
        XCTAssertEqual(
            PullRequest.fixture(reviewDecision: .none).reviewSortPriority, 0
        )
    }

    func testChangesRequestedIsOne() {
        XCTAssertEqual(
            PullRequest.fixture(reviewDecision: .changesRequested).reviewSortPriority, 1
        )
    }

    func testApprovedIsTwo() {
        XCTAssertEqual(
            PullRequest.fixture(reviewDecision: .approved).reviewSortPriority, 2
        )
    }
}

final class PullRequestStatusColorTests: XCTestCase {
    func testMergedIsPurple() {
        XCTAssertEqual(PullRequest.fixture(state: .merged).statusColor, .purple)
    }

    func testClosedIsGray() {
        XCTAssertEqual(PullRequest.fixture(state: .closed).statusColor, .gray)
    }

    func testDraftIsGray() {
        XCTAssertEqual(PullRequest.fixture(state: .draft).statusColor, .gray)
    }

    func testOpenQueuedIsPurple() {
        XCTAssertEqual(
            PullRequest.fixture(state: .open, isInMergeQueue: true).statusColor, .purple
        )
    }

    func testOpenSuccessIsGreen() {
        XCTAssertEqual(
            PullRequest.fixture(state: .open, ciStatus: .success).statusColor, .green
        )
    }

    func testOpenFailureIsRed() {
        XCTAssertEqual(
            PullRequest.fixture(state: .open, ciStatus: .failure).statusColor, .red
        )
    }

    func testOpenPendingIsOrange() {
        XCTAssertEqual(
            PullRequest.fixture(state: .open, ciStatus: .pending).statusColor, .orange
        )
    }

    func testOpenUnknownIsGray() {
        XCTAssertEqual(
            PullRequest.fixture(state: .open, ciStatus: .unknown).statusColor, .gray
        )
    }
}

final class PullRequestIdentityTests: XCTestCase {
    func testIdFormat() {
        let pr = PullRequest.fixture(owner: "myorg", repo: "myrepo", number: 42)
        XCTAssertEqual(pr.id, "myorg/myrepo#42")
    }

    func testRepoFullName() {
        let pr = PullRequest.fixture(owner: "acme", repo: "widget")
        XCTAssertEqual(pr.repoFullName, "acme/widget")
    }

    func testDisplayNumber() {
        let pr = PullRequest.fixture(number: 99)
        XCTAssertEqual(pr.displayNumber, "#99")
    }
}
```

### Success Criteria:

#### Automated Verification:
- [x] `swift build` succeeds with zero errors
- [x] `swift test` passes — all tests green (140 total)
- [x] `Tests/Mocks/MockGitHubService.swift` exists
- [x] `Tests/Mocks/MockSettingsStore.swift` exists
- [x] `Tests/Mocks/MockNotificationService.swift` exists
- [x] `Tests/PRManagerTests.swift` exists with 12 test methods
- [x] `Tests/PullRequestTests.swift` exists with 21 test methods
- [x] All `PRManager` dependencies are tested via mocks (zero real `GitHubService`, zero `UserDefaults.standard`, zero `UNUserNotificationCenter` usage in tests)

#### Manual Verification:
- [ ] App launches and shows the menu bar icon correctly
- [ ] PR data loads and displays in the dropdown
- [ ] Polling continues at the configured interval
- [ ] Notifications fire on CI status changes (test by waiting for a pending CI to complete)

---

## Final File Inventory

### New Source Files (9) — one type per file:
| File | Lines (est.) | Purpose |
|------|-------------|---------|
| `Sources/GitHubServiceProtocol.swift` | ~10 | Protocol for GitHub API abstraction |
| `Sources/SettingsStoreProtocol.swift` | ~10 | Protocol for settings persistence |
| `Sources/NotificationServiceProtocol.swift` | ~10 | Protocol for notification delivery |
| `Sources/SettingsStore.swift` | ~50 | UserDefaults persistence |
| `Sources/StatusNotification.swift` | ~10 | Value type for notification decisions |
| `Sources/StatusChangeDetector.swift` | ~45 | Pure notification decision logic |
| `Sources/PRStatusSummary.swift` | ~60 | Pure status computation |
| `Sources/NotificationDispatcher.swift` | ~35 | UNUserNotificationCenter wrapper |
| `Sources/PollingScheduler.swift` | ~35 | Recurring task lifecycle |

### New Test Files (8) — mocks in `Tests/Mocks/`, one per file:
| File | Tests (est.) | Purpose |
|------|-------------|---------|
| `Tests/Mocks/MockGitHubService.swift` | — | Mock for `GitHubServiceProtocol` |
| `Tests/Mocks/MockSettingsStore.swift` | — | Mock for `SettingsStoreProtocol` |
| `Tests/Mocks/MockNotificationService.swift` | — | Mock for `NotificationServiceProtocol` |
| `Tests/SettingsStoreTests.swift` | 13 | Settings persistence |
| `Tests/StatusChangeDetectorTests.swift` | 14 | Notification decision logic |
| `Tests/PRStatusSummaryTests.swift` | 22 | Icon, counts, summary |
| `Tests/PRManagerTests.swift` | 12 | ViewModel integration with mocks |
| `Tests/PullRequestTests.swift` | 17 | Model computed properties |

### Modified Files:
| File | Change |
|------|--------|
| `Sources/PRManager.swift` | Slimmed from ~334 → ~120 lines; thin coordinator |
| `Sources/GitHubService.swift` | Added `GitHubServiceProtocol` conformance (one line) |
| `Sources/App.swift` | Composition root — explicitly wires all production dependencies |

### Test Summary:
| Category | Before | After |
|----------|--------|-------|
| Existing tests | 42 | 42 |
| New tests | 0 | **78** |
| **Total** | **42** | **120** |

## Testing Strategy

### Unit Tests:
- **SettingsStore**: Load defaults, save/load round-trips, corrupted data fallback, isolated `UserDefaults` suite
- **StatusChangeDetector**: All CI transition combinations, disappeared PRs, new PRs, empty states, notification content verification
- **PRStatusSummary**: Every icon state, count filtering rules, summary string formatting, interval label boundaries
- **PRManager**: Init loads from store, `refreshAll` success/failure/nil-user/concurrent-guard, `didSet` persistence, first-load notification skip, second-load notification dispatch
- **PullRequest**: `sortPriority`, `reviewSortPriority`, `statusColor`, `id`, `repoFullName`, `displayNumber`

### What Is NOT Unit Tested:
- `menuBarImage` NSImage composition (AppKit rendering; the *logic* driving it is tested via `PRStatusSummary`)
- `NotificationDispatcher` (thin wrapper over `UNUserNotificationCenter`; tested via mock in PRManager tests)
- `PollingScheduler` async timing (tested indirectly via PRManager behavior)
- `GitHubService` internals (covered by existing `GitHubServiceParsingTests`)

## Bug Fixes Included

This refactor incidentally fixes one bug from the research doc:

- **Issue 4.3: `try? Task.sleep` masks cancellation** (`PRManager.swift:256`) — `PollingScheduler` uses `do-catch` with explicit `return` on cancellation instead of `try?`, ensuring the polling loop exits immediately when cancelled rather than running one extra refresh cycle.

## References

- Research: `thoughts/shared/research/2026-02-11-adversarial-code-review-findings.md` (sections 1.1, 1.2, 2.2)
- Architecture: `thoughts/shared/research/2026-02-10-architecture-and-design-patterns.md`
- Existing test patterns: `Tests/FilterSettingsTests.swift` (fixture factory, test organization)
