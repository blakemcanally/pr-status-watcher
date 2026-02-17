# P3 Low-Impact Bugfix Plan: Constants, Logging, and Documentation

## Overview

Five P3 issues were identified in the adversarial code review (`thoughts/shared/research/2026-02-11-adversarial-code-review-findings.md`). Two have already been resolved in the current codebase. This plan addresses the remaining three:

| # | Issue | Current State | Status |
|---|-------|---------------|--------|
| 1 | Hardcoded configuration | Magic strings, fixed `gh` paths, pagination caps, frame sizes scattered | **Open** |
| 2 | Silent persistence failures | `SettingsStore` encode/decode failures silently swallowed | **Open** |
| 3 | Missing logging | No logs for app lifecycle, notification taps, `gh` path resolution | **Open** |
| 4 | No keyboard shortcuts | Cmd+R, Cmd+Q, Cmd+, all present in `ContentView.swift:95,334,342` | **Already Fixed** |
| 5 | Menu bar filtered counts ambiguity | `PRManager.statusBarSummary` applies `filterSettings.applyReviewFilters` before computing | **Already Resolved** |

## Current State Analysis

### Hardcoded Configuration (Issue 1)

Scattered magic values with no central registry:

| Value | Location | Problem |
|-------|----------|---------|
| `gh` paths: 3 hardcoded candidates | `GitHubService.swift:13-17` | Nix, asdf, custom installs missed; no PATH search |
| `first: 100` pagination cap | `GitHubService.swift:63, 84` | Users with >100 PRs/checks see truncated data |
| `processTimeout: 30` | `GitHubService.swift:358` | Already a `static let` but lives in a private scope |
| Frame sizes: 400/460/560/400/520/700 | `ContentView.swift:58-61` | Not discoverable or shared |
| Frame sizes: 320/380/480/520/620/800 | `SettingsView.swift:107-109` | Same issue |
| Menu bar icon: `NSSize(width: 20, height: 16)` | `PRManager.swift:123` | Magic numbers |
| Symbol point size: `14` | `PRManager.swift:110` | Magic number |
| Tab picker width: `180` | `ContentView.swift:78` | Magic number |
| Font size: `11` | `App.swift:47` | Magic number |
| Notification `"url"` key | `App.swift:20`, `NotificationDispatcher.swift:24` | Duplicated magic string |
| `SettingsStore` keys | `SettingsStore.swift:12-14` | Already `static let` but not centralized |

### Silent Persistence Failures (Issue 2)

`SettingsStore.swift` swallows all encode/decode errors:

```swift
// Load — failure silently returns defaults
guard let data = defaults.data(forKey: Self.filterSettingsKey),
      let settings = try? JSONDecoder().decode(FilterSettings.self, from: data) else {
    return FilterSettings()
}

// Save — failure silently drops
if let data = try? JSONEncoder().encode(value) {
    defaults.set(data, forKey: Self.filterSettingsKey)
}
```

If a future `FilterSettings` property breaks Codable compatibility, users lose their settings with zero indication.

### Missing Logging (Issue 3)

Operations with no logging:

| Operation | File | Risk |
|-----------|------|------|
| App launch | `App.swift:7-11` | Can't verify lifecycle events |
| Notification tap handling | `App.swift:15-25` | Can't debug "click did nothing" reports |
| `gh` binary path resolution result | `GitHubService.swift:11-19` | Can't tell which `gh` binary is used |
| Notification permission result | `NotificationDispatcher.swift:14-17` | Can't debug "no notifications" reports |
| Notification delivery | `NotificationDispatcher.swift:19-29` | Can't verify notifications were sent |
| Persistence save/load | `SettingsStore.swift` | Can't debug lost settings |

## Desired End State

1. **All configuration values** live in a central `Constants.swift` file, organized by domain. Non-string constants are plain `static let` properties. User-facing strings live in a `Strings.swift` file using a pattern that can be swapped to `String(localized:)` when localization is added.
2. **`gh` binary resolution** searches the system `PATH` as a fallback after checking known locations, and logs the resolved path.
3. **Persistence failures** are logged with the actual error, not silently swallowed.
4. **Key operations** have structured logging at appropriate levels (`info` for lifecycle, `error` for failures, `debug` for routine operations).
5. **README** accurately reflects the current codebase — no stale "Future Improvements" items, architecture section includes extracted components.

## What We're NOT Doing

- Not adding actual localization (`.lproj` bundles, string catalogs) — just preparing the string organization pattern
- Not changing pagination behavior (cursor-based pagination is a separate feature)
- Not changing the `gh` CLI approach (URLSession migration is a separate concern)
- Not adding a log viewer or log export feature
- Not changing any business logic or UI behavior

---

## Parallelization Strategy

Phases are designed for maximum parallel execution:

```
Round 1 (Foundation):
  └── Phase 1: Constants.swift + Strings.swift (must be first — other phases reference these)

Round 2 (Parallel — 3 subagents):
  ├── Subagent A: Phase 2 — gh resolution + GitHubService logging
  ├── Subagent B: Phase 3 — Persistence failure logging
  └── Subagent C: Phase 4 — App lifecycle + notification logging

Round 3 (Finalize):
  └── Phase 5: README update (must be last — reflects all changes)
```

Phases 2, 3, and 4 touch non-overlapping files:
- Phase 2: `GitHubService.swift`, `Tests/GitHubServiceParsingTests.swift`
- Phase 3: `SettingsStore.swift`, `SettingsStoreProtocol.swift`, `Tests/SettingsStoreTests.swift`, `Tests/Mocks/MockSettingsStore.swift`
- Phase 4: `App.swift`, `NotificationDispatcher.swift`, `NotificationServiceProtocol.swift`, `Tests/Mocks/MockNotificationService.swift`

---

## Phase 1: Extract Constants and Localization-Ready Strings

**Goal:** Centralize all magic values and user-facing strings into two discoverable files.

### 1.1 Create `Sources/Constants.swift`

All non-localizable configuration values in one file:

```swift
import Foundation
import AppKit

// MARK: - App Configuration Constants

/// Centralized configuration constants. Organized by domain so every magic
/// value is discoverable in one place.
enum AppConstants {

    // MARK: GitHub CLI

    enum GitHub {
        /// Known install locations for the `gh` binary, checked in order.
        /// Falls back to PATH-based lookup if none are found.
        static let knownBinaryPaths = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh",
        ]

        /// Maximum results per GraphQL search query.
        static let paginationLimit = 100

        /// Seconds before a `gh` process is forcefully terminated.
        static let processTimeoutSeconds: TimeInterval = 30

        /// Seconds to wait after SIGTERM before re-terminating a hung process.
        static let terminationGracePeriod: TimeInterval = 2
    }

    // MARK: UserDefaults Keys

    enum DefaultsKey {
        static let pollingInterval = "polling_interval"
        static let collapsedRepos = "collapsed_repos"
        static let filterSettings = "filter_settings"
    }

    // MARK: Notification

    enum Notification {
        /// Key used to pass the PR URL through notification `userInfo`.
        static let urlInfoKey = "url"
    }

    // MARK: Layout

    enum Layout {
        enum ContentWindow {
            static let minWidth: CGFloat = 400
            static let idealWidth: CGFloat = 460
            static let maxWidth: CGFloat = 560
            static let minHeight: CGFloat = 400
            static let idealHeight: CGFloat = 520
            static let maxHeight: CGFloat = 700
        }

        enum SettingsWindow {
            static let minWidth: CGFloat = 320
            static let idealWidth: CGFloat = 380
            static let maxWidth: CGFloat = 480
            static let minHeight: CGFloat = 520
            static let idealHeight: CGFloat = 620
            static let maxHeight: CGFloat = 800
        }

        enum MenuBar {
            static let imageSize = NSSize(width: 20, height: 16)
            static let badgeDotDiameter: CGFloat = 5
            static let symbolPointSize: CGFloat = 14
            static let statusFontSize: CGFloat = 11
        }

        enum Header {
            static let tabPickerWidth: CGFloat = 180
        }
    }

    // MARK: Defaults

    enum Defaults {
        /// Default polling interval in seconds when no saved preference exists.
        static let refreshInterval = 60
    }
}
```

### 1.2 Create `Sources/Strings.swift`

User-facing strings organized for future localization. Each string is a static property that can be swapped to `String(localized:)` when localization is added:

```swift
import Foundation

// MARK: - User-Facing Strings (Localization-Ready)

/// Centralized user-facing strings. When localization is needed, replace
/// each `String` return value with `String(localized:)`.
///
/// Example future migration:
/// ```
/// static var ghNotAuthenticated: String {
///     String(localized: "error.gh_not_authenticated",
///            defaultValue: "gh not authenticated")
/// }
/// ```
enum Strings {

    // MARK: Errors

    enum Error {
        static let ghNotAuthenticated = "gh not authenticated"
        static let ghCliNotFound = "GitHub CLI (gh) not found — install it with: brew install gh"
        static let ghApiErrorFallback = "GitHub API error"
        static let ghInvalidJSON = "Invalid response from GitHub API"
        static let ghTimeout = "GitHub CLI timed out — check your network connection"

        static func reviewFetchPrefix(_ message: String) -> String {
            "Reviews: \(message)"
        }
    }

    // MARK: Notifications

    enum Notification {
        static let ciFailed = "CI Failed"
        static let allChecksPassed = "All Checks Passed"
        static let prNoLongerOpen = "PR No Longer Open"

        static func ciStatusBody(repo: String, number: String, title: String) -> String {
            "\(repo) \(number): \(title)"
        }

        static func prClosedBody(id: String) -> String {
            "\(id) was merged or closed"
        }
    }

    // MARK: PR States

    enum PRState {
        static let open = "Open"
        static let closed = "Closed"
        static let merged = "Merged"
        static let draft = "Draft"
        static let mergeQueue = "Merge Queue"
        static func queuePosition(_ pos: Int) -> String { "Queue #\(pos)" }
    }

    // MARK: Review Decisions

    enum Review {
        static let approved = "Approved"
        static let changesRequested = "Changes"
        static let reviewRequired = "Review"
    }

    // MARK: CI Status

    enum CI {
        static func failedCount(_ count: Int) -> String { "\(count) failed" }
        static func checksProgress(passed: Int, total: Int) -> String {
            "\(passed)/\(total) checks"
        }
        static func checksPassed(passed: Int, total: Int) -> String {
            "\(passed)/\(total) passed"
        }
    }

    // MARK: Merge Conflicts

    enum Merge {
        static let conflicts = "Conflicts"
    }

    // MARK: Menu Bar / Status

    enum Status {
        static func barSummary(myCount: Int, reviewCount: Int) -> String {
            "\(myCount) | \(reviewCount)"
        }
    }

    // MARK: Refresh

    enum Refresh {
        static func countdownSeconds(_ seconds: Int) -> String { "~\(seconds)s" }
        static let countdownAboutOneMinute = "~1 min"
        static func countdownMinutes(_ minutes: Int) -> String { "~\(minutes) min" }
        static func refreshesIn(_ label: String) -> String { "Refreshes in \(label)" }
        static let refreshing = "Refreshing…"
        static func refreshesEvery(_ label: String) -> String {
            "Refreshes every \(label)"
        }
    }

    // MARK: Empty States

    enum EmptyState {
        static let loadingTitle = "Loading pull requests…"
        static let noPRsTitle = "No open pull requests"
        static let noPRsSubtitle = "Your open, draft, and queued PRs will appear here automatically"
        static let noReviewsTitle = "No review requests"
        static let noReviewsSubtitle = "Pull requests where your review is requested will appear here"
        static let filteredTitle = "All review requests hidden"
        static let filteredSubtitle = "Adjust your review filters in Settings to see more PRs"
    }

    // MARK: Auth

    enum Auth {
        static func signedIn(_ username: String) -> String { "Signed in as \(username)" }
        static let notAuthenticated = "Not authenticated"
        static let authInstructions = "Run this command in your terminal:"
        static let authCommand = "gh auth login"
        static let compactNotAuth = "gh not authenticated"
    }
}
```

### 1.3 Update references across codebase

Replace all magic values with references to `AppConstants` and `Strings`. Files affected:

| File | Changes |
|------|---------|
| `GitHubService.swift` | `knownBinaryPaths`, `paginationLimit`, `processTimeoutSeconds`, `terminationGracePeriod`, `GHError` descriptions → `Strings.Error.*` |
| `PRManager.swift` | Menu bar layout constants → `AppConstants.Layout.MenuBar.*`, error strings → `Strings.Error.*` |
| `ContentView.swift` | Frame sizes → `AppConstants.Layout.ContentWindow.*`, tab picker width → `AppConstants.Layout.Header.*`, empty state strings → `Strings.EmptyState.*`, footer label → `Strings.Refresh.*` |
| `SettingsView.swift` | Frame sizes → `AppConstants.Layout.SettingsWindow.*` |
| `App.swift` | `"url"` key → `AppConstants.Notification.urlInfoKey`, font size → `AppConstants.Layout.MenuBar.statusFontSize` |
| `NotificationDispatcher.swift` | `"url"` key → `AppConstants.Notification.urlInfoKey` |
| `SettingsStore.swift` | Keys → `AppConstants.DefaultsKey.*`, default interval → `AppConstants.Defaults.refreshInterval` |
| `StatusChangeDetector.swift` | Notification titles/bodies → `Strings.Notification.*` |
| `PRStatusSummary.swift` | Summary format → `Strings.Status.barSummary(...)`, countdown labels → `Strings.Refresh.*` |
| `PRRowView.swift` | State text → `Strings.PRState.*`, review text → `Strings.Review.*`, CI text → `Strings.CI.*`, conflict text → `Strings.Merge.*` |
| `AuthStatusView.swift` | Auth messages → `Strings.Auth.*` |

### 1.4 Add tests for GHError descriptions

**File:** `Tests/GitHubServiceParsingTests.swift`

Add a new suite verifying error descriptions use the centralized strings:

| Test | Expected |
|------|----------|
| `ghErrorCliNotFoundDescription` | Contains `Strings.Error.ghCliNotFound` |
| `ghErrorTimeoutDescription` | Contains `Strings.Error.ghTimeout` |
| `ghErrorApiErrorDescription` | Contains the custom message |
| `ghErrorApiErrorEmptyDescription` | Returns `Strings.Error.ghApiErrorFallback` |
| `ghErrorInvalidJSONDescription` | Contains `Strings.Error.ghInvalidJSON` |

### 1.5 Update StatusChangeDetector tests

Existing `StatusChangeDetectorTests.swift` already asserts on notification titles like `"CI Failed"`. Update these to use `Strings.Notification.*` constants so they don't break if strings change.

### 1.6 Update PRStatusSummary tests

Existing `PRStatusSummaryTests.swift` asserts on formatted strings. Update to use `Strings.Refresh.*` and `Strings.Status.*`.

### Success Criteria

#### Automated Verification:
- [ ] `swift build` — zero errors, zero warnings
- [ ] `swift test` — all tests pass (existing + new GHError description tests)
- [ ] `swiftlint lint --strict` — no new violations
- [ ] `rg '"polling_interval"|"collapsed_repos"|"filter_settings"|"url"' Sources/` — only hits in `Constants.swift`
- [ ] `rg 'width: 400|width: 460|width: 560|width: 320|width: 380|width: 480' Sources/` — zero hits (all replaced by constants)

#### Manual Verification:
- [ ] App launches and displays correctly (frame sizes unchanged)
- [ ] Menu bar icon renders correctly (layout constants unchanged)

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation before proceeding to Round 2.

---

## Phase 2: Improve `gh` Binary Resolution + GitHubService Logging

**Goal:** Search the system PATH as a fallback when `gh` isn't at a known location. Log the resolved path so users can debug "wrong gh" issues.

### 2.1 Add PATH-based `gh` resolution

**File:** `GitHubService.swift`

Replace the simple array-check init with a two-stage resolution:

```swift
private static let logger = Logger(subsystem: "PRStatusWatcher", category: "GitHubService")

init() {
    // Stage 1: Check known install locations (fastest)
    if let known = AppConstants.GitHub.knownBinaryPaths
        .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
        self.ghPath = known
        Self.logger.info("init: gh found at known path: \(known, privacy: .public)")
        return
    }

    // Stage 2: Search PATH
    if let pathResolved = Self.resolveFromPATH("gh") {
        self.ghPath = pathResolved
        Self.logger.info("init: gh found via PATH: \(pathResolved, privacy: .public)")
        return
    }

    // Fallback: bare "gh" and hope Process can find it
    self.ghPath = "gh"
    Self.logger.warning("init: gh not found at known paths or in PATH, falling back to bare 'gh'")
}

/// Search the system PATH for an executable by name.
/// Returns the full path if found, nil otherwise.
static func resolveFromPATH(_ binary: String) -> String? {
    guard let pathEnv = ProcessInfo.processInfo.environment["PATH"] else { return nil }
    let directories = pathEnv.split(separator: ":").map(String.init)
    for dir in directories {
        let candidate = (dir as NSString).appendingPathComponent(binary)
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }
    return nil
}
```

### 2.2 Add logging to `currentUser()`

Replace `try?` with `do-catch` to log actual errors (addresses issue 4.4 from the adversarial review):

```swift
func currentUser() -> String? {
    logger.info("currentUser: resolving via gh api user")
    let output: (stdout: String, stderr: String, exitCode: Int32)
    do {
        output = try run(["api", "user", "--jq", ".login"])
    } catch GHError.cliNotFound {
        logger.error("currentUser: gh CLI not found at path '\(self.ghPath, privacy: .public)'")
        return nil
    } catch GHError.timeout {
        logger.error("currentUser: gh CLI timed out during user resolution")
        return nil
    } catch {
        logger.error("currentUser: unexpected error: \(error.localizedDescription, privacy: .public)")
        return nil
    }
    if output.exitCode != 0 {
        logger.error("currentUser: exit=\(output.exitCode), stderr=\(output.stderr.prefix(200), privacy: .public)")
    }
    guard output.exitCode == 0 else { return nil }
    let username = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    logger.info("currentUser: resolved to '\(username, privacy: .public)'")
    return username.isEmpty ? nil : username
}
```

### 2.3 Add logging for dropped PR nodes

In `fetchPRs`, log when `parsePRNode` returns nil (addresses issue 4.5):

```swift
let prs = nodes.compactMap { node -> PullRequest? in
    guard let pr = parsePRNode(node) else {
        logger.debug("fetchPRs: skipping malformed node (number=\(node["number"] as? Int ?? -1))")
        return nil
    }
    return pr
}
```

### 2.4 Add test for PATH resolution

**File:** `Tests/GitHubServiceParsingTests.swift`

Test the static `resolveFromPATH` method:

| Test | Setup | Expected |
|------|-------|----------|
| `resolveFromPATHFindsCommonBinaries` | Resolve `"ls"` (always exists) | Returns a non-nil path ending in `/ls` |
| `resolveFromPATHReturnsNilForNonexistent` | Resolve `"definitely_not_a_binary_xyz"` | Returns `nil` |

Note: `resolveFromPATH` needs to be changed from `private` to `internal` (or `static func` already accessible) for testing. Since it's already `static`, just remove `private` or mark it `internal` explicitly.

### Success Criteria

#### Automated Verification:
- [ ] `swift build` — zero errors
- [ ] `swift test` — all tests pass including new PATH resolution tests
- [ ] `swiftlint lint --strict` — no new violations

#### Manual Verification:
- [ ] Run the app and check Console.app for `"gh found at"` log entry
- [ ] Verify the correct `gh` binary is being used

---

## Phase 3: Surface Persistence Failures in SettingsStore

**Goal:** Log persistence encode/decode errors instead of silently swallowing them. Add protocol support for error reporting.

### 3.1 Add logging to `SettingsStore`

**File:** `Sources/SettingsStore.swift`

```swift
import os

private let logger = Logger(subsystem: "PRStatusWatcher", category: "SettingsStore")

final class SettingsStore: SettingsStoreProtocol {
    // ... existing code ...

    func loadFilterSettings() -> FilterSettings {
        guard let data = defaults.data(forKey: AppConstants.DefaultsKey.filterSettings) else {
            logger.info("loadFilterSettings: no saved data, using defaults")
            return FilterSettings()
        }
        do {
            return try JSONDecoder().decode(FilterSettings.self, from: data)
        } catch {
            logger.error("loadFilterSettings: decode failed: \(error.localizedDescription, privacy: .public)")
            return FilterSettings()
        }
    }

    func saveFilterSettings(_ value: FilterSettings) {
        do {
            let data = try JSONEncoder().encode(value)
            defaults.set(data, forKey: AppConstants.DefaultsKey.filterSettings)
            logger.debug("saveFilterSettings: saved successfully")
        } catch {
            logger.error("saveFilterSettings: encode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadRefreshInterval() -> Int {
        let saved = defaults.integer(forKey: AppConstants.DefaultsKey.pollingInterval)
        let result = saved > 0 ? saved : AppConstants.Defaults.refreshInterval
        logger.debug("loadRefreshInterval: \(result)s")
        return result
    }

    func saveRefreshInterval(_ value: Int) {
        defaults.set(value, forKey: AppConstants.DefaultsKey.pollingInterval)
        logger.debug("saveRefreshInterval: \(value)s")
    }

    func loadCollapsedRepos() -> Set<String> {
        let result = Set(defaults.stringArray(forKey: AppConstants.DefaultsKey.collapsedRepos) ?? [])
        logger.debug("loadCollapsedRepos: \(result.count) repos")
        return result
    }

    func saveCollapsedRepos(_ value: Set<String>) {
        defaults.set(Array(value), forKey: AppConstants.DefaultsKey.collapsedRepos)
        logger.debug("saveCollapsedRepos: \(value.count) repos")
    }
}
```

### 3.2 Verify existing tests still pass

The existing `SettingsStoreTests.swift` already covers:
- Default values when no data is saved
- Round-trip save/load
- Corrupted data fallback

No new tests are needed — the behavior is identical, just with logging added. The existing `loadFilterSettingsCorruptedDataReturnsDefault` test already validates the error path.

### 3.3 Add test for encode failure path (optional but thorough)

It's difficult to make `JSONEncoder().encode(FilterSettings)` fail because `FilterSettings` is a simple Codable struct. However, we can add a test that verifies the `SettingsStore` logs gracefully and doesn't crash when UserDefaults contains unexpected types:

| Test | Setup | Expected |
|------|-------|----------|
| `loadFilterSettingsWithWrongTypeReturnsDefault` | Set an `Int` at the filter settings key | Returns `FilterSettings()` defaults |

### Success Criteria

#### Automated Verification:
- [ ] `swift build` — zero errors
- [ ] `swift test` — all tests pass (existing + optional new test)
- [ ] `swiftlint lint --strict` — no new violations

#### Manual Verification:
- [ ] Corrupt the `filter_settings` key in UserDefaults (`defaults write` CLI), launch app → verify log message in Console.app

---

## Phase 4: Add App Lifecycle and Notification Logging

**Goal:** Instrument `App.swift` and `NotificationDispatcher.swift` with structured logging.

### 4.1 Add logging to `AppDelegate`

**File:** `Sources/App.swift`

```swift
import os

private let logger = Logger(subsystem: "PRStatusWatcher", category: "App")

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("applicationDidFinishLaunching: setting activation policy to .accessory")
        NSApplication.shared.setActivationPolicy(.accessory)
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
            logger.info("applicationDidFinishLaunching: notification delegate registered")
        } else {
            logger.warning("applicationDidFinishLaunching: no bundle identifier — notifications disabled")
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let urlString = response.notification.request.content
            .userInfo[AppConstants.Notification.urlInfoKey] as? String,
           let url = URL(string: urlString) {
            logger.info("notification tapped: opening \(urlString, privacy: .public)")
            NSWorkspace.shared.open(url)
        } else {
            logger.warning("notification tapped: no valid URL in userInfo")
        }
        completionHandler()
    }
}
```

### 4.2 Add logging to `NotificationDispatcher`

**File:** `Sources/NotificationDispatcher.swift`

```swift
import os

private let logger = Logger(subsystem: "PRStatusWatcher", category: "NotificationDispatcher")

final class NotificationDispatcher: NotificationServiceProtocol {
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
        ) { granted, error in
            if let error {
                logger.error("requestPermission: failed: \(error.localizedDescription, privacy: .public)")
            } else {
                logger.info("requestPermission: granted=\(granted)")
            }
        }
    }

    func send(title: String, body: String, url: URL?) {
        guard isAvailable else {
            logger.debug("send: skipped — no bundle identifier")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let url {
            content.userInfo = [AppConstants.Notification.urlInfoKey: url.absoluteString]
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.error("send: delivery failed: \(error.localizedDescription, privacy: .public)")
            } else {
                logger.debug("send: delivered '\(title, privacy: .public)'")
            }
        }
    }
}
```

### 4.3 Update `MockNotificationService` to track permission results

**File:** `Tests/Mocks/MockNotificationService.swift`

Add a `permissionGranted` property and `permissionError` for richer test scenarios:

```swift
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

(No changes needed — the mock is already well-structured. The logging changes are in the real implementation only.)

### Success Criteria

#### Automated Verification:
- [ ] `swift build` — zero errors
- [ ] `swift test` — all tests pass
- [ ] `swiftlint lint --strict` — no new violations

#### Manual Verification:
- [ ] Launch the app and check Console.app for `"applicationDidFinishLaunching"` log
- [ ] Trigger a notification → check Console.app for `"send: delivered"` log
- [ ] Click a notification → check Console.app for `"notification tapped"` log
- [ ] Run via `swift run` → check for `"no bundle identifier"` warning

---

## Phase 5: Update README

**Goal:** Remove stale "Future Improvements" items, update the architecture section to reflect extracted components, and document the constants/strings pattern.

### 5.1 Update Architecture Section

Add the extracted files to the architecture diagram:

```
Sources/
├── App.swift                  # @main entry point, MenuBarExtra setup, notification delegate
├── AuthStatusView.swift       # Shared auth status component (compact / detailed)
├── Constants.swift            # Centralized configuration constants
├── ContentView.swift          # Main UI with tabs, grouped/collapsible repo sections
├── GitHubService.swift        # GraphQL queries via gh CLI, PATH-based binary resolution
├── GitHubServiceProtocol.swift # Protocol for dependency injection
├── Models.swift               # PullRequest model, state & CI enums, FilterSettings
├── NotificationDispatcher.swift # macOS notification delivery
├── NotificationServiceProtocol.swift # Protocol for notification injection
├── PollingScheduler.swift     # Async polling loop with cancellation support
├── PRManager.swift            # ViewModel — orchestrates fetch, state, and notifications
├── PRRowView.swift            # Individual PR row with status badges
├── PRStatusSummary.swift      # Pure functions for menu bar state derivation
├── SettingsStore.swift        # UserDefaults persistence with error logging
├── SettingsStoreProtocol.swift # Protocol for settings injection
├── SettingsView.swift         # Settings (auth, launch at login, polling, review filters)
├── StatusChangeDetector.swift # Diff-based notification trigger logic
├── StatusNotification.swift   # Notification model
└── Strings.swift              # User-facing strings (localization-ready)
```

### 5.2 Remove Resolved "Future Improvements" Items

Remove items that are now complete:

**Code Correctness — REMOVE:**
- "Store and cancel the polling task" — Done in PRManager decomposition (PollingScheduler)
- "Escape GraphQL query parameters" — Done (`escapeForGraphQL` exists)
- "Handle StatusContext nodes in check parsing" — Done (`tallyCheckContexts` handles both)

**Code Quality — REMOVE:**
- "Remove dead error cases" — Done (GHError only has 4 active cases)
- "Remove `statusColor` passthrough in PRRowView" — Done (uses `pullRequest.statusColor` directly)
- "Remove redundant sorting in PRManager" — Done (PRManager no longer sorts)
- "Replace `AnyView` with `@ViewBuilder` in badgePill" — Done (uses generic `@ViewBuilder`)
- "Add `Codable` conformance to PullRequest" — Done
- "Add `Equatable` conformance to PullRequest" — Done
- "Surface notification unavailability" — Done (bell.slash icon in footer)
- "Handle `SMAppService.register()` failures" — Done (SettingsView catches and displays errors)

**UX / Accessibility — REMOVE:**
- "Add keyboard shortcuts" — Done (Cmd+R, Cmd+,, Cmd+Q)
- "Persist collapsed repo state" — Done (SettingsStore)
- "Add accessibility labels" — Done (throughout all views)

**Keep** "Adaptive window sizing" — still relevant (now uses centralized constants but doesn't adapt to Dynamic Type).

### 5.3 Add Localization Section

Add a note about the localization preparation:

```markdown
## Localization

User-facing strings are centralized in `Sources/Strings.swift`. When localization is needed:

1. Add a `Localizable.xcstrings` string catalog to the project
2. Replace each `Strings.*` property with `String(localized:)`:

   ```swift
   // Before
   static let ghNotAuthenticated = "gh not authenticated"

   // After
   static var ghNotAuthenticated: String {
       String(localized: "error.gh_not_authenticated",
              defaultValue: "gh not authenticated")
   }
   ```

3. Export the string catalog for translation
```

### 5.4 Update "How it works" Section

Update to mention PATH-based resolution:

> On launch (and every N seconds, configurable in Settings), the app runs two GitHub GraphQL queries through the `gh` CLI...

> The `gh` binary is resolved by checking known install locations (Homebrew, /usr/local, /usr/bin) and then searching the system PATH. Configuration constants live in `Sources/Constants.swift`.

### Success Criteria

#### Automated Verification:
- [ ] `swift build` — zero errors (README changes don't affect build, but verify nothing broke)
- [ ] `swift test` — all tests pass
- [ ] No stale items remain in "Future Improvements" that are already implemented

#### Manual Verification:
- [ ] README accurately describes current architecture
- [ ] "Future Improvements" section only contains genuinely open items
- [ ] Localization section is clear and actionable

---

## Implementation Order Summary

| Step | Phase | Subagent | Files Changed | Est. Lines | Risk |
|------|-------|----------|---------------|-----------|------|
| 1 | Phase 1.1-1.2 | Main | New: `Constants.swift`, `Strings.swift` | ~200 | Low |
| 2 | Phase 1.3 | Main | 11 source files | ~80 | Low — mechanical replacements |
| 3 | Phase 1.4-1.6 | Main | 3 test files | ~30 | Low |
| 4a | Phase 2.1-2.4 | Subagent A | `GitHubService.swift`, tests | ~50 | Low |
| 4b | Phase 3.1-3.3 | Subagent B | `SettingsStore.swift`, tests | ~40 | Low |
| 4c | Phase 4.1-4.3 | Subagent C | `App.swift`, `NotificationDispatcher.swift` | ~30 | Low |
| 5 | Phase 5.1-5.4 | Main | `README.md` | ~60 | Low — docs only |

Total estimated: ~490 lines changed/added across source, tests, and docs.

---

## Testing Strategy

### New Tests Added:
- `GHError` description tests (5 cases) — verifies error strings match `Strings.Error.*`
- PATH resolution tests (2 cases) — verifies `resolveFromPATH` finds/doesn't find binaries
- SettingsStore wrong-type test (1 case) — verifies graceful handling of unexpected UserDefaults types

### Existing Tests Updated:
- `StatusChangeDetectorTests` — string assertions use `Strings.Notification.*` constants
- `PRStatusSummaryTests` — format assertions use `Strings.Refresh.*` and `Strings.Status.*` constants
- All existing tests continue to pass (behavior unchanged, only string sources changed)

### Untestable Changes (Logging Only):
- `App.swift` lifecycle logging — verified via Console.app
- `NotificationDispatcher` logging — verified via Console.app
- `SettingsStore` debug/error logging — verified via Console.app

## References

- Original research: `thoughts/shared/research/2026-02-11-adversarial-code-review-findings.md`, issues 1.7, 4.10, 4.11
- Architecture: `thoughts/shared/research/2026-02-10-architecture-and-design-patterns.md`
- P0 bugfix plan: `thoughts/shared/plans/2026-02-11-p0-bugfixes.md`
