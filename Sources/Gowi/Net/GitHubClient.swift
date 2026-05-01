import Foundation

enum GitHubError: Error, LocalizedError {
    case notAuthenticated          // no token at all
    case unauthorized              // 401 from server; token is dead
    case transport(String)
    case http(Int, String)
    case graphQL([String])         // non-empty errors array in response
    case decoding(String)
    case notFound(String)          // repo or resource missing / inaccessible

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not signed in."
        case .unauthorized:     return "GitHub rejected the access token. Please sign in again."
        case .transport(let s): return "Network error: \(s)"
        case .http(let c, let s): return "HTTP \(c): \(s)"
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
            if !(200...299).contains(http.statusCode) {
                let snippet = String(data: data.prefix(300), encoding: .utf8) ?? ""
                throw GitHubError.http(http.statusCode, snippet)
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
            throw GitHubError.graphQL(errs.map(\.message))
        }
        guard let data = envelope.data else {
            throw GitHubError.decoding("GraphQL response had no data and no errors.")
        }
        return data
    }

    // MARK: - raw query (batch / partial-error handling)

    /// Execute a query and return raw JSON data. HTTP errors and 401 are still thrown,
    /// but GraphQL-level errors are left for the caller to interpret (enabling partial results).
    func sendRaw(_ query: String) async throws -> Data {
        let req = try buildRequest(query)
        return try await execute(req)
    }
}
