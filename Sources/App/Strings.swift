import Foundation

// MARK: - User-Facing Strings (Localization-Ready)

/// Centralized user-facing strings. When localization is needed, replace
/// each `String` return value with `String(localized:)`.
///
/// Example future migration:
/// ```swift
/// static var ghNotAuthenticated: String {
///     String(localized: "error.gh_not_authenticated",
///            defaultValue: "gh not authenticated")
/// }
/// ```
enum Strings {

    // MARK: Errors

    enum Error {
        static let ghNotAuthenticated = "gh not authenticated"
        static let ghCliNotFound = "GitHub CLI (gh) not found — install it with: brew install gh"
        static let ghApiErrorFallback = "GitHub API error"
        static let ghInvalidJSON = "Invalid response from GitHub API"
        static let ghTimeout = "GitHub CLI timed out — check your network connection"

        static func ghProcessLaunchFailed(_ detail: String) -> String {
            "Failed to launch GitHub CLI: \(detail)"
        }

        static func reviewFetchPrefix(_ message: String) -> String {
            "Reviews: \(message)"
        }
    }

    // MARK: Notifications

    enum Notification {
        static let ciFailed = "CI Failed"
        static let allChecksPassed = "All Checks Passed"
        static let prNoLongerOpen = "PR No Longer Open"

        static func ciStatusBody(repo: String, number: String, title: String) -> String {
            "\(repo) \(number): \(title)"
        }

        static func prClosedBody(id: String) -> String {
            "\(id) was merged or closed"
        }
    }

    // MARK: PR States

    enum PRState {
        static let open = "Open"
        static let closed = "Closed"
        static let merged = "Merged"
        static let draft = "Draft"
        static let mergeQueue = "Merge Queue"

        static func queuePosition(_ pos: Int) -> String {
            "Queue #\(pos)"
        }
    }

    // MARK: Review Decisions

    enum Review {
        static let approved = "Approved"
        static let changesRequested = "Changes"
        static let reviewRequired = "Review"
    }

    // MARK: CI Status

    enum CI {
        static func failedCount(_ count: Int) -> String {
            "\(count) failed"
        }

        static func checksProgress(passed: Int, total: Int) -> String {
            "\(passed)/\(total) checks"
        }

        static func checksPassed(passed: Int, total: Int) -> String {
            "\(passed)/\(total) passed"
        }
    }

    // MARK: Merge Conflicts

    enum Merge {
        static let conflicts = "Conflicts"
    }

    // MARK: Menu Bar / Status

    enum Status {
        static func barSummary(myCount: Int, reviewCount: Int) -> String {
            "\(myCount) | \(reviewCount)"
        }
    }

    // MARK: Refresh

    enum Refresh {
        static func countdownSeconds(_ seconds: Int) -> String {
            "~\(seconds)s"
        }

        static let countdownAboutOneMinute = "~1 min"

        static func countdownMinutes(_ minutes: Int) -> String {
            "~\(minutes) min"
        }

        static func refreshesIn(_ label: String) -> String {
            "Refreshes in \(label)"
        }

        static let refreshing = "Refreshing…"

        static func refreshesEvery(_ label: String) -> String {
            "Refreshes every \(label)"
        }
    }

    // MARK: Empty States

    enum EmptyState {
        static let loadingTitle = "Loading pull requests…"
        static let noPRsTitle = "No open pull requests"
        static let noPRsSubtitle = "Your open, draft, and queued PRs will appear here automatically"
        static let noReviewsTitle = "No review requests"
        static let noReviewsSubtitle = "Pull requests where your review is requested will appear here"

        // Filtered empty states — shown when filters hide all PRs
        static let filteredDraftsTitle = "All review requests are drafts"
        static let filteredDraftsSubtitle = "Disable \"Hide draft PRs\" in Settings to see them"
        static let filteredApprovedTitle = "All caught up"
        static let filteredApprovedSubtitle = "You've approved all pending review requests"
        static let filteredNotReadyTitle = "All caught up"
        static let filteredNotReadySubtitle = "No review requests need your attention right now"
        static let filteredMixedTitle = "All review requests hidden"
        static let filteredMixedSubtitle = "Adjust your filters in Settings to see them"
    }

    // MARK: Readiness

    enum Readiness {
        static func readyForReview(_ count: Int) -> String {
            "Ready for Review (\(count))"
        }
        static func notReady(_ count: Int) -> String {
            "Not Ready (\(count))"
        }
        static let settingsTitle = "Review Readiness"
        static let settingsDescription = "PRs won't appear as \"Ready for Review\" until these checks pass."
        static let addCheckPlaceholder = "Add check name..."
        static let requiredChecksLabel = "Required CI Checks"
        static let tipText = "Check names must match the exact name shown in GitHub CI. Checks not present on a PR are ignored."
        static let ignoredChecksLabel = "Ignored CI Checks"
        static let ignoredChecksDescription = "These CI checks are completely hidden — they won't affect readiness or appear in the CI badge."
        static let addIgnoredCheckPlaceholder = "Add check to ignore..."
    }

    // MARK: Auth

    enum Auth {
        static func signedIn(_ username: String) -> String {
            "Signed in as \(username)"
        }

        static let notAuthenticated = "Not authenticated"
        static let authInstructions = "Run this command in your terminal:"
        static let authCommand = "gh auth login"
        static let compactNotAuth = "gh not authenticated"
    }
}
