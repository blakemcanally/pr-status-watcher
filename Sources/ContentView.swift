import SwiftUI

enum PRTab: String, CaseIterable {
    case myPRs = "My PRs"
    case reviews = "Reviews"
}

struct ContentView: View {
    @EnvironmentObject var manager: PRManager
    @Environment(\.openWindow) private var openWindow
    @State private var selectedTab: PRTab = .myPRs

    /// PRs for the currently selected tab.
    private var activePRs: [PullRequest] {
        switch selectedTab {
        case .myPRs: return manager.pullRequests
        case .reviews: return manager.reviewPRs
        }
    }

    /// Active PRs after applying per-tab review filters.
    private var filteredPRs: [PullRequest] {
        guard selectedTab == .reviews else { return activePRs }
        return manager.filterSettings.applyReviewFilters(to: activePRs)
    }

    /// Active PRs grouped by repo, sorted by repo name. Sort within each repo depends on tab.
    private var groupedPRs: [(repo: String, prs: [PullRequest])] {
        let dict = Dictionary(grouping: filteredPRs, by: \.repoFullName)
        let isReviews = selectedTab == .reviews
        return dict.keys.sorted().map { key in
            (repo: key, prs: (dict[key] ?? []).sorted {
                if isReviews {
                    // Reviews tab: needs-review first, then fewest approvals, then state, then number
                    if $0.reviewSortPriority != $1.reviewSortPriority {
                        return $0.reviewSortPriority < $1.reviewSortPriority
                    }
                    if $0.approvalCount != $1.approvalCount {
                        return $0.approvalCount < $1.approvalCount
                    }
                }
                let lhsPriority = $0.sortPriority
                let rhsPriority = $1.sortPriority
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                return $0.number < $1.number
            })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            prList
            Divider()
            footer
        }
        .frame(
            minWidth: AppConstants.Layout.ContentWindow.minWidth,
            idealWidth: AppConstants.Layout.ContentWindow.idealWidth,
            maxWidth: AppConstants.Layout.ContentWindow.maxWidth,
            minHeight: AppConstants.Layout.ContentWindow.minHeight,
            idealHeight: AppConstants.Layout.ContentWindow.idealHeight,
            maxHeight: AppConstants.Layout.ContentWindow.maxHeight
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "arrow.triangle.pull")
                .font(.title3.weight(.semibold))
                .foregroundColor(.accentColor)

            Picker("", selection: $selectedTab) {
                ForEach(PRTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: AppConstants.Layout.Header.tabPickerWidth)
            .accessibilityLabel("Tab selection")

            Spacer()
            if manager.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                Task { await manager.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.body)
            }
            .buttonStyle(.borderless)
            .disabled(manager.isRefreshing)
            .help("Refresh all PRs")
            .keyboardShortcut("r", modifiers: .command)
            .accessibilityLabel("Refresh pull requests")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - PR List

    private var prList: some View {
        Group {
            if activePRs.isEmpty && !manager.hasCompletedInitialLoad {
                loadingState
            } else if activePRs.isEmpty {
                emptyState
            } else if filteredPRs.isEmpty {
                filteredEmptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groupedPRs, id: \.repo) { group in
                            repoSection(repo: group.repo, prs: group.prs)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Repo Section

    private func repoSection(repo: String, prs: [PullRequest]) -> some View {
        let isCollapsed = manager.collapsedRepos.contains(repo)

        return VStack(spacing: 0) {
            repoHeader(repo: repo, prs: prs, isCollapsed: isCollapsed)

            // PR rows
            if !isCollapsed {
                ForEach(prs) { pullRequest in
                    PRRowView(pullRequest: pullRequest)
                        .contextMenu {
                            Button("Open in Browser") {
                                NSWorkspace.shared.open(pullRequest.url)
                            }
                            Button("Copy Branch Name") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(pullRequest.headRefName, forType: .string)
                            }
                            Button("Copy URL") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(pullRequest.url.absoluteString, forType: .string)
                            }
                        }
                    if pullRequest.id != prs.last?.id {
                        Divider().padding(.leading, 36)
                    }
                }
            }

            // Separator between repo groups
            Divider()
        }
    }

    private func repoHeader(repo: String, prs: [PullRequest], isCollapsed: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isCollapsed {
                    var updated = manager.collapsedRepos
                    updated.remove(repo)
                    manager.collapsedRepos = updated
                } else {
                    var updated = manager.collapsedRepos
                    updated.insert(repo)
                    manager.collapsedRepos = updated
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))

                repoNameLabel(repo)

                Text("\(prs.count)")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(4)

                Spacer()

                if isCollapsed {
                    HStack(spacing: 3) {
                        ForEach(prs) { pullRequest in
                            Circle()
                                .fill(pullRequest.statusColor)
                                .frame(width: 6, height: 6)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.secondary.opacity(0.05))
        .accessibilityLabel("\(repo), \(prs.count) pull requests, \(isCollapsed ? "collapsed" : "expanded")")
        .accessibilityHint("Double-tap to \(isCollapsed ? "expand" : "collapse")")
    }

    @ViewBuilder
    private func repoNameLabel(_ repo: String) -> some View {
        let parts = repo.split(separator: "/")
        if parts.count == 2 {
            Text(String(parts[0]))
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
            Text("/")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.4))
            Text(String(parts[1]))
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        } else {
            Text(repo)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 10) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(Strings.EmptyState.loadingTitle)
                .font(.title3)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Loading pull requests")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: selectedTab == .myPRs ? "tray" : "eye")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text(selectedTab == .myPRs ? Strings.EmptyState.noPRsTitle : Strings.EmptyState.noReviewsTitle)
                .font(.title3)
                .foregroundColor(.secondary)
            Text(
                selectedTab == .myPRs
                    ? Strings.EmptyState.noPRsSubtitle
                    : Strings.EmptyState.noReviewsSubtitle
            )
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(selectedTab == .myPRs ? "No open pull requests" : "No review requests")
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text(Strings.EmptyState.filteredTitle)
                .font(.title3)
                .foregroundColor(.secondary)
            Text(Strings.EmptyState.filteredSubtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("All review requests hidden by filters")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            AuthStatusView(username: manager.ghUser, style: .compact)

            Spacer()

            if let error = manager.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(1)
                    .help(error)
            }

            TimelineView(.periodic(from: .now, by: 10)) { context in
                Text(refreshFooterLabel(at: context.date))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .help("Auto-refreshes every \(manager.refreshIntervalLabel)")

            if !manager.notificationsAvailable {
                Image(systemName: "bell.slash")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .help("Notifications unavailable — build as .app to enable (see README)")
            }

            Spacer()

            Button(action: openSettings) {
                Image(systemName: "gear")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityLabel("Open settings")

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .keyboardShortcut("q", modifiers: .command)
            .accessibilityLabel("Quit application")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    /// Footer label showing a coarse countdown to the next refresh, with fallbacks.
    private func refreshFooterLabel(at date: Date) -> String {
        if let next = manager.nextRefreshDate,
           let label = PRStatusSummary.countdownLabel(until: next, now: date) {
            return Strings.Refresh.refreshesIn(label)
        }
        if manager.isRefreshing {
            return Strings.Refresh.refreshing
        }
        return Strings.Refresh.refreshesEvery(manager.refreshIntervalLabel)
    }

    // MARK: - Actions

    private func openSettings() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }
}
