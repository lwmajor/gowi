import Foundation

struct DeviceCodeResponse: Decodable, Equatable {
    let deviceCode: String
    let userCode: String
    let verificationURI: URL
    let verificationURIComplete: URL?
    let expiresIn: Int
    let interval: Int

    /// The URL to open in the user's browser. Prefers the _complete variant
    /// (which pre-fills the code) and falls back to the plain one.
    var urlToOpen: URL { verificationURIComplete ?? verificationURI }

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case verificationURIComplete = "verification_uri_complete"
        case expiresIn = "expires_in"
        case interval
    }
}

enum DeviceFlowError: Error, LocalizedError, Equatable {
    case missingClientID
    case transport(String)
    case denied
    case expired
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "GitHub OAuth client ID is not configured. Replace the placeholder in Config.swift."
        case .transport(let msg): return "Network error: \(msg)"
        case .denied: return "Sign-in was cancelled in the browser."
        case .expired: return "The code expired before you authorized. Try again."
        case .unexpected(let msg): return msg
        }
    }
}

/// Interface for the two device-flow network steps — extracted so tests can inject a spy.
protocol DeviceFlowing {
    func requestCode(clientID: String, scopes: String) async throws -> DeviceCodeResponse
    func pollForToken(clientID: String, deviceCode: String, initialInterval: Int) async throws -> String
}

/// Thin wrapper around GitHub's OAuth device-flow endpoints.
/// Stateless; all state lives in `AuthService`.
struct DeviceFlowClient {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Step 1: request a device/user code pair from GitHub.
    func requestCode(clientID: String, scopes: String) async throws -> DeviceCodeResponse {
        guard clientID != "GITHUB_CLIENT_ID_TODO", !clientID.isEmpty else {
            throw DeviceFlowError.missingClientID
        }
        let body = form([
            "client_id": clientID,
            "scope": scopes
        ])
        let data = try await postForm(url: Config.deviceCodeURL, body: body)
        do {
            return try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
        } catch {
            throw DeviceFlowError.unexpected("Could not decode device-code response: \(error.localizedDescription)")
        }
    }

    /// Step 2: poll until the user authorizes (or declines). Respects the interval
    /// returned by GitHub and bumps on `slow_down`. Honours cooperative cancellation.
    func pollForToken(
        clientID: String,
        deviceCode: String,
        initialInterval: Int
    ) async throws -> String {
        var interval = max(1, initialInterval)
        while true {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            try Task.checkCancellation()

            let body = form([
                "client_id": clientID,
                "device_code": deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
            ])
            let data = try await postForm(url: Config.accessTokenURL, body: body)

            if let success = try? JSONDecoder().decode(TokenSuccess.self, from: data),
               !success.accessToken.isEmpty {
                return success.accessToken
            }
            if let err = try? JSONDecoder().decode(TokenError.self, from: data) {
                switch err.error {
                case "authorization_pending":
                    continue
                case "slow_down":
                    interval = err.interval ?? (interval + 5)
                case "access_denied":
                    throw DeviceFlowError.denied
                case "expired_token":
                    throw DeviceFlowError.expired
                default:
                    throw DeviceFlowError.unexpected(err.errorDescription ?? err.error)
                }
            } else {
                throw DeviceFlowError.unexpected("Unrecognised response from GitHub.")
            }
        }
    }

    // MARK: - internals

    private struct TokenSuccess: Decodable {
        let accessToken: String
        let tokenType: String
        let scope: String
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case tokenType = "token_type"
            case scope
        }
    }

    private struct TokenError: Decodable {
        let error: String
        let errorDescription: String?
        let interval: Int?
        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
            case interval
        }
    }

    private func form(_ pairs: [String: String]) -> Data {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))
        let body = pairs
            .map { ($0.key, $0.value) }
            .map { k, v in
                let ek = k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k
                let ev = v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v
                return "\(ek)=\(ev)"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private func postForm(url: URL, body: Data) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw DeviceFlowError.unexpected("GitHub returned HTTP \(http.statusCode).")
            }
            return data
        } catch let e as DeviceFlowError {
            throw e
        } catch {
            throw DeviceFlowError.transport(error.localizedDescription)
        }
    }
}

extension DeviceFlowClient: DeviceFlowing {}
