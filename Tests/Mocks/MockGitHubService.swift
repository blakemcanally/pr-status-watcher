import Foundation
@testable import PRStatusWatcher

final class MockGitHubService: GitHubServiceProtocol, @unchecked Sendable {
    var currentUserResult: String? = "testuser"
    var myPRsResult: Result<[PullRequest], Error> = .success([])
    var reviewPRsResult: Result<[PullRequest], Error> = .success([])

    var fetchMyPRsCallCount = 0
    var fetchReviewPRsCallCount = 0

    func currentUser() -> String? { currentUserResult }

    func fetchAllMyOpenPRs(username: String) throws -> [PullRequest] {
        fetchMyPRsCallCount += 1
        return try myPRsResult.get()
    }

    func fetchReviewRequestedPRs(username: String) throws -> [PullRequest] {
        fetchReviewPRsCallCount += 1
        return try reviewPRsResult.get()
    }
}
