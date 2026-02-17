---
date: 2026-02-11T00:04:11Z
researcher: Blake McAnally
git_commit: fb6b1c4757cf0fc01e517da1a550bba7b3148caf
branch: main
repository: blakemcanally/pr-status-watcher
topic: "Feature ideas and extension opportunities for PR Status Watcher"
tags: [research, features, launcher, enhancements, roadmap]
status: complete
last_updated: 2026-02-10
last_updated_by: Blake McAnally
---

# Research: Feature Ideas and Extension Opportunities

**Date**: 2026-02-11T00:04:11Z
**Researcher**: Blake McAnally
**Git Commit**: fb6b1c4757cf0fc01e517da1a550bba7b3148caf
**Branch**: main
**Repository**: blakemcanally/pr-status-watcher

## Research Question
What features would be useful to add to PR Status Watcher? Including possibly a launcher to open a PR in another tool.

## Summary

The app is currently a focused, read-only PR status monitor. Every user action ultimately either refreshes data or opens a URL in the default browser via `NSWorkspace.shared.open()`. There are no keyboard shortcuts, no way to choose which tool opens the PR, no click-to-open on notifications, and no quick actions beyond "Open in Browser" and "Copy URL". The GraphQL query already fetches data (branch names via `headRefOid`, review state, merge queue position) that could power richer interactions, and the GitHub API has many more fields available (labels, timestamps, additions/deletions, comments) that aren't queried yet.

Below are feature ideas organized by category, with implementation notes rooted in the current architecture.

---

## Detailed Findings

### 1. Open-In Launcher (User's Specific Ask)

Currently, every "open" action goes through `NSWorkspace.shared.open(url)` which delegates to the system default browser. There is no way to choose a target tool.

**Proposed: "Open In..." context menu or submenu**

The context menu on each PR row (`ContentView.swift:92-99`) currently has two items: "Open in Browser" and "Copy URL". This could be extended with:

| Open-In Target | What It Would Do | Implementation |
|---------------|------------------|----------------|
| **Specific browser** | Open PR URL in Safari, Chrome, Firefox, Arc, etc. | `NSWorkspace.shared.open(url, withAppBundleIdentifier:)` or `NSWorkspace.shared.open([url], withApplicationAt:)` |
| **GitHub Desktop** | Open the repo in GitHub Desktop | `x-github-client://openRepo/{repoURL}` URL scheme |
| **Terminal / iTerm** | `cd` to local clone + `git checkout {branch}` | Run `git clone` check, then `open -a Terminal` with a script, or AppleScript |
| **VS Code** | Open repo folder in VS Code | `code --goto {localPath}` or `vscode://` URL scheme |
| **Xcode** | Open `.xcodeproj`/`.xcworkspace` in repo | `open -a Xcode {path}` |
| **Fork (Git client)** | Open repo in Fork | `fork://open/{path}` URL scheme |
| **Tower (Git client)** | Open repo in Tower | `gittower://openRepo/{path}` URL scheme |

**Key design decisions:**

- The app currently has no concept of local repo paths. It only knows remote URLs (`pullRequest.url`). To open in an IDE or terminal, the app would need to either (a) discover local clones by scanning common directories or running `gh repo view --json path`, or (b) let the user configure local checkout paths per repo in settings.
- For browser-only targets, no local path is needed — just the URL + a bundle identifier.
- A "configured launchers" section in `SettingsView` would let users pick which tools appear in the context menu. The current settings view (`SettingsView.swift`) only has auth status and refresh interval, so there's room to add a section.
- The GraphQL query already fetches `headRefOid` (commit SHA) but not `headRefName` (branch name). Adding `headRefName` to the query would enable "checkout this branch" workflows.

**Simplest starting point:** Add "Open in..." submenu to the existing context menu with detected installed browsers (scan `/Applications` for known browser bundle IDs).

---

### 2. Keyboard Shortcuts

No keyboard shortcuts exist anywhere in the codebase. Potential additions:

| Shortcut | Action | Scope |
|----------|--------|-------|
| `Cmd+R` | Refresh all PRs | ContentView |
| `Cmd+,` | Open Settings | ContentView |
| `Cmd+Q` | Quit | ContentView |
| Global hotkey | Toggle menu bar window | App-wide (requires `CGEvent` or third-party like HotKey) |
| `Cmd+1..9` | Open Nth PR in browser | ContentView |
| `Cmd+C` | Copy URL of selected PR | ContentView (would need selection state) |
| `Escape` | Close menu bar window | ContentView |

SwiftUI supports `.keyboardShortcut()` on buttons — the existing Refresh, Settings, and Quit buttons could get shortcuts with one-line additions.

---

### 3. Notification Click-to-Open

The app sends notifications with `userInfo["url"]` set (`PRManager.swift:255-257`) but never sets a `UNUserNotificationCenterDelegate`. This means clicking a notification does nothing beyond bringing the app forward.

**Fix:** Set a `UNUserNotificationCenterDelegate` (on `AppDelegate` or a dedicated object), implement `userNotificationCenter(_:didReceive:withCompletionHandler:)`, extract the URL from `userInfo`, and call `NSWorkspace.shared.open(url)`.

This is a small but high-value improvement — users already get notifications but can't act on them.

---

### 4. Additional Notification Triggers

Currently only three events trigger notifications (`PRManager.swift:217-245`):
- CI pending → failure
- CI pending → success
- PR disappeared (no longer open)

Additional triggers the app could fire:

| Event | Detection Method |
|-------|-----------------|
| **Review approved** | Track `reviewDecision` changes like CI states |
| **Changes requested** | Same — `reviewDecision` changed to `.changesRequested` |
| **Merge conflicts appeared** | Track `mergeable` changes from `.mergeable` → `.conflicting` |
| **Merge queue position changed** | Track `queuePosition` changes |
| **PR merged** | Track `state` changes from `.open` → `.merged` |
| **New PR opened (by me)** | New PR ID appears that wasn't in previous set |

The existing `checkForStatusChanges` pattern (compare `previousCIStates` dict) would extend naturally to track `previousReviewStates`, `previousMergeableStates`, etc.

---

### 5. Watch PRs Beyond "My Open PRs"

Currently, the GraphQL query is hardcoded to `author:USERNAME type:pr state:open` (`GitHubService.swift:46`). The app only watches PRs the user authored. Useful extensions:

| Watch Mode | GraphQL Query Change | Use Case |
|------------|---------------------|----------|
| **PRs I'm reviewing** | `review-requested:USERNAME type:pr state:open` or `reviewed-by:USERNAME` | Track PRs you need to review |
| **PRs in specific repos** | `repo:owner/name type:pr state:open` | Monitor team repos |
| **PRs by teammates** | `author:TEAMMATE type:pr state:open` | Track team activity |
| **Recently merged** | `author:USERNAME type:pr state:closed` + filter `merged` | See what just landed |

This could be a "Watch Modes" section in settings, or separate tabs/sections in the main view. The GraphQL endpoint supports all these search qualifiers already.

---

### 6. Quick Actions from the App

Currently the app is purely read-only. Potential write actions via `gh` CLI:

| Action | CLI Command | UI Location |
|--------|-------------|-------------|
| **Approve PR** | `gh pr review {number} --repo {repo} --approve` | Context menu |
| **Request changes** | `gh pr review {number} --repo {repo} --request-changes` | Context menu |
| **Merge PR** | `gh pr merge {number} --repo {repo} --merge\|--squash\|--rebase` | Context menu |
| **Close PR** | `gh pr close {number} --repo {repo}` | Context menu |
| **Add to merge queue** | `gh pr merge {number} --repo {repo} --merge-queue` | Context menu |
| **Checkout branch** | `gh pr checkout {number} --repo {repo}` | Context menu |
| **Copy branch name** | Copy `headRefName` to pasteboard | Context menu |
| **Re-run failed checks** | GitHub API: `POST /repos/{owner}/{repo}/actions/runs/{id}/rerun-failed-jobs` | Failed checks list |

These would reuse the existing `GitHubService.run()` method (`GitHubService.swift:298-325`) which already knows how to execute `gh` commands.

**Risk:** Write actions from a menu bar app can be accidentally triggered. Would benefit from confirmation dialogs.

---

### 7. Richer PR Display Using Available (But Unfetched) GitHub Data

The GraphQL schema has many fields not in the current query. High-value additions:

| Field | What It Shows | Where to Display |
|-------|---------------|-----------------|
| `headRefName` | Branch name (e.g., `feature/new-thing`) | PR row subtitle, copy-to-clipboard |
| `baseRefName` | Target branch (e.g., `main`) | PR row subtitle |
| `createdAt` | When PR was opened | Relative timestamp ("2h ago") |
| `updatedAt` | Last activity | "Updated 15m ago" |
| `additions` / `deletions` | `+142 -38` | Stats badge on row |
| `labels` | PR labels | Colored pills on row |
| `comments.totalCount` | Comment count | Badge or icon |
| `changedFiles` | Files changed count | Stats display |
| `reviewRequests` | Who needs to review | "Waiting on @reviewer" |
| `assignees` | Who's assigned | Display in row |
| `mergeStateStatus` | CLEAN, DIRTY, DRAFT, etc. | More granular merge readiness |

The most impactful would be `headRefName` (enables branch-based workflows like checkout, copy branch name) and `createdAt`/`updatedAt` (enables relative timestamps like "opened 2 days ago").

---

### 8. Filtering and Search

The app currently shows all PRs with no way to filter or search. With more PRs (especially if watching reviewed PRs too), filtering becomes important.

| Filter | Implementation |
|--------|---------------|
| **Search by title** | Text field in header, filter `groupedPRs` |
| **Filter by CI status** | Toggle buttons: show only failing / passing / pending |
| **Filter by repo** | Checkboxes in a filter popover |
| **Filter by state** | Show/hide drafts, queued, etc. |
| **Hide/show repos** | Per-repo visibility toggle (beyond collapse) |

The existing `groupedPRs` computed property (`ContentView.swift:9-19`) is the natural place to apply filters.

---

### 9. System Integration

| Feature | Implementation | Value |
|---------|---------------|-------|
| **Launch at login** | `SMAppService.mainApp.register()` (macOS 13+) or LoginItems | High — menu bar app should auto-start |
| **Global hotkey** | `CGEvent` tap or library like `HotKey` | Medium — quick access without clicking menu bar |
| **Spotlight integration** | `CSSearchableItem` for each PR | Low — niche use case |
| **Share sheet** | `NSSharingServicePicker` for PR URL | Low — copy URL covers most cases |
| **Touch Bar** | Not relevant for most modern Macs | Skip |

**Launch at login is probably the highest-value system integration** — most menu bar apps offer this, and it's a common user expectation. `SMAppService` is available on macOS 13+, which is already the deployment target (`Package.swift`).

---

### 10. Persistence and History

Currently everything is in-memory (`PRManager.pullRequests`). PRs vanish the moment they're closed/merged.

| Feature | Implementation |
|---------|---------------|
| **Recently merged/closed PRs** | Keep closed PRs for N hours with a "recently closed" section |
| **PR history timeline** | Track state changes over time (opened → CI pass → approved → merged) |
| **Statistics** | "You merged 5 PRs this week" |
| **Offline cache** | Persist last-known state to disk, show stale data with indicator when offline |

Persistence could use `UserDefaults` for small data or a local JSON file for richer history.

---

### 11. UI Enhancements

| Enhancement | Notes |
|-------------|-------|
| **Relative timestamps** | "Opened 2h ago" instead of no time info |
| **PR body preview** | Expandable description preview on hover or click |
| **Compact mode** | Show more PRs in less space (hide badges, shrink rows) |
| **Custom sort options** | Sort by updated time, creation time, repo, CI status |
| **Drag-and-drop reorder** | Manual priority ordering |
| **Color-coded repo headers** | Visual distinction between repos |
| **Tooltip on hover** | Show PR description, labels, reviewers on hover |
| **Badge count on menu bar** | Show number of PRs or failures as a number |

---

## Priority Assessment

| # | Feature | Impact | Effort | Notes |
|---|---------|--------|--------|-------|
| 1 | **Open-In launcher (browser picker)** | High | Low | Just need bundle IDs + `NSWorkspace.open(_:withApplicationAt:)` |
| 2 | **Notification click-to-open** | High | Trivial | Set a delegate, extract URL, open it |
| 3 | **Keyboard shortcuts** | Medium | Trivial | Add `.keyboardShortcut()` to existing buttons |
| 4 | **Launch at login** | High | Low | `SMAppService.mainApp.register()` + toggle in settings |
| 5 | **Copy branch name** | High | Low | Add `headRefName` to query + context menu item |
| 6 | **Relative timestamps** | Medium | Low | Add `createdAt`/`updatedAt` to query + display |
| 7 | **Open-In launcher (IDE/terminal)** | High | Medium | Needs local repo path discovery |
| 8 | **Additional notification triggers** | Medium | Low | Extend existing `checkForStatusChanges` pattern |
| 9 | **Watch PRs I'm reviewing** | High | Medium | Second GraphQL query + UI section |
| 10 | **Quick actions (approve, merge)** | Medium | Medium | `gh pr` commands + confirmation UI |
| 11 | **Filtering/search** | Medium | Medium | Filter state + UI controls |
| 12 | **Recently merged PRs** | Medium | Medium | Persistence + new section |
| 13 | **Richer PR data (labels, stats)** | Low | Low | Extend query + display |
| 14 | **Global hotkey** | Low | Medium | Requires CGEvent or third-party |

---

## Recommended Implementation Order

**Phase A — Quick Wins (high value, trivial-to-low effort):**
1. Notification click-to-open (set delegate, ~20 lines)
2. Keyboard shortcuts (`Cmd+R`, `Cmd+,`, `Cmd+Q`)
3. Copy branch name (add `headRefName` to query + context menu)

**Phase B — Launcher Feature:**
4. Browser picker in context menu (scan `/Applications`, `NSWorkspace.open` with app URL)
5. "Checkout branch" via `gh pr checkout` in context menu
6. IDE/terminal launchers (needs local path config in settings)

**Phase C — System Polish:**
7. Launch at login toggle
8. Relative timestamps on PR rows
9. Additional notification triggers

**Phase D — Expanded Scope:**
10. Watch PRs assigned for review
11. Quick actions (approve, merge)
12. Filtering and search

---

## Code References

- Context menu (extension point for launcher): `Sources/ContentView.swift:92-99`
- URL opening (current approach): `Sources/PRRowView.swift:9` — `NSWorkspace.shared.open(pullRequest.url)`
- GraphQL query (extend for new fields): `Sources/GitHubService.swift:43-84`
- Notification sending (has URL but no delegate): `Sources/PRManager.swift:247-264`
- Settings view (add launcher config): `Sources/SettingsView.swift:16-54`
- CLI execution (reuse for quick actions): `Sources/GitHubService.swift:298-325`
- App delegate (add notification delegate): `Sources/App.swift:5-9`
- PullRequest model (extend with new fields): `Sources/Models.swift:6-26`
- Menu bar label (add badge count): `Sources/App.swift:23-28`
- Polling interval setting (pattern for new settings): `Sources/PRManager.swift:14-19`

## Related Research

- `thoughts/shared/research/2026-02-10-dry-refactoring-opportunities.md` — DRY cleanup findings
- `thoughts/shared/plans/2026-02-10-dry-cleanup.md` — DRY cleanup implementation plan
