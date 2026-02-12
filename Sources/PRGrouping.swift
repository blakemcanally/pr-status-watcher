import Foundation

// MARK: - PR Grouping (Pure Logic)

/// Pure functions for grouping and sorting PRs by repository.
/// Extracted from ContentView for testability.
enum PRGrouping {

    /// Group PRs by repository, sorting repos alphabetically and PRs within
    /// each repo by the tab-appropriate priority.
    ///
    /// - Parameters:
    ///   - prs: The PRs to group (already filtered).
    ///   - isReviews: If true, sorts by review priority first.
    /// - Returns: Array of (repo name, sorted PRs) tuples, sorted by repo name.
    static func grouped(
        prs: [PullRequest],
        isReviews: Bool
    ) -> [(repo: String, prs: [PullRequest])] {
        let dict = Dictionary(grouping: prs, by: \.repoFullName)
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
}
