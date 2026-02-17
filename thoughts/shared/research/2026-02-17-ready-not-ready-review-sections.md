---
date: 2026-02-17T12:00:00Z
researcher: Blake McAnally
git_commit: 515dbb9cd64c7775bc303404621c38b5c776f2b4
branch: main
repository: blakemcanally/pr-status-watcher
topic: "Ready vs Not Ready review sections — UI hierarchy options and required-CI-job configuration"
tags: [research, codebase, reviews-tab, sections, readiness, ci-checks, required-checks, ui-hierarchy]
status: complete
last_updated: 2026-02-17
last_updated_by: Blake McAnally
---

# Research: Ready vs Not Ready Review Sections

**Date**: 2026-02-17T12:00:00Z
**Researcher**: Blake McAnally
**Git Commit**: 515dbb9cd64c7775bc303404621c38b5c776f2b4
**Branch**: main
**Repository**: blakemcanally/pr-status-watcher

## Research Question

How should the Reviews tab be restructured to show "Ready for Review" vs "Not Ready for Review" PRs in separate sections? What are the UI hierarchy options and their tradeoffs? How does this connect to a future feature for configuring required CI jobs (e.g., "Bazel-Pipeline-PR must pass") as part of the readiness definition?

## Summary

The Reviews tab currently shows all review-requested PRs in a flat list grouped by repository, with optional filters that **hide** PRs entirely. The proposed change moves from a hide/show binary to a **sectioned layout** that separates "Ready" and "Not Ready" PRs — keeping both visible but in distinct visual zones. This is a natural evolution of the existing `FilterSettings` and `PRGrouping` architecture.

Four UI hierarchy options are analyzed below, with **Option A (Readiness sections at the top level, repos nested within)** recommended as the strongest fit for the app's existing patterns and the reviewer's primary workflow question: "What can I act on right now?"

The future required-CI-job feature maps cleanly onto the readiness concept — a PR is "ready" when all user-specified checks are passing. The data for individual check names is **already fetched** via the GraphQL `statusCheckRollup.contexts` query and parsed into `CheckInfo` structs. The main addition is a `requiredCheckNames: [String]` configuration and a readiness predicate that evaluates per-check results rather than the overall `ciStatus` rollup.

---

## Current State of the Reviews Tab

### Data flow

```
PRManager.reviewPRs (all review-requested PRs)
  → ContentView.activePRs (tab switch)
    → ContentView.filteredPRs (applies FilterSettings — hides PRs entirely)
      → PRGrouping.grouped() (groups by repo, sorts by review priority)
        → ForEach repoSection → PRRowView
```

### Current grouping: Repo-first, single-level

```
Reviews Tab
├── org/repo-a (2)
│   ├── PR #123 - Fix login         [Open] [CI ✓] [Review Required]
│   └── PR #789 - WIP feature       [Draft] [CI ✗]
├── org/repo-b (1)
│   └── PR #456 - Add tests         [Open] [CI ✓] [Approved]
└── org/repo-c (1)
    └── PR #101 - New endpoint       [Open] [CI pending]
```

### Relevant code

- **Filtering**: `Models.swift:154-164` — `FilterSettings.applyReviewFilters(to:)` returns a filtered array
- **Grouping**: `PRGrouping.swift:16-38` — `grouped(prs:isReviews:)` groups by repo, sorts by review priority
- **Rendering**: `ContentView.swift:98-110` — `prList` iterates `groupedPRs` with `repoSection()`
- **Repo sections**: `ContentView.swift:114-146` — collapsible repo headers with PR rows
- **Settings**: `SettingsView.swift:85-103` — "Review Filters" section with hide toggles

### Individual check data already available

The GraphQL query (`GitHubService.swift:116-137`) already fetches per-check details:

```graphql
statusCheckRollup {
  state
  contexts(first: 100) {
    totalCount
    nodes {
      ... on CheckRun { name, status, conclusion, detailsUrl }
      ... on StatusContext { context, state, targetUrl }
    }
  }
}
```

These are parsed in `tallyCheckContexts()` (`GitHubService.swift:333-367`) and surface as:
- `PullRequest.ciStatus` — the overall rollup (success/failure/pending/unknown)
- `PullRequest.failedChecks: [CheckInfo]` — names and URLs of failed checks
- `PullRequest.checksTotal`, `checksPassed`, `checksFailed` — aggregate counts

Currently only **failed** check names are stored on the model. To support required-check matching, we'd also need to store **all** check names and their individual statuses (or at minimum the passing ones).

---

## Defining "Readiness"

A PR is considered **Ready for Review** when all of the following are true:

1. It is not a draft (`state != .draft`)
2. It has no merge conflicts (`mergeable != .conflicting`)
3. All **required CI checks** are passing (configurable — see below)

A PR is **Not Ready for Review** when any of those conditions fail. The "not ready" section would show a reason indicator (e.g., "Draft", "CI: Bazel-Pipeline-PR failing", "Conflicts").

### Default readiness (no required checks configured)

When no required check names are configured, readiness falls back to the overall `ciStatus`:
- `ciStatus == .success` or `ciStatus == .unknown` → ready (CI-wise)
- `ciStatus == .failure` or `ciStatus == .pending` → not ready

### Custom readiness (required checks configured)

When the user specifies required check names (e.g., `["Bazel-Pipeline-PR", "lint"]`):
- Only those named checks are evaluated
- If all specified checks are passing → ready (even if other checks fail)
- If any specified check is failing or pending → not ready
- If a specified check hasn't run yet → not ready

---

## UI Hierarchy Options

### Option A: Readiness → Repo (Recommended)

Readiness sections at the top level. Repos nested within each section.

```
Reviews Tab
├── ✅ Ready for Review (3)
│   ├── org/repo-a (1)
│   │   └── PR #123 - Fix login        [Open] [CI ✓] [Review Required]
│   └── org/repo-b (2)
│       ├── PR #456 - Add tests        [Open] [CI ✓] [Approved]
│       └── PR #457 - Fix flaky test   [Open] [CI ✓] [Review Required]
│
└── ⏳ Not Ready for Review (2)
    ├── org/repo-a (1)
    │   └── PR #789 - WIP feature      [Draft]
    └── org/repo-c (1)
        └── PR #101 - New endpoint      [CI: Bazel-Pipeline-PR pending]
```

**Pros**:
- Answers the primary question first: "What can I review right now?"
- Preserves repo grouping within each section (familiar pattern)
- "Not Ready" is visible but visually demoted — good for awareness without noise
- Naturally supports collapsing the "Not Ready" section
- Cleanest information hierarchy — actionability is the top-level sort

**Cons**:
- A repo may appear in both sections, which could feel slightly redundant
- Slightly more vertical space than the current single-list layout

**Implementation complexity**: Medium — requires splitting PRs into two arrays before grouping, then rendering two sections each with their own repo groups.

---

### Option B: Repo → Readiness

Repos at the top level. Ready/Not Ready subsections within each repo.

```
Reviews Tab
├── org/repo-a (3)
│   ├── Ready (1)
│   │   └── PR #123 - Fix login
│   └── Not Ready (2)
│       ├── PR #789 - WIP feature      [Draft]
│       └── PR #790 - Broken build     [CI failing]
├── org/repo-b (2)
│   └── Ready (2)    ← only one subsection when all are same status
│       ├── PR #456 - Add tests
│       └── PR #457 - Fix flaky test
└── org/repo-c (1)
    └── Not Ready (1)
        └── PR #101 - New endpoint      [CI pending]
```

**Pros**:
- Preserves the current repo-first grouping (minimal visual change)
- Good if the user primarily thinks in terms of repos
- No repo duplication

**Cons**:
- Fragments the "ready" view across multiple repos — harder to scan "what can I act on now"
- Introduces three levels of nesting (repo → readiness → PR), which is visually heavy for a menu bar popover
- When a repo has PRs in only one readiness state, the inner section header is redundant noise
- Makes it harder to get a quick count of total ready vs not-ready PRs

**Implementation complexity**: Medium — modify `repoSection()` to split PRs within each repo.

---

### Option C: Flat Readiness (No Repo Grouping)

Readiness sections with a flat list of PRs (repo shown inline on each row).

```
Reviews Tab
├── ✅ Ready for Review (3)
│   ├── PR #123 - Fix login          org/repo-a  [Review Required]
│   ├── PR #456 - Add tests         org/repo-b  [Approved]
│   └── PR #457 - Fix flaky test    org/repo-b  [Review Required]
│
└── ⏳ Not Ready for Review (2)
    ├── PR #789 - WIP feature        org/repo-a  [Draft]
    └── PR #101 - New endpoint       org/repo-c  [CI pending]
```

**Pros**:
- Simplest layout, least visual nesting
- Very fast to scan
- Good for users with fewer review requests (< 10)

**Cons**:
- Loses repo grouping — harder to navigate when there are many PRs across many repos
- Breaks from the established visual pattern of the app (repo sections with collapsible headers)
- Repo name must be shown on every row, taking horizontal space
- Doesn't scale well beyond ~15 PRs

**Implementation complexity**: Low — simplest to implement, just partition and render.

---

### Option D: Sub-Tabs within Reviews

A segmented control within the Reviews tab to switch between Ready and Not Ready views.

```
Reviews Tab
  [Ready (3)] [Not Ready (2)]    ← sub-segmented control

  // When "Ready" selected, shows repo-grouped list:
  ├── org/repo-a (1)
  │   └── PR #123 - Fix login
  └── org/repo-b (2)
      ├── PR #456 - Add tests
      └── PR #457 - Fix flaky test
```

**Pros**:
- Clean separation — no mixed visual zones
- Each sub-tab is a simple repo-grouped list (reuses existing layout exactly)
- Counts are visible in the sub-tab labels

**Cons**:
- Hides "Not Ready" PRs behind a tab switch — less awareness of what's coming
- Adds another level of tab navigation (already have My PRs / Reviews)
- Feels over-engineered for what is typically a short list
- The "Not Ready" tab may rarely be visited, making the feature feel like it only added a filter

**Implementation complexity**: Low — add a `@State` for the sub-tab, partition PRs, render the selected partition using existing `groupedPRs` logic.

---

## Recommendation: Option A (Readiness → Repo)

Option A is the strongest fit because:

1. **Answers the right question first.** A reviewer opening the tab wants to know "what needs my review right now?" — readiness as the top-level grouping answers this immediately.

2. **Keeps "Not Ready" visible.** Unlike hiding (current filters) or sub-tabs (Option D), the "Not Ready" section stays visible, giving awareness of upcoming reviews without cluttering the actionable list.

3. **Preserves familiar patterns.** Repo grouping with collapsible headers is already the app's visual language. Option A nests it inside readiness sections, not replacing it.

4. **Scales well.** Works for 3 PRs and 30 PRs. The "Not Ready" section can be collapsed by default if the user prefers.

5. **Natural home for required-check configuration.** When a user configures "Bazel-Pipeline-PR must pass," the readiness classification directly controls which section a PR lands in. The "Not Ready" section can show the specific reason ("CI: Bazel-Pipeline-PR failing").

---

## Required CI Checks Configuration — Future Feature

### Concept

The user specifies check names that must be passing for a PR to be considered "Ready for Review." This is more granular than the current overall `ciStatus` rollup — a PR might have 15 checks where 14 pass and 1 optional linter fails, but if the user only cares about "Bazel-Pipeline-PR" passing, the PR is ready.

### Data model changes

```swift
// New: individual check results (not just failed ones)
struct CheckResult: Codable, Equatable {
    let name: String
    let status: CheckStatus  // .passed, .failed, .pending, .notRun
    let detailsUrl: URL?
}

enum CheckStatus: String, Codable {
    case passed, failed, pending, notRun
}

// On PullRequest, add:
var checkResults: [CheckResult]  // all individual check results

// On FilterSettings or a new ReadinessConfig, add:
var requiredCheckNames: [String]  // e.g., ["Bazel-Pipeline-PR", "lint"]
```

### Readiness predicate

```swift
func isReadyForReview(_ pr: PullRequest, config: ReadinessConfig) -> Bool {
    // Must not be draft
    guard pr.state != .draft else { return false }
    // Must not have conflicts
    guard pr.mergeable != .conflicting else { return false }
    
    // Check required CI jobs
    if config.requiredCheckNames.isEmpty {
        // No specific checks required — use overall CI status
        return pr.ciStatus != .failure && pr.ciStatus != .pending
    } else {
        // Only evaluate the specified checks
        for requiredName in config.requiredCheckNames {
            guard let check = pr.checkResults.first(where: { $0.name == requiredName }) else {
                return false  // required check hasn't run yet
            }
            if check.status != .passed { return false }
        }
        return true
    }
}
```

### Where check names come from

Individual check names are already fetched by the GraphQL query and parsed in `GitHubService.tallyCheckContexts()` (`GitHubService.swift:333-367`). Currently only failed check names are stored on the `PullRequest` model as `failedChecks: [CheckInfo]`. To support this feature:

1. Store **all** check results (not just failed) on the model
2. Add a `requiredCheckNames` configuration to settings
3. Use the readiness predicate to partition PRs into Ready/Not Ready sections

### Settings UI for required checks

The required check names configuration could live in the existing "Review Filters" section of Settings, or in a new "Readiness" section:

```
┌─────────────────────────────────────────┐
│  Review Readiness                       │
│  ───────────────────────────────────    │
│  Required CI Checks                     │
│  PRs won't appear as "Ready" until      │
│  these checks pass.                     │
│                                         │
│  ┌─────────────────────────┬─────┐      │
│  │ Bazel-Pipeline-PR       │  ✕  │      │
│  │ lint                    │  ✕  │      │
│  └─────────────────────────┴─────┘      │
│  [+ Add check name]                     │
│                                         │
│  Tip: check names must match the        │
│  exact name shown in GitHub CI.         │
└─────────────────────────────────────────┘
```

Discovery aid: the app could offer autocomplete based on check names seen across recent PRs. Since `checkResults` would contain all check names from fetched PRs, a simple `Set` aggregation provides the suggestion list.

---

## Implementation Sketch for Option A

### Step 1: Add readiness classification

Add a computed property or function that classifies a PR as ready or not:

```swift
// Could live on PullRequest or as a standalone function
extension PullRequest {
    func isReady(requiredChecks: [String]) -> Bool {
        guard state != .draft else { return false }
        guard mergeable != .conflicting else { return false }
        if requiredChecks.isEmpty {
            return ciStatus != .failure && ciStatus != .pending
        }
        // Check specific required checks...
    }
}
```

### Step 2: Partition PRs in ContentView

```swift
private var readyPRs: [PullRequest] {
    filteredPRs.filter { $0.isReady(requiredChecks: manager.requiredCheckNames) }
}

private var notReadyPRs: [PullRequest] {
    filteredPRs.filter { !$0.isReady(requiredChecks: manager.requiredCheckNames) }
}

private var groupedReadyPRs: [(repo: String, prs: [PullRequest])] {
    PRGrouping.grouped(prs: readyPRs, isReviews: true)
}

private var groupedNotReadyPRs: [(repo: String, prs: [PullRequest])] {
    PRGrouping.grouped(prs: notReadyPRs, isReviews: true)
}
```

### Step 3: Render two sections

```swift
ScrollView {
    LazyVStack(spacing: 0) {
        readinessSection(title: "Ready for Review", icon: "checkmark.circle.fill",
                         color: .green, groups: groupedReadyPRs)
        readinessSection(title: "Not Ready", icon: "clock.fill",
                         color: .secondary, groups: groupedNotReadyPRs)
    }
}
```

Each `readinessSection` renders a collapsible header and then the familiar `repoSection()` blocks within.

### Step 4: Store all check results (for future required-checks feature)

Extend `PullRequest` to store all individual check results, not just failed ones. Modify `tallyCheckContexts()` to produce a `[CheckResult]` array.

### Step 5: Add required check names to settings

Add `requiredCheckNames: [String]` to `FilterSettings` (or a new `ReadinessConfig` model), persisted via `SettingsStore`.

---

## Interaction with Existing Filters

The existing `FilterSettings` hide/show toggles and the new readiness sections are complementary:

1. **Filters run first** — `applyReviewFilters()` removes PRs the user never wants to see (e.g., hide drafts entirely)
2. **Readiness sections run second** — the remaining PRs are partitioned into Ready / Not Ready sections

This means:
- If "Hide draft PRs" is ON → drafts are removed entirely (not shown in either section)
- If "Hide draft PRs" is OFF → drafts appear in the "Not Ready" section with a "Draft" reason
- If "Hide CI-failing" is ON → CI-failing PRs are removed entirely
- If "Hide CI-failing" is OFF → CI-failing PRs appear in "Not Ready" with a CI reason

The user can choose their preference: completely hide certain categories, or keep them visible but demoted to "Not Ready."

---

## Code References

### Data model
- `Sources/Models.swift:6-28` — `PullRequest` struct with all fields
- `Sources/Models.swift:80-94` — `CIStatus` enum
- `Sources/Models.swift:113-116` — `CheckInfo` struct (currently only stores failed checks)
- `Sources/Models.swift:121-165` — `FilterSettings` struct and `applyReviewFilters()`

### GraphQL / check parsing
- `Sources/GitHubService.swift:116-137` — GraphQL query fetching per-check details
- `Sources/GitHubService.swift:333-367` — `tallyCheckContexts()` processes individual check nodes
- `Sources/GitHubService.swift:369-384` — `classifyCompletedCheckContext()` determines pass/fail per check

### Current grouping and rendering
- `Sources/PRGrouping.swift:16-38` — `grouped(prs:isReviews:)` — repo grouping logic
- `Sources/ContentView.swift:21-29` — `filteredPRs` and `groupedPRs` computed properties
- `Sources/ContentView.swift:98-146` — `prList` and `repoSection()` rendering

### Settings
- `Sources/SettingsView.swift:85-103` — "Review Filters" section
- `Sources/SettingsStore.swift:43-61` — `loadFilterSettings()` / `saveFilterSettings()`
- `Sources/PRManager.swift:35-36` — `@Published var filterSettings` with `didSet` persistence

## Related Research

- `thoughts/shared/research/2026-02-10-reviewability-filter-controls.md` — Filter controls research (predecessor to this work)
- `thoughts/shared/research/2026-02-10-architecture-and-design-patterns.md` — Full architecture documentation
- `thoughts/shared/research/2026-02-10-feature-ideas.md` — Feature ideas list

## Open Questions

1. **Should "Not Ready" be collapsed by default?** Option A works best if reviewers can collapse the "Not Ready" section. Should it default to collapsed, or expanded?
2. **Per-repo or global required checks?** Some repos may have different CI pipelines (e.g., "Bazel-Pipeline-PR" only exists in the monorepo). Should required checks be configurable per-repo, or is a global list sufficient (where missing checks are simply ignored)?
3. **Autocomplete for check names**: Should the settings UI offer autocomplete from recently-seen check names, or just a free-text input? Autocomplete is more user-friendly but requires aggregating check names across all fetched PRs.
