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

On launch (and at a configurable interval, default 60s), the app runs two GitHub GraphQL queries through the `gh` CLI -- one for your authored PRs and one for PRs where your review is requested -- along with their CI check status. No tokens to manage, no API keys to configure -- it piggybacks on your existing `gh auth` session.

The `gh` binary is resolved by checking known install locations (Homebrew, /usr/local, /usr/bin) and then searching the system `PATH`. Configuration constants live in `Sources/Constants.swift`.

PRs are grouped by repository and sorted by state (Open, Draft, Queued) then by PR number.

## Architecture

```
Sources/
├── App.swift                      # @main entry point, MenuBarExtra setup, notification delegate
├── AuthStatusView.swift           # Shared auth status component (compact / detailed)
├── Constants.swift                # Centralized configuration constants (layout, keys, limits)
├── ContentView.swift              # Main UI with tabs, grouped/collapsible repo sections
├── GitHubService.swift            # GraphQL queries via gh CLI, PATH-based binary resolution
├── GitHubServiceProtocol.swift    # Protocol for dependency injection
├── Models.swift                   # PullRequest model, state & CI enums, FilterSettings
├── NotificationDispatcher.swift   # macOS notification delivery with structured logging
├── NotificationServiceProtocol.swift  # Protocol for notification injection
├── PollingScheduler.swift         # Async polling loop with cancellation support
├── PRManager.swift                # ViewModel — orchestrates fetch, state, and notifications
├── PRRowView.swift                # Individual PR row with status badges
├── PRStatusSummary.swift          # Pure functions for menu bar state derivation
├── SettingsStore.swift            # UserDefaults persistence with error logging
├── SettingsStoreProtocol.swift    # Protocol for settings injection
├── SettingsView.swift             # Settings (auth, launch at login, polling, review filters)
├── StatusChangeDetector.swift     # Diff-based notification trigger logic
├── StatusNotification.swift       # Notification model
└── Strings.swift                  # User-facing strings (localization-ready)
```

- **SwiftUI** with `MenuBarExtra` (macOS 13+)
- **GitHub GraphQL API** via `gh api graphql` -- two calls per refresh (authored + reviews)
- **Swift concurrency** (async/await, TaskGroup)
- **Protocol-based dependency injection** for full testability
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
├── GitHubServiceParsingTests.swift    # GraphQL parsing, GHError descriptions, PATH resolution
├── Mocks/
│   ├── MockGitHubService.swift
│   ├── MockNotificationService.swift
│   └── MockSettingsStore.swift
├── PRManagerTests.swift               # ViewModel integration tests
├── PRStatusSummaryTests.swift         # Status icon/bar logic
├── PullRequestTests.swift             # Model computed properties
├── SettingsStoreTests.swift           # UserDefaults persistence, error handling
└── StatusChangeDetectorTests.swift    # Notification change detection
```

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

## Future Improvements

### Performance

- [ ] **Adaptive window sizing** -- `ContentView` and `SettingsView` use centralized frame constants but don't adapt to Dynamic Type, accessibility settings, or content amount.
- [ ] **Combine GraphQL queries** -- Merge the two per-refresh queries (authored + reviews) into a single aliased GraphQL query to halve process spawn overhead.
- [ ] **Cache `menuBarImage`** -- Only regenerate the menu bar icon when `overallStatusIcon` or `hasFailure` actually changes.
- [ ] **Smart polling** -- Back off on errors, pause when the system is asleep, reduce frequency when no PRs are tracked.

### Architecture

- [ ] **Remove `@unchecked Sendable`** from `GitHubService` -- Either make it an `actor` or add proper synchronization to `run()`.
- [ ] **Move business logic out of views** -- `ContentView.groupedPRs` contains domain sorting logic that can't be unit tested.

### Data

- [ ] **GraphQL pagination** -- The current `first: 100` cap (configurable in `AppConstants.GitHub.paginationLimit`) silently truncates for users with >100 PRs or check contexts. Add cursor-based pagination or surface a truncation indicator.

## License

MIT
