import Foundation

/// Stable accessibility identifiers for SwiftUI controls. Assertions in
/// `Tests/GowiUITests` look these up via `XCUIApplication`.
enum AccessibilityID {
    enum Main {
        static let emptyState = "main.empty"
        static let openSettingsButton = "main.empty.openSettings"
        static let loading = "main.loading"
        static let allClear = "main.allClear"
        static let allClearRefreshButton = "main.allClear.refresh"
        static let refreshButton = "main.refreshButton"
        static let prList = "main.prList"
        static let errorState = "main.error"
        static let errorRetryButton = "main.error.retry"
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
        static func id(_ prID: String) -> String { "prRow.\(prID)" }
        static func errorRow(_ repoID: String) -> String { "prRow.error.\(repoID)" }
        static func errorRetry(_ repoID: String) -> String { "prRow.error.\(repoID).retry" }
    }

    enum Repositories {
        static let exportButton = "exportReposButton"
        static let importButton = "importReposButton"
    }
}
