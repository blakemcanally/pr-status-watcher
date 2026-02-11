import Foundation

// MARK: - PR Status Summary (Pure Logic)

/// Pure functions that derive menu bar state from PR data.
/// No side effects, no dependencies — fully testable.
enum PRStatusSummary {

    /// SF Symbol name for the overall status icon.
    static func overallStatusIcon(for pullRequests: [PullRequest]) -> String {
        if pullRequests.isEmpty {
            return "arrow.triangle.pull"
        }
        if pullRequests.contains(where: { $0.ciStatus == .failure }) {
            return "xmark.circle.fill"
        }
        if pullRequests.contains(where: { $0.ciStatus == .pending }) {
            return "clock.circle.fill"
        }
        if pullRequests.allSatisfy({ $0.state == .merged || $0.state == .closed }) {
            return "checkmark.circle"
        }
        return "checkmark.circle.fill"
    }

    /// Whether any PR has a CI failure.
    static func hasFailure(in pullRequests: [PullRequest]) -> Bool {
        pullRequests.contains(where: { $0.ciStatus == .failure })
    }

    /// Count of open PRs not in the merge queue.
    static func openCount(in pullRequests: [PullRequest]) -> Int {
        pullRequests.filter { $0.state == .open && !$0.isInMergeQueue }.count
    }

    /// Count of draft PRs.
    static func draftCount(in pullRequests: [PullRequest]) -> Int {
        pullRequests.filter { $0.state == .draft }.count
    }

    /// Count of PRs in the merge queue.
    static func queuedCount(in pullRequests: [PullRequest]) -> Int {
        pullRequests.filter { $0.isInMergeQueue }.count
    }

    /// Compact menu bar summary string, e.g. "3·10·2" for draft·open·queued.
    static func statusBarSummary(for pullRequests: [PullRequest]) -> String {
        guard !pullRequests.isEmpty else { return "" }
        let draft = draftCount(in: pullRequests)
        let open = openCount(in: pullRequests)
        let queued = queuedCount(in: pullRequests)
        var parts: [String] = []
        if draft > 0 { parts.append("\(draft)") }
        if open > 0 { parts.append("\(open)") }
        if queued > 0 { parts.append("\(queued)") }
        return parts.joined(separator: "·")
    }

    /// Human-readable label for a polling interval in seconds.
    static func refreshIntervalLabel(for interval: Int) -> String {
        if interval < 60 { return "\(interval)s" }
        if interval == 60 { return "1 min" }
        if interval % 60 == 0 { return "\(interval / 60) min" }
        return "\(interval)s"
    }
}
