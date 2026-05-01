import XCTest

final class GitHubClientTests: XCTestCase {

    // MARK: - parseSSOHeader

    func testSSOHeaderAcceptsGitHubHTTPSURL() {
        let url = GitHubClient.parseSSOHeader(
            "required; url=https://github.com/orgs/acme/sso?authorization_request=abc"
        )
        XCTAssertEqual(url?.host, "github.com")
        XCTAssertEqual(url?.scheme, "https")
    }

    func testSSOHeaderAcceptsSubdomainOfGitHub() {
        let url = GitHubClient.parseSSOHeader("required; url=https://api.github.com/foo")
        XCTAssertEqual(url?.host, "api.github.com")
    }

    func testSSOHeaderRejectsNonHTTPSScheme() {
        XCTAssertNil(GitHubClient.parseSSOHeader("required; url=javascript:alert(1)"))
        XCTAssertNil(GitHubClient.parseSSOHeader("required; url=http://github.com/orgs/acme/sso"))
        XCTAssertNil(GitHubClient.parseSSOHeader("required; url=file:///etc/passwd"))
    }

    func testSSOHeaderRejectsForeignHost() {
        XCTAssertNil(GitHubClient.parseSSOHeader("required; url=https://evil.example.com/sso"))
        XCTAssertNil(GitHubClient.parseSSOHeader("required; url=https://github.com.evil.example/sso"))
    }

    func testSSOHeaderTolerantOfWhitespaceAndOrdering() {
        let url = GitHubClient.parseSSOHeader("  required ;   url=https://github.com/orgs/acme/sso  ")
        XCTAssertEqual(url?.host, "github.com")
    }

    func testSSOHeaderNilOnMissingURL() {
        XCTAssertNil(GitHubClient.parseSSOHeader(nil))
        XCTAssertNil(GitHubClient.parseSSOHeader("required"))
        XCTAssertNil(GitHubClient.parseSSOHeader(""))
    }

    // MARK: - GitHubError descriptions

    func testHTTPErrorDescriptionDoesNotIncludeBody() {
        let desc = GitHubError.http(500).errorDescription ?? ""
        XCTAssertTrue(desc.contains("500"))
        XCTAssertFalse(desc.lowercased().contains("html"))
        XCTAssertFalse(desc.contains("<"))
    }
}
