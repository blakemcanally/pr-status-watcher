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

    /// Compact menu bar summary string showing per-tab totals, e.g. "3 | 2" for 3 authored PRs and 2 reviews.
    ///
    /// Shows both counts when either list is non-empty so the user always knows at a glance
    /// whether they have active PRs or pending reviews. Returns empty string when both are empty.
    static func statusBarSummary(for pullRequests: [PullRequest], reviewPRs: [PullRequest]) -> String {
        guard !pullRequests.isEmpty || !reviewPRs.isEmpty else { return "" }
        return "\(pullRequests.count) | \(reviewPRs.count)"
    }

    /// Human-readable label for a polling interval in seconds.
    static func refreshIntervalLabel(for interval: Int) -> String {
        if interval < 60 { return "\(interval)s" }
        if interval == 60 { return "1 min" }
        if interval % 60 == 0 { return "\(interval / 60) min" }
        return "\(interval)s"
    }

    /// Coarse countdown label for the next refresh.
    ///
    /// Granularity: 10 s steps below 1 min, 1 min steps at ≥ 1 min.
    /// Returns `nil` when the target is fewer than 10 s away (i.e. refresh is imminent).
    static func countdownLabel(until target: Date, now: Date = .now) -> String? {
        let remaining = Int(target.timeIntervalSince(now))
        guard remaining >= 10 else { return nil }
        if remaining < 60 {
            let rounded = (remaining / 10) * 10
            return "~\(rounded)s"
        }
        let minutes = remaining / 60
        return "~\(minutes) min"
    }
}
