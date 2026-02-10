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
            "/usr/bin/gh",
        ]
        self.ghPath = candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? "gh" // fallback to PATH lookup
    }

    // MARK: - Public API

    /// Check that `gh` is installed and authenticated.
    func checkCLI() throws {
        let (_, _, exit) = try run(["auth", "status"])
        if exit != 0 {
            throw GHError.notAuthenticated
        }
    }

    /// Returns the GitHub username from `gh auth status`.
    func currentUser() -> String? {
        guard let (out, _, _) = try? run(["auth", "status", "--active"]) else { return nil }
        // Parse "Logged in to github.com account USERNAME" from the output
        for line in out.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("Logged in to") && trimmed.contains("account") {
                // Format: "✓ Logged in to github.com account blakemcanally (keyring)"
                if let range = trimmed.range(of: "account ") {
                    let after = trimmed[range.upperBound...]
                    let username = after.prefix(while: { !$0.isWhitespace && $0 != "(" })
                    if !username.isEmpty { return String(username) }
                }
            }
        }
        return nil
    }

    /// Fetch all open PRs authored by the given user in a single GraphQL call.
    /// Returns fully populated PullRequest objects including CI status.
    func fetchAllMyOpenPRs(username: String) throws -> [PullRequest] {
        let query = """
        query {
          search(query: "author:\(username) type:pr state:open", type: ISSUE, first: 100) {
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
                headRefOid
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
        let mergeQueueEntry = node["mergeQueueEntry"] as? [String: Any]
        let queuePosition = mergeQueueEntry?["position"] as? Int

        // Review decision
        let rawReview = node["reviewDecision"] as? String ?? ""
        let reviewDecision: PullRequest.ReviewDecision
        switch rawReview {
        case "APPROVED":          reviewDecision = .approved
        case "CHANGES_REQUESTED": reviewDecision = .changesRequested
        case "REVIEW_REQUIRED":   reviewDecision = .reviewRequired
        default:                  reviewDecision = .none
        }

        // Mergeable state
        let rawMergeable = node["mergeable"] as? String ?? ""
        let mergeable: PullRequest.MergeableState
        switch rawMergeable {
        case "MERGEABLE":   mergeable = .mergeable
        case "CONFLICTING": mergeable = .conflicting
        default:            mergeable = .unknown
        }

        let state: PullRequest.PRState
        switch rawState {
        case "MERGED":  state = .merged
        case "CLOSED":  state = .closed
        default:        state = isDraft ? .draft : .open
        }

        // Parse CI status from statusCheckRollup
        let ci = parseCheckStatus(from: node)

        return PullRequest(
            owner: owner,
            repo: repo,
            number: number,
            title: title,
            author: author,
            state: state,
            ciStatus: ci.status,
            isInMergeQueue: mergeQueueEntry != nil,
            checksTotal: ci.total,
            checksPassed: ci.passed,
            checksFailed: ci.failed,
            url: url,
            headSHA: String(headSHA.prefix(7)),
            lastFetched: Date(),
            reviewDecision: reviewDecision,
            mergeable: mergeable,
            queuePosition: queuePosition,
            failedChecks: ci.failedChecks
        )
    }

    private struct CIResult {
        let status: PullRequest.CIStatus
        let total: Int
        let passed: Int
        let failed: Int
        let failedChecks: [PullRequest.CheckInfo]
    }

    private func parseCheckStatus(from node: [String: Any]) -> CIResult {
        // Navigate: commits.nodes[0].commit.statusCheckRollup.contexts.nodes
        guard let commits = node["commits"] as? [String: Any],
              let commitNodes = commits["nodes"] as? [[String: Any]],
              let firstCommit = commitNodes.first,
              let commit = firstCommit["commit"] as? [String: Any],
              let rollup = commit["statusCheckRollup"] as? [String: Any],
              let contexts = rollup["contexts"] as? [String: Any],
              let totalCount = contexts["totalCount"] as? Int,
              let contextNodes = contexts["nodes"] as? [[String: Any]]
        else {
            return CIResult(status: .unknown, total: 0, passed: 0, failed: 0, failedChecks: [])
        }

        var passed = 0, failed = 0, pending = 0
        var failedChecks: [PullRequest.CheckInfo] = []

        for ctx in contextNodes {
            let status = ctx["status"] as? String ?? ""
            let conclusion = ctx["conclusion"] as? String ?? ""

            if status.isEmpty && conclusion.isEmpty {
                // StatusContext nodes (not CheckRun) show up as empty dicts in our query;
                // count them based on the rollup state if needed, or skip
                continue
            }

            if status == "COMPLETED" {
                switch conclusion {
                case "SUCCESS", "SKIPPED", "NEUTRAL":
                    passed += 1
                default:
                    failed += 1
                    // Collect failed check info
                    if let name = ctx["name"] as? String {
                        let detailsUrl = (ctx["detailsUrl"] as? String).flatMap { URL(string: $0) }
                        failedChecks.append(PullRequest.CheckInfo(name: name, detailsUrl: detailsUrl))
                    }
                }
            } else {
                pending += 1
            }
        }

        // Use totalCount from the API for accuracy (contextNodes may be partial)
        let ciStatus: PullRequest.CIStatus
        if totalCount == 0 {
            ciStatus = .unknown
        } else if failed > 0 {
            ciStatus = .failure
        } else if pending > 0 {
            ciStatus = .pending
        } else if passed == 0 {
            // All nodes were empty StatusContexts — check the rollup state
            let rollupState = rollup["state"] as? String ?? ""
            switch rollupState {
            case "SUCCESS":  ciStatus = .success
            case "FAILURE", "ERROR":  ciStatus = .failure
            case "PENDING":  ciStatus = .pending
            default:         ciStatus = .unknown
            }
        } else {
            ciStatus = .success
        }

        return CIResult(status: ciStatus, total: totalCount, passed: passed, failed: failed, failedChecks: failedChecks)
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
