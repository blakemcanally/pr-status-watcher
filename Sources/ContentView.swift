import SwiftUI

enum PRTab: String, CaseIterable {
    case myPRs = "My PRs"
    case reviews = "Reviews"
}

struct ContentView: View {
    @EnvironmentObject var manager: PRManager
    @Environment(\.openWindow) private var openWindow
    @State private var selectedTab: PRTab = .myPRs
    @State private var collapsedRepos: Set<String> = []

    /// PRs for the currently selected tab.
    private var activePRs: [PullRequest] {
        switch selectedTab {
        case .myPRs: return manager.pullRequests
        case .reviews: return manager.reviewPRs
        }
    }

    /// Active PRs grouped by repo, sorted by repo name. Sort within each repo depends on tab.
    private var groupedPRs: [(repo: String, prs: [PullRequest])] {
        let dict = Dictionary(grouping: activePRs, by: \.repoFullName)
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
            minWidth: 400, idealWidth: 460, maxWidth: 560,
            minHeight: 400, idealHeight: 520, maxHeight: 700
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
            .frame(width: 180)

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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - PR List

    private var prList: some View {
        Group {
            if activePRs.isEmpty {
                emptyState
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
        let isCollapsed = collapsedRepos.contains(repo)

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
                    collapsedRepos.remove(repo)
                } else {
                    collapsedRepos.insert(repo)
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: selectedTab == .myPRs ? "tray" : "eye")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text(selectedTab == .myPRs ? "No open pull requests" : "No review requests")
                .font(.title3)
                .foregroundColor(.secondary)
            Text(
                selectedTab == .myPRs
                    ? "Your open, draft, and queued PRs will appear here automatically"
                    : "Pull requests where your review is requested will appear here"
            )
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
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

            Text("Refreshes every \(manager.refreshIntervalLabel)")
                .font(.caption2)
                .foregroundColor(.secondary)

            Spacer()

            Button(action: openSettings) {
                Image(systemName: "gear")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Settings")

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func openSettings() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }
}
