import Foundation

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
    var lastFetched: Date
    var reviewDecision: ReviewDecision
    var mergeable: MergeableState
    var queuePosition: Int?
    var failedChecks: [CheckInfo]

    var repoFullName: String { "\(owner)/\(repo)" }
    var displayNumber: String { "#\(number)" }

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

// MARK: - Placeholder factory (used while loading)

extension PullRequest {
    static func placeholder(owner: String, repo: String, number: Int) -> PullRequest {
        PullRequest(
            owner: owner,
            repo: repo,
            number: number,
            title: "Loading\u{2026}",
            author: "",
            state: .open,
            ciStatus: .unknown,
            isInMergeQueue: false,
            checksTotal: 0,
            checksPassed: 0,
            checksFailed: 0,
            url: URL(string: "https://github.com/\(owner)/\(repo)/pull/\(number)")!,
            headSHA: "",
            lastFetched: .distantPast,
            reviewDecision: .none,
            mergeable: .unknown,
            queuePosition: nil,
            failedChecks: []
        )
    }
}

// MARK: - PR URL / Reference Parser

struct PRReference {
    let owner: String
    let repo: String
    let number: Int

    /// Parse a GitHub PR reference from either:
    ///   - Full URL:   https://github.com/owner/repo/pull/123
    ///   - Shorthand:  owner/repo#123
    static func parse(from input: String) -> PRReference? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try full URL format
        if let url = URL(string: trimmed),
           let host = url.host,
           (host == "github.com" || host == "www.github.com")
        {
            let parts = url.pathComponents
            // pathComponents: ["/", "owner", "repo", "pull", "123"]
            if parts.count >= 5, parts[3] == "pull",
               let num = Int(parts[4])
            {
                return PRReference(owner: parts[1], repo: parts[2], number: num)
            }
        }

        // Try shorthand: owner/repo#123
        let pattern = #"^([a-zA-Z0-9_.\-]+)/([a-zA-Z0-9_.\-]+)#(\d+)$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let ownerRange = Range(match.range(at: 1), in: trimmed),
           let repoRange = Range(match.range(at: 2), in: trimmed),
           let numRange = Range(match.range(at: 3), in: trimmed),
           let num = Int(trimmed[numRange])
        {
            return PRReference(
                owner: String(trimmed[ownerRange]),
                repo: String(trimmed[repoRange]),
                number: num
            )
        }

        return nil
    }
}
