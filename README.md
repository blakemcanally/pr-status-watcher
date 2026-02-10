# PR Status Watcher

A lightweight macOS menu bar app that automatically tracks all of your open GitHub pull requests. See CI status, merge queue position, draft state, and more -- without ever leaving your desktop.

![PR Status Watcher](screenshot.png)

## What it does

- **Auto-discovers** all of your open, draft, and queued PRs -- no manual setup
- **Groups by repo** with collapsible sections
- **CI status** at a glance -- pass/fail counts and colored status dots
- **Merge queue detection** -- see which PRs are actually queued vs just open
- **Click to open** any PR directly in your browser
- **Auto-refreshes** every 60 seconds via a single fast GraphQL call
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

On launch (and every 60s), the app runs a single GitHub GraphQL query through the `gh` CLI to fetch all of your open pull requests along with their CI check status. No tokens to manage, no API keys to configure -- it piggybacks on your existing `gh auth` session.

PRs are grouped by repository and sorted by state (Open, Draft, Queued) then by PR number.

## Architecture

```
Sources/
├── App.swift             # @main entry point, MenuBarExtra setup
├── Models.swift          # PullRequest model, PR URL parser
├── GitHubService.swift   # GraphQL queries via gh CLI
├── PRManager.swift       # ViewModel -- discovery, polling, state
├── ContentView.swift     # Main UI with grouped/collapsible repo sections
└── PRRowView.swift       # Individual PR row component
```

- **SwiftUI** with `MenuBarExtra` (macOS 13+)
- **GitHub GraphQL API** via `gh api graphql` -- one call gets everything
- **Swift concurrency** (async/await, TaskGroup)
- Zero third-party dependencies

## License

MIT
