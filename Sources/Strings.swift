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
        static let filteredTitle = "All review requests hidden"
        static let filteredSubtitle = "Adjust your review filters in Settings to see more PRs"
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
