#if DEBUG
import Foundation
import UserNotifications

/// Hermetic test states selectable via the `-ui-state <name>` launch argument.
/// See ``UITestConfiguration``.
enum UITestState: String {
    case empty
    case allClear
    case loaded
    case error
    case perRepoError
    case tokenRevoked
    case samlRequired
    case cachedData
}

/// Reads launch arguments and assembles fake-backed app dependencies so UI tests
/// can drive the real SwiftUI views without network / keychain / notification
/// side effects. Active only when the app is launched with `-ui-testing`.
enum UITestConfiguration {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
    }

    static var state: UITestState {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-ui-state"),
              idx + 1 < args.count,
              let parsed = UITestState(rawValue: args[idx + 1])
        else { return .empty }
        return parsed
    }

    @MainActor
    static func makeDependencies() -> (AuthService, RepoStore, NotificationService, AppModel) {
        // PRCache.shared writes to ~/Library/Application Support/gowi/cache.json which
        // persists across launches. Clear it so a previous test run's cache doesn't
        // bleed into the .error / .signedOut paths AppModel takes on a cold start.
        clearSharedDiskCache()

        let suite = "gowi.uitests.\(UUID().uuidString)"
        let storeDefaults = UserDefaults(suiteName: suite + ".store")!
        let notifyDefaults = UserDefaults(suiteName: suite + ".notify")!

        let s = state
        let keychain = UITestKeychain(token: "ui-test-token")
        let auth = AuthService(keychain: keychain, client: UITestDeviceFlow())

        let store = RepoStore(defaults: storeDefaults)
        for repo in initialRepos(for: s) { store.add(repo) }

        let notifications = NotificationService(
            store: store,
            defaults: notifyDefaults,
            center: UITestNotificationCenter()
        )

        let fetcher = UITestPRFetcher(state: s)
        let model = AppModel(auth: auth, store: store, notifications: notifications, client: fetcher)

        applyPostInitOverrides(state: s, model: model)
        return (auth, store, notifications, model)
    }

    /// For states that the production state machine can't produce in isolation
    /// from a single fetch, mutate the model after its initial refresh settles.
    @MainActor
    private static func applyPostInitOverrides(state: UITestState, model: AppModel) {
        switch state {
        case .samlRequired:
            // Production keeps state = .loading after a SAML throw. Resolve to an
            // empty loaded list so the banner has a settled view to sit above.
            Task { @MainActor [weak model] in
                await waitFor(timeoutMs: 2000) { model?.samlAuthURL != nil }
                if let model, case .loading = model.state {
                    model.state = .loaded([])
                }
            }
        case .cachedData:
            // After the initial successful fetch, flip the cached-data flag and
            // backdate lastRefresh so the banner's relative time is testable.
            Task { @MainActor [weak model] in
                await waitFor(timeoutMs: 2000) {
                    if case .loaded = model?.state { return true }
                    return false
                }
                model?.isShowingCachedData = true
                model?.lastRefresh = Date().addingTimeInterval(-300)
            }
        default:
            break
        }
    }

    private static func initialRepos(for state: UITestState) -> [TrackedRepo] {
        switch state {
        case .empty:
            return []
        case .allClear, .error, .tokenRevoked, .samlRequired, .cachedData:
            return [TrackedRepo(owner: "apple", name: "swift")]
        case .loaded, .perRepoError:
            return [
                TrackedRepo(owner: "apple", name: "swift"),
                TrackedRepo(owner: "vapor", name: "vapor")
            ]
        }
    }

    @MainActor
    private static func waitFor(timeoutMs: Int, _ check: () -> Bool) async {
        let stepMs = 50
        let steps = max(1, timeoutMs / stepMs)
        for _ in 0..<steps {
            if check() { return }
            try? await Task.sleep(nanoseconds: UInt64(stepMs) * 1_000_000)
        }
    }

    private static func clearSharedDiskCache() {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let cacheURL = base
            .appendingPathComponent("gowi", isDirectory: true)
            .appendingPathComponent("cache.json")
        try? FileManager.default.removeItem(at: cacheURL)
    }
}

// MARK: - Fakes

private final class UITestKeychain: KeychainStoring {
    private var token: String?
    init(token: String? = nil) { self.token = token }
    func store(_ token: String) throws { self.token = token }
    func read() throws -> String? { token }
    func delete() throws { token = nil }
}

private struct UITestDeviceFlow: DeviceFlowing {
    func requestCode(clientID: String, scopes: String) async throws -> DeviceCodeResponse {
        try await Task.sleep(nanoseconds: 60 * 1_000_000_000)
        throw CancellationError()
    }
    func pollForToken(clientID: String, deviceCode: String, initialInterval: Int) async throws -> String {
        throw CancellationError()
    }
}

private final class UITestNotificationCenter: NotificationCenterProtocol {
    var delegate: UNUserNotificationCenterDelegate?
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
    func currentAuthorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func add(_ request: UNNotificationRequest) {}
}

private final class UITestPRFetcher: PRFetchingClient {
    let state: UITestState
    init(state: UITestState) { self.state = state }

    func fetchViewer() async throws -> Viewer {
        Viewer(login: "ui-test", avatarUrl: URL(string: "https://example.com/avatar.png")!)
    }

    func validateRepo(_ repo: TrackedRepo) async throws {}

    func fetchOpenPRsBatched(repos: [TrackedRepo]) async throws -> BatchFetchResult {
        switch state {
        case .empty:
            return BatchFetchResult()
        case .allClear:
            var r = BatchFetchResult()
            for repo in repos {
                r.results[repo] = GitHubClient.PRFetchResult(totalCount: 0, pullRequests: [])
            }
            return r
        case .loaded, .cachedData:
            var r = BatchFetchResult()
            for (i, repo) in repos.enumerated() {
                let prs = makePRs(repo: repo, count: i == 0 ? 3 : 1)
                r.results[repo] = GitHubClient.PRFetchResult(totalCount: prs.count, pullRequests: prs)
            }
            return r
        case .error:
            throw GitHubError.transport("Simulated network failure")
        case .perRepoError:
            var r = BatchFetchResult()
            if let first = repos.first {
                let prs = makePRs(repo: first, count: 2)
                r.results[first] = GitHubClient.PRFetchResult(totalCount: prs.count, pullRequests: prs)
            }
            if repos.count > 1 {
                r.errors[repos[1]] = "Repository not found."
            }
            return r
        case .tokenRevoked:
            throw GitHubError.unauthorized
        case .samlRequired:
            throw GitHubError.samlRequired(
                URL(string: "https://github.com/orgs/example/sso?authorization_request=stub")!
            )
        }
    }

    func fetchOpenPRs(in repo: TrackedRepo) async throws -> GitHubClient.PRFetchResult {
        let prs = makePRs(repo: repo, count: 1)
        return GitHubClient.PRFetchResult(totalCount: prs.count, pullRequests: prs)
    }

    private func makePRs(repo: TrackedRepo, count: Int) -> [PullRequest] {
        let reviews: [ReviewDecision] = [.approved, .changesRequested, .reviewRequired, .noReview]
        let checks: [CheckStatus] = [.success, .failure, .pending, .noChecks]
        return (0..<count).map { i in
            PullRequest(
                id: "\(repo.id)#\(i)",
                number: 100 + i,
                title: "Sample PR \(i + 1) in \(repo.name)",
                url: URL(string: "https://github.com/\(repo.nameWithOwner)/pull/\(100 + i)")!,
                authorLogin: "octocat",
                authorAvatarURL: nil,
                isDraft: count > 2 && i == 2,
                createdAt: Date().addingTimeInterval(-Double(i + 1) * 3600),
                updatedAt: Date().addingTimeInterval(-Double(i + 1) * 1800),
                repo: repo,
                reviewDecision: reviews[i % reviews.count],
                checkStatus: checks[i % checks.count]
            )
        }
    }
}
#endif
