# PR Status Watcher

A lightweight macOS menu bar app that automatically tracks all of your open GitHub pull requests. See CI status, merge queue position, draft state, and more -- without ever leaving your desktop.

![PR Status Watcher](screenshot.png)

## What it does

- **Auto-discovers** all of your open, draft, and queued PRs -- no manual setup
- **Groups by repo** with collapsible sections
- **CI status** at a glance -- pass/fail counts and colored status dots
- **Merge queue detection** -- see which PRs are actually queued vs just open
- **Click to open** any PR directly in your browser
- **Auto-refreshes** every 60 seconds via fast GraphQL calls
- Lives entirely in the menu bar -- no Dock icon, no windows

## Menu Bar Icon

| Icon | Meaning |
|------|---------|
| Pull arrow | No open PRs |
| Green checkmark (filled) | All checks passing |
| Green checkmark (outline) | All PRs merged/closed |
| Orange clock | Some checks still running |
| Red X | One or more checks failing |

## Prerequisites

1. **macOS 13 (Ventura)** or later
2. **Xcode Command Line Tools**
   ```bash
   xcode-select --install
   ```
3. **GitHub CLI (`gh`)** -- installed and authenticated
   ```bash
   # Install
   brew install gh

   # Authenticate (follow the prompts)
   gh auth login
   ```
   If you work with a GitHub org that uses SSO, make sure to authorize your token for that org during login.

## Run locally

```bash
# Clone and run
git clone <your-repo-url>
cd pr-status-watcher
swift run
```

The app appears in your menu bar. Click the icon to see your PRs.

## Build as a standalone .app

```bash
./build.sh
```

Then either run it directly or install to Applications:

```bash
open ".build/release/PR Status Watcher.app"

# or
cp -r ".build/release/PR Status Watcher.app" /Applications/
```

## How it works

On launch (and every 60s), the app runs two GitHub GraphQL queries through the `gh` CLI -- one for your authored PRs and one for PRs where your review is requested -- along with their CI check status. No tokens to manage, no API keys to configure -- it piggybacks on your existing `gh auth` session.

PRs are grouped by repository and sorted by state (Open, Draft, Queued) then by PR number.

## Architecture

```
Sources/
├── App.swift                  # @main entry point, MenuBarExtra setup, notification delegate
├── AuthStatusView.swift       # Shared auth status component (compact / detailed)
├── Models.swift               # PullRequest model, FilterSettings, state & CI enums
├── GitHubService.swift        # GraphQL queries via gh CLI (paginated, with error surfacing)
├── GitHubServiceProtocol.swift # Protocol for dependency injection / testing
├── PRManager.swift            # ViewModel -- discovery, polling, state, notifications
├── PRStatusSummary.swift      # Pure functions for status icon, bar summary, countdown
├── PollingScheduler.swift     # Encapsulated polling timer with cancellation
├── StatusChangeDetector.swift # Diffing logic for CI status change notifications
├── StatusNotification.swift   # Notification data model
├── NotificationDispatcher.swift # UNUserNotificationCenter wrapper
├── NotificationServiceProtocol.swift # Protocol for notification injection
├── SettingsStore.swift        # UserDefaults-backed persistence
├── SettingsStoreProtocol.swift # Protocol for settings injection
├── ContentView.swift          # Main UI with tabs, grouped/collapsible repo sections
├── PRRowView.swift            # Individual PR row with status badges
└── SettingsView.swift         # Settings (auth, launch at login, polling interval)
```

- **SwiftUI** with `MenuBarExtra` (macOS 13+)
- **GitHub GraphQL API** via `gh api graphql` -- paginated cursor-based fetching (authored + reviews)
- **Swift concurrency** (async/await, Task.detached)
- **Protocol-driven architecture** -- all services injectable via protocols for testability
- Zero third-party dependencies

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

## Future Improvements

### Code Correctness

- [ ] **Harden `gh auth status` parsing** -- Replace the current string-matching against `gh auth status --active` human-readable output ("Logged in to github.com account USERNAME") with structured output via `gh api user --jq .login`. The current approach is fragile and one `gh` CLI version change away from breaking.

### Code Quality

- [ ] **Remove `statusColor` passthrough in PRRowView** -- `private var statusColor` on line 101 of `PRRowView.swift` is a one-liner alias for `pullRequest.statusColor`. Inline it at the single call site.
- [ ] **Remove redundant sorting in PRManager** -- `refreshAll()` sorts PRs by repo+number, but `ContentView.groupedPRs` re-sorts by priority+number. The PRManager sort is wasted work.
- [ ] **Replace `AnyView` with `@ViewBuilder` in badgePill** -- The `trailing` parameter uses `AnyView` type erasure, which defeats SwiftUI's view diffing optimizer. Use a generic `@ViewBuilder` closure or a concrete `Image` parameter instead.
- [ ] **Surface notification unavailability** -- When running via `swift run` (no bundle identifier), notifications are silently disabled. Show feedback so the user knows why notifications aren't working.
- [ ] **Handle `SMAppService.register()` failures** -- The launch-at-login toggle in `SettingsView` silently swallows errors with `try?`. If registration fails (e.g., app not codesigned), the toggle appears to flip but nothing happens.

### UX / Accessibility

- [ ] **Add keyboard shortcuts** -- `Cmd+R` for refresh, `Cmd+,` for settings, `Cmd+Q` for quit. These are standard macOS conventions and require only one-line `.keyboardShortcut()` additions to existing buttons.
- [ ] **Add accessibility labels** -- No `accessibilityLabel`, `accessibilityHint`, or other accessibility modifiers exist anywhere in the codebase beyond the menu bar icon image.
- [ ] **Adaptive window sizing** -- `ContentView` and `SettingsView` use hardcoded frame sizes that don't adapt to Dynamic Type, accessibility settings, or content amount.

## License

MIT
