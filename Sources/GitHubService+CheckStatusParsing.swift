import Foundation
import os

// MARK: - Check Status Parsing

private let logger = Logger(subsystem: "PRStatusWatcher", category: "GitHubService.CheckStatus")

extension GitHubService {

    struct CIResult {
        let status: PullRequest.CIStatus
        let total: Int
        let passed: Int
        let failed: Int
        let failedChecks: [PullRequest.CheckInfo]
        let checkResults: [PullRequest.CheckResult]
    }

    struct TypedRollupData {
        let rollupState: String?
        let totalCount: Int
        let contextNodes: [PRNode.CheckContext]
    }

    func parseCheckStatus(from node: PRNode) -> CIResult {
        guard let rollupData = extractRollupData(from: node) else {
            return CIResult(status: .unknown, total: 0, passed: 0, failed: 0,
                            failedChecks: [], checkResults: [])
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
            failedChecks: counts.failedChecks,
            checkResults: counts.allChecks
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
        var allChecks: [PullRequest.CheckResult]
    }

    func tallyCheckContexts(_ contexts: [PRNode.CheckContext]) -> CheckCounts {
        var counts = CheckCounts(passed: 0, failed: 0, pending: 0, failedChecks: [], allChecks: [])

        for ctx in contexts {
            if let contextName = ctx.context {
                // StatusContext node
                let targetUrl = ctx.targetUrl.flatMap { URL(string: $0) }
                switch ctx.state ?? "" {
                case "SUCCESS":
                    counts.passed += 1
                    counts.allChecks.append(PullRequest.CheckResult(
                        name: contextName, status: .passed, detailsUrl: targetUrl
                    ))
                case "FAILURE", "ERROR":
                    counts.failed += 1
                    counts.failedChecks.append(PullRequest.CheckInfo(name: contextName, detailsUrl: targetUrl))
                    counts.allChecks.append(PullRequest.CheckResult(
                        name: contextName, status: .failed, detailsUrl: targetUrl
                    ))
                default: // PENDING, EXPECTED, or unknown
                    counts.pending += 1
                    counts.allChecks.append(PullRequest.CheckResult(
                        name: contextName, status: .pending, detailsUrl: targetUrl
                    ))
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
                    if let name = ctx.name {
                        counts.allChecks.append(PullRequest.CheckResult(
                            name: name, status: .pending,
                            detailsUrl: ctx.detailsUrl.flatMap { URL(string: $0) }
                        ))
                    }
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
        let detailsUrl = ctx.detailsUrl.flatMap { URL(string: $0) }
        switch conclusion {
        case "SUCCESS", "SKIPPED", "NEUTRAL":
            counts.passed += 1
            if let name = ctx.name {
                counts.allChecks.append(PullRequest.CheckResult(
                    name: name, status: .passed, detailsUrl: detailsUrl
                ))
            }
        default:
            counts.failed += 1
            if let name = ctx.name {
                counts.failedChecks.append(PullRequest.CheckInfo(name: name, detailsUrl: detailsUrl))
                counts.allChecks.append(PullRequest.CheckResult(
                    name: name, status: .failed, detailsUrl: detailsUrl
                ))
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
}
