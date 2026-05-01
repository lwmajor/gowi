import Foundation

struct PRCache {
    static let shared = PRCache()

    private let url: URL? = {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("gowi", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cache.json")
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func load() -> [RepoGroup]? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode([RepoGroup].self, from: data)
    }

    func save(_ groups: [RepoGroup]) {
        guard let url, let data = try? encoder.encode(groups) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
