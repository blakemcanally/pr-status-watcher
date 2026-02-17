# Ignored CI Checks — Implementation Plan

## Overview

Add an "Ignored CI Checks" feature to the Reviews tab — the contrapositive of the existing "Required CI Checks" allowlist. Users specify CI checks to **completely disregard** (flaky checks, Graphite stack management, etc.). Ignored checks are stripped from the CI badge, failed checks list, status color, and readiness evaluation on the Reviews tab. The "My PRs" tab remains unaffected — it always shows the full, unfiltered CI status.

## Current State Analysis

The existing codebase has the full "Required CI Checks + Readiness Sections" feature implemented:

- `FilterSettings` has `hideDrafts: Bool` and `requiredCheckNames: [String]` (`Sources/Models/Models.swift:155-181`)
- `PullRequest` stores `ciStatus`, `checksTotal`, `checksPassed`, `checksFailed`, `failedChecks: [CheckInfo]`, and `checkResults: [CheckResult]` (`Sources/Models/Models.swift:6-29`)
- `PullRequest.isReady(requiredChecks:)` evaluates readiness (`Sources/Models/Models.swift:134-149`)
- `ContentView` partitions Reviews tab into "Ready for Review" / "Not Ready" sections (`Sources/App/ContentView.swift:32-48`)
- `PRRowView` displays CI badge, status dot, and expandable failed checks list (`Sources/App/PRRowView.swift`)
- `SettingsView` has a "Review Readiness" section with hide-drafts toggle, required checks list, and autocomplete (`Sources/App/SettingsView.swift:84-157`)
- `PRManager.availableCheckNames` aggregates all unique check names from review PRs for autocomplete (`Sources/App/PRManager.swift:49-52`)

**Key architecture pattern:** Settings don't leak into the service layer. `GitHubService` fetches raw data; `PullRequest` stores it truthfully; user preferences are consumed at the view/readiness layer. The ignored-checks feature follows this same pattern.

### Key code references:
- `Sources/Models/Models.swift:6-29` — `PullRequest` struct with all CI fields
- `Sources/Models/Models.swift:55-68` — `statusColor` computed property (uses `ciStatus`)
- `Sources/Models/Models.swift:79-93` — `CIStatus` enum with `color` property
- `Sources/Models/Models.swift:112-129` — `CheckInfo`, `CheckStatus`, `CheckResult` types
- `Sources/Models/Models.swift:134-149` — `isReady(requiredChecks:)` predicate
- `Sources/Models/Models.swift:154-181` — `FilterSettings` with `requiredCheckNames`
- `Sources/App/PRRowView.swift:13-15` — Status dot using `statusColor`
- `Sources/App/PRRowView.swift:43-44` — Review badge visibility using `ciStatus`
- `Sources/App/PRRowView.swift:56-83` — Expandable failed checks list
- `Sources/App/PRRowView.swift:109-127` — `ciIcon` and `ciText` using CI fields
- `Sources/App/PRRowView.swift:169-211` — CI badge with expand toggle
- `Sources/App/ContentView.swift:34-48` — Readiness partitioning
- `Sources/App/ContentView.swift:189-236` — Readiness section header with collapsed status dots
- `Sources/App/SettingsView.swift:84-157` — Review Readiness settings section
- `Sources/App/PRManager.swift:49-52` — `availableCheckNames` for autocomplete
- `Sources/App/PRManager.swift:54-56` — `filterSettings` with `didSet` persistence
- `Sources/App/Strings.swift:141-153` — Readiness strings

## Desired End State

After implementation:

1. `FilterSettings` has a new `ignoredCheckNames: [String]` property, persisted via UserDefaults JSON
2. `PullRequest` has "effective" computed methods that exclude ignored checks: `effectiveCIStatus`, `effectiveFailedChecks`, `effectiveCheckCounts`, `effectiveStatusColor`
3. `isReady()` accepts an `ignoredChecks` parameter and filters them out before evaluating readiness
4. On the **Reviews tab**, `PRRowView` uses effective values — ignored checks are invisible in the CI badge, status dot, failed checks list, and readiness section placement
5. On the **My PRs tab**, `PRRowView` uses raw values — full, unfiltered CI status (unchanged behavior)
6. Settings has a new "Ignored CI Checks" section, visually distinct from "Required CI Checks", with its own description, check list, and autocomplete
7. Mutual exclusion: the UI prevents a check from being in both `requiredCheckNames` and `ignoredCheckNames`
8. Raw data is preserved on the model — `ciStatus`, `failedChecks`, `checkResults`, and counts are never mutated

**Verification example:**

A PR has 10 checks: 9 passing, 1 flaky check ("graphite/stack-check") failing. With "graphite/stack-check" in the ignore list:
- Reviews tab: CI badge shows "9/9 passed", status dot is green, PR lands in "Ready for Review"
- My PRs tab: CI badge shows "1 failed", status dot is red (unchanged)
- Settings: "graphite/stack-check" appears in the Ignored CI Checks list with a remove button

## What We're NOT Doing

- **Option 3 (lossy post-processing)** — We preserve raw data on the model. We do NOT mutate `checkResults`, `failedChecks`, or `ciStatus` after fetch.
- **Ignored checks on the My PRs tab** — My PRs always shows full, unfiltered CI status. The ignore list only affects the Reviews tab.
- **"Show but don't block" mode (Philosophy B)** — Ignored checks are fully hidden on the Reviews tab, not just demoted. The user explicitly said "pretend these don't exist."
- **Ignore list applies first (Semantic A)** — We chose mutual exclusion (Semantic C) instead. The UI prevents a check from being in both lists, eliminating ambiguity entirely.
- **Refreshing on settings change** — Since Option 2 uses computed properties, SwiftUI's reactive binding automatically re-evaluates views when `filterSettings` changes. No explicit `refreshAll()` call is needed.

## Implementation Approach

Four phases, each independently testable:

1. **Phase 1:** Data model — `ignoredCheckNames` on `FilterSettings`, effective computed methods on `PullRequest`, updated `isReady()` signature
2. **Phase 2:** View integration — Update `ContentView` readiness to pass ignored checks, update `PRRowView` to use effective values for review PRs
3. **Phase 3:** Settings UI — "Ignored CI Checks" section with mutual exclusion validation, updated autocomplete, new strings
4. **Phase 4:** Tests — Codable tests, effective method tests, readiness tests with ignored checks

---

## Phase 1: Data Model & Effective Methods

### Overview

Add `ignoredCheckNames` to `FilterSettings`, add effective computed methods on `PullRequest` that exclude ignored checks, and update `isReady()` to accept an `ignoredChecks` parameter.

### Changes Required

#### 1. Add `ignoredCheckNames` to `FilterSettings`

**File:** `Sources/Models/Models.swift`

Add the new property to `FilterSettings`:

```swift
struct FilterSettings: Codable, Equatable {
    var hideDrafts: Bool
    var requiredCheckNames: [String]
    var ignoredCheckNames: [String]   // NEW
}
```

Update `init`:

```swift
init(
    hideDrafts: Bool = true,
    requiredCheckNames: [String] = [],
    ignoredCheckNames: [String] = []    // NEW
) {
    self.hideDrafts = hideDrafts
    self.requiredCheckNames = requiredCheckNames
    self.ignoredCheckNames = ignoredCheckNames  // NEW
}
```

Update the custom `init(from:)` decoder (add after the `requiredCheckNames` line):

```swift
ignoredCheckNames = try container.decodeIfPresent([String].self, forKey: .ignoredCheckNames) ?? []
```

This follows the exact same backward-compatible `decodeIfPresent` pattern used when `requiredCheckNames` was added. Previously-saved JSON without `ignoredCheckNames` decodes cleanly with a `[]` default.

#### 2. Add effective computed methods on `PullRequest`

**File:** `Sources/Models/Models.swift`

Add these methods after the existing `isReady` method:

```swift
// MARK: - Effective Values (Ignored Checks Filtering)

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

/// Status color recomputed with effective CI status (for ignored checks filtering).
func effectiveStatusColor(ignoredChecks: [String]) -> Color {
    guard !ignoredChecks.isEmpty else { return statusColor }
    switch state {
    case .merged: return .purple
    case .closed: return .gray
    case .draft: return .gray
    case .open:
        if isInMergeQueue { return .purple }
        switch effectiveCIStatus(ignoredChecks: ignoredChecks) {
        case .success: return .green
        case .failure: return .red
        case .pending: return .orange
        case .unknown: return .gray
        }
    }
}
```

**Design note:** Each effective method takes `ignoredChecks: [String]` and short-circuits when the list is empty (returning the raw value). This means callers on the My PRs tab can pass `[]` and get zero overhead — the methods become identity functions.

#### 3. Update `isReady()` to accept `ignoredChecks`

**File:** `Sources/Models/Models.swift`

Update the existing `isReady` method signature and implementation:

```swift
/// Whether this PR is ready for review given the user's check configuration.
func isReady(requiredChecks: [String], ignoredChecks: [String] = []) -> Bool {
    guard state != .draft else { return false }
    guard mergeable != .conflicting else { return false }

    if requiredChecks.isEmpty {
        // Default mode: use effective CI status (excluding ignored checks)
        let effectiveStatus = effectiveCIStatus(ignoredChecks: ignoredChecks)
        return effectiveStatus != .failure && effectiveStatus != .pending
    }

    // Required-checks mode: evaluate only required checks (minus any ignored).
    // With mutual exclusion enforced by the UI, a check shouldn't be in both
    // lists — but we handle it defensively by skipping ignored checks.
    let ignored = Set(ignoredChecks)
    for name in requiredChecks {
        if ignored.contains(name) { continue }
        guard let check = checkResults.first(where: { $0.name == name }) else {
            continue
        }
        if check.status != .passed { return false }
    }
    return true
}
```

**Note:** The default `ignoredChecks: [String] = []` ensures all existing call sites compile without changes until we thread the parameter through in Phase 2.

### Success Criteria

#### Automated Verification:
- [x] Build succeeds: `swift build`
- [x] All existing tests pass: `swift test`

#### Manual Verification:
- [x] N/A — no UI changes in this phase

**Implementation Note:** After completing this phase and all automated verification passes, proceed to Phase 2.

---

## Phase 2: View Integration (ContentView + PRRowView)

### Overview

Update `ContentView` to pass the ignored checks list through to readiness evaluation and `PRRowView`. Update `PRRowView` to use effective values (effective CI status, effective failed checks, effective counts, effective status color) when rendering review PRs.

### Changes Required

#### 1. Update `PRRowView` to accept `ignoredCheckNames`

**File:** `Sources/App/PRRowView.swift`

Add a new property with an empty default:

```swift
struct PRRowView: View {
    let pullRequest: PullRequest
    var ignoredCheckNames: [String] = []    // NEW
    @State private var showFailures = false
```

Add computed properties for the effective display values:

```swift
// MARK: - Effective Display Values (filtered for ignored checks)

private var displayCIStatus: PullRequest.CIStatus {
    pullRequest.effectiveCIStatus(ignoredChecks: ignoredCheckNames)
}

private var displayFailedChecks: [PullRequest.CheckInfo] {
    pullRequest.effectiveFailedChecks(ignoredChecks: ignoredCheckNames)
}

private var displayStatusColor: Color {
    pullRequest.effectiveStatusColor(ignoredChecks: ignoredCheckNames)
}

private var displayCheckCounts: (total: Int, passed: Int, failed: Int) {
    pullRequest.effectiveCheckCounts(ignoredChecks: ignoredCheckNames)
}
```

Then update every CI data reference in the view body to use these display values:

| Current reference | Replace with | Location |
|---|---|---|
| `pullRequest.statusColor` | `displayStatusColor` | Status dot (line 14) |
| `pullRequest.ciStatus == .success \|\| .unknown` | `displayCIStatus == .success \|\| .unknown` | Review badge visibility (lines 43-44) |
| `pullRequest.failedChecks.isEmpty` | `displayFailedChecks.isEmpty` | Expand toggle condition (line 56) |
| `pullRequest.failedChecks` | `displayFailedChecks` | ForEach failed checks list (line 58) |
| `pullRequest.checksTotal > 0` | `displayCheckCounts.total > 0` | CI badge visibility (line 169) |
| `pullRequest.failedChecks.isEmpty` | `displayFailedChecks.isEmpty` | CI badge button action guard (line 170-172) |
| `pullRequest.ciStatus.color` | `displayCIStatus.color` | CI badge background color (line 180) |
| `pullRequest.ciStatus` | `displayCIStatus` | `ciIcon` switch (lines 110-115) |
| `pullRequest.checksFailed` | `displayCheckCounts.failed` | `ciText` failed count (line 119) |
| `pullRequest.checksTotal` | `displayCheckCounts.total` | `ciText` total (lines 122, 124, 126) |
| `pullRequest.checksPassed` | `displayCheckCounts.passed` | `ciText` passed (lines 124, 126) |

**Detailed changes to `ciIcon`:**

```swift
private var ciIcon: String {
    switch displayCIStatus {
    case .success: return "checkmark.circle.fill"
    case .failure: return "xmark.circle.fill"
    case .pending: return "clock.fill"
    case .unknown: return "questionmark.circle"
    }
}
```

**Detailed changes to `ciText`:**

```swift
private var ciText: String {
    let counts = displayCheckCounts
    if counts.failed > 0 {
        return Strings.CI.failedCount(counts.failed)
    }
    let pending = counts.total - counts.passed - counts.failed
    if pending > 0 {
        return Strings.CI.checksProgress(passed: counts.passed, total: counts.total)
    }
    return Strings.CI.checksPassed(passed: counts.passed, total: counts.total)
}
```

**Why a parameter instead of `@EnvironmentObject`:** A parameter makes the data flow explicit, keeps `PRRowView` independently testable, and naturally handles the My PRs vs Reviews distinction — the My PRs tab passes `[]`, the Reviews tab passes the actual ignore list.

#### 2. Thread `ignoredCheckNames` through `ContentView`

**File:** `Sources/App/ContentView.swift`

**Step 2a:** Update readiness partitioning to pass `ignoredChecks`:

```swift
private var readyPRs: [PullRequest] {
    filteredPRs.filter {
        $0.isReady(
            requiredChecks: manager.filterSettings.requiredCheckNames,
            ignoredChecks: manager.filterSettings.ignoredCheckNames
        )
    }
}

private var notReadyPRs: [PullRequest] {
    filteredPRs.filter {
        !$0.isReady(
            requiredChecks: manager.filterSettings.requiredCheckNames,
            ignoredChecks: manager.filterSettings.ignoredCheckNames
        )
    }
}
```

**Step 2b:** Add a convenience property for the ignore list:

```swift
/// Ignored check names from settings, used for effective value filtering on the Reviews tab.
private var reviewIgnoredChecks: [String] {
    selectedTab == .reviews ? manager.filterSettings.ignoredCheckNames : []
}
```

**Step 2c:** Update `repoSection` to accept and forward `ignoredCheckNames`:

```swift
private func repoSection(repo: String, prs: [PullRequest], ignoredCheckNames: [String] = []) -> some View {
    let isCollapsed = manager.collapsedRepos.contains(repo)

    return VStack(spacing: 0) {
        repoHeader(repo: repo, prs: prs, isCollapsed: isCollapsed)

        if !isCollapsed {
            ForEach(prs) { pullRequest in
                PRRowView(pullRequest: pullRequest, ignoredCheckNames: ignoredCheckNames)
                    .contextMenu {
                        // ... existing context menu (unchanged) ...
                    }
                if pullRequest.id != prs.last?.id {
                    Divider().padding(.leading, 36)
                }
            }
        }

        Divider()
    }
}
```

**Step 2d:** Update `readinessSection` to pass `ignoredCheckNames` to `repoSection`:

```swift
private func readinessSection(
    key: String,
    title: String,
    icon: String,
    color: Color,
    groups: [(repo: String, prs: [PullRequest])]
) -> some View {
    let isCollapsed = manager.collapsedReadinessSections.contains(key)
    let ignoredChecks = manager.filterSettings.ignoredCheckNames

    return VStack(spacing: 0) {
        readinessSectionHeader(
            key: key,
            title: title,
            icon: icon,
            color: color,
            isCollapsed: isCollapsed,
            prs: groups.flatMap(\.prs),
            ignoredCheckNames: ignoredChecks
        )

        if !isCollapsed {
            ForEach(groups, id: \.repo) { group in
                repoSection(repo: group.repo, prs: group.prs, ignoredCheckNames: ignoredChecks)
            }
        }
    }
}
```

**Step 2e:** Update `readinessSectionHeader` to use effective status color for collapsed dots:

```swift
private func readinessSectionHeader(
    key: String,
    title: String,
    icon: String,
    color: Color,
    isCollapsed: Bool,
    prs: [PullRequest],
    ignoredCheckNames: [String] = []    // NEW
) -> some View {
    Button {
        withAnimation(.easeInOut(duration: 0.2)) {
            manager.toggleReadinessSectionCollapsed(key)
        }
    } label: {
        HStack(spacing: 6) {
            // ... existing chevron, icon, title, Spacer (unchanged) ...

            if isCollapsed {
                HStack(spacing: 3) {
                    ForEach(prs) { pullRequest in
                        Circle()
                            .fill(pullRequest.effectiveStatusColor(ignoredChecks: ignoredCheckNames))
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
        // ... existing padding, contentShape (unchanged) ...
    }
    // ... existing buttonStyle, background, accessibility (unchanged) ...
}
```

**Step 2f:** The My PRs tab path is unchanged — `repoSection` is called without the `ignoredCheckNames` parameter, so it defaults to `[]`, and `PRRowView` receives `[]`, causing all effective methods to return raw values.

### Success Criteria

#### Automated Verification:
- [x] Build succeeds: `swift build`
- [x] All existing tests pass: `swift test`

#### Manual Verification:
- [ ] With no ignored checks configured, behavior is identical to current (no regression)
- [ ] My PRs tab is completely unaffected — always shows full CI status
- [ ] Reviews tab PR rows use effective values (verified in Phase 3 after settings UI is available)

**Implementation Note:** After completing this phase and all automated verification passes, proceed to Phase 3.

---

## Phase 3: Settings UI & Strings

### Overview

Add an "Ignored CI Checks" section to `SettingsView`, visually distinct from the "Required CI Checks" section. Add mutual exclusion validation that prevents a check from being in both lists. Add a subsection label for the existing required checks. Update autocomplete to exclude names already in the other list.

### Changes Required

#### 1. Add ignored checks strings

**File:** `Sources/App/Strings.swift`

Add to the existing `Readiness` enum:

```swift
enum Readiness {
    // ... existing strings ...
    static let ignoredChecksLabel = "Ignored CI Checks"
    static let ignoredChecksDescription = "These CI checks are completely hidden — they won't affect readiness or appear in the CI badge."
    static let addIgnoredCheckPlaceholder = "Add check to ignore..."
    static let mutualExclusionWarning = "This check is already in the other list. Remove it there first."
}
```

#### 2. Restructure the Settings UI

**File:** `Sources/App/SettingsView.swift`

Add a new `@State` for the ignored check text field:

```swift
@State private var newIgnoredCheckName = ""
```

Restructure the "Review Readiness" section to have clearly labeled subsections. The current single section becomes three visually distinct sections:

**Section 1: Review Readiness (general)**

Keep the existing "Review Readiness" header and hide-drafts toggle. Remove the required checks UI from this section (it moves to its own section below):

```swift
// Review Readiness Section (general)
VStack(alignment: .leading, spacing: 8) {
    Text(Strings.Readiness.settingsTitle)
        .font(.headline)

    Toggle("Hide draft PRs", isOn: filterBinding(\.hideDrafts))
}

Divider()
```

**Section 2: Required CI Checks**

Move the existing required checks UI into its own section with its own label and description:

```swift
// Required CI Checks Section
VStack(alignment: .leading, spacing: 8) {
    Text(Strings.Readiness.requiredChecksLabel)
        .font(.headline)

    Text(Strings.Readiness.settingsDescription)
        .font(.caption)
        .foregroundColor(.secondary)

    // Current required checks list (existing code, unchanged)
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
                            .foregroundStyle(.secondary)
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

    // Add new check name (existing code, unchanged)
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
        .accessibilityLabel("Add required check name")
    }

    // Autocomplete suggestions (updated to exclude ignored checks)
    let requiredSuggestions = requiredCheckNameSuggestions
    if !requiredSuggestions.isEmpty && !newCheckName.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(requiredSuggestions, id: \.self) { suggestion in
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

Divider()
```

**Section 3: Ignored CI Checks (NEW)**

Add a new section that mirrors the required checks pattern:

```swift
// Ignored CI Checks Section (NEW)
VStack(alignment: .leading, spacing: 8) {
    Text(Strings.Readiness.ignoredChecksLabel)
        .font(.headline)

    Text(Strings.Readiness.ignoredChecksDescription)
        .font(.caption)
        .foregroundColor(.secondary)

    // Current ignored checks list
    if !manager.filterSettings.ignoredCheckNames.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(manager.filterSettings.ignoredCheckNames, id: \.self) { name in
                HStack {
                    Text(name)
                        .font(.system(.caption, design: .monospaced))
                    Spacer()
                    Button {
                        manager.filterSettings.ignoredCheckNames.removeAll { $0 == name }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

    // Add new ignored check name
    HStack(spacing: 6) {
        TextField(Strings.Readiness.addIgnoredCheckPlaceholder, text: $newIgnoredCheckName)
            .textFieldStyle(.roundedBorder)
            .font(.system(.caption, design: .monospaced))
            .onSubmit { addIgnoredCheck() }

        Button {
            addIgnoredCheck()
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.body)
        }
        .buttonStyle(.borderless)
        .disabled(newIgnoredCheckName.trimmingCharacters(in: .whitespaces).isEmpty)
        .accessibilityLabel("Add ignored check name")
    }

    // Autocomplete suggestions (excluding required checks)
    let ignoredSuggestions = ignoredCheckNameSuggestions
    if !ignoredSuggestions.isEmpty && !newIgnoredCheckName.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(ignoredSuggestions, id: \.self) { suggestion in
                    Button(suggestion) {
                        newIgnoredCheckName = suggestion
                        addIgnoredCheck()
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
}
```

#### 3. Add helper methods for ignored checks

**File:** `Sources/App/SettingsView.swift`

Add alongside the existing `addRequiredCheck()`:

```swift
private func addIgnoredCheck() {
    let trimmed = newIgnoredCheckName.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty,
          !manager.filterSettings.ignoredCheckNames.contains(trimmed),
          !manager.filterSettings.requiredCheckNames.contains(trimmed) else { return }
    manager.filterSettings.ignoredCheckNames.append(trimmed)
    newIgnoredCheckName = ""
}
```

#### 4. Add mutual exclusion validation to `addRequiredCheck()`

**File:** `Sources/App/SettingsView.swift`

Update the existing `addRequiredCheck()` to also check the ignored list:

```swift
private func addRequiredCheck() {
    let trimmed = newCheckName.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty,
          !manager.filterSettings.requiredCheckNames.contains(trimmed),
          !manager.filterSettings.ignoredCheckNames.contains(trimmed) else { return }
    manager.filterSettings.requiredCheckNames.append(trimmed)
    newCheckName = ""
}
```

The guard silently prevents the addition if the name exists in the other list. Since both the autocomplete and the add function filter these out, the user shouldn't normally encounter this — it's a defensive measure.

#### 5. Update autocomplete to respect mutual exclusion

**File:** `Sources/App/SettingsView.swift`

Rename the existing `checkNameSuggestions` and add the ignored variant:

```swift
/// Autocomplete for required checks: exclude names already required OR ignored.
private var requiredCheckNameSuggestions: [String] {
    let excluded = Set(manager.filterSettings.requiredCheckNames)
        .union(manager.filterSettings.ignoredCheckNames)
    let query = newCheckName.lowercased()
    return manager.availableCheckNames
        .filter { !excluded.contains($0) && $0.lowercased().contains(query) }
}

/// Autocomplete for ignored checks: exclude names already ignored OR required.
private var ignoredCheckNameSuggestions: [String] {
    let excluded = Set(manager.filterSettings.ignoredCheckNames)
        .union(manager.filterSettings.requiredCheckNames)
    let query = newIgnoredCheckName.lowercased()
    return manager.availableCheckNames
        .filter { !excluded.contains($0) && $0.lowercased().contains(query) }
}
```

### Success Criteria

#### Automated Verification:
- [x] Build succeeds: `swift build`
- [x] All existing tests pass: `swift test`

#### Manual Verification:
- [ ] Settings shows three distinct sections: "Review Readiness" (hide drafts), "Required CI Checks", and "Ignored CI Checks"
- [ ] Each check list section has its own headline, description, check list, and add field
- [ ] Adding an ignored check name via text field + enter/button works
- [ ] Duplicate ignored check names are prevented (silently rejected)
- [ ] Adding a check that's already in the required list is prevented (mutual exclusion)
- [ ] Adding a required check that's already in the ignored list is prevented (mutual exclusion)
- [ ] Removing an ignored check via X button works
- [ ] Autocomplete suggestions appear while typing in the ignored checks field
- [ ] Autocomplete excludes names already in both lists (required AND ignored)
- [ ] Clicking a suggestion adds it and clears the text field
- [ ] Added ignored check names persist across app restart
- [ ] With an ignored check configured, a PR on the Reviews tab with that check failing now shows as if the check doesn't exist (CI badge count reduced, failed check not in list, status color reflects effective status)
- [ ] Same PR on the My PRs tab still shows the full CI status including the ignored check
- [ ] With an ignored check configured, readiness section placement changes: a PR that was "Not Ready" because of the ignored check now moves to "Ready for Review"

**Implementation Note:** After completing this phase and all manual verification passes, proceed to Phase 4.

---

## Phase 4: Tests

### Overview

Add comprehensive tests for the new `ignoredCheckNames` on `FilterSettings`, the effective computed methods on `PullRequest`, and the updated `isReady()` behavior with ignored checks.

### Changes Required

#### 1. FilterSettings Codable tests

**File:** `Tests/FilterSettingsTests.swift`

Add to `FilterSettingsDefaultsTests`:

```swift
@Test func defaultIgnoredCheckNamesIsEmpty() {
    #expect(FilterSettings().ignoredCheckNames.isEmpty)
}
```

Add to `FilterSettingsCodableTests`:

```swift
@Test func codableRoundTripWithIgnoredCheckNames() throws {
    let original = FilterSettings(ignoredCheckNames: ["flaky-check", "graphite/stack"])
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(FilterSettings.self, from: data)
    #expect(decoded.ignoredCheckNames == ["flaky-check", "graphite/stack"])
}

@Test func decodingWithoutIgnoredCheckNamesDefaultsToEmpty() throws {
    let json = #"{"hideDrafts": true, "requiredCheckNames": ["build"]}"#.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(FilterSettings.self, from: json)
    #expect(decoded.ignoredCheckNames.isEmpty)
    #expect(decoded.requiredCheckNames == ["build"])
}

@Test func codableRoundTripWithBothCheckLists() throws {
    let original = FilterSettings(
        requiredCheckNames: ["build"],
        ignoredCheckNames: ["flaky-lint"]
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(FilterSettings.self, from: data)
    #expect(decoded.requiredCheckNames == ["build"])
    #expect(decoded.ignoredCheckNames == ["flaky-lint"])
}
```

Add to `FilterSettingsPersistenceTests`:

```swift
@Test func persistAndReloadIgnoredCheckNamesViaUserDefaults() throws {
    let original = FilterSettings(ignoredCheckNames: ["flaky-check"])
    let data = try JSONEncoder().encode(original)
    UserDefaults.standard.set(data, forKey: testKey)

    let loaded = try #require(UserDefaults.standard.data(forKey: testKey))
    let decoded = try JSONDecoder().decode(FilterSettings.self, from: loaded)
    #expect(decoded.ignoredCheckNames == ["flaky-check"])
}
```

#### 2. Effective methods tests

**File:** `Tests/PullRequestTests.swift`

Add a new test suite:

```swift
// MARK: - Effective Values Tests (Ignored Checks)

@Suite struct EffectiveValuesTests {
    private let checksFixture: [PullRequest.CheckResult] = [
        .init(name: "build", status: .passed, detailsUrl: nil),
        .init(name: "lint", status: .failed, detailsUrl: nil),
        .init(name: "graphite/stack", status: .failed, detailsUrl: nil),
        .init(name: "test", status: .pending, detailsUrl: nil),
    ]

    private let failedFixture: [PullRequest.CheckInfo] = [
        .init(name: "lint", detailsUrl: nil),
        .init(name: "graphite/stack", detailsUrl: nil),
    ]

    // effectiveCheckResults

    @Test func effectiveCheckResultsWithEmptyIgnoreListReturnsAll() {
        let pr = PullRequest.fixture(checkResults: checksFixture)
        #expect(pr.effectiveCheckResults(ignoredChecks: []).count == 4)
    }

    @Test func effectiveCheckResultsFiltersIgnoredChecks() {
        let pr = PullRequest.fixture(checkResults: checksFixture)
        let effective = pr.effectiveCheckResults(ignoredChecks: ["graphite/stack"])
        #expect(effective.count == 3)
        #expect(!effective.contains(where: { $0.name == "graphite/stack" }))
    }

    @Test func effectiveCheckResultsFiltersMultipleIgnoredChecks() {
        let pr = PullRequest.fixture(checkResults: checksFixture)
        let effective = pr.effectiveCheckResults(ignoredChecks: ["lint", "graphite/stack"])
        #expect(effective.count == 2)
        #expect(effective.map(\.name).sorted() == ["build", "test"])
    }

    // effectiveFailedChecks

    @Test func effectiveFailedChecksFiltersIgnoredChecks() {
        let pr = PullRequest.fixture(failedChecks: failedFixture)
        let effective = pr.effectiveFailedChecks(ignoredChecks: ["graphite/stack"])
        #expect(effective.count == 1)
        #expect(effective.first?.name == "lint")
    }

    @Test func effectiveFailedChecksWithEmptyIgnoreListReturnsAll() {
        let pr = PullRequest.fixture(failedChecks: failedFixture)
        #expect(pr.effectiveFailedChecks(ignoredChecks: []).count == 2)
    }

    // effectiveCIStatus

    @Test func effectiveCIStatusIgnoringFailingCheckBecomesSuccess() {
        let pr = PullRequest.fixture(
            ciStatus: .failure,
            checkResults: [
                .init(name: "build", status: .passed, detailsUrl: nil),
                .init(name: "flaky", status: .failed, detailsUrl: nil),
            ]
        )
        #expect(pr.effectiveCIStatus(ignoredChecks: ["flaky"]) == .success)
    }

    @Test func effectiveCIStatusIgnoringAllChecksReturnsUnknown() {
        let pr = PullRequest.fixture(
            ciStatus: .failure,
            checkResults: [
                .init(name: "only-check", status: .failed, detailsUrl: nil),
            ]
        )
        #expect(pr.effectiveCIStatus(ignoredChecks: ["only-check"]) == .unknown)
    }

    @Test func effectiveCIStatusWithPendingAfterFilteringReturnsPending() {
        let pr = PullRequest.fixture(
            ciStatus: .failure,
            checkResults: [
                .init(name: "build", status: .pending, detailsUrl: nil),
                .init(name: "flaky", status: .failed, detailsUrl: nil),
            ]
        )
        #expect(pr.effectiveCIStatus(ignoredChecks: ["flaky"]) == .pending)
    }

    @Test func effectiveCIStatusWithEmptyIgnoreListReturnsRawStatus() {
        let pr = PullRequest.fixture(ciStatus: .failure)
        #expect(pr.effectiveCIStatus(ignoredChecks: []) == .failure)
    }

    // effectiveCheckCounts

    @Test func effectiveCheckCountsExcludeIgnoredChecks() {
        let pr = PullRequest.fixture(checkResults: checksFixture)
        let counts = pr.effectiveCheckCounts(ignoredChecks: ["graphite/stack"])
        #expect(counts.total == 3)
        #expect(counts.passed == 1)
        #expect(counts.failed == 1)
    }

    // effectiveStatusColor

    @Test func effectiveStatusColorReflectsEffectiveCIStatus() {
        let pr = PullRequest.fixture(
            state: .open, ciStatus: .failure,
            checkResults: [
                .init(name: "build", status: .passed, detailsUrl: nil),
                .init(name: "flaky", status: .failed, detailsUrl: nil),
            ]
        )
        #expect(pr.statusColor == .red)
        #expect(pr.effectiveStatusColor(ignoredChecks: ["flaky"]) == .green)
    }

    @Test func effectiveStatusColorForDraftIsAlwaysGray() {
        let pr = PullRequest.fixture(state: .draft, ciStatus: .failure)
        #expect(pr.effectiveStatusColor(ignoredChecks: ["anything"]) == .gray)
    }
}
```

#### 3. Readiness tests with ignored checks

**File:** `Tests/PullRequestTests.swift`

Add to the existing `ReadinessTests` suite:

```swift
// Ignored checks mode (default — no required checks)

@Test func ignoredFailingCheckMakesPRReadyInDefaultMode() {
    let pr = PullRequest.fixture(
        state: .open, ciStatus: .failure,
        checkResults: [
            .init(name: "build", status: .passed, detailsUrl: nil),
            .init(name: "flaky", status: .failed, detailsUrl: nil),
        ]
    )
    #expect(!pr.isReady(requiredChecks: []))
    #expect(pr.isReady(requiredChecks: [], ignoredChecks: ["flaky"]))
}

@Test func ignoredPendingCheckMakesPRReadyInDefaultMode() {
    let pr = PullRequest.fixture(
        state: .open, ciStatus: .pending,
        checkResults: [
            .init(name: "build", status: .passed, detailsUrl: nil),
            .init(name: "slow-check", status: .pending, detailsUrl: nil),
        ]
    )
    #expect(!pr.isReady(requiredChecks: []))
    #expect(pr.isReady(requiredChecks: [], ignoredChecks: ["slow-check"]))
}

@Test func ignoringAllChecksReturnsReadyInDefaultMode() {
    let pr = PullRequest.fixture(
        state: .open, ciStatus: .failure,
        checkResults: [
            .init(name: "only-check", status: .failed, detailsUrl: nil),
        ]
    )
    // All checks ignored → effectiveCIStatus == .unknown → ready
    #expect(pr.isReady(requiredChecks: [], ignoredChecks: ["only-check"]))
}

@Test func ignoredChecksDontOverrideDraftStatus() {
    let pr = PullRequest.fixture(
        state: .draft, ciStatus: .failure,
        checkResults: [
            .init(name: "flaky", status: .failed, detailsUrl: nil),
        ]
    )
    #expect(!pr.isReady(requiredChecks: [], ignoredChecks: ["flaky"]))
}

@Test func ignoredChecksDontOverrideConflicts() {
    let pr = PullRequest.fixture(
        state: .open, mergeable: .conflicting, ciStatus: .failure,
        checkResults: [
            .init(name: "flaky", status: .failed, detailsUrl: nil),
        ]
    )
    #expect(!pr.isReady(requiredChecks: [], ignoredChecks: ["flaky"]))
}

// Ignored checks + required checks mode

@Test func ignoredCheckWithRequiredChecksMode() {
    let pr = PullRequest.fixture(
        state: .open, ciStatus: .failure,
        checkResults: [
            .init(name: "build", status: .passed, detailsUrl: nil),
            .init(name: "flaky", status: .failed, detailsUrl: nil),
        ]
    )
    // "build" is required, "flaky" is ignored → ready
    #expect(pr.isReady(requiredChecks: ["build"], ignoredChecks: ["flaky"]))
}

@Test func ignoredCheckInBothListsDefensivelyIgnored() {
    // Mutual exclusion should prevent this, but test defensive behavior
    let pr = PullRequest.fixture(
        state: .open,
        checkResults: [
            .init(name: "build", status: .failed, detailsUrl: nil),
        ]
    )
    // "build" is in both lists — ignored wins (defensive)
    #expect(pr.isReady(requiredChecks: ["build"], ignoredChecks: ["build"]))
}

@Test func emptyIgnoredChecksDoesNotAffectReadiness() {
    let pr = PullRequest.fixture(state: .open, ciStatus: .failure)
    #expect(!pr.isReady(requiredChecks: [], ignoredChecks: []))
}
```

### Success Criteria

#### Automated Verification:
- [x] Build succeeds: `swift build`
- [x] All tests pass: `swift test`
- [x] All new tests specifically pass

#### Manual Verification:
- [x] N/A — tests only

**Implementation Note:** After completing this phase and all automated verification passes, the feature is complete.

---

## Testing Strategy

### Unit Tests (automated, per phase)

**Phase 1:**
- `FilterSettingsDefaultsTests` — default `ignoredCheckNames` is empty
- `FilterSettingsCodableTests` — round-trip with `ignoredCheckNames`, backward-compatible decoding, both lists together

**Phase 4:**
- `EffectiveValuesTests` — all effective methods with various ignore list configurations
- `ReadinessTests` (additions) — `isReady` with ignored checks in default mode, required-checks mode, edge cases (all ignored, draft, conflicts, both lists)
- `FilterSettingsPersistenceTests` — persist and reload with `ignoredCheckNames`

### Manual Testing Steps

1. Launch app with no saved settings → no ignored checks, behavior identical to current
2. Open Settings → three distinct sections visible: "Review Readiness", "Required CI Checks", "Ignored CI Checks"
3. Add a check name to the ignore list (e.g., "graphite/stack-check")
4. Verify Reviews tab: PR with that check failing now shows reduced CI count, green status if all other checks pass, and lands in "Ready for Review"
5. Verify My PRs tab: same PR still shows full CI status including the ignored check
6. Try adding the same check name to the required list → silently prevented (mutual exclusion)
7. Try adding a check from the required list to the ignore list → silently prevented
8. Remove the check from the ignore list → CI badge, status color, and readiness section revert immediately
9. Restart the app → ignored check list persists
10. Add multiple ignored checks → all are excluded from the Reviews tab display
11. Collapse a readiness section → status dots use effective colors (green instead of red if only ignored checks are failing)

---

## Performance Considerations

- Effective methods short-circuit when `ignoredChecks` is empty (the common case for users who don't use this feature), returning the raw value with zero allocation overhead.
- When the ignore list is non-empty, each effective method creates a `Set<String>` and filters. This is O(n) per method call where n is the number of checks. With typical check counts < 100, this is negligible.
- Multiple calls to effective methods in PRRowView each create their own `Set`. For the common case of 1-5 ignored checks, this is trivial. If performance becomes a concern (unlikely), the `Set` could be created once per render pass.
- SwiftUI's view diffing ensures PRRowView only re-renders when `filterSettings` actually changes, not on every frame.

---

## Migration Notes

- **No breaking changes to persisted data.** `FilterSettings` uses `decodeIfPresent` for `ignoredCheckNames`, so existing saved JSON without this key decodes cleanly with a `[]` default.
- **No new UserDefaults keys needed.** `ignoredCheckNames` is part of the `FilterSettings` JSON blob, which is already persisted under the existing `filterSettings` key.
- **No data layer changes.** `GitHubService`, `GitHubService+CheckStatusParsing`, and `GitHubService+NodeConversion` are untouched — all filtering happens at the model/view layer.

---

## Complete File Impact Summary

| File | Change | Phase |
|------|--------|-------|
| `Sources/Models/Models.swift` | Add `ignoredCheckNames` to `FilterSettings` | 1 |
| `Sources/Models/Models.swift` | Add `init` and `init(from decoder:)` updates | 1 |
| `Sources/Models/Models.swift` | Add 5 effective methods on `PullRequest` | 1 |
| `Sources/Models/Models.swift` | Update `isReady()` signature to accept `ignoredChecks` | 1 |
| `Sources/App/PRRowView.swift` | Add `ignoredCheckNames` property, display computed properties, use effective values | 2 |
| `Sources/App/ContentView.swift` | Pass `ignoredChecks` to readiness partitioning | 2 |
| `Sources/App/ContentView.swift` | Thread `ignoredCheckNames` through `repoSection` and `readinessSection` | 2 |
| `Sources/App/ContentView.swift` | Use `effectiveStatusColor` in collapsed readiness dots | 2 |
| `Sources/App/SettingsView.swift` | Add `@State newIgnoredCheckName` | 3 |
| `Sources/App/SettingsView.swift` | Restructure into 3 distinct sections | 3 |
| `Sources/App/SettingsView.swift` | Add "Ignored CI Checks" section (list, add field, autocomplete) | 3 |
| `Sources/App/SettingsView.swift` | Add mutual exclusion guards to `addRequiredCheck()` and `addIgnoredCheck()` | 3 |
| `Sources/App/SettingsView.swift` | Update autocomplete to exclude names from the other list | 3 |
| `Sources/App/Strings.swift` | Add ignored checks strings | 3 |
| `Tests/FilterSettingsTests.swift` | Codable + persistence tests for `ignoredCheckNames` | 4 |
| `Tests/PullRequestTests.swift` | Effective methods tests | 4 |
| `Tests/PullRequestTests.swift` | Readiness tests with ignored checks | 4 |

**Files NOT changed:**
- `Sources/GitHub/GitHubService.swift` — data fetching unchanged
- `Sources/GitHub/GitHubService+CheckStatusParsing.swift` — parsing unchanged
- `Sources/GitHub/GitHubService+NodeConversion.swift` — node conversion unchanged
- `Sources/App/PRManager.swift` — no changes needed (filterSettings `didSet` already saves; `availableCheckNames` already aggregates all check names)
- `Sources/Settings/SettingsStore.swift` — no changes (FilterSettings JSON covers it)
- `Sources/Settings/SettingsStoreProtocol.swift` — no changes
- `Tests/Mocks/MockSettingsStore.swift` — no changes (FilterSettings struct is the same protocol)
- `Tests/PRManagerTests.swift` — no changes needed

---

## References

- Research doc: `thoughts/shared/research/2026-02-17-ignored-ci-checks-contrapositive.md`
- Readiness sections plan: `thoughts/shared/plans/2026-02-17-ready-not-ready-review-sections.md`
- Readiness sections research: `thoughts/shared/research/2026-02-17-ready-not-ready-review-sections.md`
