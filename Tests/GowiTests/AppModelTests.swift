import XCTest
import UserNotifications

// MARK: - Test doubles

private final class SpyFetcher: PRFetchingClient {
    var viewerResult: Result<Viewer, Error> = .success(
        Viewer(login: "test-user", avatarUrl: URL(string: "https://example.com/avatar.png")!)
    )
    var batchResult: Result<BatchFetchResult, Error> = .success(BatchFetchResult())
    var singleResult: Result<GitHubClient.PRFetchResult, Error> = .success(
        GitHubClient.PRFetchResult(totalCount: 0, pullRequests: [])
    )
    var batchCallCount = 0

    func fetchViewer() async throws -> Viewer { try viewerResult.get() }
    func validateRepo(_ repo: TrackedRepo) async throws {}
    func fetchOpenPRsBatched(repos: [TrackedRepo]) async throws -> BatchFetchResult {
        batchCallCount += 1
        return try batchResult.get()
    }
    func fetchOpenPRs(in repo: TrackedRepo) async throws -> GitHubClient.PRFetchResult {
        try singleResult.get()
    }
}

private final class MockKeychain: KeychainStoring {
    var storedToken: String?
    init(token: String? = nil) { self.storedToken = token }
    func store(_ token: String) throws { storedToken = token }
    func read() throws -> String? { storedToken }
    func delete() throws { storedToken = nil }
}

// DeviceFlow that blocks indefinitely so sign-in never completes during tests.
private struct BlockingDeviceFlow: DeviceFlowing {
    func requestCode(clientID: String, scopes: String) async throws -> DeviceCodeResponse {
        try await Task.sleep(nanoseconds: 60 * 1_000_000_000)
        throw CancellationError()
    }
    func pollForToken(clientID: String, deviceCode: String, initialInterval: Int) async throws -> String {
        throw CancellationError()
    }
}

private final class SilentNotifCenter: NotificationCenterProtocol {
    var delegate: UNUserNotificationCenterDelegate?
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { false }
    func currentAuthorizationStatus() async -> UNAuthorizationStatus { .notDetermined }
    func add(_ request: UNNotificationRequest) {}
}

// MARK: - Helpers

private func makeRepo(_ name: String = "repo") -> TrackedRepo {
    TrackedRepo(owner: "org", name: name)
}

private func makePR(id: String, repo: TrackedRepo) -> PullRequest {
    PullRequest(
        id: id,
        number: 1,
        title: "PR \(id)",
        url: URL(string: "https://github.com/org/repo/pull/1")!,
        authorLogin: "dev",
        authorAvatarURL: nil,
        isDraft: false,
        createdAt: Date(),
        updatedAt: Date(),
        repo: repo,
        reviewDecision: .noReview,
        checkStatus: .noChecks
    )
}

private func batchResult(repo: TrackedRepo, prs: [PullRequest]) -> BatchFetchResult {
    var r = BatchFetchResult()
    r.results[repo] = GitHubClient.PRFetchResult(totalCount: prs.count, pullRequests: prs)
    return r
}

private func rateLimitInfo(remaining: Int, cost: Int = 1) -> RateLimitInfo {
    RateLimitInfo(remaining: remaining, resetAt: Date().addingTimeInterval(3600), cost: cost)
}

// MARK: - Tests

@MainActor
final class AppModelTests: XCTestCase {
    private var fetcher: SpyFetcher!
    private var auth: AuthService!
    private var store: RepoStore!
    private var notifications: NotificationService!
    private var model: AppModel!

    override func setUp() async throws {
        let uid = UUID().uuidString
        let storeDefaults = UserDefaults(suiteName: "gowi.tests.model.store.\(uid)")!
        let notifyDefaults = UserDefaults(suiteName: "gowi.tests.model.notify.\(uid)")!
        let notifyStore = RepoStore(defaults: UserDefaults(suiteName: "gowi.tests.model.nstore.\(uid)")!)

        let keychain = MockKeychain(token: "test-token")
        auth = AuthService(keychain: keychain, client: BlockingDeviceFlow())
        store = RepoStore(defaults: storeDefaults)
        notifications = NotificationService(store: notifyStore, defaults: notifyDefaults, center: SilentNotifCenter())
        fetcher = SpyFetcher()
        model = AppModel(auth: auth, store: store, notifications: notifications, client: fetcher)

        // Establish a loaded baseline state before each test.
        await model.performRefresh()
    }

    override func tearDown() async throws {
        model = nil
        notifications = nil
        store = nil
        auth = nil
        fetcher = nil
    }

    // MARK: - Initial state

    func testInitialStateAfterSignIn() {
        if case .loaded(let groups) = model.state {
            XCTAssertTrue(groups.isEmpty, "No repos → empty groups")
        } else {
            XCTFail("Expected .loaded, got \(model.state)")
        }
        XCTAssertFalse(model.isShowingCachedData)
        XCTAssertFalse(model.tokenRevoked)
        XCTAssertFalse(model.rateLimitWarning)
        XCTAssertNil(model.samlAuthURL)
    }

    // MARK: - Successful refresh

    func testSuccessfulRefreshWithReposProducesLoadedGroups() async {
        let repo = makeRepo()
        store.add(repo)
        let pr = makePR(id: "pr1", repo: repo)
        fetcher.batchResult = .success(batchResult(repo: repo, prs: [pr]))

        await model.performRefresh()

        guard case .loaded(let groups) = model.state else {
            return XCTFail("Expected .loaded")
        }
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.pullRequests.count, 1)
        XCTAssertEqual(groups.first?.pullRequests.first?.id, "pr1")
    }

    func testSuccessfulRefreshClearsStalenessFlagAndSetsLastRefresh() async {
        model.isShowingCachedData = true

        await model.performRefresh()

        XCTAssertFalse(model.isShowingCachedData)
        XCTAssertNotNil(model.lastRefresh)
    }

    func testEmptyRepoListProducesLoadedEmpty() async {
        await model.performRefresh()

        guard case .loaded(let groups) = model.state else {
            return XCTFail("Expected .loaded")
        }
        XCTAssertTrue(groups.isEmpty)
    }

    // MARK: - Error paths

    func testNetworkErrorOnLoadingTransitionsToErrorState() async {
        let repo = makeRepo()
        store.add(repo)
        fetcher.batchResult = .failure(GitHubError.transport("timeout"))
        model.state = .loading

        await model.performRefresh()

        if case .error = model.state {} else {
            XCTFail("Expected .error, got \(model.state)")
        }
    }

    func testNetworkErrorWhileLoadedKeepsLoadedAndSetsStalenessFlag() async {
        let repo = makeRepo()
        store.add(repo)
        // First refresh succeeds
        let pr = makePR(id: "pr1", repo: repo)
        fetcher.batchResult = .success(batchResult(repo: repo, prs: [pr]))
        await model.performRefresh()
        XCTAssertFalse(model.isShowingCachedData)

        // Second refresh fails
        fetcher.batchResult = .failure(GitHubError.transport("offline"))
        await model.performRefresh()

        guard case .loaded(let groups) = model.state else {
            return XCTFail("State should remain .loaded, got \(model.state)")
        }
        XCTAssertEqual(groups.first?.pullRequests.count, 1, "Groups must be unchanged")
        XCTAssertTrue(model.isShowingCachedData)
    }

    func testNetworkErrorPreservesLastRefreshDate() async {
        let repo = makeRepo()
        store.add(repo)
        fetcher.batchResult = .success(batchResult(repo: repo, prs: []))
        await model.performRefresh()
        let firstRefresh = model.lastRefresh

        fetcher.batchResult = .failure(GitHubError.transport("down"))
        await model.performRefresh()

        XCTAssertEqual(model.lastRefresh, firstRefresh, "lastRefresh must not update on failure")
    }

    // MARK: - Unauthorized (token revoked)

    func testUnauthorizedSetsTokenRevokedAndSignsOut() async {
        let repo = makeRepo()
        store.add(repo)
        fetcher.batchResult = .failure(GitHubError.unauthorized)

        await model.performRefresh()

        XCTAssertTrue(model.tokenRevoked)
        XCTAssertEqual(auth.state, .signedOut)
    }

    func testViewerUnauthorizedSetsTokenRevokedAndSignsOut() async {
        fetcher.viewerResult = .failure(GitHubError.unauthorized)

        await model.refreshViewer()

        XCTAssertTrue(model.tokenRevoked)
        XCTAssertEqual(auth.state, .signedOut)
    }

    func testViewerSuccessClearsTokenRevoked() async {
        model.tokenRevoked = true

        await model.refreshViewer()

        XCTAssertFalse(model.tokenRevoked)
    }

    // MARK: - SAML

    func testSAMLRequiredSetsSAMLAuthURL() async {
        let repo = makeRepo()
        store.add(repo)
        let samlURL = URL(string: "https://github.com/orgs/myorg/sso")!
        fetcher.batchResult = .failure(GitHubError.samlRequired(samlURL))

        await model.performRefresh()

        XCTAssertEqual(model.samlAuthURL, samlURL)
        // State stays .loaded (was already loaded), not .error
        if case .loaded = model.state {} else {
            XCTFail("State should remain .loaded after SAML error")
        }
    }

    // MARK: - Rate limit

    func testRateLimitWarningSetWhenRemainingBelowThreshold() async {
        let repo = makeRepo()
        store.add(repo)
        var result = batchResult(repo: repo, prs: [])
        result.rateLimit = rateLimitInfo(remaining: 5, cost: 1)  // well below threshold
        fetcher.batchResult = .success(result)

        await model.performRefresh()

        XCTAssertTrue(model.rateLimitWarning)
    }

    func testRateLimitWarningClearedWhenRemainingHigh() async {
        // Seed a warning first
        let repo = makeRepo()
        store.add(repo)
        var lowResult = batchResult(repo: repo, prs: [])
        lowResult.rateLimit = rateLimitInfo(remaining: 5, cost: 1)
        fetcher.batchResult = .success(lowResult)
        await model.performRefresh()
        XCTAssertTrue(model.rateLimitWarning)

        // Now return healthy rate limit
        var highResult = batchResult(repo: repo, prs: [])
        highResult.rateLimit = rateLimitInfo(remaining: 5000, cost: 1)
        fetcher.batchResult = .success(highResult)
        await model.performRefresh()

        XCTAssertFalse(model.rateLimitWarning)
    }

    // MARK: - moveRepo

    func testMoveRepoReordersGroupsWithoutExtraFetch() async {
        let repoA = makeRepo("alpha")
        let repoB = makeRepo("beta")
        store.add(repoA)
        store.add(repoB)
        fetcher.batchResult = .success(batchResult(repo: repoA, prs: []))
        await model.performRefresh()
        let callsBefore = fetcher.batchCallCount

        model.moveRepo(fromOffsets: IndexSet(integer: 1), toOffset: 0)

        guard case .loaded(let groups) = model.state else {
            return XCTFail("Expected .loaded after move")
        }
        XCTAssertEqual(groups.first?.repo, repoB, "Repo B should be first after move")
        XCTAssertEqual(fetcher.batchCallCount, callsBefore, "moveRepo must not trigger a fetch")
    }

    // MARK: - refreshSingleRepo

    func testRefreshSingleRepoUpdatesOnlyThatGroup() async {
        let repoA = makeRepo("alpha")
        let repoB = makeRepo("beta")
        store.add(repoA)
        store.add(repoB)
        let prA = makePR(id: "prA", repo: repoA)
        let prB = makePR(id: "prB", repo: repoB)
        fetcher.batchResult = .success({
            var r = BatchFetchResult()
            r.results[repoA] = .init(totalCount: 1, pullRequests: [prA])
            r.results[repoB] = .init(totalCount: 1, pullRequests: [prB])
            return r
        }())
        await model.performRefresh()

        // Single-repo retry succeeds with updated PR list
        let prA2 = makePR(id: "prA2", repo: repoA)
        fetcher.singleResult = .success(.init(totalCount: 1, pullRequests: [prA2]))
        model.refreshSingleRepo(repoA)

        let timeout = Date().addingTimeInterval(2)
        while Date() < timeout {
            guard case .loaded(let groups) = model.state else {
                return XCTFail("Expected .loaded")
            }
            if groups.first(where: { $0.repo == repoA })?.pullRequests.first?.id == "prA2" { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        guard case .loaded(let groups) = model.state else {
            return XCTFail("Expected .loaded")
        }
        let groupA = groups.first(where: { $0.repo == repoA })
        let groupB = groups.first(where: { $0.repo == repoB })
        XCTAssertEqual(groupA?.pullRequests.first?.id, "prA2", "Repo A should be updated")
        XCTAssertEqual(groupB?.pullRequests.first?.id, "prB", "Repo B should be untouched")
    }
}
