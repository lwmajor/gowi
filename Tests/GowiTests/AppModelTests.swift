import XCTest
import Combine
import UserNotifications

// MARK: - Test doubles

private final class SpyAuth: AuthServiceProtocol {
    var state: AuthState
    private let subject: CurrentValueSubject<AuthState, Never>
    var statePublisher: AnyPublisher<AuthState, Never> { subject.eraseToAnyPublisher() }
    var accessToken: String? { "stub-token" }
    private(set) var signOutCallCount = 0

    init(state: AuthState = .signedOut) {
        self.state = state
        subject = CurrentValueSubject(state)
    }

    func signOut() {
        signOutCallCount += 1
        state = .signedOut
        subject.send(.signedOut)
    }
}

private final class SpyGitHub: GitHubClientProtocol {
    var viewerResult: Result<Viewer, Error> = .success(
        Viewer(login: "test", avatarUrl: URL(string: "https://example.com/a")!)
    )
    var batchResult: Result<BatchFetchResult, Error> = .success(BatchFetchResult())

    func fetchViewer() async throws -> Viewer { try viewerResult.get() }
    func fetchOpenPRsBatched(repos: [TrackedRepo]) async throws -> BatchFetchResult { try batchResult.get() }
    func fetchOpenPRs(in repo: TrackedRepo) async throws -> GitHubClient.PRFetchResult {
        GitHubClient.PRFetchResult(totalCount: 0, pullRequests: [])
    }
    func validateRepo(_ repo: TrackedRepo) async throws {}
}

private final class NullCenter: NotificationCenterProtocol {
    var delegate: UNUserNotificationCenterDelegate?
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { false }
    func currentAuthorizationStatus() async -> UNAuthorizationStatus { .notDetermined }
    func add(_ request: UNNotificationRequest) {}
}

// MARK: - Tests

@MainActor
final class AppModelTests: XCTestCase {
    private var modelDefaults: UserDefaults!
    private var storeDefaults: UserDefaults!

    override func setUp() async throws {
        let uid = UUID().uuidString
        modelDefaults = UserDefaults(suiteName: "gowi.tests.appmodel.\(uid)")!
        storeDefaults = UserDefaults(suiteName: "gowi.tests.appmodel.store.\(uid)")!
    }

    override func tearDown() async throws {
        modelDefaults.removePersistentDomain(forName: modelDefaults.description)
        storeDefaults.removePersistentDomain(forName: storeDefaults.description)
        modelDefaults = nil
        storeDefaults = nil
    }

    private func makeModel(
        auth: SpyAuth,
        github: SpyGitHub,
        repos: [TrackedRepo] = []
    ) -> AppModel {
        let store = RepoStore(defaults: storeDefaults)
        repos.forEach { store.add($0) }
        let notifications = NotificationService(store: store, defaults: modelDefaults, center: NullCenter())
        return AppModel(auth: auth, store: store, notifications: notifications, github: github)
    }

    // MARK: - tokenRevoked

    // Zero-repos case: doRefresh() returns early, so only refreshViewer() can set tokenRevoked.
    func testRefreshViewerUnauthorized_setsTokenRevokedAndSignsOut() async {
        let auth = SpyAuth()
        let github = SpyGitHub()
        github.viewerResult = .failure(GitHubError.unauthorized)
        let model = makeModel(auth: auth, github: github)

        await model.refreshViewer()

        XCTAssertTrue(model.tokenRevoked)
        XCTAssertEqual(auth.signOutCallCount, 1)
    }

    func testRefreshViewerSuccess_clearsTokenRevoked() async {
        let auth = SpyAuth()
        let model = makeModel(auth: auth, github: SpyGitHub())
        model.tokenRevoked = true

        await model.refreshViewer()

        XCTAssertFalse(model.tokenRevoked)
        XCTAssertEqual(auth.signOutCallCount, 0)
    }

    func testDoRefreshUnauthorized_setsTokenRevokedAndSignsOut() async {
        let auth = SpyAuth()    // starts .signedOut — no init cascade
        let github = SpyGitHub()
        github.batchResult = .failure(GitHubError.unauthorized)
        let model = makeModel(
            auth: auth,
            github: github,
            repos: [TrackedRepo(owner: "apple", name: "swift")]
        )
        // Set .signedIn without publishing so the Combine sink doesn't spawn competing tasks.
        auth.state = .signedIn

        await model.performRefresh()

        XCTAssertTrue(model.tokenRevoked)
        XCTAssertGreaterThan(auth.signOutCallCount, 0)
    }
}
