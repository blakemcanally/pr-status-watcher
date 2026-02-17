import Foundation

// MARK: - Node Conversion (Codable → PullRequest)

extension GitHubService {

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
            failedChecks: checkResult.failedChecks,
            checkResults: checkResult.checkResults
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
}
