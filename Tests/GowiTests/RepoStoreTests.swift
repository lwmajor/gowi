#if canImport(XCTest)
import XCTest
@testable import Gowi

@MainActor
final class RepoStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: RepoStore!

    override func setUp() async throws {
        let suite = "gowi.tests.repostore." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        store = RepoStore(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: defaults.description)
        store = nil
        defaults = nil
    }

    func testStartsEmpty() {
        XCTAssertTrue(store.repos.isEmpty)
    }

    func testAddAndPersistenceAcrossReload() {
        store.add(TrackedRepo(owner: "apple", name: "swift"))
        store.add(TrackedRepo(owner: "pointfreeco", name: "swift-composable-architecture"))
        XCTAssertEqual(store.repos.map(\.nameWithOwner),
                       ["apple/swift", "pointfreeco/swift-composable-architecture"])

        // reload from the same defaults to prove persistence
        let reloaded = RepoStore(defaults: defaults)
        XCTAssertEqual(reloaded.repos.map(\.nameWithOwner),
                       ["apple/swift", "pointfreeco/swift-composable-architecture"])
    }

    func testAddDuplicateIsNoop() {
        let repo = TrackedRepo(owner: "apple", name: "swift")
        store.add(repo)
        store.add(repo)
        XCTAssertEqual(store.repos.count, 1)
    }

    func testRemove() {
        let a = TrackedRepo(owner: "apple", name: "swift")
        let b = TrackedRepo(owner: "apple", name: "swift-package-manager")
        store.add(a); store.add(b)
        store.remove(a)
        XCTAssertEqual(store.repos, [b])
    }

    func testMove() {
        let a = TrackedRepo(owner: "a", name: "x")
        let b = TrackedRepo(owner: "b", name: "y")
        let c = TrackedRepo(owner: "c", name: "z")
        store.add(a); store.add(b); store.add(c)
        store.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(store.repos, [c, a, b])
    }
}
#endif
