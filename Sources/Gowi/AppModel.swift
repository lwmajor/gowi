import Foundation
import SwiftUI
import Combine

enum PRState {
    case signedOut
    case loading
    case loaded([RepoGroup])
    case error(String)
}

struct RepoGroup: Identifiable, Hashable, Codable {
    let repo: TrackedRepo
    let pullRequests: [PullRequest]
    let totalCount: Int          // may exceed pullRequests.count when the repo has >50 open PRs
    let error: String?
    var id: String { repo.id }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var state: PRState = .signedOut
    @Published var viewer: Viewer?
    @Published var lastError: String?
    @Published var isRefreshing: Bool = false
    @Published var lastRefresh: Date?
    @Published var rateLimitWarning: Bool = false
    @Published var samlAuthURL: URL?
    @Published var isShowingCachedData: Bool = false
    @Published var tokenRevoked: Bool = false

    let github: any PRFetchingClient
    private let auth: AuthService
    private let store: RepoStore
    private let notifications: NotificationService
    private var cancellables = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var rateLimitPauseUntil: Date?
    private var suppressNextStoreRefresh = false

    init(
        auth: AuthService,
        store: RepoStore,
        notifications: NotificationService,
        client: (any PRFetchingClient)? = nil
    ) {
        self.auth = auth
        self.store = store
        self.notifications = notifications
        self.github = client ?? GitHubClient(tokenProvider: { [weak auth] in auth?.accessToken })

        auth.$state
            .removeDuplicates()
            .sink { [weak self] newState in
                guard let self else { return }
                switch newState {
                case .signedIn:
                    Task { await self.refreshViewer() }
                    self.loadCacheIfNeeded()
                    self.refresh()
                    self.startTicking()
                case .signedOut, .failed, .awaitingUserCode:
                    self.viewer = nil
                    self.state = .signedOut
                    self.isShowingCachedData = false
                    self.refreshTask?.cancel()
                    self.tickTask?.cancel()
                    self.rateLimitWarning = false
                    self.rateLimitPauseUntil = nil
                    self.samlAuthURL = nil
                }
            }
            .store(in: &cancellables)

        store.$repos
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                if self.suppressNextStoreRefresh {
                    self.suppressNextStoreRefresh = false
                    return
                }
                self.refresh()
            }
            .store(in: &cancellables)

        // Restart the tick loop after system sleep so the timer isn't stale.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.handleWake()
        }
    }

    // MARK: - viewer

    func refreshViewer() async {
        do {
            viewer = try await github.fetchViewer()
            if tokenRevoked { tokenRevoked = false }
            lastError = nil
        } catch GitHubError.unauthorized {
            handleUnauthorized()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - PR refresh

    func refresh() {
        guard auth.state == .signedIn else { return }
        guard !isRefreshing else { return }

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.doRefresh()
        }
    }

    /// Async variant used by SwiftUI's `.refreshable`. Coalesces with any
    /// in-flight refresh so the pull gesture's spinner stays visible until
    /// the real work finishes.
    func performRefresh() async {
        guard auth.state == .signedIn else { return }
        if isRefreshing, let task = refreshTask {
            await task.value
            return
        }
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.doRefresh()
        }
        refreshTask = task
        await task.value
    }

    /// Retry a single repo without touching other groups.
    func refreshSingleRepo(_ repo: TrackedRepo) {
        guard auth.state == .signedIn else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.doRefreshSingleRepo(repo)
        }
    }

    /// Reorder repos without triggering a network re-fetch.
    /// Updates the displayed groups immediately and persists the new order to the store.
    func moveRepo(fromOffsets: IndexSet, toOffset: Int) {
        guard case .loaded(var groups) = state else { return }
        groups.move(fromOffsets: fromOffsets, toOffset: toOffset)
        state = .loaded(groups)
        suppressNextStoreRefresh = true
        store.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    // MARK: - private refresh

    private func handleUnauthorized() {
        tokenRevoked = true
        auth.signOut()
    }

    private func doRefresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        let repos = store.repos
        if repos.isEmpty {
            state = .loaded([])
            isShowingCachedData = false
            lastRefresh = Date()
            return
        }

        if case .loaded = state {} else { state = .loading }

        do {
            let batchResult = try await github.fetchOpenPRsBatched(repos: repos)

            updateRateLimit(batchResult.rateLimit)

            let groups: [RepoGroup] = repos.map { repo in
                if let result = batchResult.results[repo] {
                    return RepoGroup(repo: repo, pullRequests: result.pullRequests, totalCount: result.totalCount, error: nil)
                } else if let errMsg = batchResult.errors[repo] {
                    return RepoGroup(repo: repo, pullRequests: [], totalCount: 0, error: errMsg)
                } else {
                    return RepoGroup(repo: repo, pullRequests: [], totalCount: 0, error: nil)
                }
            }

            state = .loaded(groups)
            isShowingCachedData = false
            lastRefresh = Date()
            notifications.process(groups: groups)
            PRCache.shared.save(groups)
        } catch GitHubError.unauthorized {
            handleUnauthorized()
        } catch GitHubError.samlRequired(let url) {
            samlAuthURL = url
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if case .loaded = state {
                isShowingCachedData = true
            } else {
                state = .error(msg)
            }
            lastError = msg
        }
    }

    private func doRefreshSingleRepo(_ repo: TrackedRepo) async {
        do {
            let result = try await github.fetchOpenPRs(in: repo)
            guard case .loaded(var groups) = state else { return }
            if let idx = groups.firstIndex(where: { $0.repo == repo }) {
                groups[idx] = RepoGroup(repo: repo, pullRequests: result.pullRequests, totalCount: result.totalCount, error: nil)
                state = .loaded(groups)
                notifications.process(groups: [groups[idx]])
                PRCache.shared.save(groups)
            }
        } catch GitHubError.unauthorized {
            handleUnauthorized()
        } catch GitHubError.samlRequired(let url) {
            samlAuthURL = url
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if case .loaded(var groups) = state,
               let idx = groups.firstIndex(where: { $0.repo == repo }) {
                groups[idx] = RepoGroup(repo: repo, pullRequests: [], totalCount: 0, error: msg)
                state = .loaded(groups)
            }
        }
    }

    // MARK: - cache

    private func loadCacheIfNeeded() {
        guard case .signedOut = state else { return }
        if let cached = PRCache.shared.load(), !cached.isEmpty {
            state = .loaded(cached)
            isShowingCachedData = true
        }
    }

    // MARK: - rate limit

    private func updateRateLimit(_ rl: RateLimitInfo?) {
        guard let rl else { return }
        let threshold = max(100, 10 * rl.cost)
        if rl.remaining < threshold {
            rateLimitWarning = true
            rateLimitPauseUntil = rl.resetAt
        } else {
            rateLimitWarning = false
            rateLimitPauseUntil = nil
        }
    }

    // MARK: - tick loop

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                // Honor rate-limit pause before sleeping for the normal interval.
                if let pauseUntil = self.rateLimitPauseUntil, pauseUntil > Date() {
                    let delay = max(0, pauseUntil.timeIntervalSinceNow)
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1e9))
                    self.rateLimitWarning = false
                    self.rateLimitPauseUntil = nil
                    continue
                }

                let minutes = UserDefaults.standard.integer(forKey: "refreshIntervalMinutes")
                let m = max(1, minutes == 0 ? 5 : minutes)
                try? await Task.sleep(nanoseconds: UInt64(m) * 60 * 1_000_000_000)
                guard !Task.isCancelled else { return }
                self.refresh()
            }
        }
    }

    private func handleWake() {
        guard auth.state == .signedIn else { return }
        let minutes = UserDefaults.standard.integer(forKey: "refreshIntervalMinutes")
        let interval = TimeInterval(max(1, minutes == 0 ? 5 : minutes) * 60)
        let intervalElapsed: Bool
        if let last = lastRefresh {
            intervalElapsed = Date().timeIntervalSince(last) >= interval
        } else {
            intervalElapsed = true
        }
        startTicking()
        if intervalElapsed { refresh() }
    }
}
