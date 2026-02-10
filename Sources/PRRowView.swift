import SwiftUI

struct PRRowView: View {
    let pr: PullRequest
    @State private var showFailures = false

    var body: some View {
        Button(action: { NSWorkspace.shared.open(pr.url) }) {
            HStack(spacing: 10) {
                // Status dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 3) {
                    // PR number + author
                    HStack(spacing: 4) {
                        Text(pr.displayNumber)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        if !pr.author.isEmpty {
                            Text("by \(pr.author)")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                    }

                    // Title
                    Text(pr.title)
                        .font(.system(.body, design: .default))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    // Status badges row — prioritize actionable info
                    // Review badge only shown when CI is passing or unknown (not actionable during failure/pending)
                    HStack(spacing: 6) {
                        stateBadge
                        conflictBadge
                        ciBadge
                        if pr.state != .draft && (pr.ciStatus == .success || pr.ciStatus == .unknown) {
                            reviewBadge
                        }
                        Spacer()
                        if !pr.headSHA.isEmpty {
                            Text(pr.headSHA)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }

                    // Expandable failed checks list
                    if showFailures && !pr.failedChecks.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(pr.failedChecks.indices, id: \.self) { i in
                                let check = pr.failedChecks[i]
                                Button(action: {
                                    if let url = check.detailsUrl {
                                        NSWorkspace.shared.open(url)
                                    }
                                }) {
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
        switch pr.state {
        case .merged: return .purple
        case .closed: return .gray
        case .draft:  return .gray
        case .open:
            if pr.isInMergeQueue { return .purple }
            switch pr.ciStatus {
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
        switch pr.state {
        case .open:
            return pr.isInMergeQueue ? "arrow.triangle.merge" : "arrow.triangle.pull"
        case .closed:
            return "xmark.circle"
        case .merged:
            return "arrow.triangle.merge"
        case .draft:
            return "pencil.line"
        }
    }

    private var stateText: String {
        switch pr.state {
        case .open:
            if pr.isInMergeQueue {
                if let pos = pr.queuePosition {
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
        switch pr.reviewDecision {
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
        if pr.mergeable == .conflicting {
            badgePill(icon: "exclamationmark.triangle.fill", text: "Conflicts", color: .red)
        }
    }

    // MARK: - CI Badge

    @ViewBuilder
    private var ciBadge: some View {
        if pr.checksTotal > 0 {
            Button(action: {
                if !pr.failedChecks.isEmpty {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showFailures.toggle()
                    }
                }
            }) {
                HStack(spacing: 3) {
                    Image(systemName: ciIcon)
                        .font(.caption2)
                    Text(ciText)
                        .font(.caption2.weight(.medium))
                    if !pr.failedChecks.isEmpty {
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
        switch pr.ciStatus {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .pending: return "clock.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var ciText: String {
        if pr.checksFailed > 0 {
            return "\(pr.checksFailed) failed"
        }
        let pending = pr.checksTotal - pr.checksPassed - pr.checksFailed
        if pending > 0 {
            return "\(pr.checksPassed)/\(pr.checksTotal) checks"
        }
        return "\(pr.checksPassed)/\(pr.checksTotal) passed"
    }

    private var ciColor: Color {
        switch pr.ciStatus {
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
