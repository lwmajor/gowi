#if canImport(XCTest)
import XCTest
@testable import Gowi

final class TrackedRepoTests: XCTestCase {
    func testValidInput() {
        let r = TrackedRepo(nameWithOwner: "apple/swift")
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.owner, "apple")
        XCTAssertEqual(r?.name, "swift")
        XCTAssertEqual(r?.nameWithOwner, "apple/swift")
    }

    func testAllowedChars() {
        XCTAssertNotNil(TrackedRepo(nameWithOwner: "owner-with-dashes/repo_with_underscores"))
        XCTAssertNotNil(TrackedRepo(nameWithOwner: "owner.with.dots/repo.name"))
    }

    func testRejectsEmpty() {
        XCTAssertNil(TrackedRepo(nameWithOwner: ""))
        XCTAssertNil(TrackedRepo(nameWithOwner: "owner/"))
        XCTAssertNil(TrackedRepo(nameWithOwner: "/repo"))
    }

    func testRejectsTooManyParts() {
        XCTAssertNil(TrackedRepo(nameWithOwner: "a/b/c"))
    }

    func testRejectsWhitespace() {
        XCTAssertNil(TrackedRepo(nameWithOwner: "own er/repo"))
        XCTAssertNil(TrackedRepo(nameWithOwner: "owner/re po"))
    }

    func testPullsURL() {
        let r = TrackedRepo(owner: "apple", name: "swift")
        XCTAssertEqual(r.pullsURL.absoluteString, "https://github.com/apple/swift/pulls")
    }
}
#endif
