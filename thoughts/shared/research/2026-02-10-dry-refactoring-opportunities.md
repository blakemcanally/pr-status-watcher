---
date: 2026-02-10T23:00:00Z
researcher: Blake McAnally
git_commit: 78b69fec9f57cc1f0303e987d64355bc9b44d7e4
branch: main
repository: blakemcanally/pr-status-watcher
topic: "DRY refactoring opportunities and shared code path analysis"
tags: [research, codebase, refactoring, dry]
status: complete
last_updated: 2026-02-10
last_updated_by: Blake McAnally
---

# Research: DRY Refactoring Opportunities

**Date**: 2026-02-10T23:00:00Z
**Researcher**: Blake McAnally
**Git Commit**: 78b69fec9f57cc1f0303e987d64355bc9b44d7e4
**Branch**: main
**Repository**: blakemcanally/pr-status-watcher

## Research Question
Identify potential refactoring improvements on shared code paths, or things that could generally be DRYed up.

## Summary

Six concrete DRY/refactoring opportunities were identified, ranging from dead code removal to color mapping consolidation and badge view extraction.

## Detailed Findings

### 1. Dead Code: `PRReference`, `PullRequest.placeholder`, `checkCLI()`

Three items exist in the codebase that are defined but never called:

- **`PRReference` struct** (`Models.swift:134-174`) — a URL/shorthand parser from the original manual-add flow. The app now auto-discovers PRs via GraphQL; nothing calls `PRReference.parse(from:)`.
- **`PullRequest.placeholder(owner:repo:number:)`** (`Models.swift:90-117`) plus **`fallbackURL`** (`Models.swift:120-129`) — a factory for loading-state placeholders from the old per-PR fetch flow. No call site remains.
- **`GitHubService.checkCLI()`** (`GitHubService.swift:23-28`) — auth check method. The app uses `currentUser()` instead; `checkCLI()` is never invoked.

### 2. `CIStatus` Color Mapping Duplicated

`PRRowView.ciColor` (`PRRowView.swift:228-235`) maps `CIStatus` to a `Color` for CI badge styling. This is a standalone mapping of the enum to a color that could live directly on `PullRequest.CIStatus` as a computed property, similar to how `statusColor` now lives on `PullRequest`. This would make it reusable if CI colors are ever needed elsewhere (e.g., notifications UI, menu bar tooltips).

```
// PRRowView.swift:228-235 — currently private to the view
private var ciColor: Color {
    switch pullRequest.ciStatus {
    case .success: return .green
    case .failure: return .red
    case .pending: return .orange
    case .unknown: return .secondary
    }
}
```

### 3. `statusDotColor` Is a Trivial Passthrough

`ContentView.statusDotColor(for:)` (`ContentView.swift:189-191`) is a one-liner that just returns `pullRequest.statusColor`. It could be inlined at the single call site (`ContentView.swift:155`) to eliminate the unnecessary indirection.

### 4. Sort Priority Could Live on the Model

`ContentView.statePriority(_:)` (`ContentView.swift:22-30`) defines the Open/Draft/Queued sort order. This is presentation-coupled sorting logic that could be a computed property on `PullRequest` (e.g., `var sortPriority: Int`) or a `Comparable` conformance on `PRState`. This would make the sort order reusable if another view or export feature needs the same ordering, and prevents divergence if the sort order needs to change.

### 5. Badge Pill Styling Is Partially Shared

`PRRowView.badgePill(icon:text:color:)` (`PRRowView.swift:239-251`) creates the rounded pill with icon + text. It's used by `reviewBadge`, `conflictBadge`. However:

- **`stateBadge`** (`PRRowView.swift:105-117`) manually builds the same visual pattern inline instead of calling `badgePill`, because it uses `statusColor` for both background and foreground. It could call `badgePill(icon: stateIcon, text: stateText, color: statusColor)` and get identical output.
- **`ciBadge`** (`PRRowView.swift:178-206`) also builds the pill pattern inline (the inner HStack with `.padding(.horizontal, 6).padding(.vertical, 2).background(...).cornerRadius(4)`), but wraps it in a `Button` and adds the chevron. The inner styling still duplicates `badgePill`.

### 6. "Not Authenticated" UI Appears in Two Places

The unauthenticated state is rendered in both:
- `ContentView.footer` (`ContentView.swift:229-236`) — compact: warning icon + "gh not authenticated"
- `SettingsView` (`SettingsView.swift:38-58`) — detailed: warning icon + explanation + `gh auth login` command

These serve different purposes (compact footer vs. full settings panel), so they're not exact duplicates, but the authenticated state display (green icon + username) also appears in both (`ContentView.swift:220-227` and `SettingsView.swift:28-36`). A shared `AuthStatusBadge` component with a `compact` vs `detailed` mode could unify them.

## Code References

- `Sources/Models.swift:90-129` — Dead code: `placeholder` factory + `fallbackURL`
- `Sources/Models.swift:134-174` — Dead code: `PRReference` struct
- `Sources/GitHubService.swift:23-28` — Dead code: `checkCLI()`
- `Sources/PRRowView.swift:228-235` — `ciColor` mapping (candidate for model)
- `Sources/ContentView.swift:189-191` — `statusDotColor` passthrough
- `Sources/ContentView.swift:22-30` — `statePriority` (candidate for model)
- `Sources/PRRowView.swift:105-117` — `stateBadge` duplicates `badgePill` pattern
- `Sources/PRRowView.swift:188-202` — `ciBadge` inner HStack duplicates pill styling
- `Sources/ContentView.swift:220-236` — Footer auth status display
- `Sources/SettingsView.swift:27-59` — Settings auth status display

## Priority Assessment

| # | Finding | Impact | Effort |
|---|---------|--------|--------|
| 1 | Dead code removal | Reduces noise, no risk | Trivial |
| 2 | `CIStatus` color on model | Prevents future divergence | Trivial |
| 3 | Inline `statusDotColor` | Cleanliness | Trivial |
| 4 | Sort priority on model | Reusability, single source of truth | Low |
| 5 | Unify badge pill usage | DRY, consistency | Low |
| 6 | Shared auth status component | DRY across views | Medium |
