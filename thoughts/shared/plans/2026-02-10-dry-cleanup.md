# DRY Cleanup Implementation Plan

## Overview

Consolidate duplicated logic, remove dead code, and extract shared components across the PR Status Watcher codebase. All changes are behavior-preserving refactors.

## Current State Analysis

The codebase has accumulated dead code from earlier architectural iterations (manual PR add flow, per-PR fetching) and has several duplicated patterns across views. The recent `statusColor` consolidation onto the `PullRequest` model proved the pattern; this plan extends that approach to the remaining duplication.

### Key Discoveries:
- `PRReference`, `PullRequest.placeholder`, `fallbackURL`, `checkCLI()` are defined but never called
- `CIStatus` -> `Color` mapping lives privately in `PRRowView` but could diverge if used elsewhere
- `ContentView.statusDotColor` is a one-line passthrough to `pullRequest.statusColor`
- Sort priority is defined as a private function in `ContentView` with no reuse path
- `badgePill` helper exists but `stateBadge` and `ciBadge` duplicate its styling inline
- Auth status display (authenticated + unauthenticated) appears in both `ContentView.footer` and `SettingsView`

## What We're NOT Doing

- No behavioral changes — all refactors are strictly cosmetic/structural
- No new features or UI changes
- No changes to `GitHubService` GraphQL query or parsing logic (beyond removing `checkCLI`)
- No changes to `PRManager` notification or polling logic

## Implementation Approach

Four phases, each independently buildable and verifiable. Each phase ends with `swift build` passing cleanly (which includes SwiftLint via the build plugin).

---

## Phase 1: Dead Code Removal + Trivial Inlines

### Overview
Remove unused code from previous iterations and inline a trivial passthrough.

### Changes Required:

#### 1. Remove `PRReference` struct and `PullRequest.placeholder` factory
**File**: `Sources/Models.swift`
**Changes**:
- Delete `PRReference` struct (lines 134-174)
- Delete `PullRequest.placeholder(owner:repo:number:)` (lines 90-117)
- Delete `PullRequest.fallbackURL` (lines 119-129)

#### 2. Remove `checkCLI()` method
**File**: `Sources/GitHubService.swift`
**Changes**:
- Delete the `checkCLI()` method (lines 23-28)

#### 3. Move `ciColor` to `CIStatus` enum
**File**: `Sources/Models.swift`
**Changes**:
- Add a `color` computed property on `PullRequest.CIStatus`:

```swift
enum CIStatus: String {
    case success
    case failure
    case pending
    case unknown

    var color: Color {
        switch self {
        case .success: return .green
        case .failure: return .red
        case .pending: return .orange
        case .unknown: return .secondary
        }
    }
}
```

**File**: `Sources/PRRowView.swift`
**Changes**:
- Delete `private var ciColor: Color` computed property
- Replace all references to `ciColor` with `pullRequest.ciStatus.color`

#### 4. Inline `statusDotColor` passthrough
**File**: `Sources/ContentView.swift`
**Changes**:
- Delete `statusDotColor(for:)` method
- Replace the single call site with `pullRequest.statusColor` directly:

```swift
// Before
.fill(statusDotColor(for: pullRequest))

// After
.fill(pullRequest.statusColor)
```

### Success Criteria:
- [x] `swift build` succeeds with zero warnings/errors (includes SwiftLint)
- [x] No references remain to `PRReference`, `placeholder`, `fallbackURL`, `checkCLI`, `ciColor`, or `statusDotColor` in the codebase

---

## Phase 2: Sort Priority on the Model

### Overview
Move PR sort priority from a private `ContentView` function to a computed property on `PullRequest`, making it reusable and preventing divergence.

### Changes Required:

#### 1. Add `sortPriority` to `PullRequest`
**File**: `Sources/Models.swift`
**Changes**:
- Add a computed property alongside `statusColor`:

```swift
/// Sort priority: Open = 0, Draft = 1, Queued = 2, Closed/Merged = 3.
var sortPriority: Int {
    if isInMergeQueue { return 2 }
    switch state {
    case .open: return 0
    case .draft: return 1
    case .merged: return 3
    case .closed: return 3
    }
}
```

#### 2. Replace `statePriority` in `ContentView`
**File**: `Sources/ContentView.swift`
**Changes**:
- Delete `statePriority(_:)` function
- Update `groupedPRs` sort closure:

```swift
(repo: key, prs: (dict[key] ?? []).sorted {
    let lhsPriority = $0.sortPriority
    let rhsPriority = $1.sortPriority
    if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
    return $0.number < $1.number
})
```

### Success Criteria:
- [x] `swift build` succeeds with zero warnings/errors
- [x] No references remain to `statePriority` in the codebase

---

## Phase 3: Unify Badge Pill Usage in PRRowView

### Overview
Make `stateBadge` and `ciBadge` use the existing `badgePill` helper instead of duplicating its styling.

### Changes Required:

#### 1. Refactor `stateBadge` to use `badgePill`
**File**: `Sources/PRRowView.swift`
**Changes**:
- Replace the inline pill construction with a call to `badgePill`:

```swift
private var stateBadge: some View {
    badgePill(icon: stateIcon, text: stateText, color: statusColor)
}
```

#### 2. Extract `ciBadge` inner pill to use `badgePill`
**File**: `Sources/PRRowView.swift`
**Changes**:
- The `ciBadge` button wraps a pill with an optional chevron. Refactor to compose `badgePill`-style content inside the button, keeping the chevron addition. Since `ciBadge` needs a custom background opacity (0.12 vs 0.12 — same value) and adds a chevron, the cleanest approach is to make `badgePill` accept an optional trailing view:

```swift
private func badgePill(
    icon: String,
    text: String,
    color: Color,
    trailing: (() -> AnyView)? = nil
) -> some View {
    HStack(spacing: 3) {
        Image(systemName: icon)
            .font(.caption2)
        Text(text)
            .font(.caption2.weight(.medium))
        if let trailing { trailing() }
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(color.opacity(0.12))
    .foregroundColor(color)
    .cornerRadius(4)
}
```

Then `ciBadge` becomes:

```swift
@ViewBuilder
private var ciBadge: some View {
    if pullRequest.checksTotal > 0 {
        Button {
            if !pullRequest.failedChecks.isEmpty {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showFailures.toggle()
                }
            }
        } label: {
            badgePill(
                icon: ciIcon,
                text: ciText,
                color: pullRequest.ciStatus.color,
                trailing: !pullRequest.failedChecks.isEmpty ? {
                    AnyView(
                        Image(systemName: showFailures ? "chevron.up" : "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                    )
                } : nil
            )
        }
        .buttonStyle(.plain)
    }
}
```

Note: `stateBadge` currently uses `statusColor.opacity(0.15)` for background while `badgePill` uses `0.12`. Unify to `0.12` (the value used by all other badges).

### Success Criteria:
- [x] `swift build` succeeds with zero warnings/errors
- [x] All badge pills use the shared `badgePill` helper — search for `.cornerRadius(4)` in `PRRowView.swift` and confirm it only appears inside `badgePill`

---

## Phase 4: Shared Auth Status Component

### Overview
Extract the authenticated/unauthenticated display into a shared `AuthStatusView` used by both `ContentView.footer` and `SettingsView`.

### Changes Required:

#### 1. Create `AuthStatusView`
**File**: `Sources/AuthStatusView.swift` (new file)
**Changes**:

```swift
import SwiftUI

struct AuthStatusView: View {
    let username: String?
    let style: Style

    enum Style {
        case compact   // footer: icon + username only
        case detailed  // settings: full card with instructions
    }

    var body: some View {
        if let username {
            authenticatedView(username: username)
        } else {
            unauthenticatedView
        }
    }

    @ViewBuilder
    private func authenticatedView(username: String) -> some View {
        switch style {
        case .compact:
            HStack(spacing: 4) {
                Image(systemName: "person.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                Text(username)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .detailed:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Signed in as **\(username)**")
                Spacer()
            }
            .padding(10)
            .background(Color.green.opacity(0.08))
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private var unauthenticatedView: some View {
        switch style {
        case .compact:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("gh not authenticated")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .detailed:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not authenticated")
                        .font(.body.weight(.medium))
                    Text("Run this command in your terminal:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("gh auth login")
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(4)
                }
                Spacer()
            }
            .padding(10)
            .background(Color.orange.opacity(0.08))
            .cornerRadius(8)
        }
    }
}
```

#### 2. Update `ContentView.footer`
**File**: `Sources/ContentView.swift`
**Changes**:
- Replace the inline auth status block with:

```swift
AuthStatusView(username: manager.ghUser, style: .compact)
```

#### 3. Update `SettingsView`
**File**: `Sources/SettingsView.swift`
**Changes**:
- Replace the full auth section body (the `if let user` / `else` block) with:

```swift
AuthStatusView(username: manager.ghUser, style: .detailed)
```

### Success Criteria:
- [x] `swift build` succeeds with zero warnings/errors
- [x] `ContentView.swift` and `SettingsView.swift` contain no inline auth status rendering — only `AuthStatusView` references
- [x] New file `Sources/AuthStatusView.swift` exists and is lint-clean

---

## References

- Research: `thoughts/shared/research/2026-02-10-dry-refactoring-opportunities.md`
