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
        // Stage 1: Check known install locations (fastest)
        if let known = AppConstants.GitHub.knownBinaryPaths
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            self.ghPath = known
            logger.info("init: gh found at known path: \(known, privacy: .public)")
            return
        }

        // Stage 2: Search PATH
        if let pathResolved = Self.resolveFromPATH("gh") {
            self.ghPath = pathResolved
            logger.info("init: gh found via PATH: \(pathResolved, privacy: .public)")
            return
        }

        // Fallback: bare "gh" and hope Process can find it
        self.ghPath = "gh"
        logger.warning("init: gh not found at known paths or in PATH, falling back to bare 'gh'")
    }

    /// Search the system PATH for an executable by name.
    /// Returns the full path if found, nil otherwise.
    static func resolveFromPATH(_ binary: String) -> String? {
        guard let pathEnv = ProcessInfo.processInfo.environment["PATH"] else { return nil }
        let directories = pathEnv.split(separator: ":").map(String.init)
        for dir in directories {
            let candidate = (dir as NSString).appendingPathComponent(binary)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Public API

    /// Returns the GitHub username from `gh api user`.
    func currentUser() -> String? {
        logger.info("currentUser: resolving via gh api user")
        let output: (stdout: String, stderr: String, exitCode: Int32)
        do {
            output = try run(["api", "user", "--jq", ".login"])
        } catch GHError.cliNotFound {
            logger.error("currentUser: gh CLI not found at path '\(self.ghPath, privacy: .public)'")
            return nil
        } catch GHError.timeout {
            logger.error("currentUser: gh CLI timed out during user resolution")
            return nil
        } catch {
            logger.error("currentUser: unexpected error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        if output.exitCode != 0 {
            logger.error("currentUser: exit=\(output.exitCode), stderr=\(output.stderr.prefix(200), privacy: .public)")
        }
        guard output.exitCode == 0 else { return nil }
        let username = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info("currentUser: resolved to '\(username, privacy: .public)'")
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

    /// Escape special characters for safe interpolation into a GraphQL/JSON string literal.
    private func escapeForGraphQL(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Maximum number of pages to fetch before stopping (1000 PRs at 100/page).
    private static let maxPages = 10

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

            let page = try fetchPRPage(
                escapedQuery: escapedQuery,
                cursor: cursor,
                searchQuery: searchQuery
            )
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
        let afterClause = cursor.map { #", after: \"\#($0)\""# } ?? ""
        let query = buildSearchQuery(
            escapedQuery: escapedQuery,
            pageSize: pageSize,
            afterClause: afterClause
        )

        logger.info(
            "fetchPRs: query=\(searchQuery.prefix(80), privacy: .public), cursor=\(cursor ?? "nil", privacy: .public)"
        )
        let (stdout, stderr, exit) = try run(["api", "graphql", "-f", "query=\(query)"])

        guard exit == 0 else {
            logger.error("fetchPRs: exit=\(exit), stderr=\(stderr.prefix(500), privacy: .public)")
            throw GHError.apiError(stderr.isEmpty ? stdout : stderr)
        }

        guard let data = stdout.data(using: .utf8) else {
            logger.error("fetchPRs: failed to convert stdout to Data")
            throw GHError.invalidJSON
        }

        let response: GraphQLResponse
        do {
            response = try JSONDecoder().decode(GraphQLResponse.self, from: data)
        } catch {
            logger.error("fetchPRs: JSON decode failed: \(error.localizedDescription, privacy: .public)")
            throw GHError.invalidJSON
        }

        // Surface GraphQL errors (rate limits, schema errors, partial failures)
        if let errors = response.errors, let first = errors.first {
            logger.error("fetchPRs: GraphQL error: \(first.message, privacy: .public)")
            throw GHError.apiError(first.message)
        }

        guard let searchResult = response.data?.search else {
            logger.error("fetchPRs: missing data.search in response")
            throw GHError.invalidJSON
        }

        var skippedCount = 0
        let prs = searchResult.nodes.compactMap { node -> PullRequest? in
            guard let parsed = convertNode(node) else {
                skippedCount += 1
                let nodeNum = node.number.map(String.init) ?? "nil"
                let nodeTitle = node.title?.prefix(50).description ?? "nil"
                logger.warning(
                    "fetchPRs: skipping malformed node (number=\(nodeNum, privacy: .public), title=\"\(nodeTitle, privacy: .public)\")"
                )
                return nil
            }
            return parsed
        }

        if skippedCount > 0 {
            logger.warning("fetchPRs: skipped \(skippedCount) malformed nodes out of \(searchResult.nodes.count)")
        }

        let hasNextPage = searchResult.pageInfo?.hasNextPage ?? false
        let nextCursor = hasNextPage ? searchResult.pageInfo?.endCursor : nil

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

    // MARK: - Node Conversion (Codable → PullRequest)

    func convertNode(_ node: PRNode) -> PullRequest? {
        guard let number = node.number,
              let title = node.title,
              let urlString = node.url,
              let url = URL(string: urlString),
              let nameWithOwner = node.repository?.nameWithOwner
        else { return nil }

        let repoParts = nameWithOwner.split(separator: "/")
        guard repoParts.count == 2 else { return nil }
        let owner = String(repoParts[0])
        let repo = String(repoParts[1])

        let author = node.author?.login ?? "unknown"
        let isDraft = node.isDraft ?? false
        let rawState = node.state ?? "OPEN"
        let headSHA = node.headRefOid ?? ""
        let headRefName = node.headRefName ?? ""
        let queuePosition = node.mergeQueueEntry?.position
        let approvalCount = node.reviews?.totalCount ?? 0

        let reviewDecision = parseReviewDecision(raw: node.reviewDecision)
        let mergeable = parseMergeableState(raw: node.mergeable)
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
            isInMergeQueue: node.mergeQueueEntry != nil,
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

    func parseReviewDecision(raw: String?) -> PullRequest.ReviewDecision {
        switch raw ?? "" {
        case "APPROVED": return .approved
        case "CHANGES_REQUESTED": return .changesRequested
        case "REVIEW_REQUIRED": return .reviewRequired
        default: return .none
        }
    }

    func parseMergeableState(raw: String?) -> PullRequest.MergeableState {
        switch raw ?? "" {
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

    // MARK: - Check Status Parsing (typed)

    struct TypedRollupData {
        let rollupState: String?
        let totalCount: Int
        let contextNodes: [PRNode.CheckContext]
    }

    func parseCheckStatus(from node: PRNode) -> CIResult {
        guard let rollupData = extractRollupData(from: node) else {
            return CIResult(status: .unknown, total: 0, passed: 0, failed: 0, failedChecks: [])
        }

        let counts = tallyCheckContexts(rollupData.contextNodes)

        let ciStatus = resolveOverallStatus(
            totalCount: rollupData.totalCount,
            passed: counts.passed,
            failed: counts.failed,
            pending: counts.pending,
            rollupState: rollupData.rollupState
        )

        return CIResult(
            status: ciStatus,
            total: rollupData.totalCount,
            passed: counts.passed,
            failed: counts.failed,
            failedChecks: counts.failedChecks
        )
    }

    func extractRollupData(from node: PRNode) -> TypedRollupData? {
        guard let commits = node.commits?.nodes,
              let firstCommit = commits.first,
              let rollup = firstCommit.commit.statusCheckRollup,
              let contexts = rollup.contexts
        else { return nil }

        if contexts.totalCount > contexts.nodes.count {
            logger.warning(
                "extractRollupData: check contexts truncated — \(contexts.nodes.count)/\(contexts.totalCount) fetched"
            )
        }

        return TypedRollupData(
            rollupState: rollup.state,
            totalCount: contexts.totalCount,
            contextNodes: contexts.nodes
        )
    }

    struct CheckCounts {
        var passed: Int
        var failed: Int
        var pending: Int
        var failedChecks: [PullRequest.CheckInfo]
    }

    func tallyCheckContexts(_ contexts: [PRNode.CheckContext]) -> CheckCounts {
        var counts = CheckCounts(passed: 0, failed: 0, pending: 0, failedChecks: [])

        for ctx in contexts {
            if let contextName = ctx.context {
                // StatusContext node
                switch ctx.state ?? "" {
                case "SUCCESS":
                    counts.passed += 1
                case "FAILURE", "ERROR":
                    counts.failed += 1
                    let targetUrl = ctx.targetUrl.flatMap { URL(string: $0) }
                    counts.failedChecks.append(PullRequest.CheckInfo(name: contextName, detailsUrl: targetUrl))
                case "PENDING", "EXPECTED":
                    counts.pending += 1
                default:
                    counts.pending += 1
                }
            } else {
                // CheckRun node
                let status = ctx.status ?? ""
                let conclusion = ctx.conclusion ?? ""

                if status.isEmpty && conclusion.isEmpty { continue }

                if status == "COMPLETED" {
                    classifyCompletedCheckContext(ctx, conclusion: conclusion, counts: &counts)
                } else {
                    counts.pending += 1
                }
            }
        }

        return counts
    }

    func classifyCompletedCheckContext(
        _ ctx: PRNode.CheckContext,
        conclusion: String,
        counts: inout CheckCounts
    ) {
        switch conclusion {
        case "SUCCESS", "SKIPPED", "NEUTRAL":
            counts.passed += 1
        default:
            counts.failed += 1
            if let name = ctx.name {
                let detailsUrl = ctx.detailsUrl.flatMap { URL(string: $0) }
                counts.failedChecks.append(PullRequest.CheckInfo(name: name, detailsUrl: detailsUrl))
            }
        }
    }

    func resolveOverallStatus(
        totalCount: Int,
        passed: Int,
        failed: Int,
        pending: Int,
        rollupState: String?
    ) -> PullRequest.CIStatus {
        if totalCount == 0 { return .unknown }
        if failed > 0 { return .failure }
        if pending > 0 { return .pending }

        // All nodes were empty StatusContexts — fall back to rollup state
        if passed == 0 {
            switch rollupState ?? "" {
            case "SUCCESS": return .success
            case "FAILURE", "ERROR": return .failure
            case "PENDING": return .pending
            default: return .unknown
            }
        }

        return .success
    }

    // MARK: - gh CLI Helpers

    private static let processTimeout: TimeInterval = AppConstants.GitHub.processTimeoutSeconds

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
            DispatchQueue.global().asyncAfter(deadline: .now() + AppConstants.GitHub.terminationGracePeriod) {
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
            return Strings.Error.ghCliNotFound
        case .apiError(let msg):
            let trimmed = msg.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? Strings.Error.ghApiErrorFallback : trimmed
        case .invalidJSON:
            return Strings.Error.ghInvalidJSON
        case .timeout:
            return Strings.Error.ghTimeout
        case .processLaunchFailed(let detail):
            return Strings.Error.ghProcessLaunchFailed(detail)
        }
    }
}
