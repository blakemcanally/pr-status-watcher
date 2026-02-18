---
date: 2026-02-18T16:07:46Z
researcher: bmcanally
git_commit: cec247e54f4927880bba41f04506555a07029006
branch: main
repository: pr-status-watcher
topic: "Review SLA Configuration — How to add configurable review deadlines and exceeded-SLA indicators"
tags: [research, codebase, sla, review-deadline, configuration, timestamps, github-graphql]
status: complete
last_updated: 2026-02-18
last_updated_by: bmcanally
last_updated_note: "Resolved open questions: publishedAt-only (no fallback), SLA sections on Reviews tab, wall-clock hours, badge-first notifications later, global SLA with per-repo future"
---

# Research: Review SLA Configuration

**Date**: 2026-02-18T16:07:46Z
**Researcher**: bmcanally
**Git Commit**: cec247e54f4927880bba41f04506555a07029006
**Branch**: main
**Repository**: pr-status-watcher

## Research Question

How can we add a review SLA configuration where the individual is expected to give a review within a certain number of hours after the pull request has been opened? Research how we could introduce that configuration and then indicate which requests have exceeded SLA.

## Summary

Adding review SLA support requires changes across four layers: (1) **GitHub API** — the GraphQL query must be extended with `publishedAt`, (2) **data model** — `PullRequest` needs a date field and SLA computation, (3) **configuration** — `FilterSettings` needs an SLA threshold setting, and (4) **UI** — the Reviews tab needs SLA-exceeded sections and per-row badges to visually alert the user.

**Key design decisions** (resolved):

- **Timestamp**: Use `publishedAt` directly — no `createdAt` fallback. This is the canonical "when did the PR become reviewable" field and aligns with how other SLA metrics are calculated.
- **Display approach**: SLA is **display-only** — it does not filter or hide PRs. Instead, SLA-exceeded PRs are visually highlighted via badges and potentially organized into an "SLA Exceeded" section on the Reviews tab (similar to Ready/Not Ready sections). No PRs are removed from the list.
- **Scope**: Reviews tab only. Wall-clock hours. Global threshold (per-repo as a future enhancement). Notifications deferred — implement badge/section first.

The exact semantics of `publishedAt` have gaps in GitHub's documentation — see the [deep-dive on `publishedAt`](#10-deep-dive-publishedat-semantics-and-unknowns) below — but we proceed with it directly since it's likely the field other SLA metrics are calculated against.

## Detailed Findings

### 1. Current State: No Timestamps Exist

The `PullRequest` model (`Sources/Models/Models.swift:6-30`) has **no GitHub-originated timestamp fields**. The only `Date` property is `lastFetched` (line 23), which is set to `Date()` at fetch time in `GitHubService+NodeConversion.swift:56` — it records when the app fetched the data, not when the PR was created or updated.

The GraphQL query (`Sources/GitHub/GitHubService.swift:211-268`) does **not** request `createdAt`, `updatedAt`, `publishedAt`, or any other timestamp field. The response types in `GraphQLResponse.swift` similarly have no date fields on `PRNode` (lines 34-49).

This means the very first step for any SLA feature is extending the GraphQL query and data pipeline to include timestamp data.

### 2. GitHub GraphQL API: Available Timestamp Sources

There are three approaches to getting the timestamp for "when was a review requested," ranging from simple to precise:

#### Approach A: `PullRequest.createdAt` (Simplest)

- **Field**: `createdAt: DateTime!` on the `PullRequest` GraphQL type
- **Meaning**: When the PR was opened
- **Pros**: Single scalar field, trivial to add, always present, no pagination
- **Cons**: Not the same as "when review was requested" — if a reviewer is added 2 hours after PR creation, the SLA clock would have started 2 hours early
- **Best for**: Teams where review is auto-requested at PR creation (via CODEOWNERS, branch rules, etc.)

#### Approach B: `PullRequest.publishedAt` (Chosen)

- **Field**: `publishedAt: DateTime` on the `PullRequest` GraphQL type
- **Meaning**: When the PR was made available for review — see [deep-dive below](#10-deep-dive-publishedat-semantics-and-unknowns) for documentation gaps
- **Chosen approach**: Use `publishedAt` directly as the SLA start date. No `createdAt` fallback. This is the canonical "when did the PR become reviewable" timestamp and aligns with how other SLA metrics are typically calculated.
- **Pros**: Captures "when the PR became reviewable," which is semantically correct for an SLA clock. Single scalar field, no pagination.
- **Cons**: GitHub's documentation is vague about exact semantics — see unknowns below. Edge cases around draft→ready→draft cycles may need handling.

**SLA start date**: Simply `publishedAt`. If `publishedAt` is null (e.g., the PR is currently a draft or an edge case), the SLA badge should not render — a null `publishedAt` means the PR hasn't been published for review yet, so no SLA applies.

#### Approach C: `timelineItems` with `ReviewRequestedEvent` (Most Precise)

- **Query**: Use `timelineItems(first: N, itemTypes: [REVIEW_REQUESTED_EVENT])` on the PullRequest
- **Event type**: `ReviewRequestedEvent` has `createdAt: DateTime!` and identifies the requested reviewer
- **Pros**: Tells you exactly when a specific reviewer was requested
- **Cons**: Requires fetching timeline events (potentially paginated), more complex parsing, may need `requestedReviewer` field inspection, and the `itemTypes` filter may not be supported in all schema versions

**Important note**: The `ReviewRequest` object (from `pullRequest.reviewRequests`) does **not** have a `createdAt` field. It only has `id`, `pullRequest`, and `reviewer`. To get the timestamp of when a review was requested, you must use the timeline events.

**Reference**: [GitHub GraphQL PullRequest](https://docs.github.com/en/graphql/reference/objects#pullrequest), [ReviewRequestedEvent](https://docs.github.com/en/graphql/reference/objects#reviewrequestedevent)

### 3. Configuration System: Where SLA Settings Would Live

The app's configuration system follows a clear pattern documented across `FilterSettings` (`Sources/Models/Models.swift:217-264`), `SettingsStore` (`Sources/Settings/SettingsStore.swift`), and `PRManager` (`Sources/App/PRManager.swift`).

**Existing `FilterSettings` structure** (Models.swift:217-264):

```swift
struct FilterSettings: Codable, Equatable {
    var hideDrafts: Bool
    var hideApprovedByMe: Bool
    var hideNotReady: Bool
    var requiredCheckNames: [String]
    var ignoredCheckNames: [String]
    var ignoredRepositories: [String]
}
```

**Pattern for adding new properties**:

1. Add property with default to `FilterSettings`
2. Add to `init(from decoder:)` with `decodeIfPresent` for backward compatibility
3. Add UI in `SettingsView` (toggle via `filterBinding`, or custom section for complex types)
4. Use in `ContentView`/`PRRowView`/`PRManager` where needed
5. Add strings to `Sources/App/Strings.swift`

The SLA threshold fits naturally as a new property on `FilterSettings`:

```swift
var reviewSLAHours: Int?  // nil = disabled, e.g. 24 = 24-hour SLA
```

Using `Int?` (optional) allows "disabled" as the default without requiring a separate boolean toggle. The `decodeIfPresent` pattern already used by all properties handles backward compatibility.

### 4. PullRequest Model: What Needs to Change

Current `PullRequest` stored properties (`Sources/Models/Models.swift:6-30`):

```
owner, repo, number, title, author, state, ciStatus, isInMergeQueue,
checksTotal, checksPassed, checksFailed, url, headSHA, headRefName,
lastFetched, reviewDecision, mergeable, queuePosition, approvalCount,
failedChecks, checkResults, viewerHasApproved
```

**New field needed**:

```swift
var publishedAt: Date?    // When PR was published / made available for review (from GitHub)
```

No `createdAt` field is needed — `publishedAt` is used directly.

**SLA computation** (computed property or method on `PullRequest`):

```swift
/// Whether this PR has exceeded the given SLA deadline.
/// Returns false when publishedAt is nil (PR not yet published / still a draft).
func isSLAExceeded(hours: Int, now: Date = .now) -> Bool {
    guard let published = publishedAt else { return false }
    let deadline = published.addingTimeInterval(TimeInterval(hours) * 3600)
    return now > deadline
}

/// How long since the PR was published (for display purposes).
/// Returns nil when publishedAt is nil.
func slaDuration(now: Date = .now) -> TimeInterval? {
    guard let published = publishedAt else { return nil }
    return now.timeIntervalSince(published)
}
```

**Important**: These methods are pure computations used for **display purposes only**. They do not affect filtering, readiness classification, or section placement. When `publishedAt` is nil, the SLA badge simply doesn't render — no fallback needed.

### 5. GraphQL Query: What Needs to Change

Current query fragment (`Sources/GitHub/GitHubService.swift:219-265`):

```graphql
... on PullRequest {
    number
    title
    author { login }
    isDraft
    state
    url
    # ... (no timestamp fields)
}
```

**Minimal addition**:

```graphql
... on PullRequest {
    number
    title
    publishedAt    # NEW — when PR was made available for review
    author { login }
    isDraft
    state
    url
    # ... rest unchanged ...
}
```

**Response type changes** (`Sources/GitHub/GraphQLResponse.swift`):

```swift
struct PRNode: Codable {
    // ... existing fields ...
    let publishedAt: String?   // NEW — ISO8601 DateTime
}
```

**Conversion changes** (`Sources/GitHub/GitHubService+NodeConversion.swift`):

Parse the ISO8601 string into a `Date?` using `ISO8601DateFormatter` during the `convertNode()` call. Pass `nil` through when the field is absent.

### 6. Reviews Tab UI: Where SLA Indicators Would Appear

The Reviews tab currently renders PRs in two readiness sections ("Ready for Review" / "Not Ready") with repo groups inside each section (`Sources/App/ContentView.swift:154-177`).

Each PR is displayed via `PRRowView` (`Sources/App/PRRowView.swift`), which has a badges row (line 58-73):

```
[stateBadge] [conflictBadge] [ciBadge] [reviewBadge] [approvalCountBadge] [Spacer] [headSHA]
```

#### SLA is Display-Only (No Filtering)

SLA **does not** filter or hide PRs. Unlike `hideDrafts` / `hideApprovedByMe` / `hideNotReady` (which remove PRs from the list), SLA is purely visual — all PRs remain visible. However, SLA **does** organize PRs into sections and add badges:

- No PRs are hidden or removed because of SLA status
- SLA does not affect `applyReviewFilters()`
- The `reviewSLAHours` setting controls whether SLA sections and badges appear, not whether PRs are shown

#### SLA Sections: Grouping by SLA Status

Similar to how the Reviews tab already groups PRs into "Ready for Review" and "Not Ready" sections, SLA would add an additional grouping layer. When SLA is enabled, PRs in the "Ready for Review" section could be further split into:

- **SLA Exceeded** — PRs where `publishedAt` + SLA threshold < now. Visually urgent (red/warning styling).
- **Within SLA** — PRs still within the deadline. Normal styling.

This follows the existing `readinessSection` pattern in `ContentView` (`Sources/App/ContentView.swift:183-209`). The SLA sections would use the same collapsible header, status dots, and repo-grouped subsections — just with SLA-based partitioning instead of readiness-based.

**Possible section hierarchy** (when SLA is enabled):

```
Reviews Tab
├── ⚠️ SLA Exceeded (2)                    ← new section, visually urgent
│   ├── org/repo-a (1)
│   │   └── PR #123 - Fix login        [Open] [CI ✓] [SLA: 3d overdue]
│   └── org/repo-b (1)
│       └── PR #456 - Add tests        [Open] [CI ✓] [SLA: 12h overdue]
│
├── ✅ Ready for Review (3)
│   ├── org/repo-a (1)
│   │   └── PR #789 - New feature      [Open] [CI ✓]
│   └── org/repo-c (2)
│       └── ...
│
└── ⏳ Not Ready (1)
    └── ...
```

**Design question for implementation**: Should "SLA Exceeded" be a top-level section alongside Ready/Not Ready? Or a sub-grouping within "Ready for Review" only? Both approaches use the same `readinessSection` mechanics. The top-level approach is more visually prominent; the sub-grouping keeps the current two-section structure intact.

#### SLA Badge on Individual PR Rows

In addition to sections, each PR row gets an SLA badge in the badges row. The existing `badgePill` helper (PRRowView:253-279) can be reused for consistent styling.

**Badge design options**:

1. **SLA-exceeded badge**: Only show a badge when SLA is breached (e.g., red "SLA: 2d overdue")
2. **Countdown/elapsed hybrid**: Show time elapsed, colored green when within SLA and red when exceeded
3. **Time-since badge**: Always show elapsed time (e.g., "2h ago", "3d ago") — informational, no judgment

### 7. Notification Patterns: SLA Breach Alerts

The existing `StatusChangeDetector` (`Sources/Notifications/StatusChangeDetector.swift:18-62`) provides a pattern for SLA notifications:

- It tracks `previousCIStates` and `previousPRIds` across refresh cycles
- On each poll, it diffs current state against previous and emits `StatusNotification` values
- Notifications are delivered via `NotificationServiceProtocol.send(title:body:url:)`

**SLA notification approach**:

1. Track which PRs have already triggered an SLA breach notification (to avoid duplicate alerts)
2. On each refresh cycle, check review PRs: if `isSLAExceeded(hours:)` is true and the PR hasn't been notified yet, emit a notification
3. Store the set of "already notified" PR IDs in a `Set<String>` (similar to `previousPRIds`)
4. Clear a PR from the notified set when it disappears from the review list (review completed or PR closed)

This fits cleanly into `PRManager.checkForStatusChanges()` or a parallel method.

### 8. Data Flow for SLA Feature

```
GitHubService (GraphQL query with publishedAt)
  → PRNode (new optional String field)
    → convertNode() (parse ISO8601 → Date?)
      → PullRequest (new publishedAt: Date?)
        → PRManager.reviewPRs
          → ContentView
              ├── SLA section partitioning (new: split ready PRs by SLA status)
              └── PRRowView (SLA badge using isSLAExceeded + filterSettings.reviewSLAHours)

FilterSettings.reviewSLAHours
  → SettingsView (configurable via picker)
    → PRManager.filterSettings.didSet → SettingsStore (persisted as JSON)
      → ContentView (SLA sections) + PRRowView (SLA badge)
```

Note: `applyReviewFilters()` is **not touched** by SLA — no PRs are hidden. SLA adds a partitioning step (similar to the existing readiness partitioning) and badges. Reviews tab only.

### 9. Sorting and Grouping Options

The existing `PRGrouping.grouped()` (`Sources/Models/PRGrouping.swift:17-38`) sorts by `reviewSortPriority` then `approvalCount` on the Reviews tab. SLA-exceeded PRs could optionally sort higher (more urgent) by modifying the sort comparator or adding an SLA-aware sort priority.

### 10. Deep-Dive: `publishedAt` Semantics and Unknowns

`publishedAt` is the preferred timestamp for SLA because it semantically represents "when the PR became available for review." However, GitHub's documentation is sparse, and several behaviors are unconfirmed.

#### What GitHub Documents

The `publishedAt` field comes from the `UpdatableComment` interface (which `PullRequest` implements). The schema description is:

> "Identifies when the comment was published at."

- **Type**: `DateTime` (nullable)
- **Source**: [GitHub GraphQL PullRequest](https://docs.github.com/en/graphql/reference/objects#pullrequest), [octokit/graphql-schema](https://github.com/octokit/graphql-schema/blob/main/schema.graphql)

The generic "comment" phrasing is because the interface is shared across `PullRequest`, `Issue`, `IssueComment`, etc. For pull requests specifically, "published" is widely understood as when the PR was first made available for review.

#### What We Know

- `publishedAt` is `DateTime` (nullable) — it can be null
- A PR **can** go back to draft after being published ([GitHub docs: Changing the stage of a pull request](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/changing-the-stage-of-a-pull-request))
- There is no REST API equivalent for `publishedAt`

#### What We Don't Know (Needs Empirical Testing)

These are the key unknowns that should be tested against real GitHub PRs before implementation:

| Question | Possible Answers | Impact on SLA |
|----------|-----------------|---------------|
| Is `publishedAt` null for PRs that were never drafts? | (a) null, (b) equals `createdAt` | If (a): our `publishedAt ?? createdAt` fallback is correct. If (b): we can simplify to just `publishedAt`. |
| What happens to `publishedAt` when a PR goes draft → ready → draft → ready? | (a) First publish time, (b) Last publish time, (c) Cleared when going back to draft | If (a): SLA clock starts from original publish. If (b): SLA clock resets on re-publish. If (c): need to handle null during draft state. |
| Is `publishedAt` set when a non-draft PR is created? | (a) Set to creation time, (b) null | Same as question 1 from the PR creation angle. |

#### Recommended Empirical Tests

Before implementing, run these GraphQL queries against real repos to confirm behavior:

1. **Non-draft PR**: Create a PR directly (not as draft). Query `publishedAt` — is it null or equal to `createdAt`?
2. **Draft → Ready**: Create a draft PR, then mark ready for review. Query `publishedAt` — does it match the "mark ready" time?
3. **Draft → Ready → Draft → Ready**: Create a draft, mark ready, convert back to draft, mark ready again. Query `publishedAt` — first publish time or second?
4. **Draft → Ready → Draft (still draft)**: While the PR is currently a draft (after being published once), query `publishedAt` — is it null or the previous publish time?

Example test query:

```graphql
query {
  repository(owner: "YOUR_ORG", name: "YOUR_REPO") {
    pullRequest(number: 123) {
      createdAt
      publishedAt
      isDraft
      state
    }
  }
}
```

#### Implementation Approach: `publishedAt` Only, No Fallback

We use `publishedAt` directly with no `createdAt` fallback. When `publishedAt` is nil, the SLA badge simply doesn't render — this means "the PR hasn't been published for review yet, so no SLA applies." This is the correct behavior:

- **Draft PRs**: `publishedAt` is likely null → no SLA badge → correct (drafts aren't reviewable)
- **Non-draft PRs**: `publishedAt` should be set → SLA badge renders → correct
- **Draft→Ready→Draft cycle**: If `publishedAt` is cleared when going back to draft → no SLA badge during draft → correct

If edge cases arise where `publishedAt` is unexpectedly null for a non-draft PR, we accept that the SLA badge won't show rather than introducing a `createdAt` fallback that muddies the semantics. The empirical tests in section above can confirm whether this edge case exists in practice.

## Code References

- `Sources/Models/Models.swift:6-30` — `PullRequest` struct (no date fields today)
- `Sources/Models/Models.swift:23` — `lastFetched: Date` (only date, set to `Date()` at fetch time)
- `Sources/Models/Models.swift:217-264` — `FilterSettings` (pattern for adding new config)
- `Sources/Models/Models.swift:243-251` — Custom `init(from decoder:)` with `decodeIfPresent`
- `Sources/GitHub/GitHubService.swift:219-265` — GraphQL query (no timestamp fields)
- `Sources/GitHub/GraphQLResponse.swift:34-49` — `PRNode` (no date fields)
- `Sources/GitHub/GitHubService+NodeConversion.swift:7-65` — Node → PullRequest conversion
- `Sources/App/PRRowView.swift:58-73` — Badges row (where SLA badge would go)
- `Sources/App/PRRowView.swift:253-279` — `badgePill` helper (reusable for SLA badge)
- `Sources/App/ContentView.swift:42-57` — Readiness partitioning
- `Sources/App/ContentView.swift:154-177` — Reviews readiness list rendering
- `Sources/App/PRManager.swift:78-80` — `filterSettings` with `didSet` persistence
- `Sources/App/PRManager.swift:325-340` — `checkForStatusChanges` (notification pattern)
- `Sources/Notifications/StatusChangeDetector.swift:18-62` — Diff-based change detection pattern
- `Sources/App/SettingsView.swift:88-96` — Review Readiness settings section
- `Sources/Models/PRStatusSummary.swift:67-78` — `countdownLabel` (time math pattern)
- `Sources/App/PollingScheduler.swift:20-33` — Polling loop (SLA checks piggyback on this)

## Architecture Documentation

### Established Patterns Relevant to SLA

1. **Settings live in `FilterSettings`** — All review-tab-specific preferences are stored in this Codable struct, persisted as JSON via UserDefaults. New properties use `decodeIfPresent` for backward compatibility.

2. **Raw data preserved, computation at view layer** — `GitHubService` fetches raw data, `PullRequest` stores it truthfully, and user preferences (like ignored checks) are applied via computed methods at the view layer. SLA follows this: store `publishedAt` as raw data, compute SLA status via methods that accept the threshold.

3. **`PRRowView` uses display properties** — The pattern of `displayCIStatus`, `displayFailedChecks`, etc. (computed from raw data + settings) is the right approach for SLA. An `slaBadge` computed view would check `isSLAExceeded(hours: filterSettings.reviewSLAHours)`.

4. **Notifications use diff-based detection** — `StatusChangeDetector` compares previous state to current state and emits notifications only on transitions. SLA breach notification should follow this: track "already notified" PRs, only notify on first breach.

5. **Settings flow through `PRManager`** — `SettingsView` mutates `manager.filterSettings` → `didSet` saves → SwiftUI reactivity re-evaluates views. No manual refresh is needed.

### Timestamp Decision

**`publishedAt` only** — no `createdAt` fallback:
- `publishedAt` is the semantically correct field — it represents when the PR became available for review
- Aligns with how other SLA metrics are typically calculated
- Adds only 1 scalar field to the GraphQL query (near-zero performance impact)
- No pagination concerns (unlike timeline events)
- When `publishedAt` is null, SLA simply doesn't apply (correct for drafts)
- Can be upgraded to timeline-based precision later if needed

### Configuration Design

A single `reviewSLAHours: Int?` property (nil = disabled) is simpler and more ergonomic than a separate enable toggle + value. The Settings UI would use a picker or stepper:

- Off (nil)
- 4 hours
- 8 hours (1 business day)
- 24 hours
- 48 hours
- Custom (text field)

### SLA Badge Design (Display-Only)

The SLA badge renders alongside existing badges in the `PRRowView` badges row. It does not affect filtering — all PRs remain visible.

Recommended: a `badgePill` that shows when SLA is exceeded, using the same pattern as existing badges:

```swift
@ViewBuilder
private var slaBadge: some View {
    if let slaHours = reviewSLAHours,
       pullRequest.isSLAExceeded(hours: slaHours) {
        let elapsed = pullRequest.slaDuration()
        badgePill(
            icon: "exclamationmark.triangle.fill",
            text: formatSLAOverdue(elapsed ?? 0, slaHours: slaHours),
            color: .red
        )
    }
}
```

For a gentler approach, show elapsed time always (green within SLA, red when exceeded):

```swift
@ViewBuilder
private var slaBadge: some View {
    if let slaHours = reviewSLAHours,
       let elapsed = pullRequest.slaDuration() {
        let exceeded = pullRequest.isSLAExceeded(hours: slaHours)
        badgePill(
            icon: exceeded ? "exclamationmark.triangle.fill" : "clock",
            text: formatElapsed(elapsed),
            color: exceeded ? .red : .secondary
        )
    }
}
```

In both cases, the badge is additive — it appears alongside `stateBadge`, `ciBadge`, `reviewBadge`, etc. without hiding any existing information. The badge only renders when `publishedAt` is non-nil (PR has been published).

## Related Research

- `thoughts/shared/plans/2026-02-17-ready-not-ready-review-sections.md` — Readiness sections implementation plan (established the readiness partitioning and `isReady()` patterns)
- `thoughts/shared/plans/2026-02-17-ignored-ci-checks-contrapositive.md` — Ignored CI checks plan (established the effective-values pattern on `PullRequest`)
- `thoughts/shared/research/2026-02-17-ignored-repositories.md` — Ignored repositories research

## Resolved Questions

1. **~~Which timestamp approach?~~** — Use `publishedAt` directly, no `createdAt` fallback. This is the canonical "when did the PR become reviewable" field and aligns with how other SLA metrics are calculated. When `publishedAt` is null, SLA simply doesn't apply.

2. **~~Empirical `publishedAt` testing~~** — Not blocking implementation. We proceed with `publishedAt` directly. The [deep-dive section](#10-deep-dive-publishedat-semantics-and-unknowns) documents the unknowns for reference, but we don't need to resolve them before building — the implementation handles null gracefully.

3. **~~SLA scope~~** — Reviews tab only. SLA is about the reviewer's obligation to respond. My PRs tab is unaffected.

4. **~~Business hours?~~** — Wall-clock hours. Simple, always counting. Business hours could be a future enhancement but adds significant complexity (timezone config, holiday calendars).

5. **~~SLA notification frequency~~** — Decide later. Implement badge and section UI first, add notifications as a follow-up feature.

6. **~~Per-repo SLA?~~** — Global threshold first. Per-repo SLA thresholds are a future enhancement.

7. **~~SLA and readiness interaction~~** — SLA is display-only. It does not filter or hide PRs. It adds visual badges and optionally organizes PRs into SLA sections — but all PRs remain visible.

## Open Questions

1. **SLA section hierarchy** — Should "SLA Exceeded" be a top-level section alongside "Ready for Review" / "Not Ready"? Or a sub-grouping within "Ready for Review" only? The top-level approach is more visually prominent; the sub-grouping keeps the current two-section structure intact. See [section 6](#6-reviews-tab-ui-where-sla-indicators-would-appear) for the mockup.

2. **SLA badge style** — Should the badge show only when SLA is exceeded (red warning), or always show elapsed time (green within SLA, red when exceeded)? The exceeded-only approach is less noisy; the always-show approach is more informational.
