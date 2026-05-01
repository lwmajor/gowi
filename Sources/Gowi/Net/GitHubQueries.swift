import Foundation

struct Viewer: Decodable, Equatable {
    let login: String
    let avatarUrl: URL
}

extension GitHubClient {
    // MARK: - viewer

    private struct ViewerQueryData: Decodable {
        let viewer: Viewer
        let rateLimit: RateLimitInfo?
    }

    func fetchViewer() async throws -> Viewer {
        let query = """
        query {
          viewer { login avatarUrl }
          rateLimit { remaining resetAt cost }
        }
        """
        let data: ViewerQueryData = try await send(query)
        return data.viewer
    }

    // MARK: - validateRepo

    private struct ValidateRepoData: Decodable {
        let repository: RepoRef?
        let rateLimit: RateLimitInfo?
        struct RepoRef: Decodable {
            let nameWithOwner: String
        }
    }

    /// Throws `.notFound` if the repo doesn't exist or isn't accessible to the
    /// signed-in user. Returns silently on success.
    func validateRepo(_ repo: TrackedRepo) async throws {
        let query = """
        query($owner: String!, $name: String!) {
          repository(owner: $owner, name: $name) { nameWithOwner }
          rateLimit { remaining resetAt cost }
        }
        """
        let data: ValidateRepoData = try await send(
            query,
            variables: ["owner": repo.owner, "name": repo.name]
        )
        if data.repository == nil {
            throw GitHubError.notFound("\(repo.nameWithOwner) was not found or isn't accessible.")
        }
    }

    // MARK: - fetchOpenPRs (single repo)

    private struct PRsQueryData: Decodable {
        let repository: RepoPRs?
        let rateLimit: RateLimitInfo?
        struct RepoPRs: Decodable {
            let pullRequests: PRNodes
        }
        struct PRNodes: Decodable {
            let totalCount: Int
            let nodes: [PRWire]
        }
    }

    struct PRFetchResult {
        let totalCount: Int
        let pullRequests: [PullRequest]
    }

    struct PRWire: Decodable {
        let id: String
        let number: Int
        let title: String
        let url: URL
        let isDraft: Bool
        let createdAt: Date
        let updatedAt: Date
        let author: Author?
        let reviewDecision: String?
        let commits: CommitsContainer?

        struct Author: Decodable {
            let login: String
            let avatarUrl: URL?
        }
        struct CommitsContainer: Decodable {
            let nodes: [CommitNode]
        }
        struct CommitNode: Decodable {
            let commit: Commit
        }
        struct Commit: Decodable {
            let statusCheckRollup: Rollup?
        }
        struct Rollup: Decodable {
            let state: String
        }
    }

    func fetchOpenPRs(in repo: TrackedRepo) async throws -> PRFetchResult {
        let query = """
        query($owner: String!, $name: String!) {
          repository(owner: $owner, name: $name) {
            pullRequests(states: OPEN, first: 50, orderBy: {field: UPDATED_AT, direction: DESC}) {
              totalCount
              nodes {
                id
                number
                title
                url
                isDraft
                createdAt
                updatedAt
                author { login avatarUrl }
                reviewDecision
                commits(last: 1) {
                  nodes { commit { statusCheckRollup { state } } }
                }
              }
            }
          }
          rateLimit { remaining resetAt cost }
        }
        """
        let data: PRsQueryData = try await send(
            query,
            variables: ["owner": repo.owner, "name": repo.name]
        )
        guard let repoData = data.repository else {
            throw GitHubError.notFound("\(repo.nameWithOwner) was not found or isn't accessible.")
        }
        let prs = repoData.pullRequests.nodes.map { PRMapper.toPullRequest($0, repo: repo) }
        return PRFetchResult(
            totalCount: repoData.pullRequests.totalCount,
            pullRequests: prs
        )
    }
}

/// Mapping wire types → domain model. Public so tests can exercise it directly.
enum PRMapper {
    static func toPullRequest(_ w: GitHubClient.PRWire, repo: TrackedRepo) -> PullRequest {
        PullRequest(
            id: w.id,
            number: w.number,
            title: w.title,
            url: w.url,
            authorLogin: w.author?.login,
            authorAvatarURL: w.author?.avatarUrl,
            isDraft: w.isDraft,
            createdAt: w.createdAt,
            updatedAt: w.updatedAt,
            repo: repo,
            reviewDecision: mapReview(w.reviewDecision),
            checkStatus: mapChecks(w.commits?.nodes.first?.commit.statusCheckRollup?.state)
        )
    }

    static func mapReview(_ raw: String?) -> ReviewDecision {
        switch raw {
        case "APPROVED":          return .approved
        case "CHANGES_REQUESTED": return .changesRequested
        case "REVIEW_REQUIRED":   return .reviewRequired
        default:                  return .noReview
        }
    }

    static func mapChecks(_ raw: String?) -> CheckStatus {
        switch raw {
        case "SUCCESS":              return .success
        case "FAILURE", "ERROR":     return .failure
        case "PENDING", "EXPECTED":  return .pending
        default:                     return .noChecks
        }
    }
}
