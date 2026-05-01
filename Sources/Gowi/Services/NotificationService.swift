import Foundation
import AppKit
import Combine
import UserNotifications

@MainActor
final class NotificationService: NSObject, ObservableObject {
    @Published private(set) var enabledRepos: Set<String> = []
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let defaults: UserDefaults
    private let center: UNUserNotificationCenter
    private var seenPRIds: [String: Set<String>] = [:]
    private var seededRepos: Set<String> = []
    private var cancellables = Set<AnyCancellable>()

    private enum Keys {
        static let enabled = "notifyOnNewPR"
        static let seenIds = "seenPRIds"
        static let seeded = "seededRepos"
    }

    init(store: RepoStore, defaults: UserDefaults = .standard, center: UNUserNotificationCenter = .current()) {
        self.defaults = defaults
        self.center = center
        super.init()

        loadFromDefaults()
        center.delegate = self

        Task { await refreshAuthorizationStatus() }

        store.$repos
            .dropFirst()
            .sink { [weak self] repos in
                self?.pruneRemovedRepos(currentRepos: repos)
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.refreshAuthorizationStatus() }
        }
    }

    // MARK: - Per-repo enabled state

    func isEnabled(_ repo: TrackedRepo) -> Bool {
        enabledRepos.contains(repo.id)
    }

    func setEnabled(_ enabled: Bool, for repo: TrackedRepo) async {
        if enabled {
            _ = await requestAuthorizationIfNeeded()
            enabledRepos.insert(repo.id)
        } else {
            enabledRepos.remove(repo.id)
            // Clear seen state so a later re-enable seeds silently rather than
            // notifying for every currently-open PR.
            seenPRIds.removeValue(forKey: repo.id)
            seededRepos.remove(repo.id)
        }
        persist()
    }

    // MARK: - Authorization

    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        await refreshAuthorizationStatus()
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            await refreshAuthorizationStatus()
            return granted
        @unknown default:
            return false
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    // MARK: - Test

    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "gowi"
        content.body = "Test notification — you'll see one of these when a new PR is raised."
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: "test-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(req)
    }

    // MARK: - Diff & post

    func process(groups: [RepoGroup]) {
        var didMutate = false

        for group in groups {
            if group.error != nil { continue }

            let repoID = group.repo.id
            let currentIds = Set(group.pullRequests.map(\.id))

            if !seededRepos.contains(repoID) {
                seenPRIds[repoID] = currentIds
                seededRepos.insert(repoID)
                didMutate = true
                continue
            }

            if enabledRepos.contains(repoID) {
                let previous = seenPRIds[repoID] ?? []
                let newIds = currentIds.subtracting(previous)
                if !newIds.isEmpty {
                    let newPRs = group.pullRequests.filter { newIds.contains($0.id) }
                    postNotifications(for: newPRs, repo: group.repo)
                }
            }

            // Union with previous so a PR that scrolls past the 50-item window
            // and later returns isn't re-notified.
            seenPRIds[repoID] = currentIds.union(seenPRIds[repoID] ?? [])
            didMutate = true
        }

        if didMutate { persist() }
    }

    // MARK: - Posting

    private func postNotifications(for prs: [PullRequest], repo: TrackedRepo) {
        if prs.count > 3 {
            postSummary(count: prs.count, repo: repo)
        } else {
            for pr in prs {
                postSingle(pr: pr, repo: repo)
            }
        }
    }

    private func postSingle(pr: PullRequest, repo: TrackedRepo) {
        let content = UNMutableNotificationContent()
        content.title = repo.nameWithOwner
        let author = pr.authorLogin ?? "Someone"
        content.body = "\(author) raised a new PR — \(pr.title)"
        content.sound = .default
        content.userInfo = ["url": pr.url.absoluteString]
        let req = UNNotificationRequest(identifier: pr.id, content: content, trigger: nil)
        center.add(req)
    }

    private func postSummary(count: Int, repo: TrackedRepo) {
        let content = UNMutableNotificationContent()
        content.title = repo.nameWithOwner
        content.body = "\(count) new pull requests"
        content.sound = .default
        content.userInfo = ["url": repo.pullsURL.absoluteString]
        let id = "summary-\(repo.id)-\(Int(Date().timeIntervalSince1970))"
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(req)
    }

    // MARK: - Cleanup

    private func pruneRemovedRepos(currentRepos: [TrackedRepo]) {
        let currentIDs = Set(currentRepos.map(\.id))
        let staleEnabled = enabledRepos.subtracting(currentIDs)
        let staleSeeded = seededRepos.subtracting(currentIDs)
        let staleSeen = Set(seenPRIds.keys).subtracting(currentIDs)
        guard !staleEnabled.isEmpty || !staleSeeded.isEmpty || !staleSeen.isEmpty else { return }
        enabledRepos.subtract(staleEnabled)
        seededRepos.subtract(staleSeeded)
        for key in staleSeen { seenPRIds.removeValue(forKey: key) }
        persist()
    }

    // MARK: - Persistence

    private func loadFromDefaults() {
        if let arr = defaults.stringArray(forKey: Keys.enabled) {
            enabledRepos = Set(arr)
        }
        if let arr = defaults.stringArray(forKey: Keys.seeded) {
            seededRepos = Set(arr)
        }
        if let dict = defaults.dictionary(forKey: Keys.seenIds) as? [String: [String]] {
            seenPRIds = dict.mapValues { Set($0) }
        }
    }

    private func persist() {
        defaults.set(Array(enabledRepos), forKey: Keys.enabled)
        defaults.set(Array(seededRepos), forKey: Keys.seeded)
        let dict: [String: [String]] = seenPRIds.mapValues { Array($0) }
        defaults.set(dict, forKey: Keys.seenIds)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
            DispatchQueue.main.async {
                NSWorkspace.shared.open(url)
            }
        }
        completionHandler()
    }
}
