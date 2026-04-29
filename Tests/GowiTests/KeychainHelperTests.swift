import XCTest

final class KeychainHelperTests: XCTestCase {
    private let helper = KeychainHelper(
        service: "com.lloydmajor.gowi.tests",
        account: "oauth-access-token-test"
    )

    override func setUpWithError() throws {
        try? helper.delete()
    }

    override func tearDownWithError() throws {
        try? helper.delete()
    }

    func testRoundTrip() throws {
        try helper.store("ghs_abc123")
        XCTAssertEqual(try helper.read(), "ghs_abc123")
    }

    func testOverwrite() throws {
        try helper.store("first")
        try helper.store("second")
        XCTAssertEqual(try helper.read(), "second")
    }

    func testDelete() throws {
        try helper.store("to-delete")
        try helper.delete()
        XCTAssertNil(try helper.read())
    }

    func testReadWhenAbsent() throws {
        XCTAssertNil(try helper.read())
    }
}
