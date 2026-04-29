import Foundation
import SwiftUI

@MainActor
final class RepoStore: ObservableObject {
    @Published private(set) var repos: [TrackedRepo] = []

    private let key = "trackedRepos"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - mutation

    func add(_ repo: TrackedRepo) {
        guard !repos.contains(repo) else { return }
        repos.append(repo)
        save()
    }

    func remove(at offsets: IndexSet) {
        repos.remove(atOffsets: offsets)
        save()
    }

    func remove(_ repo: TrackedRepo) {
        repos.removeAll { $0 == repo }
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        repos.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - persistence

    private func load() {
        let raw = defaults.stringArray(forKey: key) ?? []
        repos = raw.compactMap { TrackedRepo(nameWithOwner: $0) }
    }

    private func save() {
        defaults.set(repos.map(\.nameWithOwner), forKey: key)
    }
}
