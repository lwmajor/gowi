import Foundation

enum Config {
    /// GitHub OAuth App client ID. Read from the gitignored `Secrets.swift`
    /// so forks/clones supply their own. See `Secrets.swift.template`.
    static var githubClientID: String { Secrets.githubClientID }

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

    /// GitHub token settings page — fallback destination when a SAML auth URL
    /// isn't available from response headers.
    static let tokenSettingsURL = URL(string: "https://github.com/settings/tokens")!
}
