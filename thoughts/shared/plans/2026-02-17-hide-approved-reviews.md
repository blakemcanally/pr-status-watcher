# Hide Already-Approved Reviews — Implementation Plan

## Overview

Add an opt-in toggle to hide PRs on the Reviews tab where the current user has already submitted an approval. This lets reviewers focus on PRs that still need their attention, reducing noise from PRs they've already signed off on. The toggle defaults to **OFF** — the user opts in when they want to narrow their stream.

## Current State Analysis

The Reviews tab shows all PRs where the user's review is requested, grouped into "Ready for Review" and "Not Ready for Review" readiness sections (with repo groups nested within). Filtering is handled by `FilterSettings.applyReviewFilters()`, which currently only supports hiding draft PRs.

**The missing data:** The GraphQL query does **not** fetch the viewer's individual review state. It fetches:
- `reviewDecision` — the overall PR review decision (all reviewers combined)
- `reviews(states: APPROVED, first: 0) { totalCount }` — total approval count across all reviewers

Neither tells us whether **the current user specifically** has approved. To support this feature, we need to add `latestReviews` to the GraphQL query, which returns the most recent review per reviewer with their state.

**Key code locations:**
- `Sources/GitHub/GitHubService.swift:208-261` — `buildSearchQuery()` GraphQL query string
- `Sources/GitHub/GraphQLResponse.swift:34-101` — `PRNode` Codable types
- `Sources/GitHub/GitHubService+NodeConversion.swift:7-56` — `convertNode()` maps PRNode → PullRequest
- `Sources/Models/Models.swift:6-29` — `PullRequest` struct fields
- `Sources/Models/Models.swift:214-247` — `FilterSettings` struct with `applyReviewFilters()`
- `Sources/App/ContentView.swift:22-24` — `filteredPRs` applies filters before readiness split
- `Sources/App/ContentView.swift:118-140` — `prList` routing including `filteredEmptyState`
- `Sources/App/SettingsView.swift:87-93` — "Review Readiness" section with `hideDrafts` toggle
- `Sources/App/Strings.swift:129-137` — `EmptyState` strings (hardcoded to drafts case)

## Desired End State

After implementation:

1. `PullRequest` has a `viewerHasApproved: Bool` field indicating whether the current user's latest review is APPROVED
2. `FilterSettings` has a `hideApprovedByMe: Bool` toggle (default `false`)
3. When enabled, PRs where `viewerHasApproved == true` are removed from **both** Ready and Not Ready sections
4. Settings shows a "Hide PRs I've approved" toggle in the Review Readiness section
5. When all review PRs are hidden because the user approved them all, a distinct empty state is shown: "All caught up" with a checkmark icon and helpful subtitle
6. The GraphQL query fetches `latestReviews` data for all PRs, making the viewer's review state available to the model
7. Every PR row displays the approval count as a subtle green badge (e.g., `person.fill.checkmark` icon + "2") when the PR has at least one approval — visible on both "My PRs" and "Reviews" tabs

**Verification:**
```
Settings: [x] Hide PRs I've approved

Reviews Tab (before toggle):
├── ✅ Ready for Review (3)
│   ├── org/repo-a (2)
│   │   ├── PR #123 - Fix login        [Approved 👤✓3]       ← would be hidden
│   │   └── PR #124 - Add caching      [Review 👤✓1]
│   └── org/repo-b (1)
│       └── PR #456 - Add tests        [Review]
└── ⏳ Not Ready (1)
    └── org/repo-c (1)
        └── PR #101 - New endpoint     [CI pending 👤✓2]     ← would be hidden

Reviews Tab (after toggle enabled):
├── ✅ Ready for Review (2)
│   ├── org/repo-a (1)
│   │   └── PR #124 - Add caching      [Review 👤✓1]
│   └── org/repo-b (1)
│       └── PR #456 - Add tests        [Review]

My PRs Tab (approval count always visible):
├── org/repo-a (2)
│   ├── PR #200 - New feature          [Open] [CI ✓] [Approved 👤✓3]
│   └── PR #201 - Refactor             [Open] [CI ✓] [Review 👤✓1]
```

## What We're NOT Doing

- **Re-review detection** — If the author pushes new commits after your approval and GitHub re-requests your review, we still treat your latest review state as APPROVED (since `latestReviews` returns APPROVED). A future enhancement could cross-reference the review timestamp against the latest commit timestamp to detect stale approvals. For now, the simple "latest review is APPROVED" check is sufficient.
- **Per-reviewer breakdown UI** — We're not showing who approved or which reviewers are pending. We show the aggregate approval count, but not individual reviewer names or states.
- **Applying the filter to the "My PRs" tab** — The hide-approved filter only affects the Reviews tab. However, the approval count badge is shown on both tabs since it's useful context everywhere.
- **Filtering by other review states** — We're not adding "hide PRs where I requested changes" or similar. Just the approval case for now.

## Design Principle: Viewer State via `latestReviews`

GitHub's `latestReviews(first: N)` field returns the most recent review per unique reviewer. This is more accurate than `reviews(states: APPROVED)` for our purpose:

- If the viewer approved, then later submitted "Changes Requested," their latest review state is `CHANGES_REQUESTED` — the PR would **not** be hidden (correct behavior: the viewer has outstanding feedback)
- If the viewer approved and that's still their latest review, the PR is hidden (correct: nothing more for the viewer to do)
- If the viewer submitted only comments (state: `COMMENTED`), the PR is not hidden (correct: commenting isn't approval)

---

## Implementation Approach

Three phases, each independently testable:

1. **Phase 1:** Data layer — GraphQL query expansion, response types, `viewerHasApproved` on PullRequest, node conversion threading, unit tests.
2. **Phase 2:** Filter & settings UI — `hideApprovedByMe` toggle, filter logic, SettingsView toggle, dynamic empty state, strings, unit tests.
3. **Phase 3:** Approval count badge — display the number of approvals on each PR row, visible on both "My PRs" and "Reviews" tabs. No data layer changes needed — `approvalCount` is already on the model.

---

## Phase 1: Data Layer — Viewer Review State

### Overview

Expand the GraphQL query to fetch `latestReviews`, add response types, thread the viewer username through node conversion, and store `viewerHasApproved` on the `PullRequest` model.

### Changes Required

#### 1. Add `latestReviews` to the GraphQL query

**File:** `Sources/GitHub/GitHubService.swift`

In `buildSearchQuery()` (line 208), add `latestReviews` to the PR fragment, after the existing `reviews(states: APPROVED, first: 0) { totalCount }` line (line 228):

```swift
reviews(states: APPROVED, first: 0) { totalCount }
latestReviews(first: 20) {
  nodes {
    author { login }
    state
  }
}
```

The `first: 20` limit covers up to 20 unique reviewers per PR, which is more than sufficient for any practical review team.

#### 2. Add response types for `latestReviews`

**File:** `Sources/GitHub/GraphQLResponse.swift`

Add new Codable types inside `PRNode` (after `ReviewsRef`, around line 62):

```swift
struct LatestReviewNode: Codable {
    let author: AuthorRef?
    let state: String?
}

struct LatestReviewsConnection: Codable {
    let nodes: [LatestReviewNode]
}
```

Add the field to `PRNode` (after the `reviews` property, around line 45):

```swift
let latestReviews: LatestReviewsConnection?
```

#### 3. Add `viewerHasApproved` to `PullRequest`

**File:** `Sources/Models/Models.swift`

Add a new stored property on `PullRequest` (after `checkResults`, line 29):

```swift
var viewerHasApproved: Bool
```

#### 4. Thread viewer username through internal fetch methods

**File:** `Sources/GitHub/GitHubService.swift`

Update the public fetch methods to pass the username through to the shared `fetchPRs`:

```swift
func fetchAllMyOpenPRs(username: String) throws -> [PullRequest] {
    try fetchPRs(searchQuery: "author:\(username) type:pr state:open", viewerUsername: username)
}

func fetchReviewRequestedPRs(username: String) throws -> [PullRequest] {
    try fetchPRs(searchQuery: "review-requested:\(username) type:pr state:open", viewerUsername: username)
}
```

Update the private `fetchPRs` signature (line 99):

```swift
private func fetchPRs(searchQuery: String, viewerUsername: String) throws -> [PullRequest] {
```

Thread through to `fetchPRPage` (line 136):

```swift
private func fetchPRPage(
    escapedQuery: String,
    cursor: String?,
    searchQuery: String,
    viewerUsername: String
) throws -> PRPageResult {
```

And pass to `convertNode` in the `compactMap` (line 184):

```swift
let prs = searchResult.nodes.compactMap { node -> PullRequest? in
    guard let parsed = convertNode(node, viewerUsername: viewerUsername) else {
```

Update all internal call sites to pass the new parameter through.

#### 5. Compute `viewerHasApproved` in `convertNode`

**File:** `Sources/GitHub/GitHubService+NodeConversion.swift`

Update the method signature (line 7):

```swift
func convertNode(_ node: PRNode, viewerUsername: String) -> PullRequest? {
```

Add the viewer approval check before the `return PullRequest(...)` (after line 31):

```swift
let viewerHasApproved: Bool = {
    guard let latestReviews = node.latestReviews?.nodes else { return false }
    return latestReviews.contains { review in
        guard let login = review.author?.login, let state = review.state else { return false }
        return login.caseInsensitiveCompare(viewerUsername) == .orderedSame && state == "APPROVED"
    }
}()
```

Add to the `PullRequest` initializer call (after `checkResults`):

```swift
return PullRequest(
    // ... existing fields ...
    checkResults: checkResult.checkResults,
    viewerHasApproved: viewerHasApproved
)
```

#### 6. Update test fixture

**File:** `Tests/FilterSettingsTests.swift`

Update `PullRequest.fixture()` to include `viewerHasApproved`:

```swift
static func fixture(
    // ... existing parameters ...
    checkResults: [CheckResult] = [],
    viewerHasApproved: Bool = false   // NEW
) -> PullRequest {
    PullRequest(
        // ... existing fields ...
        checkResults: checkResults,
        viewerHasApproved: viewerHasApproved   // NEW
    )
}
```

#### 7. Add `latestReviews` parsing tests

**File:** `Tests/GitHubServiceParsingTests.swift`

Add tests for `convertNode` with `latestReviews` data. These tests need to verify both the node-level fixture and the conversion logic:

```swift
@Test func convertNodeSetsViewerHasApprovedWhenViewerApproved() {
    let node = PRNode.fixture(
        latestReviews: PRNode.LatestReviewsConnection(nodes: [
            PRNode.LatestReviewNode(author: PRNode.AuthorRef(login: "viewer"), state: "APPROVED"),
            PRNode.LatestReviewNode(author: PRNode.AuthorRef(login: "other"), state: "CHANGES_REQUESTED"),
        ])
    )
    let pr = service.convertNode(node, viewerUsername: "viewer")
    #expect(pr?.viewerHasApproved == true)
}

@Test func convertNodeSetsViewerHasApprovedFalseWhenViewerRequestedChanges() {
    let node = PRNode.fixture(
        latestReviews: PRNode.LatestReviewsConnection(nodes: [
            PRNode.LatestReviewNode(author: PRNode.AuthorRef(login: "viewer"), state: "CHANGES_REQUESTED"),
        ])
    )
    let pr = service.convertNode(node, viewerUsername: "viewer")
    #expect(pr?.viewerHasApproved == false)
}

@Test func convertNodeSetsViewerHasApprovedFalseWhenViewerNotInReviews() {
    let node = PRNode.fixture(
        latestReviews: PRNode.LatestReviewsConnection(nodes: [
            PRNode.LatestReviewNode(author: PRNode.AuthorRef(login: "other"), state: "APPROVED"),
        ])
    )
    let pr = service.convertNode(node, viewerUsername: "viewer")
    #expect(pr?.viewerHasApproved == false)
}

@Test func convertNodeSetsViewerHasApprovedFalseWhenNoLatestReviews() {
    let node = PRNode.fixture(latestReviews: nil)
    let pr = service.convertNode(node, viewerUsername: "viewer")
    #expect(pr?.viewerHasApproved == false)
}

@Test func convertNodeViewerMatchIsCaseInsensitive() {
    let node = PRNode.fixture(
        latestReviews: PRNode.LatestReviewsConnection(nodes: [
            PRNode.LatestReviewNode(author: PRNode.AuthorRef(login: "Viewer"), state: "APPROVED"),
        ])
    )
    let pr = service.convertNode(node, viewerUsername: "viewer")
    #expect(pr?.viewerHasApproved == true)
}

@Test func convertNodeCommentedReviewIsNotApproved() {
    let node = PRNode.fixture(
        latestReviews: PRNode.LatestReviewsConnection(nodes: [
            PRNode.LatestReviewNode(author: PRNode.AuthorRef(login: "viewer"), state: "COMMENTED"),
        ])
    )
    let pr = service.convertNode(node, viewerUsername: "viewer")
    #expect(pr?.viewerHasApproved == false)
}
```

Update the `PRNode.fixture()` to accept a `latestReviews` parameter:

```swift
static func fixture(
    // ... existing parameters ...
    latestReviews: LatestReviewsConnection? = nil
) -> PRNode {
    PRNode(
        // ... existing fields ...
        latestReviews: latestReviews
    )
}
```

Update existing `convertNode` test calls to pass the new `viewerUsername` parameter (use `"testuser"` as default):

```swift
// Before:
let pr = service.convertNode(node)
// After:
let pr = service.convertNode(node, viewerUsername: "testuser")
```

### Success Criteria

#### Automated Verification:
- [x] Build succeeds: `swift build`
- [x] All existing tests pass: `swift test`
- [x] New `convertNode` viewer-approval tests pass
- [x] PRNode fixture includes `latestReviews` parameter

**Implementation Note:** After completing this phase and all automated verification passes, proceed to Phase 2.

---

## Phase 2: Filter Logic, Settings UI & Empty State

### Overview

Add the `hideApprovedByMe` toggle to `FilterSettings`, wire it into the filter pipeline, add the Settings UI toggle, and create a context-aware empty state for when all reviews are hidden.

### Changes Required

#### 1. Add `hideApprovedByMe` to `FilterSettings`

**File:** `Sources/Models/Models.swift`

Add the new property to `FilterSettings` (after `hideDrafts`, line 217):

```swift
struct FilterSettings: Codable, Equatable {
    var hideDrafts: Bool
    var hideApprovedByMe: Bool          // NEW
    var requiredCheckNames: [String]
    var ignoredCheckNames: [String]
```

Update the memberwise `init` (line 221):

```swift
init(
    hideDrafts: Bool = true,
    hideApprovedByMe: Bool = false,     // NEW — defaults to OFF
    requiredCheckNames: [String] = [],
    ignoredCheckNames: [String] = []
) {
    self.hideDrafts = hideDrafts
    self.hideApprovedByMe = hideApprovedByMe
    self.requiredCheckNames = requiredCheckNames
    self.ignoredCheckNames = ignoredCheckNames
}
```

Update the custom `init(from decoder:)` (line 233):

```swift
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    hideDrafts = try container.decodeIfPresent(Bool.self, forKey: .hideDrafts) ?? true
    hideApprovedByMe = try container.decodeIfPresent(Bool.self, forKey: .hideApprovedByMe) ?? false
    requiredCheckNames = try container.decodeIfPresent([String].self, forKey: .requiredCheckNames) ?? []
    ignoredCheckNames = try container.decodeIfPresent([String].self, forKey: .ignoredCheckNames) ?? []
}
```

#### 2. Update `applyReviewFilters` to hide approved PRs

**File:** `Sources/Models/Models.swift`

Update `applyReviewFilters(to:)` (line 241):

```swift
func applyReviewFilters(to prs: [PullRequest]) -> [PullRequest] {
    prs.filter { pr in
        if hideDrafts && pr.state == .draft { return false }
        if hideApprovedByMe && pr.viewerHasApproved { return false }
        return true
    }
}
```

#### 3. Add empty state strings

**File:** `Sources/App/Strings.swift`

Update the `EmptyState` enum. Replace the current hardcoded filtered strings (lines 135-136) with context-aware variants:

```swift
enum EmptyState {
    static let loadingTitle = "Loading pull requests…"
    static let noPRsTitle = "No open pull requests"
    static let noPRsSubtitle = "Your open, draft, and queued PRs will appear here automatically"
    static let noReviewsTitle = "No review requests"
    static let noReviewsSubtitle = "Pull requests where your review is requested will appear here"

    // Filtered empty states — shown when filters hide all PRs
    static let filteredDraftsTitle = "All review requests are drafts"
    static let filteredDraftsSubtitle = "Disable \"Hide draft PRs\" in Settings to see them"
    static let filteredApprovedTitle = "All caught up"
    static let filteredApprovedSubtitle = "You've approved all pending review requests"
    static let filteredMixedTitle = "All review requests hidden"
    static let filteredMixedSubtitle = "Adjust your filters in Settings to see them"
}
```

Remove the old `filteredTitle` and `filteredSubtitle` constants once all references are updated.

#### 4. Update `ContentView` filtered empty state

**File:** `Sources/App/ContentView.swift`

Replace the `filteredEmptyState` view (around line 393) with a context-aware version that picks the right message based on which filter is responsible:

```swift
private var filteredEmptyState: some View {
    let (icon, title, subtitle) = filteredEmptyMessage

    return VStack(spacing: 10) {
        Spacer()
        Image(systemName: icon)
            .font(.system(size: 32))
            .foregroundColor(.secondary)
        Text(title)
            .font(.title3)
            .foregroundColor(.secondary)
        Text(subtitle)
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        Spacer()
    }
    .frame(maxWidth: .infinity)
    .accessibilityLabel("All review requests hidden by filters")
}

/// Determine the appropriate empty state message based on active filters.
private var filteredEmptyMessage: (icon: String, title: String, subtitle: String) {
    let settings = manager.filterSettings
    let allDrafts = activePRs.allSatisfy { $0.state == .draft }
    let allApproved = activePRs.allSatisfy { $0.viewerHasApproved }

    if settings.hideApprovedByMe && allApproved {
        return (
            "checkmark.circle",
            Strings.EmptyState.filteredApprovedTitle,
            Strings.EmptyState.filteredApprovedSubtitle
        )
    } else if settings.hideDrafts && allDrafts {
        return (
            "line.3.horizontal.decrease.circle",
            Strings.EmptyState.filteredDraftsTitle,
            Strings.EmptyState.filteredDraftsSubtitle
        )
    } else {
        return (
            "line.3.horizontal.decrease.circle",
            Strings.EmptyState.filteredMixedTitle,
            Strings.EmptyState.filteredMixedSubtitle
        )
    }
}
```

#### 5. Add toggle to `SettingsView`

**File:** `Sources/App/SettingsView.swift`

In the "Review Readiness" section (around line 87-93), add the new toggle after the existing "Hide draft PRs" toggle:

```swift
// Review Readiness Section (general)
VStack(alignment: .leading, spacing: 8) {
    Text(Strings.Readiness.settingsTitle)
        .font(.headline)

    Toggle("Hide draft PRs", isOn: filterBinding(\.hideDrafts))
    Toggle("Hide PRs I've approved", isOn: filterBinding(\.hideApprovedByMe))
}
```

The existing `filterBinding` helper already supports any `WritableKeyPath<FilterSettings, Bool>`, so no additional helper code is needed.

#### 6. Add `FilterSettings` unit tests

**File:** `Tests/FilterSettingsTests.swift`

Add to `FilterSettingsDefaultsTests`:

```swift
@Test func defaultHideApprovedByMeIsFalse() {
    #expect(!FilterSettings().hideApprovedByMe)
}
```

Add to `FilterSettingsCodableTests`:

```swift
@Test func codableRoundTripWithHideApprovedByMe() throws {
    let original = FilterSettings(hideApprovedByMe: true)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(FilterSettings.self, from: data)
    #expect(decoded.hideApprovedByMe)
}

@Test func decodingWithoutHideApprovedByMeDefaultsToFalse() throws {
    let json = #"{"hideDrafts": true}"#.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(FilterSettings.self, from: json)
    #expect(!decoded.hideApprovedByMe)
}
```

Add to `FilterPredicateTests`:

```swift
@Test func hideApprovedByMeFiltersApprovedPRs() {
    let settings = FilterSettings(hideDrafts: false, hideApprovedByMe: true)
    let prs = [
        PullRequest.fixture(number: 1, viewerHasApproved: true),
        PullRequest.fixture(number: 2, viewerHasApproved: false),
        PullRequest.fixture(number: 3, viewerHasApproved: true),
    ]
    let result = settings.applyReviewFilters(to: prs)
    #expect(result.count == 1)
    #expect(result.first?.number == 2)
}

@Test func hideApprovedByMeDisabledShowsAllPRs() {
    let settings = FilterSettings(hideDrafts: false, hideApprovedByMe: false)
    let prs = [
        PullRequest.fixture(number: 1, viewerHasApproved: true),
        PullRequest.fixture(number: 2, viewerHasApproved: false),
    ]
    let result = settings.applyReviewFilters(to: prs)
    #expect(result.count == 2)
}

@Test func hideApprovedByMeDoesNotAffectNonApprovedPRs() {
    let settings = FilterSettings(hideApprovedByMe: true)
    let prs = [PullRequest.fixture(viewerHasApproved: false)]
    let result = settings.applyReviewFilters(to: prs)
    #expect(result.count == 1)
}
```

Add to `FilterCombinationTests`:

```swift
@Test func hideDraftsAndHideApprovedCombined() {
    let settings = FilterSettings(hideDrafts: true, hideApprovedByMe: true)
    let prs = [
        PullRequest.fixture(number: 1, state: .draft, viewerHasApproved: false),
        PullRequest.fixture(number: 2, state: .open, viewerHasApproved: true),
        PullRequest.fixture(number: 3, state: .open, viewerHasApproved: false),
        PullRequest.fixture(number: 4, state: .draft, viewerHasApproved: true),
    ]
    let result = settings.applyReviewFilters(to: prs)
    #expect(result.count == 1)
    #expect(result.first?.number == 3)
}

@Test func allPRsApprovedAndHiddenReturnsEmpty() {
    let settings = FilterSettings(hideDrafts: false, hideApprovedByMe: true)
    let prs = [
        PullRequest.fixture(number: 1, viewerHasApproved: true),
        PullRequest.fixture(number: 2, viewerHasApproved: true),
    ]
    let result = settings.applyReviewFilters(to: prs)
    #expect(result.isEmpty)
}
```

Add to `FilterSettingsPersistenceTests`:

```swift
@Test func persistAndReloadHideApprovedByMeViaUserDefaults() throws {
    let original = FilterSettings(hideApprovedByMe: true)
    let data = try JSONEncoder().encode(original)
    UserDefaults.standard.set(data, forKey: testKey)

    let loaded = try #require(UserDefaults.standard.data(forKey: testKey))
    let decoded = try JSONDecoder().decode(FilterSettings.self, from: loaded)
    #expect(decoded.hideApprovedByMe)
}
```

### Success Criteria

#### Automated Verification:
- [x] Build succeeds: `swift build`
- [x] All existing tests pass: `swift test`
- [x] New `FilterSettings` default, codable, predicate, and persistence tests pass
- [x] New filter combination tests pass

**Implementation Note:** After completing this phase and all automated verification passes, proceed to Phase 3.

---

## Phase 3: Approval Count Badge

### Overview

Display the number of approvals on each PR row as a subtle badge. This uses the existing `approvalCount` field on `PullRequest` — already populated from the GraphQL query — so no data layer changes are needed. The badge is visible on **both** tabs since knowing how many approvals a PR has is useful context for both authors and reviewers.

**Note:** This phase has no dependency on Phases 1 or 2. It can be implemented independently, even before the other phases, since `approvalCount` is already available on the model.

### Changes Required

#### 1. Add approval count badge to `PRRowView`

**File:** `Sources/App/PRRowView.swift`

Add a new `approvalCountBadge` computed property (after `reviewBadge`, around line 173):

```swift
// MARK: - Approval Count Badge

@ViewBuilder
private var approvalCountBadge: some View {
    if pullRequest.approvalCount > 0 {
        badgePill(
            icon: "person.fill.checkmark",
            text: "\(pullRequest.approvalCount)",
            color: .green
        )
    }
}
```

**Design rationale:**
- Uses `person.fill.checkmark` (SF Symbols 4, macOS 13+) to visually distinguish from the review decision badge (`checkmark.circle.fill`) — the person icon communicates "N people approved" rather than "overall approval state"
- Green color matches the positive semantic of approvals
- Only shown when `approvalCount > 0` — no badge clutter for PRs with zero approvals
- The text is just the count number (e.g., "2") — concise and scannable

#### 2. Add the badge to the badge row

**File:** `Sources/App/PRRowView.swift`

In the status badges row (line 58-72), add `approvalCountBadge` after the review badge conditional and before the `Spacer()`:

```swift
// Status badges row — prioritize actionable info
// Review badge only shown when CI is passing or unknown (not actionable during failure/pending)
HStack(spacing: 6) {
    stateBadge
    conflictBadge
    ciBadge
    if pullRequest.state != .draft &&
        (displayCIStatus == .success || displayCIStatus == .unknown) {
        reviewBadge
    }
    approvalCountBadge
    Spacer()
    if !pullRequest.headSHA.isEmpty {
        Text(pullRequest.headSHA)
            .font(.system(.caption2, design: .monospaced))
            .foregroundColor(.secondary.opacity(0.6))
    }
}
```

The approval count badge is **not** gated by the CI status or draft conditions — it's always visible when there are approvals. This is intentional: even when CI is failing, knowing a PR has 3 approvals is useful context.

#### 3. Add accessibility label

The badge inherits the pill's text content, but we should ensure the accessibility label on the row includes approval info. Update the existing accessibility label on the outer `Button` (line 117):

```swift
.accessibilityLabel(
    "\(pullRequest.title), \(pullRequest.displayNumber) by \(pullRequest.author), \(stateText)"
    + (pullRequest.approvalCount > 0 ? ", \(pullRequest.approvalCount) approvals" : "")
)
```

### Success Criteria

#### Automated Verification:
- [x] Build succeeds: `swift build`
- [x] All existing tests pass: `swift test`

**Implementation Note:** After completing this phase and all automated verification passes, proceed to manual verification.

---

## Testing Strategy

### Unit Tests (automated, per phase)

**Phase 1:**
- `GitHubServiceParsingTests` — `convertNode` with `latestReviews` data: viewer approved, viewer requested changes, viewer not in reviews, no reviews, case-insensitive match, COMMENTED state

**Phase 2:**
- `FilterSettingsDefaultsTests` — `hideApprovedByMe` defaults to `false`
- `FilterSettingsCodableTests` — round-trip encoding, backward-compatible decoding from JSON without the new key
- `FilterPredicateTests` — `hideApprovedByMe` filters approved PRs, doesn't affect non-approved PRs
- `FilterCombinationTests` — combined `hideDrafts + hideApprovedByMe`, all-approved-and-hidden edge case
- `FilterSettingsPersistenceTests` — UserDefaults round-trip

**Phase 3:**
- No new unit tests required — the badge is a pure view layer addition using the existing `approvalCount` field, which is already tested in `GitHubServiceParsingTests` (node conversion populates it from `reviews.totalCount`)

### Manual Verification

After all three phases pass automated verification, confirm the following manually. The feature is complete once all items are checked.

#### Hide-Approved Filter (Phase 2)

- [ ] Settings shows "Hide PRs I've approved" toggle in the Review Readiness section
- [ ] Toggle defaults to OFF on fresh install
- [ ] Enabling the toggle hides PRs where the viewer's latest review is APPROVED from both Ready and Not Ready sections
- [ ] Disabling the toggle shows all review PRs again
- [ ] PRs where the viewer submitted "Changes Requested" (not APPROVED) are NOT hidden
- [ ] PRs where the viewer only commented (COMMENTED) are NOT hidden
- [ ] PRs where a different reviewer approved (but not the viewer) are NOT hidden
- [ ] When all reviews are approved and the toggle is on, the "All caught up" empty state appears with the checkmark icon
- [ ] When all reviews are drafts and hide-drafts is on, the existing drafts empty state message still appears
- [ ] When both filters cause the empty state, the generic "All review requests hidden" message appears
- [ ] Toggle state persists across app restart
- [ ] "My PRs" tab is completely unaffected by this toggle

#### Filter Combinations

- [ ] Enable both "Hide draft PRs" and "Hide PRs I've approved" → verify both filters work together (only non-draft, non-approved PRs remain)
- [ ] Approve a PR in GitHub → wait for refresh (or click refresh) → PR disappears from Reviews tab (with toggle on)
- [ ] On a PR you approved, submit "Changes Requested" in GitHub → refresh → PR reappears (your latest review is no longer APPROVED)

#### Approval Count Badge (Phase 3)

- [ ] PR rows with approvals show the approval count badge (green pill with person+checkmark icon and count number)
- [ ] PR rows with zero approvals do NOT show the badge
- [ ] Badge appears on both "My PRs" and "Reviews" tabs
- [ ] Badge is visible even when CI is failing or pending (not gated by CI status)
- [ ] Badge is visible on draft PRs that have prior approvals
- [ ] Badge visually distinguishes from the "Approved" review decision badge (different icon: person vs checkmark-circle)
- [ ] A PR with `reviewDecision: .approved` and `approvalCount: 3` shows both "Approved" badge and "3" count badge — not redundant (one is status, one is count)
- [ ] A PR with `reviewDecision: .reviewRequired` and `approvalCount: 1` shows "Review" badge and "1" count badge — communicates "partially approved, needs more"
- [ ] Badge is compact and doesn't cause layout overflow on narrow popover widths

---

## Performance Considerations

- The `latestReviews(first: 20)` addition to the GraphQL query adds a small amount of data per PR (20 review nodes max, each with a login and state string). This is negligible compared to the existing check status data.
- The viewer-match computation in `convertNode` is O(r) where r = number of unique reviewers per PR (typically < 10). No optimization needed.
- `applyReviewFilters` adds one additional boolean check per PR — O(1) per PR.

---

## Migration Notes

- **No breaking changes to persisted data.** `FilterSettings` uses `decodeIfPresent` for `hideApprovedByMe`, defaulting to `false` when reading previously-saved JSON that doesn't include the key.
- **`viewerHasApproved`** is populated on the next fetch cycle. No stored PR data needs migration — all PR data is fetched fresh from GitHub on each refresh.
- **No protocol changes.** `GitHubServiceProtocol` method signatures are unchanged. Only internal private methods are modified to thread the viewer username.
- **Existing tests.** The `convertNode` calls in existing tests need the new `viewerUsername` parameter added (use `"testuser"` as a neutral default). The `PullRequest.fixture()` gains `viewerHasApproved` with a `false` default, so existing test call sites don't need changes.

---

## References

- README future improvements: line 219, "Hide already-approved PRs on the Reviews tab"
- Research: `thoughts/shared/research/2026-02-17-ready-not-ready-review-sections.md` (readiness sections architecture)
- Research: `thoughts/shared/research/2026-02-17-ignored-ci-checks-contrapositive.md` (effective-properties pattern)
- Existing plan: `thoughts/shared/plans/2026-02-17-ready-not-ready-review-sections.md` (readiness sections implementation)
- Existing plan: `thoughts/shared/plans/2026-02-17-ignored-ci-checks-contrapositive.md` (ignored checks implementation)
