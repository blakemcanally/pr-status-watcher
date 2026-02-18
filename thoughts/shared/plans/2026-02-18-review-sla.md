# Review SLA — Implementation Plan

## Overview

Add a configurable Review SLA feature that visually highlights overdue pull requests on the Reviews tab. When enabled, PRs that have been waiting longer than the configured threshold are pulled into a prominent top-level "SLA Exceeded" section with warning-style red styling. The feature is toggle on/off with a configurable deadline in minutes or hours.

SLA is **display-only** — it does not filter or hide PRs. It reorganizes the Reviews tab into up to three mutually exclusive sections: SLA Exceeded, Ready for Review, and Not Ready.

## Current State Analysis

- `PullRequest` has no GitHub-originated timestamps (`Sources/Models/Models.swift:6-30`). The only `Date` field is `lastFetched` (line 23), set to `Date()` at fetch time.
- The GraphQL query (`Sources/GitHub/GitHubService.swift:219-264`) requests no timestamp fields.
- `PRNode` (`Sources/GitHub/GraphQLResponse.swift:34-49`) has no date fields.
- `FilterSettings` (`Sources/Models/Models.swift:217-264`) uses `decodeIfPresent` for backward compatibility — the pattern for adding new properties is well-established.
- The Reviews tab already partitions PRs into "Ready for Review" / "Not Ready" sections via `readinessSection()` (`Sources/App/ContentView.swift:154-177, 182-209`).
- `PRRowView` does not need changes — no per-row SLA badges.

### Key code references:
- `Sources/Models/Models.swift:6-30` — `PullRequest` stored properties
- `Sources/Models/Models.swift:217-264` — `FilterSettings` with `init`, `init(from:)`, `applyReviewFilters()`
- `Sources/GitHub/GitHubService.swift:210-268` — `buildSearchQuery()` GraphQL template
- `Sources/GitHub/GraphQLResponse.swift:34-49` — `PRNode` fields
- `Sources/GitHub/GitHubService+NodeConversion.swift:7-65` — `convertNode()` mapping
- `Sources/App/ContentView.swift:40-66` — Readiness partitioning (`readyPRs`, `notReadyPRs`)
- `Sources/App/ContentView.swift:154-177` — `reviewsReadinessList` rendering
- `Sources/App/ContentView.swift:182-209` — `readinessSection()` reusable section builder
- `Sources/App/SettingsView.swift:87-96` — Review Readiness toggles section
- `Sources/App/Strings.swift:151-168` — Readiness strings
- `Sources/App/PRManager.swift:78-80` — `filterSettings` with `didSet` persistence
- `Tests/FilterSettingsTests.swift:7-59` — `PullRequest.fixture()` test helper

## Desired End State

After implementation:

1. The GraphQL query fetches `publishedAt` for every PR
2. `PullRequest` stores `publishedAt: Date?` and exposes `isSLAExceeded(minutes:now:)` for SLA computation
3. `FilterSettings` has `reviewSLAEnabled: Bool` (default: false) and `reviewSLAMinutes: Int` (default: 480 / 8 hours)
4. When SLA is enabled on the Reviews tab, PRs are partitioned into three mutually exclusive sections:
   - **SLA Exceeded** — PRs where `publishedAt` + threshold < now (red/warning styling)
   - **Ready for Review** — remaining PRs that pass readiness checks
   - **Not Ready** — remaining PRs that fail readiness checks
5. When SLA is disabled, the Reviews tab works exactly as it does today (Ready / Not Ready)
6. Settings has a new "Review SLA" section with a toggle, a numeric field, and a unit picker (minutes/hours)
7. All changes are backward-compatible — existing persisted settings decode cleanly

**Verification example:**

User enables SLA with a 4-hour (240-minute) threshold. They have 5 review PRs:
- PR #101 — published 6 hours ago, CI passing → appears in **SLA Exceeded**
- PR #102 — published 5 hours ago, CI failing → appears in **SLA Exceeded**
- PR #103 — published 2 hours ago, CI passing → appears in **Ready for Review**
- PR #104 — published 1 hour ago, CI failing → appears in **Not Ready**
- PR #105 — draft, publishedAt is nil → appears in **Not Ready** (no SLA applies)

When SLA is toggled off, all 5 PRs revert to the current Ready/Not Ready layout.

## What We're NOT Doing

- **Per-row SLA badges** — The section-level styling is sufficient. Badges can be added later if needed.
- **SLA notifications** — Deferred to a future enhancement. Implement visual indicators first.
- **Per-repo SLA thresholds** — Global threshold only. Per-repo is a future enhancement.
- **Business hours calculation** — Wall-clock time only. Business-hours adds timezone/calendar complexity.
- **`createdAt` fallback** — Use `publishedAt` directly. When null (draft PRs), SLA simply doesn't apply.
- **Filtering/hiding PRs based on SLA** — SLA is display-only. All PRs remain visible; they're just reorganized into sections.

## Implementation Approach

Six phases — Phases 1–5 are code changes with automated verification after each. Phase 6 kills, rebuilds, and relaunches the app for consolidated manual verification of all features.

1. **Phase 1:** Data pipeline — `publishedAt` in GraphQL, PRNode, PullRequest, and conversion
2. **Phase 2:** Configuration + computation — `FilterSettings` SLA properties, `PullRequest` SLA methods
3. **Phase 3:** UI — Reviews tab SLA section in ContentView
4. **Phase 4:** UI — Settings toggle + value configuration, strings
5. **Phase 5:** Tests — SLA computation, FilterSettings backward compat, fixture update
6. **Phase 6:** Kill running app, rebuild, relaunch, and run through full manual verification checklist

---

## Phase 1: Data Pipeline

### Overview
Extend the GraphQL query to fetch `publishedAt`, add the field to the response type and domain model, and parse the ISO 8601 timestamp during node conversion.

### Changes Required:

#### 1. GraphQL Query
**File**: `Sources/GitHub/GitHubService.swift`
**Changes**: Add `publishedAt` field to the PullRequest fragment in `buildSearchQuery()`.

Add `publishedAt` after `title` (line 222):

```swift
... on PullRequest {
    number
    title
    publishedAt
    author { login }
    isDraft
    // ... rest unchanged ...
```

#### 2. GraphQL Response Type
**File**: `Sources/GitHub/GraphQLResponse.swift`
**Changes**: Add `publishedAt` field to `PRNode`.

Add after `title` (line 36):

```swift
struct PRNode: Codable {
    let number: Int?
    let title: String?
    let publishedAt: String?
    let url: String?
    // ... rest unchanged ...
```

#### 3. Domain Model
**File**: `Sources/Models/Models.swift`
**Changes**: Add `publishedAt: Date?` stored property to `PullRequest`.

Add after `lastFetched` (line 23):

```swift
var lastFetched: Date
var publishedAt: Date?
var reviewDecision: ReviewDecision
```

#### 4. Node Conversion
**File**: `Sources/GitHub/GitHubService+NodeConversion.swift`
**Changes**: Parse the ISO 8601 string into a `Date?` and pass it to the `PullRequest` initializer.

Add a static ISO8601 formatter (at the top of the extension or as a file-level constant):

```swift
private let iso8601Formatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
```

In `convertNode()`, parse `publishedAt` and pass it through:

```swift
let publishedAt: Date? = node.publishedAt.flatMap { iso8601Formatter.date(from: $0) }
```

Add to the `PullRequest(...)` initializer call:

```swift
return PullRequest(
    // ... existing fields ...
    lastFetched: Date(),
    publishedAt: publishedAt,
    reviewDecision: reviewDecision,
    // ... rest unchanged ...
)
```

### Success Criteria:

#### Automated Verification:
- [x] Project compiles: `swift build`
- [x] All existing tests pass: `swift test`

---

## Phase 2: Configuration + SLA Computation

### Overview
Add SLA settings to `FilterSettings` and SLA computation methods to `PullRequest`.

### Changes Required:

#### 1. FilterSettings — New Properties
**File**: `Sources/Models/Models.swift`
**Changes**: Add `reviewSLAEnabled` and `reviewSLAMinutes` to `FilterSettings`.

Add after `ignoredRepositories` (line 223):

```swift
struct FilterSettings: Codable, Equatable {
    var hideDrafts: Bool
    var hideApprovedByMe: Bool
    var hideNotReady: Bool
    var requiredCheckNames: [String]
    var ignoredCheckNames: [String]
    var ignoredRepositories: [String]
    var reviewSLAEnabled: Bool
    var reviewSLAMinutes: Int
```

Update the memberwise `init` (add to the end of the parameter list):

```swift
init(
    // ... existing parameters ...
    ignoredRepositories: [String] = [],
    reviewSLAEnabled: Bool = false,
    reviewSLAMinutes: Int = 480
) {
    // ... existing assignments ...
    self.ignoredRepositories = ignoredRepositories
    self.reviewSLAEnabled = reviewSLAEnabled
    self.reviewSLAMinutes = reviewSLAMinutes
}
```

Update `init(from decoder:)` — add at the end:

```swift
reviewSLAEnabled = try container.decodeIfPresent(Bool.self, forKey: .reviewSLAEnabled) ?? false
reviewSLAMinutes = try container.decodeIfPresent(Int.self, forKey: .reviewSLAMinutes) ?? 480
```

#### 2. PullRequest — SLA Methods
**File**: `Sources/Models/Models.swift`
**Changes**: Add SLA computation methods to `PullRequest`, after the existing `effectiveStatusColor` method.

```swift
// MARK: - Review SLA

/// Whether this PR has exceeded the given SLA deadline.
/// Returns false when publishedAt is nil (PR not yet published / still a draft).
func isSLAExceeded(minutes: Int, now: Date = .now) -> Bool {
    guard let published = publishedAt else { return false }
    let deadline = published.addingTimeInterval(TimeInterval(minutes) * 60)
    return now > deadline
}
```

### Success Criteria:

#### Automated Verification:
- [x] Project compiles: `swift build`
- [x] All existing tests pass: `swift test`

---

## Phase 3: UI — Reviews Tab SLA Section

### Overview
When SLA is enabled, partition review PRs into three mutually exclusive sections: SLA Exceeded (top), Ready for Review, and Not Ready. The SLA Exceeded section uses red/warning styling to stand out.

### Changes Required:

#### 1. SLA Partitioning
**File**: `Sources/App/ContentView.swift`
**Changes**: Add SLA-based partitioning computed properties. When SLA is enabled, PRs that exceed the deadline go into the SLA section; the remaining PRs flow into the existing Ready/Not Ready sections.

Add after the existing `notReadyPRs` computed property (after line 57):

```swift
// MARK: - SLA Partitioning (Reviews tab only)

private var slaExceededPRs: [PullRequest] {
    guard manager.filterSettings.reviewSLAEnabled else { return [] }
    let minutes = manager.filterSettings.reviewSLAMinutes
    return filteredPRs.filter { $0.isSLAExceeded(minutes: minutes) }
}

private var nonSLAExceededPRs: [PullRequest] {
    guard manager.filterSettings.reviewSLAEnabled else { return filteredPRs }
    let minutes = manager.filterSettings.reviewSLAMinutes
    return filteredPRs.filter { !$0.isSLAExceeded(minutes: minutes) }
}

private var groupedSLAExceededPRs: [(repo: String, prs: [PullRequest])] {
    PRGrouping.grouped(prs: slaExceededPRs, isReviews: true)
}
```

Modify `readyPRs` and `notReadyPRs` to partition from `nonSLAExceededPRs` instead of `filteredPRs`:

```swift
private var readyPRs: [PullRequest] {
    nonSLAExceededPRs.filter {
        $0.isReady(
            requiredChecks: manager.filterSettings.requiredCheckNames,
            ignoredChecks: manager.filterSettings.ignoredCheckNames
        )
    }
}

private var notReadyPRs: [PullRequest] {
    nonSLAExceededPRs.filter {
        !$0.isReady(
            requiredChecks: manager.filterSettings.requiredCheckNames,
            ignoredChecks: manager.filterSettings.ignoredCheckNames
        )
    }
}
```

#### 2. Reviews Readiness List — Add SLA Section
**File**: `Sources/App/ContentView.swift`
**Changes**: Add the SLA Exceeded section at the top of `reviewsReadinessList`.

```swift
private var reviewsReadinessList: some View {
    ScrollView {
        LazyVStack(spacing: 0) {
            if !slaExceededPRs.isEmpty {
                readinessSection(
                    key: "slaExceeded",
                    title: Strings.SLA.slaExceeded(slaExceededPRs.count),
                    icon: "exclamationmark.triangle.fill",
                    color: .red,
                    groups: groupedSLAExceededPRs
                )
            }
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

### Success Criteria:

#### Automated Verification:
- [x] Project compiles: `swift build`
- [x] All existing tests pass: `swift test`

---

## Phase 4: UI — Settings + Strings

### Overview
Add a "Review SLA" section in SettingsView with a toggle and a value configuration (number + unit picker). Add all SLA-related strings.

### Changes Required:

#### 1. Strings
**File**: `Sources/App/Strings.swift`
**Changes**: Add a new `SLA` enum after the `Readiness` enum.

```swift
// MARK: SLA

enum SLA {
    static let settingsTitle = "Review SLA"
    static let settingsDescription = "Highlight review requests that have been waiting longer than the deadline. SLA is measured in wall-clock time from when the PR was published."
    static let enableToggle = "Enable review SLA"
    static let deadlineLabel = "Deadline"
    static let unitMinutes = "Minutes"
    static let unitHours = "Hours"

    static func slaExceeded(_ count: Int) -> String {
        "SLA Exceeded (\(count))"
    }
}
```

#### 2. SLA Unit Enum
**File**: `Sources/App/SettingsView.swift`
**Changes**: Add an SLA unit enum for the unit picker.

Add at the top of the file (after imports):

```swift
private enum SLAUnit: String, CaseIterable {
    case minutes = "Minutes"
    case hours = "Hours"
}
```

#### 3. Settings Section
**File**: `Sources/App/SettingsView.swift`
**Changes**: Add the Review SLA section after the Review Readiness toggles section (after line 96, before the Divider leading into Required CI Checks).

Add a `@State` property for tracking the unit selection:

```swift
@State private var slaUnit: SLAUnit = .hours
```

Initialize `slaUnit` based on the current `reviewSLAMinutes` value. Add an `.onAppear` to the settings body (or compute the initial unit from the stored minutes):

The SLA section UI:

```swift
Divider()

// Review SLA Section
VStack(alignment: .leading, spacing: 8) {
    Text(Strings.SLA.settingsTitle)
        .font(.headline)

    Text(Strings.SLA.settingsDescription)
        .font(.caption)
        .foregroundColor(.secondary)

    Toggle(Strings.SLA.enableToggle, isOn: filterBinding(\.reviewSLAEnabled))

    if manager.filterSettings.reviewSLAEnabled {
        HStack(spacing: 8) {
            Text(Strings.SLA.deadlineLabel)
                .font(.caption)

            TextField("", value: slaValueBinding, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)

            Picker("", selection: $slaUnit) {
                ForEach(SLAUnit.allCases, id: \.self) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
        }
    }
}
```

Add a computed binding that converts between the display value (in the selected unit) and the stored minutes:

```swift
private var slaValueBinding: Binding<Int> {
    Binding(
        get: {
            let minutes = manager.filterSettings.reviewSLAMinutes
            switch slaUnit {
            case .minutes: return minutes
            case .hours: return minutes / 60
            }
        },
        set: { newValue in
            let clamped = max(1, newValue)
            switch slaUnit {
            case .minutes: manager.filterSettings.reviewSLAMinutes = clamped
            case .hours: manager.filterSettings.reviewSLAMinutes = clamped * 60
            }
        }
    )
}
```

When `slaUnit` changes, update the stored minutes to keep the value consistent. Add an `.onChange(of: slaUnit)` modifier or handle it within the binding. The simplest approach: when the unit picker changes, convert the current display value to the new unit:

```swift
.onChange(of: slaUnit) { newUnit in
    // Re-derive stored minutes from the current display value in the NEW unit
    // This is handled by slaValueBinding's getter/setter already.
    // But we need to re-convert: if user switches from "8 hours" to minutes,
    // display should show 480 and store should stay 480.
    // Since slaValueBinding reads from stored minutes, no action needed.
}
```

Actually, the binding already reads from stored minutes and converts for display, so switching units will automatically show the correct converted value. No `.onChange` is needed.

Initialize `slaUnit` on appear based on stored value:

```swift
.onAppear {
    let minutes = manager.filterSettings.reviewSLAMinutes
    slaUnit = (minutes >= 60 && minutes % 60 == 0) ? .hours : .minutes
}
```

### Success Criteria:

#### Automated Verification:
- [x] Project compiles: `swift build`
- [x] All existing tests pass: `swift test`

---

## Phase 5: Tests

### Overview
Add tests for SLA computation, FilterSettings backward compatibility, and update the test fixture.

### Changes Required:

#### 1. Update PullRequest.fixture()
**File**: `Tests/FilterSettingsTests.swift`
**Changes**: Add `publishedAt` parameter to the fixture helper.

```swift
static func fixture(
    // ... existing parameters ...
    viewerHasApproved: Bool = false,
    publishedAt: Date? = nil
) -> PullRequest {
    PullRequest(
        // ... existing fields ...
        viewerHasApproved: viewerHasApproved,
        publishedAt: publishedAt
    )
}
```

Note: The `publishedAt` parameter needs to be added in the correct position to match the `PullRequest` struct's stored property order (after `lastFetched`). Since `PullRequest` uses default memberwise initialization order, the fixture must match:

```swift
static func fixture(
    // ... existing parameters ...
    lastFetched: Date = Date(),
    publishedAt: Date? = nil,
    reviewDecision: ReviewDecision = .reviewRequired,
    // ... rest unchanged ...
```

#### 2. SLA Computation Tests
**File**: `Tests/PullRequestTests.swift`
**Changes**: Add a new test suite for SLA computation.

```swift
@Suite struct SLATests {
    private let now = Date()
    private let twoHoursAgo = Date().addingTimeInterval(-2 * 3600)
    private let tenHoursAgo = Date().addingTimeInterval(-10 * 3600)

    @Test func slaNotExceededWhenWithinDeadline() {
        let pr = PullRequest.fixture(publishedAt: twoHoursAgo)
        #expect(!pr.isSLAExceeded(minutes: 480, now: now))
    }

    @Test func slaExceededWhenPastDeadline() {
        let pr = PullRequest.fixture(publishedAt: tenHoursAgo)
        #expect(pr.isSLAExceeded(minutes: 480, now: now))
    }

    @Test func slaNotExceededWhenPublishedAtIsNil() {
        let pr = PullRequest.fixture(publishedAt: nil)
        #expect(!pr.isSLAExceeded(minutes: 480, now: now))
    }

    @Test func slaExceededAtExactBoundary() {
        let exactlyAtDeadline = now.addingTimeInterval(-480 * 60)
        let pr = PullRequest.fixture(publishedAt: exactlyAtDeadline)
        #expect(!pr.isSLAExceeded(minutes: 480, now: now))
    }

    @Test func slaExceededJustPastBoundary() {
        let justPast = now.addingTimeInterval(-480 * 60 - 1)
        let pr = PullRequest.fixture(publishedAt: justPast)
        #expect(pr.isSLAExceeded(minutes: 480, now: now))
    }

    @Test func slaWithSmallMinuteThreshold() {
        let fiveMinutesAgo = now.addingTimeInterval(-5 * 60)
        let pr = PullRequest.fixture(publishedAt: fiveMinutesAgo)
        #expect(!pr.isSLAExceeded(minutes: 10, now: now))
        #expect(pr.isSLAExceeded(minutes: 3, now: now))
    }
}
```

#### 3. FilterSettings Backward Compatibility Tests
**File**: `Tests/FilterSettingsTests.swift`
**Changes**: Add tests verifying that old JSON (without SLA fields) decodes correctly with defaults.

```swift
@Test func defaultReviewSLAEnabledIsFalse() {
    #expect(!FilterSettings().reviewSLAEnabled)
}

@Test func defaultReviewSLAMinutesIs480() {
    #expect(FilterSettings().reviewSLAMinutes == 480)
}

@Test func decodingOldJSONWithoutSLAFieldsUsesDefaults() throws {
    let json = """
    {"hideDrafts": true, "hideApprovedByMe": false, "hideNotReady": false,
     "requiredCheckNames": [], "ignoredCheckNames": [], "ignoredRepositories": []}
    """
    let data = json.data(using: .utf8)!
    let settings = try JSONDecoder().decode(FilterSettings.self, from: data)
    #expect(!settings.reviewSLAEnabled)
    #expect(settings.reviewSLAMinutes == 480)
}

@Test func decodingJSONWithSLAFieldsPreservesValues() throws {
    let json = """
    {"hideDrafts": true, "hideApprovedByMe": false, "hideNotReady": false,
     "requiredCheckNames": [], "ignoredCheckNames": [], "ignoredRepositories": [],
     "reviewSLAEnabled": true, "reviewSLAMinutes": 240}
    """
    let data = json.data(using: .utf8)!
    let settings = try JSONDecoder().decode(FilterSettings.self, from: data)
    #expect(settings.reviewSLAEnabled)
    #expect(settings.reviewSLAMinutes == 240)
}
```

### Success Criteria:

#### Automated Verification:
- [x] All tests pass: `swift test`
- [x] No compiler warnings

---

## Phase 6: Relaunch + Manual Verification

### Overview
Kill any running instances of the app, rebuild, and relaunch for live manual verification of all features introduced in Phases 1–5.

### Steps:

#### 1. Kill and Relaunch
```bash
pkill -f "PR Status Watcher" 2>/dev/null || true
pkill -f "PRStatusWatcher" 2>/dev/null || true
swift run &
```

#### 2. Manual Verification Checklist

**Data Pipeline (Phase 1):**
- [ ] PRs load correctly on both tabs (no regressions from adding `publishedAt`)

**Reviews Tab — SLA Section (Phase 3):**
- [ ] Open Settings, enable SLA with a short threshold (e.g. 1 minute) for testing
- [ ] Switch to Reviews tab — verify "SLA Exceeded" section appears at the top with red/warning styling
- [ ] Verify PRs in "SLA Exceeded" are NOT duplicated in "Ready for Review" or "Not Ready"
- [ ] Verify PRs with `publishedAt` = nil (drafts) never appear in SLA Exceeded
- [ ] Disable SLA toggle — verify Reviews tab reverts to normal Ready / Not Ready layout

**Settings UI (Phase 4):**
- [ ] Open Settings → verify "Review SLA" section appears with toggle, description, and disabled state
- [ ] Toggle SLA on → verify deadline field and unit picker appear
- [ ] Set value to 4 hours → close and reopen Settings → verify value persisted
- [ ] Switch unit from Hours to Minutes → verify display value updates correctly (4 hours → 240 minutes)
- [ ] Toggle SLA off → verify deadline fields disappear
- [ ] Verify toggling SLA on/off immediately updates the Reviews tab sections

**Persistence:**
- [ ] Quit the app entirely and relaunch → verify SLA enabled state and threshold persisted

**Implementation Note**: After completing all manual verification, confirm everything is working as expected before considering the feature done.

## Testing Strategy

### Unit Tests (Phase 5):
- `isSLAExceeded(minutes:now:)` — within deadline, past deadline, nil publishedAt, boundary cases
- `FilterSettings` — default values, backward-compatible decoding, round-trip encoding

### Manual / Integration Tests (Phase 6):
- Kill any running instances, rebuild, and relaunch for live testing
- Full manual verification checklist covering data pipeline, section UI, settings, and persistence

## Performance Considerations

- `publishedAt` adds one scalar field to the GraphQL query — negligible performance impact
- SLA partitioning is O(n) over filtered PRs — trivial for typical PR counts (< 100)
- No new network calls, no new polling — SLA computation piggybacks on existing refresh cycle

## References

- Research: `thoughts/shared/research/2026-02-18-review-sla-configuration.md`
- Readiness sections pattern: `Sources/App/ContentView.swift:154-209`
- FilterSettings pattern: `Sources/Models/Models.swift:217-264`
- Node conversion pattern: `Sources/GitHub/GitHubService+NodeConversion.swift:7-65`
