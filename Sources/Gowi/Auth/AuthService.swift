import Foundation
import AppKit

enum AuthState: Equatable {
    case signedOut
    case awaitingUserCode(DeviceCodeResponse)
    case signedIn
    case failed(String)
}

@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var state: AuthState = .signedOut

    private let keychain: KeychainHelper
    private let client: DeviceFlowClient
    private var pollingTask: Task<Void, Never>?

    init(
        keychain: KeychainHelper = KeychainHelper(),
        client: DeviceFlowClient = DeviceFlowClient()
    ) {
        self.keychain = keychain
        self.client = client
        if let token = try? keychain.read(), !token.isEmpty {
            self.state = .signedIn
        }
    }

    /// Returns the stored access token if signed in, otherwise nil.
    var accessToken: String? {
        (try? keychain.read()).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Kicks off the device flow. Updates `state` as it progresses.
    func startSignIn(publicReposOnly: Bool) {
        cancelSignIn()
        let scopes = publicReposOnly ? Config.publicScopes : Config.fullScopes
        let clientID = Config.githubClientID

        pollingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let code = try await self.client.requestCode(clientID: clientID, scopes: scopes)
                await MainActor.run { self.state = .awaitingUserCode(code) }

                // Copy code to clipboard and open the verification URL.
                await MainActor.run {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(code.userCode, forType: .string)
                    NSWorkspace.shared.open(code.urlToOpen)
                }

                let token = try await self.client.pollForToken(
                    clientID: clientID,
                    deviceCode: code.deviceCode,
                    initialInterval: code.interval
                )
                try self.keychain.store(token)
                await MainActor.run { self.state = .signedIn }
            } catch is CancellationError {
                await MainActor.run { self.state = .signedOut }
            } catch let e as DeviceFlowError {
                let msg = e.errorDescription ?? "Sign-in failed."
                await MainActor.run { self.state = .failed(msg) }
            } catch {
                await MainActor.run { self.state = .failed(error.localizedDescription) }
            }
        }
    }

    func cancelSignIn() {
        pollingTask?.cancel()
        pollingTask = nil
        if case .awaitingUserCode = state { state = .signedOut }
        if case .failed = state { state = .signedOut }
    }

    func signOut() {
        cancelSignIn()
        try? keychain.delete()
        state = .signedOut
    }
}
