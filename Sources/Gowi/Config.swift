import Foundation

enum Config {
    /// GitHub OAuth App client ID. Public by design (device flow ships the client ID
    /// to the user's browser) — safe to commit.
    static let githubClientID = "Ov23lijdfBe0dBDCDccH"

    /// Bundle identifier. Must match the Xcode project bundle ID when we migrate.
    static let bundleID = "com.lloydmajor.gowi"

    /// Keychain service identifier used for the OAuth access token.
    static let keychainService = bundleID + ".github"

    /// Scopes requested during device flow. `repo` grants read/write on private repos
    /// because GitHub doesn't expose a read-only private-repo scope for OAuth apps.
    /// If the user ticks "Public repos only" on sign-in, `publicScopes` is used instead.
    static let fullScopes = "repo"
    static let publicScopes = "public_repo"

    /// GitHub OAuth endpoints.
    static let deviceCodeURL = URL(string: "https://github.com/login/device/code")!
    static let accessTokenURL = URL(string: "https://github.com/login/oauth/access_token")!

    /// GitHub GraphQL endpoint.
    static let graphQLURL = URL(string: "https://api.github.com/graphql")!
}
