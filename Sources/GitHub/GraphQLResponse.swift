import Foundation

// MARK: - GitHub GraphQL API Response Types

/// Top-level response from `gh api graphql`.
struct GraphQLResponse: Codable {
    let data: GraphQLData?
    let errors: [GraphQLError]?
}

struct GraphQLError: Codable {
    let message: String
    let type: String?
}

struct GraphQLData: Codable {
    let search: SearchResult
}

struct SearchResult: Codable {
    let pageInfo: PageInfo?
    let nodes: [PRNode]
}

struct PageInfo: Codable {
    let hasNextPage: Bool
    let endCursor: String?
}

/// A PR node from the GraphQL search results.
/// All fields are optional to handle partial/malformed responses from
/// inline fragments gracefully — the conversion to `PullRequest` validates
/// required fields.
struct PRNode: Codable {
    let number: Int?
    let title: String?
    let publishedAt: String?
    let url: String?
    let repository: RepositoryRef?
    let author: AuthorRef?
    let isDraft: Bool?
    let state: String?
    let reviewDecision: String?
    let mergeable: String?
    let mergeQueueEntry: MergeQueueEntryRef?
    let reviews: ReviewsRef?
    let latestReviews: LatestReviewsConnection?
    let headRefOid: String?
    let headRefName: String?
    let commits: CommitConnection?

    struct RepositoryRef: Codable {
        let nameWithOwner: String
    }

    struct AuthorRef: Codable {
        let login: String
    }

    struct MergeQueueEntryRef: Codable {
        let position: Int?
    }

    struct ReviewsRef: Codable {
        let totalCount: Int
    }

    struct LatestReviewNode: Codable {
        let author: AuthorRef?
        let state: String?
    }

    struct LatestReviewsConnection: Codable {
        let nodes: [LatestReviewNode]
    }

    struct CommitConnection: Codable {
        let nodes: [CommitNode]?
    }

    struct CommitNode: Codable {
        let commit: CommitRef
    }

    struct CommitRef: Codable {
        let statusCheckRollup: StatusCheckRollup?
    }

    struct StatusCheckRollup: Codable {
        let state: String?
        let contexts: CheckContextConnection?
    }

    struct CheckContextConnection: Codable {
        let totalCount: Int
        let nodes: [CheckContext]
    }

    /// Represents either a CheckRun or a StatusContext.
    /// Both inline fragment types decode into one struct with optional fields.
    struct CheckContext: Codable {
        // CheckRun fields
        let name: String?
        let status: String?
        let conclusion: String?
        let detailsUrl: String?
        // StatusContext fields
        let context: String?
        let state: String?
        let targetUrl: String?
    }
}
