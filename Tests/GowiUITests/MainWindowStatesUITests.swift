import XCTest

/// Drives the real `MainWindow` via `XCUIApplication`, with backing services
/// stubbed by `UITestConfiguration` (selected via the `-ui-state` launch arg).
/// The accessibility identifiers asserted here are defined in
/// `Sources/Gowi/UI/AccessibilityID.swift`.
final class MainWindowStatesUITests: XCTestCase {
    private let waitTimeout: TimeInterval = 8

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func launch(state: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-state", state]
        app.launch()
        return app
    }

    private func assertExists(_ element: XCUIElement, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: waitTimeout), message, file: file, line: line)
    }

    /// Generic identifier lookup that works regardless of which XCUIElementType
    /// SwiftUI assigned (buttons, links, "other", etc.). Use when the production
    /// view applies a custom `.buttonStyle(...)` that changes the surfaced type.
    private func element(_ app: XCUIApplication, withIdentifier id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    // Identifier mirrors of AccessibilityID.swift — kept in sync by hand because
    // the UI test target doesn't share source with the main module.
    private enum ID {
        enum Main {
            static let emptyState = "main.empty"
            static let openSettingsButton = "main.empty.openSettings"
            static let allClear = "main.allClear"
            static let allClearRefresh = "main.allClear.refresh"
            static let prList = "main.prList"
            static let errorState = "main.error"
            static let errorRetry = "main.error.retry"
            static let refreshButton = "main.refreshButton"
        }
        enum Banner {
            static let tokenRevoked = "banner.tokenRevoked"
            static let tokenRevokedDismiss = "banner.tokenRevoked.dismiss"
            static let saml = "banner.saml"
            static let samlAuthorize = "banner.saml.authorize"
            static let samlDismiss = "banner.saml.dismiss"
            static let cached = "banner.cached"
            static let cachedRetry = "banner.cached.retry"
        }
        enum PRRow {
            static func errorRow(_ repoID: String) -> String { "prRow.error.\(repoID)" }
            static func errorRetry(_ repoID: String) -> String { "prRow.error.\(repoID).retry" }
            static func id(_ prID: String) -> String { "prRow.\(prID)" }
        }
    }

    // MARK: - Tests

    func test_empty_showsOpenSettingsButton() {
        let app = launch(state: "empty")
        assertExists(app.buttons[ID.Main.openSettingsButton], "Open Settings button should exist")
    }

    func test_allClear_showsCheckmarkAndRefresh() {
        let app = launch(state: "allClear")
        assertExists(app.buttons[ID.Main.allClearRefresh], "All clear refresh button should be visible")
        XCTAssertTrue(app.buttons[ID.Main.refreshButton].exists, "Toolbar refresh button should be visible")
    }

    func test_loaded_showsPRList() {
        let app = launch(state: "loaded")
        // Fixture seeds 3 PRs in apple/swift (first id "apple/swift#0") and 1 in vapor/vapor.
        // Just verify at least one identifiable PR row exists.
        let firstRow = app.descendants(matching: .any)[ID.PRRow.id("apple/swift#0")]
        assertExists(firstRow, "First PR row in apple/swift should exist")
    }

    func test_globalError_showsRetry() {
        let app = launch(state: "error")
        assertExists(app.buttons[ID.Main.errorRetry], "Error retry button should exist")
    }

    func test_perRepoError_showsErrorRowAndRetry() {
        let app = launch(state: "perRepoError")
        // OK repo (apple/swift) renders rows; failing repo (vapor/vapor) renders an error row + retry.
        // The per-repo retry uses .buttonStyle(.link) which SwiftUI surfaces as a link, not a button.
        assertExists(app.descendants(matching: .any)[ID.PRRow.id("apple/swift#0")], "Healthy repo's first PR should appear")
        assertExists(element(app, withIdentifier: ID.PRRow.errorRetry("vapor/vapor")), "Per-repo retry should exist")
    }

    func test_tokenRevoked_showsBannerAboveSignIn() {
        let app = launch(state: "tokenRevoked")
        assertExists(app.buttons[ID.Banner.tokenRevokedDismiss], "Banner dismiss button should exist")
        app.buttons[ID.Banner.tokenRevokedDismiss].click()
        // After dismiss, the dismiss button should no longer be hittable.
        let dismissedExpectation = expectation(
            for: NSPredicate(format: "exists == NO"),
            evaluatedWith: app.buttons[ID.Banner.tokenRevokedDismiss]
        )
        wait(for: [dismissedExpectation], timeout: 2)
    }

    func test_samlRequired_showsBannerWithAuthorize() {
        let app = launch(state: "samlRequired")
        assertExists(app.buttons[ID.Banner.samlAuthorize], "SAML Authorize button should exist")
        XCTAssertTrue(app.buttons[ID.Banner.samlDismiss].exists, "SAML Dismiss button should exist")
    }

    func test_cachedData_showsBannerWithRetry() {
        let app = launch(state: "cachedData")
        // Cached-data retry uses .buttonStyle(.borderless), which SwiftUI doesn't always
        // surface as `Button`, so look up by identifier across any element type.
        assertExists(element(app, withIdentifier: ID.Banner.cachedRetry), "Cached-data retry should exist")
    }
}
