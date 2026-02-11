import Foundation

/// Abstraction over GitHub API access, enabling mock injection for tests.
protocol GitHubServiceProtocol: Sendable {
    func currentUser() -> String?
    func fetchAllMyOpenPRs(username: String) throws -> [PullRequest]
    func fetchReviewRequestedPRs(username: String) throws -> [PullRequest]
}
