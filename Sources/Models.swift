import Foundation
import SwiftUI

// MARK: - Pull Request Model

struct PullRequest: Identifiable {
    var id: String { "\(owner)/\(repo)#\(number)" }

    let owner: String
    let repo: String
    let number: Int
    var title: String
    var author: String
    var state: PRState
    var ciStatus: CIStatus
    var isInMergeQueue: Bool
    var checksTotal: Int
    var checksPassed: Int
    var checksFailed: Int
    var url: URL
    var headSHA: String
    var headRefName: String
    var lastFetched: Date
    var reviewDecision: ReviewDecision
    var mergeable: MergeableState
    var queuePosition: Int?
    var approvalCount: Int
    var failedChecks: [CheckInfo]

    var repoFullName: String { "\(owner)/\(repo)" }
    var displayNumber: String { "#\(number)" }

    /// Sort priority: Open = 0, Draft = 1, Queued = 2, Closed/Merged = 3.
    var sortPriority: Int {
        if isInMergeQueue { return 2 }
        switch state {
        case .open: return 0
        case .draft: return 1
        case .merged: return 3
        case .closed: return 3
        }
    }

    /// Review sort priority for the Reviews tab.
    /// Needs-review first (0), then changes-requested (1), then approved (2).
    var reviewSortPriority: Int {
        switch reviewDecision {
        case .reviewRequired, .none: return 0
        case .changesRequested: return 1
        case .approved: return 2
        }
    }

    /// Canonical status color used for row dots and collapsed summary dots.
    var statusColor: Color {
        switch state {
        case .merged: return .purple
        case .closed: return .gray
        case .draft: return .gray
        case .open:
            if isInMergeQueue { return .purple }
            switch ciStatus {
            case .success: return .green
            case .failure: return .red
            case .pending: return .orange
            case .unknown: return .gray
            }
        }
    }

    // MARK: State & CI Enums

    enum PRState: String {
        case open
        case closed
        case merged
        case draft
    }

    enum CIStatus: String {
        case success
        case failure
        case pending
        case unknown

        var color: Color {
            switch self {
            case .success: return .green
            case .failure: return .red
            case .pending: return .orange
            case .unknown: return .secondary
            }
        }
    }

    // MARK: Review & Merge Enums

    enum ReviewDecision: String {
        case approved
        case changesRequested
        case reviewRequired
        case none
    }

    enum MergeableState: String {
        case mergeable
        case conflicting
        case unknown
    }

    // MARK: Check Info

    struct CheckInfo {
        let name: String
        let detailsUrl: URL?
    }
}
