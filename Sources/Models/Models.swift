import Foundation
import SwiftUI

// MARK: - Pull Request Model

struct PullRequest: Identifiable, Codable, Equatable {
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
    var checkResults: [CheckResult]

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

    enum PRState: String, Codable {
        case open
        case closed
        case merged
        case draft
    }

    enum CIStatus: String, Codable {
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

    enum ReviewDecision: String, Codable {
        case approved
        case changesRequested
        case reviewRequired
        case none
    }

    enum MergeableState: String, Codable {
        case mergeable
        case conflicting
        case unknown
    }

    // MARK: Check Info

    struct CheckInfo: Codable, Equatable {
        let name: String
        let detailsUrl: URL?
    }

    // MARK: Check Result (all checks, not just failed)

    enum CheckStatus: String, Codable {
        case passed
        case failed
        case pending
    }

    struct CheckResult: Codable, Equatable {
        let name: String
        let status: CheckStatus
        let detailsUrl: URL?
    }

    // MARK: Readiness

    /// Whether this PR is ready for review given the user's check configuration.
    func isReady(requiredChecks: [String], ignoredChecks: [String] = []) -> Bool {
        guard state != .draft else { return false }
        guard mergeable != .conflicting else { return false }

        if requiredChecks.isEmpty {
            // Default mode: use effective CI status (excluding ignored checks)
            let effectiveStatus = effectiveCIStatus(ignoredChecks: ignoredChecks)
            return effectiveStatus != .failure && effectiveStatus != .pending
        }

        // Required-checks mode: evaluate only required checks (minus any ignored).
        // With mutual exclusion enforced by the UI, a check shouldn't be in both
        // lists — but we handle it defensively by skipping ignored checks.
        let ignored = Set(ignoredChecks)
        for name in requiredChecks {
            if ignored.contains(name) { continue }
            guard let check = checkResults.first(where: { $0.name == name }) else {
                continue
            }
            if check.status != .passed { return false }
        }
        return true
    }

    // MARK: - Effective Values (Ignored Checks Filtering)

    /// Check results excluding ignored check names.
    func effectiveCheckResults(ignoredChecks: [String]) -> [CheckResult] {
        guard !ignoredChecks.isEmpty else { return checkResults }
        let ignored = Set(ignoredChecks)
        return checkResults.filter { !ignored.contains($0.name) }
    }

    /// Failed checks excluding ignored check names.
    func effectiveFailedChecks(ignoredChecks: [String]) -> [CheckInfo] {
        guard !ignoredChecks.isEmpty else { return failedChecks }
        let ignored = Set(ignoredChecks)
        return failedChecks.filter { !ignored.contains($0.name) }
    }

    /// Recomputed CI status excluding ignored checks.
    func effectiveCIStatus(ignoredChecks: [String]) -> CIStatus {
        guard !ignoredChecks.isEmpty else { return ciStatus }
        let effective = effectiveCheckResults(ignoredChecks: ignoredChecks)
        if effective.isEmpty { return .unknown }
        if effective.contains(where: { $0.status == .failed }) { return .failure }
        if effective.contains(where: { $0.status == .pending }) { return .pending }
        return .success
    }

    /// Recomputed check counts excluding ignored checks.
    func effectiveCheckCounts(ignoredChecks: [String]) -> (total: Int, passed: Int, failed: Int) {
        let effective = effectiveCheckResults(ignoredChecks: ignoredChecks)
        let passed = effective.filter { $0.status == .passed }.count
        let failed = effective.filter { $0.status == .failed }.count
        return (total: effective.count, passed: passed, failed: failed)
    }

    /// Status color recomputed with effective CI status (for ignored checks filtering).
    func effectiveStatusColor(ignoredChecks: [String]) -> Color {
        guard !ignoredChecks.isEmpty else { return statusColor }
        switch state {
        case .merged: return .purple
        case .closed: return .gray
        case .draft: return .gray
        case .open:
            if isInMergeQueue { return .purple }
            switch effectiveCIStatus(ignoredChecks: ignoredChecks) {
            case .success: return .green
            case .failure: return .red
            case .pending: return .orange
            case .unknown: return .gray
            }
        }
    }
}

// MARK: - Review Filter Settings

/// User preferences for the Reviews tab.
struct FilterSettings: Codable, Equatable {
    var hideDrafts: Bool
    var requiredCheckNames: [String]
    var ignoredCheckNames: [String]

    init(
        hideDrafts: Bool = true,
        requiredCheckNames: [String] = [],
        ignoredCheckNames: [String] = []
    ) {
        self.hideDrafts = hideDrafts
        self.requiredCheckNames = requiredCheckNames
        self.ignoredCheckNames = ignoredCheckNames
    }

    // Custom decoder: use decodeIfPresent so that adding new filter
    // properties in the future doesn't break previously-saved JSON.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hideDrafts = try container.decodeIfPresent(Bool.self, forKey: .hideDrafts) ?? true
        requiredCheckNames = try container.decodeIfPresent([String].self, forKey: .requiredCheckNames) ?? []
        ignoredCheckNames = try container.decodeIfPresent([String].self, forKey: .ignoredCheckNames) ?? []
    }

    /// Filter a list of PRs for the Reviews tab, removing draft PRs when configured.
    func applyReviewFilters(to prs: [PullRequest]) -> [PullRequest] {
        prs.filter { pr in
            if hideDrafts && pr.state == .draft { return false }
            return true
        }
    }
}
