import Foundation
import os
// MARK: - GitHub Service (via `gh` CLI)

private let logger = Logger(subsystem: "PRStatusWatcher", category: "GitHubService")

/// Thread-safe: all stored properties are `let` and `Sendable`.
/// If mutable state is ever added, convert to `actor` instead of using `@unchecked`.
final class GitHubService: GitHubServiceProtocol, Sendable {
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
        logger.info("currentUser: resolving via gh api user")
        let out: String
        let stderr: String
        let exit: Int32
        do {
            (out, stderr, exit) = try run(["api", "user", "--jq", ".login"])
        } catch let error as GHError {
            logger.error("currentUser: \(error.localizedDescription, privacy: .public)")
            return nil
        } catch {
            logger.error("currentUser: unexpected error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        if exit != 0 {
            logger.error("currentUser: exit=\(exit), stderr=\(stderr.prefix(200), privacy: .public)")
        }
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

    /// Maximum number of pages to fetch before stopping (1000 PRs at 100/page).
    private static let maxPages = 10

    /// Escape special characters for safe interpolation into a GraphQL/JSON string literal.
    private func escapeForGraphQL(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Fetch PRs matching an arbitrary GitHub search query string, with cursor-based pagination.
    private func fetchPRs(searchQuery: String) throws -> [PullRequest] {
        let escapedQuery = escapeForGraphQL(searchQuery)
        var allPRs: [PullRequest] = []
        var cursor: String?
        var pageCount = 0

        repeat {
            pageCount += 1
            if pageCount > Self.maxPages {
                logger.warning("fetchPRs: reached max page limit (\(Self.maxPages)), stopping pagination")
                break
            }

            let page = try fetchPRPage(escapedQuery: escapedQuery, cursor: cursor, searchQuery: searchQuery)
            allPRs.append(contentsOf: page.prs)

            logger.info(
                "fetchPRs: parsed \(page.prs.count) PRs from page \(pageCount) (total: \(allPRs.count))"
            )

            cursor = page.nextCursor
        } while cursor != nil

        return allPRs
    }

    /// Result of fetching a single page of PR search results.
    private struct PRPageResult {
        let prs: [PullRequest]
        let nextCursor: String?
    }

    /// Build the GraphQL query for a single page and parse the response.
    private func fetchPRPage(
        escapedQuery: String,
        cursor: String?,
        searchQuery: String
    ) throws -> PRPageResult {
        let pageSize = 100
        let afterClause = cursor.map { #", after: "\#($0)""# } ?? ""
        let query = buildSearchQuery(escapedQuery: escapedQuery, pageSize: pageSize, afterClause: afterClause)

        logger.info(
            "fetchPRs: query=\(searchQuery.prefix(80), privacy: .public), cursor=\(cursor ?? "nil", privacy: .public)"
        )
        let (stdout, stderr, exit) = try run(["api", "graphql", "-f", "query=\(query)"])

        guard exit == 0 else {
            logger.error("fetchPRs: exit=\(exit), stderr=\(stderr.prefix(500), privacy: .public)")
            throw GHError.apiError(stderr.isEmpty ? stdout : stderr)
        }

        let search = try parseGraphQLSearchResponse(stdout)

        let nodes = search["nodes"] as? [[String: Any]] ?? []
        let prs = nodes.compactMap { node -> PullRequest? in
            guard let parsed = parsePRNode(node) else {
                logger.debug("fetchPRs: skipping malformed PR node: \(String(describing: node["number"]))")
                return nil
            }
            return parsed
        }

        let pageInfo = search["pageInfo"] as? [String: Any]
        let hasNextPage = pageInfo?["hasNextPage"] as? Bool ?? false
        let nextCursor = hasNextPage ? (pageInfo?["endCursor"] as? String) : nil

        return PRPageResult(prs: prs, nextCursor: nextCursor)
    }

    /// Build the GraphQL search query string for a single page.
    private func buildSearchQuery(escapedQuery: String, pageSize: Int, afterClause: String) -> String {
        """
        query {
          search(query: "\(escapedQuery)", type: ISSUE, first: \(pageSize)\(afterClause)) {
            pageInfo {
              hasNextPage
              endCursor
            }
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
    }

    /// Parse a GraphQL response string into the `search` dictionary, surfacing errors.
    private func parseGraphQLSearchResponse(_ stdout: String) throws -> [String: Any] {
        guard let data = stdout.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            logger.error("fetchPRs: failed to parse JSON response")
            throw GHError.invalidJSON
        }

        // Surface GraphQL errors (rate limits, schema errors, auth failures)
        if let errors = json["errors"] as? [[String: Any]],
           let firstError = errors.first,
           let message = firstError["message"] as? String {
            logger.error("fetchPRs: GraphQL error: \(message, privacy: .public)")
            throw GHError.apiError(message)
        }

        guard let dataDict = json["data"] as? [String: Any],
              let search = dataDict["search"] as? [String: Any]
        else {
            logger.error("fetchPRs: unexpected JSON structure")
            throw GHError.invalidJSON
        }

        return search
    }

    // MARK: - GraphQL Response Parsing

    func parsePRNode(_ node: [String: Any]) -> PullRequest? {
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

    func parseReviewDecision(from node: [String: Any]) -> PullRequest.ReviewDecision {
        let raw = node["reviewDecision"] as? String ?? ""
        switch raw {
        case "APPROVED": return .approved
        case "CHANGES_REQUESTED": return .changesRequested
        case "REVIEW_REQUIRED": return .reviewRequired
        default: return .none
        }
    }

    func parseMergeableState(from node: [String: Any]) -> PullRequest.MergeableState {
        let raw = node["mergeable"] as? String ?? ""
        switch raw {
        case "MERGEABLE": return .mergeable
        case "CONFLICTING": return .conflicting
        default: return .unknown
        }
    }

    func parsePRState(rawState: String, isDraft: Bool) -> PullRequest.PRState {
        switch rawState {
        case "MERGED": return .merged
        case "CLOSED": return .closed
        default: return isDraft ? .draft : .open
        }
    }

    struct CIResult {
        let status: PullRequest.CIStatus
        let total: Int
        let passed: Int
        let failed: Int
        let failedChecks: [PullRequest.CheckInfo]
    }

    func parseCheckStatus(from node: [String: Any]) -> CIResult {
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

    struct RollupData {
        let rollup: [String: Any]
        let totalCount: Int
        let contextNodes: [[String: Any]]
    }

    func extractRollupData(from node: [String: Any]) -> RollupData? {
        guard let commits = node["commits"] as? [String: Any],
              let commitNodes = commits["nodes"] as? [[String: Any]],
              let firstCommit = commitNodes.first,
              let commit = firstCommit["commit"] as? [String: Any],
              let rollup = commit["statusCheckRollup"] as? [String: Any],
              let contexts = rollup["contexts"] as? [String: Any],
              let totalCount = contexts["totalCount"] as? Int,
              let contextNodes = contexts["nodes"] as? [[String: Any]]
        else { return nil }

        if totalCount > contextNodes.count {
            logger.warning(
                "extractRollupData: check contexts truncated — \(contextNodes.count)/\(totalCount) fetched"
            )
        }

        return RollupData(rollup: rollup, totalCount: totalCount, contextNodes: contextNodes)
    }

    struct CheckCounts {
        var passed: Int
        var failed: Int
        var pending: Int
        var failedChecks: [PullRequest.CheckInfo]
    }

    func tallyCheckContexts(_ contextNodes: [[String: Any]]) -> CheckCounts {
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

    func classifyCompletedCheck(
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

    func resolveOverallStatus(
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

    private static let processTimeout: TimeInterval = 30

    /// Run a `gh` subcommand synchronously and capture output.
    ///
    /// Drains stdout and stderr on background threads to avoid a pipe-buffer
    /// deadlock: if the subprocess writes more than ~64 KB to a pipe before the
    /// parent reads it, the write blocks — and if the parent is stuck in
    /// `waitUntilExit()`, both sides deadlock.
    ///
    /// The process is terminated if it hasn't exited within `processTimeout`
    /// seconds, and `GHError.timeout` is thrown.
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
            logger.error("run: process launch failed: \(error.localizedDescription, privacy: .public)")
            throw GHError.processLaunchFailed(error.localizedDescription)
        }

        // Close write ends in parent to ensure EOF when child exits
        outPipe.fileHandleForWriting.closeFile()
        errPipe.fileHandleForWriting.closeFile()

        // Drain both pipes concurrently to prevent pipe-buffer deadlock
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global().async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        // Wait for process with timeout instead of blocking indefinitely
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        let result = semaphore.wait(timeout: .now() + Self.processTimeout)
        if result == .timedOut {
            logger.error("run: gh process timed out after \(Self.processTimeout)s, terminating")
            process.terminate()
            // Give it a moment to clean up, then force-kill if needed
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { process.terminate() }
            }
            throw GHError.timeout
        }

        // Process exited normally — wait for pipes to finish draining
        group.wait()

        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        return (stdout, stderr, process.terminationStatus)
    }
}

// MARK: - Errors

enum GHError: LocalizedError {
    case cliNotFound
    case apiError(String)
    case invalidJSON
    case timeout
    case processLaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            return "GitHub CLI (gh) not found — install it with: brew install gh"
        case .apiError(let msg):
            let trimmed = msg.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "GitHub API error" : trimmed
        case .invalidJSON:
            return "Invalid response from GitHub API"
        case .timeout:
            return "GitHub CLI timed out — check your network connection"
        case .processLaunchFailed(let detail):
            return "Failed to launch GitHub CLI: \(detail)"
        }
    }
}
