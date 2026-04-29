import Foundation
import SwiftUI
import Combine

enum PRState {
    case signedOut
    case loading
    case loaded([RepoGroup])
    case error(String)
}

struct RepoGroup: Identifiable, Hashable {
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

    let github: GitHubClient
    private let auth: AuthService
    private let store: RepoStore
    private var cancellables = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    init(auth: AuthService, store: RepoStore) {
        self.auth = auth
        self.store = store
        self.github = GitHubClient(tokenProvider: { [weak auth] in auth?.accessToken })

        // React to auth state transitions. Combine fires the current value
        // immediately on subscribe, which handles the "already signed in on
        // launch" case without extra wiring.
        auth.$state
            .removeDuplicates()
            .sink { [weak self] newState in
                guard let self else { return }
                switch newState {
                case .signedIn:
                    Task { await self.refreshViewer() }
                    self.refresh()
                    self.startTicking()
                case .signedOut, .failed, .awaitingUserCode:
                    self.viewer = nil
                    self.state = .signedOut
                    self.refreshTask?.cancel()
                    self.tickTask?.cancel()
                }
            }
            .store(in: &cancellables)

        // Re-fetch whenever the tracked-repo list changes, after the initial load.
        store.$repos
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    // MARK: - viewer

    /// Fetch the signed-in user's login/avatar. A 401 here means the stored
    /// token has been revoked — clear it and send the user back to sign-in.
    func refreshViewer() async {
        do {
            viewer = try await github.fetchViewer()
            lastError = nil
        } catch GitHubError.unauthorized {
            auth.signOut()
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

    private func doRefresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        let repos = store.repos
        if repos.isEmpty {
            state = .loaded([])
            lastRefresh = Date()
            return
        }

        if case .loaded = state {} else { state = .loading }

        var groups: [RepoGroup] = []
        for repo in repos {
            if Task.isCancelled { return }
            do {
                let result = try await github.fetchOpenPRs(in: repo)
                groups.append(RepoGroup(
                    repo: repo,
                    pullRequests: result.pullRequests,
                    totalCount: result.totalCount,
                    error: nil
                ))
            } catch GitHubError.unauthorized {
                auth.signOut()
                return
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                groups.append(RepoGroup(
                    repo: repo,
                    pullRequests: [],
                    totalCount: 0,
                    error: msg
                ))
            }
        }
        state = .loaded(groups)
        lastRefresh = Date()
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                let minutes = UserDefaults.standard.integer(forKey: "refreshIntervalMinutes")
                let m = max(1, minutes == 0 ? 5 : minutes)
                let ns = UInt64(m) * 60 * 1_000_000_000
                try? await Task.sleep(nanoseconds: ns)
                guard let self else { return }
                self.refresh()
            }
        }
    }
}
