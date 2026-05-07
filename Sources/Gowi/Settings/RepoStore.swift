import Foundation
import OSLog
import SwiftUI

@MainActor
final class RepoStore: ObservableObject {
    @Published private(set) var repos: [TrackedRepo] = []

    struct ImportResult: Equatable {
        let added: Int
        let skipped: Int
    }

    private let key = "trackedRepos"
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.lloydmajor.gowi", category: "RepoStore")

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

    func exportText() -> String {
        repos.map(\.nameWithOwner).joined(separator: "\n")
    }

    @discardableResult
    func importRepos(from text: String) -> ImportResult {
        var updatedRepos = repos
        var added = 0
        var skipped = 0

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let repo = TrackedRepo(nameWithOwner: line) else {
                skipped += 1
                #if DEBUG
                logger.debug("Skipping invalid imported repo line: \(line, privacy: .public)")
                #endif
                continue
            }
            guard !updatedRepos.contains(repo) else {
                skipped += 1
                continue
            }
            updatedRepos.append(repo)
            added += 1
        }

        if added > 0 {
            repos = updatedRepos
            save()
        }

        return ImportResult(added: added, skipped: skipped)
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
