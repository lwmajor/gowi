import Foundation
import OSLog

private let logger = Logger(subsystem: "com.lloydmajor.gowi", category: "PRCache")

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
        guard let url else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode([RepoGroup].self, from: data)
        } catch {
            logger.error("Cache load failed: \(error.localizedDescription)")
            return nil
        }
    }

    func save(_ groups: [RepoGroup]) {
        guard let url else { return }
        do {
            let data = try encoder.encode(groups)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Cache save failed: \(error.localizedDescription)")
        }
    }
}
