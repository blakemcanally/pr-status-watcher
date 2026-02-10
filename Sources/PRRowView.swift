import SwiftUI

struct PRRowView: View {
    let pr: PullRequest

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

                    // Status badges row
                    HStack(spacing: 8) {
                        stateBadge
                        ciBadge
                        Spacer()
                        if !pr.headSHA.isEmpty {
                            Text(pr.headSHA)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
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
            return pr.isInMergeQueue ? "Merge Queue" : "Open"
        case .closed:
            return "Closed"
        case .merged:
            return "Merged"
        case .draft:
            return "Draft"
        }
    }

    // MARK: - CI Badge

    @ViewBuilder
    private var ciBadge: some View {
        if pr.checksTotal > 0 {
            HStack(spacing: 3) {
                Image(systemName: ciIcon)
                    .font(.caption2)
                Text(ciText)
                    .font(.caption2.weight(.medium))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(ciColor.opacity(0.12))
            .foregroundColor(ciColor)
            .cornerRadius(4)
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
}
