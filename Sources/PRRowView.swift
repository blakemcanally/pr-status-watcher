import SwiftUI

struct PRRowView: View {
    let pullRequest: PullRequest
    @State private var showFailures = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(pullRequest.url)
        } label: {
            HStack(spacing: 10) {
                // Status dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)

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
                            (pullRequest.ciStatus == .success || pullRequest.ciStatus == .unknown) {
                            reviewBadge
                        }
                        Spacer()
                        if !pullRequest.headSHA.isEmpty {
                            Text(pullRequest.headSHA)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }

                    // Expandable failed checks list
                    if showFailures && !pullRequest.failedChecks.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(pullRequest.failedChecks.indices, id: \.self) { index in
                                let check = pullRequest.failedChecks[index]
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
    }

    // MARK: - Status Color

    private var statusColor: Color {
        switch pullRequest.state {
        case .merged: return .purple
        case .closed: return .gray
        case .draft: return .gray
        case .open:
            if pullRequest.isInMergeQueue { return .purple }
            switch pullRequest.ciStatus {
            case .success: return .green
            case .failure: return .red
            case .pending: return .orange
            case .unknown: return .gray
            }
        }
    }

    // MARK: - State Badge

    private var stateBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: stateIcon)
                .font(.caption2)
            Text(stateText)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(statusColor.opacity(0.15))
        .foregroundColor(statusColor)
        .cornerRadius(4)
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
                    return "Queue #\(pos)"
                }
                return "Merge Queue"
            }
            return "Open"
        case .closed:
            return "Closed"
        case .merged:
            return "Merged"
        case .draft:
            return "Draft"
        }
    }

    // MARK: - Review Badge

    @ViewBuilder
    private var reviewBadge: some View {
        switch pullRequest.reviewDecision {
        case .approved:
            badgePill(icon: "checkmark.circle.fill", text: "Approved", color: .green)
        case .changesRequested:
            badgePill(icon: "exclamationmark.circle.fill", text: "Changes", color: .red)
        case .reviewRequired:
            badgePill(icon: "eye.fill", text: "Review", color: .orange)
        case .none:
            EmptyView()
        }
    }

    // MARK: - Conflict Badge

    @ViewBuilder
    private var conflictBadge: some View {
        if pullRequest.mergeable == .conflicting {
            badgePill(icon: "exclamationmark.triangle.fill", text: "Conflicts", color: .red)
        }
    }

    // MARK: - CI Badge

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
                HStack(spacing: 3) {
                    Image(systemName: ciIcon)
                        .font(.caption2)
                    Text(ciText)
                        .font(.caption2.weight(.medium))
                    if !pullRequest.failedChecks.isEmpty {
                        Image(systemName: showFailures ? "chevron.up" : "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(ciColor.opacity(0.12))
                .foregroundColor(ciColor)
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
        }
    }

    private var ciIcon: String {
        switch pullRequest.ciStatus {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .pending: return "clock.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var ciText: String {
        if pullRequest.checksFailed > 0 {
            return "\(pullRequest.checksFailed) failed"
        }
        let pending = pullRequest.checksTotal - pullRequest.checksPassed - pullRequest.checksFailed
        if pending > 0 {
            return "\(pullRequest.checksPassed)/\(pullRequest.checksTotal) checks"
        }
        return "\(pullRequest.checksPassed)/\(pullRequest.checksTotal) passed"
    }

    private var ciColor: Color {
        switch pullRequest.ciStatus {
        case .success: return .green
        case .failure: return .red
        case .pending: return .orange
        case .unknown: return .secondary
        }
    }

    // MARK: - Badge Helper

    private func badgePill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12))
        .foregroundColor(color)
        .cornerRadius(4)
    }
}
