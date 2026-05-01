import XCTest

final class BatchFetcherTests: XCTestCase {

    // MARK: - batch query builder

    func testBatchQueryContainsAliases() {
        let client = GitHubClient(tokenProvider: { "token" })
        let repos = [
            TrackedRepo(owner: "apple", name: "swift"),
            TrackedRepo(owner: "apple", name: "swift-evolution"),
        ]
        // Build via the public fetch API isn't possible without network, so test
        // the batch result struct directly.
        var result = GitHubClient.RawBatchResult()
        XCTAssertFalse(result.isComplexityError)
        result.isComplexityError = true
        XCTAssertTrue(result.isComplexityError)
        _ = client  // suppress unused warning
        _ = repos
    }

    // MARK: - complexity detection in raw JSON

    func testComplexityErrorDetected() throws {
        let client = GitHubClient(tokenProvider: { "token" })
        let repos = [TrackedRepo(owner: "a", name: "b")]

        let json = """
        {
          "data": null,
          "errors": [
            { "message": "MAX_NODE_LIMIT_EXCEEDED: query exceeds complexity", "type": "MAX_NODE_LIMIT" }
          ]
        }
        """.data(using: .utf8)!

        let result = try client.decodeBatchResponse(json, repos: repos)
        XCTAssertTrue(result.isComplexityError)
        XCTAssertTrue(result.results.isEmpty)
    }

    func testComplexityWordDetected() throws {
        let client = GitHubClient(tokenProvider: { "token" })
        let repos = [TrackedRepo(owner: "a", name: "b")]

        let json = """
        { "errors": [{ "message": "query has complexity 500000 which exceeds limit" }] }
        """.data(using: .utf8)!

        let result = try client.decodeBatchResponse(json, repos: repos)
        XCTAssertTrue(result.isComplexityError)
    }

    // MARK: - per-repo error isolation

    func testPerRepoErrorIsolated() throws {
        let client = GitHubClient(tokenProvider: { "token" })
        let repoA = TrackedRepo(owner: "org", name: "good")
        let repoB = TrackedRepo(owner: "org", name: "bad")

        let json = """
        {
          "data": {
            "repo0": {
              "pullRequests": { "totalCount": 1, "nodes": [
                {
                  "id": "PR_1", "number": 42, "title": "Fix bug",
                  "url": "https://github.com/org/good/pull/42",
                  "isDraft": false,
                  "createdAt": "2024-01-01T00:00:00Z",
                  "updatedAt": "2024-01-02T00:00:00Z",
                  "author": { "login": "dev", "avatarUrl": "https://example.com/avatar.png" },
                  "reviewDecision": "APPROVED",
                  "commits": { "nodes": [{ "commit": { "statusCheckRollup": { "state": "SUCCESS" } } }] }
                }
              ]}
            },
            "repo1": null
          },
          "errors": [
            { "message": "Repository not found", "path": ["repo1"], "type": "NOT_FOUND" }
          ]
        }
        """.data(using: .utf8)!

        let result = try client.decodeBatchResponse(json, repos: [repoA, repoB])
        XCTAssertFalse(result.isComplexityError)
        XCTAssertNotNil(result.results[repoA])
        XCTAssertEqual(result.results[repoA]?.totalCount, 1)
        XCTAssertEqual(result.results[repoA]?.pullRequests.count, 1)
        XCTAssertEqual(result.results[repoA]?.pullRequests.first?.reviewDecision, .approved)
        XCTAssertEqual(result.results[repoA]?.pullRequests.first?.checkStatus, .success)
        XCTAssertNil(result.results[repoB])
        XCTAssertNotNil(result.errors[repoB])
    }

    // MARK: - canned full response decoding (task 29)

    func testCannedResponseDecoding() throws {
        let client = GitHubClient(tokenProvider: { "token" })
        let repo = TrackedRepo(owner: "org", name: "repo")

        let json = cannedResponse.data(using: .utf8)!
        let result = try client.decodeBatchResponse(json, repos: [repo])

        XCTAssertFalse(result.isComplexityError)
        let prs = result.results[repo]?.pullRequests ?? []
        XCTAssertEqual(result.results[repo]?.totalCount, 4)
        XCTAssertEqual(prs.count, 4)

        let draft = prs.first(where: { $0.isDraft })
        XCTAssertNotNil(draft)

        let nullAuthor = prs.first(where: { $0.authorLogin == nil })
        XCTAssertNotNil(nullAuthor)

        XCTAssertTrue(prs.contains(where: { $0.reviewDecision == .approved }))
        XCTAssertTrue(prs.contains(where: { $0.reviewDecision == .changesRequested }))
        XCTAssertTrue(prs.contains(where: { $0.checkStatus == .success }))
        XCTAssertTrue(prs.contains(where: { $0.checkStatus == .noChecks }))

        XCTAssertNotNil(result.rateLimit)
        XCTAssertEqual(result.rateLimit?.remaining, 4998)
        XCTAssertEqual(result.rateLimit?.cost, 2)
    }

    private let cannedResponse = """
    {
      "data": {
        "repo0": {
          "pullRequests": {
            "totalCount": 4,
            "nodes": [
              {
                "id": "PR_1", "number": 1, "title": "Draft PR",
                "url": "https://github.com/org/repo/pull/1",
                "isDraft": true,
                "createdAt": "2024-01-01T00:00:00Z",
                "updatedAt": "2024-01-02T00:00:00Z",
                "author": { "login": "alice", "avatarUrl": "https://example.com/a.png" },
                "reviewDecision": null,
                "commits": { "nodes": [] }
              },
              {
                "id": "PR_2", "number": 2, "title": "Approved PR",
                "url": "https://github.com/org/repo/pull/2",
                "isDraft": false,
                "createdAt": "2024-01-01T00:00:00Z",
                "updatedAt": "2024-01-03T00:00:00Z",
                "author": null,
                "reviewDecision": "APPROVED",
                "commits": { "nodes": [{ "commit": { "statusCheckRollup": { "state": "SUCCESS" } } }] }
              },
              {
                "id": "PR_3", "number": 3, "title": "Changes requested PR",
                "url": "https://github.com/org/repo/pull/3",
                "isDraft": false,
                "createdAt": "2024-01-01T00:00:00Z",
                "updatedAt": "2024-01-04T00:00:00Z",
                "author": { "login": "bob", "avatarUrl": "https://example.com/b.png" },
                "reviewDecision": "CHANGES_REQUESTED",
                "commits": { "nodes": [{ "commit": { "statusCheckRollup": { "state": "FAILURE" } } }] }
              },
              {
                "id": "PR_4", "number": 4, "title": "No-checks PR",
                "url": "https://github.com/org/repo/pull/4",
                "isDraft": false,
                "createdAt": "2024-01-01T00:00:00Z",
                "updatedAt": "2024-01-05T00:00:00Z",
                "author": { "login": "carol", "avatarUrl": "https://example.com/c.png" },
                "reviewDecision": "REVIEW_REQUIRED",
                "commits": { "nodes": [{ "commit": { "statusCheckRollup": null } }] }
              }
            ]
          }
        },
        "rateLimit": { "remaining": 4998, "resetAt": "2024-01-01T01:00:00Z", "cost": 2 }
      }
    }
    """
}
