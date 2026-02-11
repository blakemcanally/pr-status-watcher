import Foundation

// MARK: - GitHub Service (via `gh` CLI)

final class GitHubService: @unchecked Sendable {
    /// Path to the gh binary. Resolved once at init.
    private let ghPath: String

    init() {
        // Common install locations
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh"
        ]
        self.ghPath = candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? "gh" // fallback to PATH lookup
    }

    // MARK: - Public API

    /// Returns the GitHub username from `gh api user`.
    func currentUser() -> String? {
        guard let (out, _, exit) = try? run(["api", "user", "--jq", ".login"]) else { return nil }
        guard exit == 0 else { return nil }
        let username = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return username.isEmpty ? nil : username
    }

    /// Fetch all open PRs authored by the given user.
    func fetchAllMyOpenPRs(username: String) throws -> [PullRequest] {
        try fetchPRs(searchQuery: "author:\(username) type:pr state:open")
    }

    /// Fetch open PRs where the given user has a pending review request.
    func fetchReviewRequestedPRs(username: String) throws -> [PullRequest] {
        try fetchPRs(searchQuery: "review-requested:\(username) type:pr state:open")
    }

    // MARK: - Shared Fetch

    /// Fetch PRs matching an arbitrary GitHub search query string.
    private func fetchPRs(searchQuery: String) throws -> [PullRequest] {
        let query = """
        query {
          search(query: "\(searchQuery)", type: ISSUE, first: 100) {
            nodes {
              ... on PullRequest {
                number
                title
                author { login }
                isDraft
                state
                url
                repository { nameWithOwner }
                reviewDecision
                mergeable
                mergeQueueEntry { position }
                reviews(states: APPROVED, first: 0) { totalCount }
                headRefOid
                headRefName
                commits(last: 1) {
                  nodes {
                    commit {
                      statusCheckRollup {
                        state
                        contexts(first: 100) {
                          totalCount
                          nodes {
                            ... on CheckRun {
                              name
                              status
                              conclusion
                              detailsUrl
                            }
                            ... on StatusContext {
                              context
                              state
                              targetUrl
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        """

        let (stdout, stderr, exit) = try run(["api", "graphql", "-f", "query=\(query)"])

        guard exit == 0 else {
            throw GHError.apiError(stderr.isEmpty ? stdout : stderr)
        }

        guard let data = stdout.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let search = dataDict["search"] as? [String: Any],
              let nodes = search["nodes"] as? [[String: Any]]
        else {
            throw GHError.invalidJSON
        }

        return nodes.compactMap { node -> PullRequest? in
            parsePRNode(node)
        }
    }

    // MARK: - GraphQL Response Parsing

    private func parsePRNode(_ node: [String: Any]) -> PullRequest? {
        guard let number = node["number"] as? Int,
              let title = node["title"] as? String,
              let urlString = node["url"] as? String,
              let url = URL(string: urlString),
              let repoDict = node["repository"] as? [String: Any],
              let nameWithOwner = repoDict["nameWithOwner"] as? String
        else { return nil }

        let repoParts = nameWithOwner.split(separator: "/")
        guard repoParts.count == 2 else { return nil }
        let owner = String(repoParts[0])
        let repo = String(repoParts[1])

        let authorDict = node["author"] as? [String: Any]
        let author = authorDict?["login"] as? String ?? "unknown"
        let isDraft = node["isDraft"] as? Bool ?? false
        let rawState = node["state"] as? String ?? "OPEN"
        let headSHA = node["headRefOid"] as? String ?? ""
        let headRefName = node["headRefName"] as? String ?? ""
        let mergeQueueEntry = node["mergeQueueEntry"] as? [String: Any]
        let queuePosition = mergeQueueEntry?["position"] as? Int
        let reviewsDict = node["reviews"] as? [String: Any]
        let approvalCount = reviewsDict?["totalCount"] as? Int ?? 0

        let reviewDecision = parseReviewDecision(from: node)
        let mergeable = parseMergeableState(from: node)
        let state = parsePRState(rawState: rawState, isDraft: isDraft)
        let checkResult = parseCheckStatus(from: node)

        return PullRequest(
            owner: owner,
            repo: repo,
            number: number,
            title: title,
            author: author,
            state: state,
            ciStatus: checkResult.status,
            isInMergeQueue: mergeQueueEntry != nil,
            checksTotal: checkResult.total,
            checksPassed: checkResult.passed,
            checksFailed: checkResult.failed,
            url: url,
            headSHA: String(headSHA.prefix(7)),
            headRefName: headRefName,
            lastFetched: Date(),
            reviewDecision: reviewDecision,
            mergeable: mergeable,
            queuePosition: queuePosition,
            approvalCount: approvalCount,
            failedChecks: checkResult.failedChecks
        )
    }

    private func parseReviewDecision(from node: [String: Any]) -> PullRequest.ReviewDecision {
        let raw = node["reviewDecision"] as? String ?? ""
        switch raw {
        case "APPROVED": return .approved
        case "CHANGES_REQUESTED": return .changesRequested
        case "REVIEW_REQUIRED": return .reviewRequired
        default: return .none
        }
    }

    private func parseMergeableState(from node: [String: Any]) -> PullRequest.MergeableState {
        let raw = node["mergeable"] as? String ?? ""
        switch raw {
        case "MERGEABLE": return .mergeable
        case "CONFLICTING": return .conflicting
        default: return .unknown
        }
    }

    private func parsePRState(rawState: String, isDraft: Bool) -> PullRequest.PRState {
        switch rawState {
        case "MERGED": return .merged
        case "CLOSED": return .closed
        default: return isDraft ? .draft : .open
        }
    }

    private struct CIResult {
        let status: PullRequest.CIStatus
        let total: Int
        let passed: Int
        let failed: Int
        let failedChecks: [PullRequest.CheckInfo]
    }

    private func parseCheckStatus(from node: [String: Any]) -> CIResult {
        guard let rollupData = extractRollupData(from: node) else {
            return CIResult(status: .unknown, total: 0, passed: 0, failed: 0, failedChecks: [])
        }

        let counts = tallyCheckContexts(rollupData.contextNodes)

        let ciStatus = resolveOverallStatus(
            totalCount: rollupData.totalCount,
            passed: counts.passed,
            failed: counts.failed,
            pending: counts.pending,
            rollup: rollupData.rollup
        )

        return CIResult(
            status: ciStatus,
            total: rollupData.totalCount,
            passed: counts.passed,
            failed: counts.failed,
            failedChecks: counts.failedChecks
        )
    }

    private struct RollupData {
        let rollup: [String: Any]
        let totalCount: Int
        let contextNodes: [[String: Any]]
    }

    private func extractRollupData(from node: [String: Any]) -> RollupData? {
        guard let commits = node["commits"] as? [String: Any],
              let commitNodes = commits["nodes"] as? [[String: Any]],
              let firstCommit = commitNodes.first,
              let commit = firstCommit["commit"] as? [String: Any],
              let rollup = commit["statusCheckRollup"] as? [String: Any],
              let contexts = rollup["contexts"] as? [String: Any],
              let totalCount = contexts["totalCount"] as? Int,
              let contextNodes = contexts["nodes"] as? [[String: Any]]
        else { return nil }

        return RollupData(rollup: rollup, totalCount: totalCount, contextNodes: contextNodes)
    }

    private struct CheckCounts {
        var passed: Int
        var failed: Int
        var pending: Int
        var failedChecks: [PullRequest.CheckInfo]
    }

    private func tallyCheckContexts(_ contextNodes: [[String: Any]]) -> CheckCounts {
        var counts = CheckCounts(passed: 0, failed: 0, pending: 0, failedChecks: [])

        for ctx in contextNodes {
            if let contextName = ctx["context"] as? String {
                // StatusContext node
                let state = ctx["state"] as? String ?? ""
                switch state {
                case "SUCCESS":
                    counts.passed += 1
                case "FAILURE", "ERROR":
                    counts.failed += 1
                    let targetUrl = (ctx["targetUrl"] as? String).flatMap { URL(string: $0) }
                    counts.failedChecks.append(PullRequest.CheckInfo(name: contextName, detailsUrl: targetUrl))
                case "PENDING", "EXPECTED":
                    counts.pending += 1
                default:
                    counts.pending += 1
                }
            } else {
                // CheckRun node
                let status = ctx["status"] as? String ?? ""
                let conclusion = ctx["conclusion"] as? String ?? ""

                if status.isEmpty && conclusion.isEmpty { continue }

                if status == "COMPLETED" {
                    classifyCompletedCheck(ctx, conclusion: conclusion, counts: &counts)
                } else {
                    counts.pending += 1
                }
            }
        }

        return counts
    }

    private func classifyCompletedCheck(
        _ ctx: [String: Any],
        conclusion: String,
        counts: inout CheckCounts
    ) {
        switch conclusion {
        case "SUCCESS", "SKIPPED", "NEUTRAL":
            counts.passed += 1
        default:
            counts.failed += 1
            if let name = ctx["name"] as? String {
                let detailsUrl = (ctx["detailsUrl"] as? String).flatMap { URL(string: $0) }
                counts.failedChecks.append(PullRequest.CheckInfo(name: name, detailsUrl: detailsUrl))
            }
        }
    }

    private func resolveOverallStatus(
        totalCount: Int,
        passed: Int,
        failed: Int,
        pending: Int,
        rollup: [String: Any]
    ) -> PullRequest.CIStatus {
        if totalCount == 0 { return .unknown }
        if failed > 0 { return .failure }
        if pending > 0 { return .pending }

        // All nodes were empty StatusContexts — fall back to rollup state
        if passed == 0 {
            let rollupState = rollup["state"] as? String ?? ""
            switch rollupState {
            case "SUCCESS": return .success
            case "FAILURE", "ERROR": return .failure
            case "PENDING": return .pending
            default: return .unknown
            }
        }

        return .success
    }

    // MARK: - gh CLI Helpers

    /// Run a `gh` subcommand synchronously and capture output.
    private func run(_ arguments: [String]) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ghPath)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw GHError.cliNotFound
        }
        process.waitUntilExit()

        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (stdout, stderr, process.terminationStatus)
    }
}

// MARK: - Errors

enum GHError: LocalizedError {
    case cliNotFound
    case notAuthenticated
    case notFound(String)
    case apiError(String)
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            return "GitHub CLI (gh) not found — install it with: brew install gh"
        case .notAuthenticated:
            return "Not logged in — run: gh auth login"
        case .notFound(let path):
            return "Not found: \(path)"
        case .apiError(let msg):
            let trimmed = msg.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "GitHub API error" : trimmed
        case .invalidJSON:
            return "Invalid response from GitHub API"
        }
    }
}
