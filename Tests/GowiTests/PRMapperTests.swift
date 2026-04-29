import XCTest

final class PRMapperTests: XCTestCase {
    func testMapReviewKnownValues() {
        XCTAssertEqual(PRMapper.mapReview("APPROVED"), .approved)
        XCTAssertEqual(PRMapper.mapReview("CHANGES_REQUESTED"), .changesRequested)
        XCTAssertEqual(PRMapper.mapReview("REVIEW_REQUIRED"), .reviewRequired)
    }

    func testMapReviewFallbacks() {
        XCTAssertEqual(PRMapper.mapReview(nil), .noReview)
        XCTAssertEqual(PRMapper.mapReview(""), .noReview)
        XCTAssertEqual(PRMapper.mapReview("SOMETHING_ELSE"), .noReview)
    }

    func testMapChecksKnownValues() {
        XCTAssertEqual(PRMapper.mapChecks("SUCCESS"), .success)
        XCTAssertEqual(PRMapper.mapChecks("FAILURE"), .failure)
        XCTAssertEqual(PRMapper.mapChecks("ERROR"), .failure)
        XCTAssertEqual(PRMapper.mapChecks("PENDING"), .pending)
        XCTAssertEqual(PRMapper.mapChecks("EXPECTED"), .pending)
    }

    func testMapChecksFallbacks() {
        XCTAssertEqual(PRMapper.mapChecks(nil), .noChecks)
        XCTAssertEqual(PRMapper.mapChecks(""), .noChecks)
        XCTAssertEqual(PRMapper.mapChecks("UNKNOWN"), .noChecks)
    }
}
