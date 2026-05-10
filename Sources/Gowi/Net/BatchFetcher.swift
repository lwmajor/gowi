import Foundation

struct BatchFetchResult {
    var results: [TrackedRepo: GitHubClient.PRFetchResult] = [:]
    var errors: [TrackedRepo: String] = [:]
    var rateLimit: RateLimitInfo?
}

extension GitHubClient {
    static let defaultBatchSize = 4

    /// Fetch open PRs for all `repos` using aliased sub-queries, defaulting to batches of 4.
    /// On complexity errors the batch is halved and retried automatically.
    /// Sub-query errors are isolated per repo; other repos in the batch still succeed.
    func fetchOpenPRsBatched(repos: [TrackedRepo]) async throws -> BatchFetchResult {
        var combined = BatchFetchResult()
        try await processBatch(repos, batchSize: Self.defaultBatchSize, into: &combined)
        return combined
    }

    // MARK: - private

    private func processBatch(
        _ repos: [TrackedRepo],
        batchSize: Int,
        into combined: inout BatchFetchResult
    ) async throws {
        var i = 0
        while i < repos.count {
            let slice = Array(repos[i..<min(i + batchSize, repos.count)])
            let raw = try await fetchOneBatch(slice)
            if raw.isComplexityError {
                let halfSize = batchSize / 2
                if halfSize >= 1 {
                    try await processBatch(slice, batchSize: halfSize, into: &combined)
                } else {
                    for repo in slice {
                        combined.errors[repo] = "Request complexity exceeds GitHub's limit."
                    }
                }
            } else {
                for (repo, result) in raw.results { combined.results[repo] = result }
                for (repo, msg) in raw.errors { combined.errors[repo] = msg }
                if let rl = raw.rateLimit { combined.rateLimit = rl }
            }
            i += slice.count
        }
    }

    private func fetchOneBatch(_ repos: [TrackedRepo]) async throws -> RawBatchResult {
        let query = buildBatchQuery(repos)
        let data = try await sendRaw(query)
        return try decodeBatchResponse(data, repos: repos)
    }

    private func buildBatchQuery(_ repos: [TrackedRepo]) -> String {
        let subs = repos.enumerated().map { i, r in
            """
              repo\(i): repository(owner: "\(r.owner)", name: "\(r.name)") {
                pullRequests(states: OPEN, first: 50, orderBy: {field: UPDATED_AT, direction: DESC}) {
                  totalCount
                  nodes {
                    id number title url isDraft createdAt updatedAt
                    author { login avatarUrl }
                    reviewDecision
                    assignees(first: 5) { nodes { login avatarUrl } }
                    commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
                  }
                }
              }
            """
        }.joined(separator: "\n")
        return "query {\n\(subs)\n  rateLimit { remaining resetAt cost }\n}"
    }

    struct RawBatchResult {
        var results: [TrackedRepo: GitHubClient.PRFetchResult] = [:]
        var errors: [TrackedRepo: String] = [:]
        var rateLimit: RateLimitInfo?
        var isComplexityError = false
    }

    private struct RepoPRsWire: Decodable {
        struct PRNodesWire: Decodable {
            let totalCount: Int
            let nodes: [PRWire]
        }
        let pullRequests: PRNodesWire
    }

    func decodeBatchResponse(_ data: Data, repos: [TrackedRepo]) throws -> RawBatchResult {
        var result = RawBatchResult()

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GitHubError.decoding("Invalid JSON in batch response")
        }

        // Check for complexity and SAML errors; also build per-alias error map.
        var aliasErrors: [String: String] = [:]
        if let errors = json["errors"] as? [[String: Any]] {
            let messages = errors.compactMap { $0["message"] as? String }
            let isComplexity = messages.contains {
                $0.contains("MAX_NODE_LIMIT_EXCEEDED") || $0.lowercased().contains("complexity")
            }
            if isComplexity {
                result.isComplexityError = true
                return result
            }
            // Top-level SAML errors have no path and block the whole request.
            let topLevelSAML = errors.contains { err in
                (err["path"] as? [String]) == nil &&
                GitHubClient.isSAMLError((err["message"] as? String) ?? "")
            }
            if topLevelSAML {
                throw GitHubError.samlRequired(Config.tokenSettingsURL)
            }
            for error in errors {
                guard let path = error["path"] as? [String], let alias = path.first else { continue }
                let msg = (error["message"] as? String) ?? "Unknown error"
                aliasErrors[alias] = GitHubClient.isSAMLError(msg)
                    ? "SSO authorization required — authorize your token on GitHub."
                    : msg
            }
        }

        guard let dataDict = json["data"] as? [String: Any] else { return result }

        // Decode top-level rateLimit.
        if let rlObj = dataDict["rateLimit"] as? [String: Any],
           let rlData = try? JSONSerialization.data(withJSONObject: rlObj),
           let rl = try? decoder.decode(RateLimitInfo.self, from: rlData) {
            result.rateLimit = rl
        }

        // Decode each aliased repo sub-query.
        for (i, repo) in repos.enumerated() {
            let alias = "repo\(i)"
            if let errMsg = aliasErrors[alias] {
                result.errors[repo] = errMsg
                continue
            }
            guard let repoObj = dataDict[alias] as? [String: Any],
                  let repoData = try? JSONSerialization.data(withJSONObject: repoObj),
                  let repoPRs = try? decoder.decode(RepoPRsWire.self, from: repoData) else { continue }
            let prs = repoPRs.pullRequests.nodes.map { PRMapper.toPullRequest($0, repo: repo) }
            result.results[repo] = GitHubClient.PRFetchResult(
                totalCount: repoPRs.pullRequests.totalCount,
                pullRequests: prs
            )
        }

        return result
    }
}
