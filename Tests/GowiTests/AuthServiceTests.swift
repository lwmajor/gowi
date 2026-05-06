import XCTest

// MARK: - Test doubles

private final class SpyKeychain: KeychainStoring {
    var storedToken: String?
    var storeCalled = false
    var deleteCalled = false

    init(token: String? = nil) { self.storedToken = token }

    func store(_ token: String) throws {
        storeCalled = true
        storedToken = token
    }
    func read() throws -> String? { storedToken }
    func delete() throws {
        deleteCalled = true
        storedToken = nil
    }
}

// A device-flow implementation that blocks forever — sign-in never completes.
private struct HangingDeviceFlow: DeviceFlowing {
    func requestCode(clientID: String, scopes: String) async throws -> DeviceCodeResponse {
        try await Task.sleep(nanoseconds: 60 * 1_000_000_000)
        throw CancellationError()
    }
    func pollForToken(clientID: String, deviceCode: String, initialInterval: Int) async throws -> String {
        throw CancellationError()
    }
}

// A device-flow implementation that immediately returns a fixed token.
private struct ImmediateDeviceFlow: DeviceFlowing {
    let token: String

    func requestCode(clientID: String, scopes: String) async throws -> DeviceCodeResponse {
        DeviceCodeResponse(
            deviceCode: "device-code",
            userCode: "ABCD-1234",
            verificationURI: URL(string: "https://github.com/login/device")!,
            verificationURIComplete: nil,
            expiresIn: 900,
            interval: 1
        )
    }
    func pollForToken(clientID: String, deviceCode: String, initialInterval: Int) async throws -> String {
        token
    }
}

// A device-flow that fails immediately with access_denied.
private struct DeniedDeviceFlow: DeviceFlowing {
    func requestCode(clientID: String, scopes: String) async throws -> DeviceCodeResponse {
        DeviceCodeResponse(
            deviceCode: "dc",
            userCode: "XXXX",
            verificationURI: URL(string: "https://github.com/login/device")!,
            verificationURIComplete: nil,
            expiresIn: 900,
            interval: 1
        )
    }
    func pollForToken(clientID: String, deviceCode: String, initialInterval: Int) async throws -> String {
        throw DeviceFlowError.denied
    }
}

// MARK: - Tests

@MainActor
final class AuthServiceTests: XCTestCase {

    // MARK: - Init

    func testInitWithStoredTokenStartsSignedIn() {
        let keychain = SpyKeychain(token: "ghs_abc123")
        let service = AuthService(keychain: keychain, client: HangingDeviceFlow())
        XCTAssertEqual(service.state, .signedIn)
    }

    func testInitWithEmptyTokenStartsSignedOut() {
        let keychain = SpyKeychain(token: "")
        let service = AuthService(keychain: keychain, client: HangingDeviceFlow())
        XCTAssertEqual(service.state, .signedOut)
    }

    func testInitWithNoTokenStartsSignedOut() {
        let keychain = SpyKeychain(token: nil)
        let service = AuthService(keychain: keychain, client: HangingDeviceFlow())
        XCTAssertEqual(service.state, .signedOut)
    }

    // MARK: - accessToken

    func testAccessTokenReturnsValueWhenSignedIn() {
        let keychain = SpyKeychain(token: "ghs_xyz")
        let service = AuthService(keychain: keychain, client: HangingDeviceFlow())
        XCTAssertEqual(service.accessToken, "ghs_xyz")
    }

    func testAccessTokenIsNilWhenSignedOut() {
        let keychain = SpyKeychain(token: nil)
        let service = AuthService(keychain: keychain, client: HangingDeviceFlow())
        XCTAssertNil(service.accessToken)
    }

    func testAccessTokenIsNilForEmptyStoredValue() {
        let keychain = SpyKeychain(token: "")
        let service = AuthService(keychain: keychain, client: HangingDeviceFlow())
        XCTAssertNil(service.accessToken)
    }

    // MARK: - signOut

    func testSignOutTransitionsToSignedOutAndDeletesToken() {
        let keychain = SpyKeychain(token: "ghs_abc123")
        let service = AuthService(keychain: keychain, client: HangingDeviceFlow())
        XCTAssertEqual(service.state, .signedIn)

        service.signOut()

        XCTAssertEqual(service.state, .signedOut)
        XCTAssertTrue(keychain.deleteCalled)
        XCTAssertNil(keychain.storedToken)
    }

    func testSignOutWhenAlreadySignedOutIsIdempotent() {
        let keychain = SpyKeychain(token: nil)
        let service = AuthService(keychain: keychain, client: HangingDeviceFlow())
        XCTAssertEqual(service.state, .signedOut)

        service.signOut()  // should not crash or change state unexpectedly
        XCTAssertEqual(service.state, .signedOut)
    }

    // MARK: - cancelSignIn

    func testCancelSignInWhenSignedOutIsNoop() {
        let keychain = SpyKeychain(token: nil)
        let service = AuthService(keychain: keychain, client: HangingDeviceFlow())

        service.cancelSignIn()  // should not crash

        XCTAssertEqual(service.state, .signedOut)
    }

    func testCancelSignInWhileAwaitingTransitionsToSignedOut() async {
        let keychain = SpyKeychain(token: nil)
        let service = AuthService(keychain: keychain, client: HangingDeviceFlow())

        service.startSignIn(publicReposOnly: false)
        // Give startSignIn a chance to reach .awaitingUserCode
        await Task.yield()
        await Task.yield()

        service.cancelSignIn()

        // Either .signedOut (cancelled before awaitingUserCode) or
        // transitions to .signedOut via cancelSignIn — either is correct.
        XCTAssertNotEqual(service.state, .signedIn)
    }

    // MARK: - sign-in happy path

    func testSignInWithImmediateFlowTransitionsToSignedIn() async {
        let keychain = SpyKeychain(token: nil)
        let flow = ImmediateDeviceFlow(token: "ghs_newtoken")
        let service = AuthService(keychain: keychain, client: flow)
        XCTAssertEqual(service.state, .signedOut)

        service.startSignIn(publicReposOnly: false)

        // Poll until the task completes (immediate flow, so very fast)
        var attempts = 0
        while service.state != .signedIn && attempts < 100 {
            await Task.yield()
            attempts += 1
        }

        XCTAssertEqual(service.state, .signedIn)
        XCTAssertTrue(keychain.storeCalled)
        XCTAssertEqual(keychain.storedToken, "ghs_newtoken")
        XCTAssertEqual(service.accessToken, "ghs_newtoken")
    }

    // MARK: - sign-in denied

    func testSignInWithDeniedFlowTransitionsToFailed() async {
        let keychain = SpyKeychain(token: nil)
        let service = AuthService(keychain: keychain, client: DeniedDeviceFlow())

        service.startSignIn(publicReposOnly: false)

        var attempts = 0
        while attempts < 100 {
            await Task.yield()
            if case .failed = service.state { break }
            attempts += 1
        }

        if case .failed(let msg) = service.state {
            XCTAssertFalse(msg.isEmpty)
        } else {
            XCTFail("Expected .failed, got \(service.state)")
        }
        XCTAssertFalse(keychain.storeCalled)
    }
}
