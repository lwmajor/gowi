import Foundation

enum GitHubError: Error, LocalizedError {
    case notAuthenticated          // no token at all
    case unauthorized              // 401 from server; token is dead
    case samlRequired(URL)         // org enforces SAML SSO; token needs authorization
    case transport(String)
    case http(Int)
    case graphQL([String])         // non-empty errors array in response
    case decoding(String)
    case notFound(String)          // repo or resource missing / inaccessible

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not signed in."
        case .unauthorized:     return "GitHub rejected the access token. Please sign in again."
        case .samlRequired:     return "One or more repos require GitHub SSO authorization."
        case .transport(let s): return "Network error: \(s)"
        case .http(let c):      return "GitHub returned HTTP \(c)."
        case .graphQL(let msgs): return msgs.joined(separator: "; ")
        case .decoding(let s):  return "Could not parse GitHub response: \(s)"
        case .notFound(let s):  return s
        }
    }
}

struct RateLimitInfo: Decodable, Equatable {
    let remaining: Int
    let resetAt: Date
    let cost: Int
}

struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T?
    let errors: [GraphQLErrorEntry]?

    struct GraphQLErrorEntry: Decodable {
        let message: String
        let type: String?
    }
}

/// Stateless-ish GraphQL client for GitHub's v4 API.
///
/// `tokenProvider` is called on every request so the client always sees the
/// latest token without holding a reference to `AuthService` / `KeychainHelper`.
/// Throwing `.unauthorized` on a 401 is the signal for callers to sign out.
final class GitHubClient {
    private let tokenProvider: () -> String?
    private let session: URLSession
    let decoder: JSONDecoder

    init(tokenProvider: @escaping () -> String?, session: URLSession = .shared) {
        self.tokenProvider = tokenProvider
        self.session = session
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        self.decoder = d
    }

    // MARK: - internal transport

    private func buildRequest(_ query: String, variables: [String: Any] = [:]) throws -> URLRequest {
        guard let token = tokenProvider(), !token.isEmpty else {
            throw GitHubError.notAuthenticated
        }
        var req = URLRequest(url: Config.graphQLURL)
        req.httpMethod = "POST"
        req.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("gowi/0.1 (macOS)", forHTTPHeaderField: "User-Agent")
        var body: [String: Any] = ["query": query]
        if !variables.isEmpty { body["variables"] = variables }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private func execute(_ req: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw GitHubError.transport(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 { throw GitHubError.unauthorized }
            if http.statusCode == 403 {
                // GitHub signals SAML SSO enforcement via this header on org-protected resources.
                // Format: "required; url=https://github.com/orgs/ORG/sso?authorization_request=..."
                let authURL = Self.parseSSOHeader(http.value(forHTTPHeaderField: "X-GitHub-SSO"))
                throw GitHubError.samlRequired(authURL ?? Config.tokenSettingsURL)
            }
            if !(200...299).contains(http.statusCode) {
                throw GitHubError.http(http.statusCode)
            }
        }
        return data
    }

    // MARK: - typed query (single data type)

    /// Execute a GraphQL query, return the decoded `data` payload.
    /// Throws on network error, 401, non-2xx HTTP, or non-empty GraphQL `errors`.
    func send<T: Decodable>(
        _ query: String,
        variables: [String: String] = [:],
        as type: T.Type = T.self
    ) async throws -> T {
        let req = try buildRequest(query, variables: Dictionary(uniqueKeysWithValues: variables.map { ($0.key, $0.value as Any) }))
        let raw = try await execute(req)

        let envelope: GraphQLResponse<T>
        do {
            envelope = try decoder.decode(GraphQLResponse<T>.self, from: raw)
        } catch {
            throw GitHubError.decoding(error.localizedDescription)
        }
        if let errs = envelope.errors, !errs.isEmpty {
            if errs.contains(where: { $0.type == "NOT_FOUND" }) {
                throw GitHubError.notFound(errs.first?.message ?? "Not found")
            }
            if errs.contains(where: { Self.isSAMLError($0.message) }) {
                throw GitHubError.samlRequired(Config.tokenSettingsURL)
            }
            throw GitHubError.graphQL(errs.map(\.message))
        }
        guard let data = envelope.data else {
            throw GitHubError.decoding("GraphQL response had no data and no errors.")
        }
        return data
    }

    // MARK: - SAML helpers

    /// Parses `X-GitHub-SSO: required; url=<URL>` and returns the URL component
    /// only when it points to an `https://...github.com` resource. Anything
    /// else (different scheme, different host, malformed) returns nil so the
    /// caller falls back to a known-safe URL.
    static func parseSSOHeader(_ header: String?) -> URL? {
        guard let header else { return nil }
        let urlValue = header
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("url=") }
            .map { String($0.dropFirst("url=".count)) }
        guard let urlValue,
              let url = URL(string: urlValue),
              url.scheme == "https",
              let host = url.host,
              host == "github.com" || host.hasSuffix(".github.com")
        else { return nil }
        return url
    }

    static func isSAMLError(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("saml") ||
        message.contains("organization SAML enforcement") ||
        message.contains("grant your OAuth token access to this organization")
    }

    // MARK: - raw query (batch / partial-error handling)

    /// Execute a query and return raw JSON data. HTTP errors and 401 are still thrown,
    /// but GraphQL-level errors are left for the caller to interpret (enabling partial results).
    func sendRaw(_ query: String) async throws -> Data {
        let req = try buildRequest(query)
        return try await execute(req)
    }
}
