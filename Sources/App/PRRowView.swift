import SwiftUI

struct PRRowView: View {
    let pullRequest: PullRequest
    var ignoredCheckNames: [String] = []
    @State private var showFailures = false

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

    var body: some View {
        Button {
            NSWorkspace.shared.open(pullRequest.url)
        } label: {
            HStack(spacing: 10) {
                // Status dot
                Circle()
                    .fill(displayStatusColor)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    // PR number + author
                    HStack(spacing: 4) {
                        Text(pullRequest.displayNumber)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        if !pullRequest.author.isEmpty {
                            Text("by \(pullRequest.author)")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                    }

                    // Title
                    Text(pullRequest.title)
                        .font(.system(.body, design: .default))
                        .lineLimit(1)
                        .truncationMode(.tail)

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

                    // Expandable failed checks list
                    if showFailures && !displayFailedChecks.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(displayFailedChecks.indices, id: \.self) { index in
                                let check = displayFailedChecks[index]
                                Button {
                                    if let url = check.detailsUrl {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundColor(.red)
                                        Text(check.name)
                                            .font(.caption2)
                                            .foregroundColor(.red)
                                            .lineLimit(1)
                                        if check.detailsUrl != nil {
                                            Image(systemName: "arrow.up.right")
                                                .font(.system(size: 7))
                                                .foregroundColor(.red.opacity(0.6))
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(pullRequest.title), \(pullRequest.displayNumber) by \(pullRequest.author), \(stateText)"
            + (pullRequest.approvalCount > 0 ? ", \(pullRequest.approvalCount) approvals" : "")
        )
        .accessibilityHint("Opens in browser")
    }

    // MARK: - State Badge

    private var stateBadge: some View {
        badgePill(icon: stateIcon, text: stateText, color: pullRequest.statusColor)
    }

    private var stateIcon: String {
        switch pullRequest.state {
        case .open:
            return pullRequest.isInMergeQueue ? "arrow.triangle.merge" : "arrow.triangle.pull"
        case .closed:
            return "xmark.circle"
        case .merged:
            return "arrow.triangle.merge"
        case .draft:
            return "pencil.line"
        }
    }

    private var stateText: String {
        switch pullRequest.state {
        case .open:
            if pullRequest.isInMergeQueue {
                if let pos = pullRequest.queuePosition {
                    return Strings.PRState.queuePosition(pos)
                }
                return Strings.PRState.mergeQueue
            }
            return Strings.PRState.open
        case .closed:
            return Strings.PRState.closed
        case .merged:
            return Strings.PRState.merged
        case .draft:
            return Strings.PRState.draft
        }
    }

    // MARK: - Review Badge

    @ViewBuilder
    private var reviewBadge: some View {
        switch pullRequest.reviewDecision {
        case .approved:
            badgePill(icon: "checkmark.circle.fill", text: Strings.Review.approved, color: .green)
        case .changesRequested:
            badgePill(icon: "exclamationmark.circle.fill", text: Strings.Review.changesRequested, color: .red)
        case .reviewRequired:
            badgePill(icon: "eye.fill", text: Strings.Review.reviewRequired, color: .orange)
        case .none:
            EmptyView()
        }
    }

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

    // MARK: - Conflict Badge

    @ViewBuilder
    private var conflictBadge: some View {
        if pullRequest.mergeable == .conflicting {
            badgePill(icon: "exclamationmark.triangle.fill", text: Strings.Merge.conflicts, color: .red)
        }
    }

    // MARK: - CI Badge

    @ViewBuilder
    private var ciBadge: some View {
        if displayCheckCounts.total > 0 {
            Button {
                if !displayFailedChecks.isEmpty {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showFailures.toggle()
                    }
                }
            } label: {
                badgePill(
                    icon: ciIcon,
                    text: ciText,
                    color: displayCIStatus.color
                ) {
                    if !displayFailedChecks.isEmpty {
                        Image(systemName: showFailures ? "chevron.up" : "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("CI status: \(ciText)")
            .accessibilityHint(!displayFailedChecks.isEmpty ? "Double-tap to show failed checks" : "")
        }
    }

    private var ciIcon: String {
        switch displayCIStatus {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .pending: return "clock.fill"
        case .unknown: return "questionmark.circle"
        }
    }

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

    // MARK: - Badge Helper

    private func badgePill(
        icon: String,
        text: String,
        color: Color
    ) -> some View {
        badgePill(icon: icon, text: text, color: color) { EmptyView() }
    }

    private func badgePill<Trailing: View>(
        icon: String,
        text: String,
        color: Color,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2.weight(.medium))
            trailing()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12))
        .foregroundColor(color)
        .cornerRadius(4)
    }
}
