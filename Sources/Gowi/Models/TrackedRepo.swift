import Foundation

struct TrackedRepo: Codable, Hashable, Identifiable {
    let owner: String
    let name: String

    var nameWithOwner: String { "\(owner)/\(name)" }
    var id: String { nameWithOwner }
    var pullsURL: URL { URL(string: "https://github.com/\(owner)/\(name)/pulls")! }

    init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }

    /// Parses "owner/name" into a `TrackedRepo`. Returns nil on invalid input.
    init?(nameWithOwner: String) {
        let parts = nameWithOwner.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty, !parts[1].isEmpty,
              parts[0].allSatisfy(Self.isValidChar),
              parts[1].allSatisfy(Self.isValidChar)
        else { return nil }
        self.owner = String(parts[0])
        self.name = String(parts[1])
    }

    private static func isValidChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "-" || c == "_" || c == "."
    }
}
