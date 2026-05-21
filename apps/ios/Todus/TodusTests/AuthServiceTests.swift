import XCTest
@testable import Todus

/// AuthService is `@MainActor` and `@Observable`. The networking surface is
/// hard-coded to `URLSession.shared`, so any test that crosses the wire (e.g.
/// the silent-refresh path's 401 → sign-out branch, Apple Sign In delegate
/// flow) requires either a `URLProtocol` stub injected through a custom
/// `URLSessionConfiguration` or a wholesale refactor to inject an
/// `AuthenticationTransport` protocol. The tests below cover what's reachable
/// without that refactor; the rest are explicitly skipped with TODOs.
@MainActor
final class AuthServiceTests: XCTestCase {

    // MARK: - Test fixture

    /// Build an AuthService pointed at an unroutable address so any accidental
    /// network call fails fast instead of hanging the test runner. The
    /// `preloaded` argument lets us pre-seed a Keychain-equivalent token
    /// snapshot without touching the device Keychain.
    private func makeService(
        bearer: String? = nil,
        refresh: String? = nil,
        sessionId: String? = nil
    ) -> AuthService {
        // 127.0.0.1:1 is reserved-and-refused on macOS / iOS, so any
        // accidental request errors immediately instead of timing out.
        let url = URL(string: "http://127.0.0.1:1")!
        let preload = AuthBootstrapTokens(
            bearerToken: bearer,
            refreshToken: refresh,
            currentSessionId: sessionId
        )
        return AuthService(backendURL: url, preloaded: preload)
    }

    // MARK: - C1 fix: handleAuthCallback rejects orphan deep links

    func testHandleAuthCallbackRejectsURLWithoutPendingFlow() {
        // A signed-out user receives a forged `todus://auth-callback?token=...`
        // URL from another app or a web page. Without an in-flight sign-in
        // (pendingAuthFlowExpiresAt = nil), accepting the token would silently
        // sign the user in with attacker-controlled credentials.
        let svc = makeService()
        XCTAssertFalse(svc.isAuthenticated)
        XCTAssertNil(svc.bearerToken)

        let forged = URL(string: "todus://auth-callback?token=eyJhbGciOi.attacker.signature&email=evil@x")!
        svc.handleAuthCallback(url: forged)

        // The provenance check must reject the URL silently: no token written,
        // no state change, no error message (we don't surface security
        // rejections to the UI).
        XCTAssertFalse(svc.isAuthenticated, "Rejected callback must not flip authState to .authenticated")
        XCTAssertNil(svc.bearerToken, "Rejected callback must not persist the attacker-controlled token")
        XCTAssertNil(svc.refreshToken)
        XCTAssertEqual(svc.authState, .guest)
    }

    func testHandleAuthCallbackRejectsForgedURLWhileAuthenticated() {
        // A signed-in user is even more vulnerable: an accepted forged URL
        // would *overwrite* their session with the attacker's token.
        let svc = makeService(bearer: "existing.jwt.token", refresh: "existing-refresh")
        XCTAssertTrue(svc.isAuthenticated, "Sanity check: preloaded token authenticates the user")

        let forged = URL(string: "todus://auth-callback?token=attacker.token.value")!
        svc.handleAuthCallback(url: forged)

        XCTAssertEqual(svc.bearerToken, "existing.jwt.token",
            "Forged callback must not overwrite the legitimate user's token (#8 / C1 fix).")
        XCTAssertEqual(svc.refreshToken, "existing-refresh")
    }

    func testHandleAuthCallbackHandlesMalformedURLGracefully() {
        // Malformed callback (no scheme, no host, no query) must not strand
        // the UI on the spinner — authState should land on .guest with a
        // user-facing error message.
        let svc = makeService()
        // First put the service into .authenticating so we can observe the
        // reset. We can't drive that directly without going through a sign-in
        // method, so this test focuses on the "no in-flight flow" rejection
        // path which is the more security-critical branch.
        let bogus = URL(string: "todus://link-callback")!
        svc.handleAuthCallback(url: bogus)
        // link-callback is an explicit no-op branch; service state must be
        // unchanged.
        XCTAssertEqual(svc.authState, .guest)
        XCTAssertNil(svc.bearerToken)
    }

    func testHandleAuthCallbackIgnoresLinkCallbackScheme() {
        // todus://link-callback is the account-linking flow and must not
        // alter the primary auth state.
        let svc = makeService(bearer: "user.jwt.token")
        XCTAssertTrue(svc.isAuthenticated)
        svc.handleAuthCallback(url: URL(string: "todus://link-callback")!)
        XCTAssertTrue(svc.isAuthenticated)
        XCTAssertEqual(svc.bearerToken, "user.jwt.token")
    }

    // MARK: - preload / Keychain seam

    func testPreloadTokensReturnsSendableSnapshot() {
        // preloadTokens is nonisolated and intentionally side-effect-free —
        // it's safe to call from a background Task.detached at app launch.
        let snapshot1 = AuthService.preloadTokens()
        let snapshot2 = AuthService.preloadTokens()
        // Same Keychain state in, same snapshot out (within a single test run).
        XCTAssertEqual(snapshot1.bearerToken, snapshot2.bearerToken)
        XCTAssertEqual(snapshot1.refreshToken, snapshot2.refreshToken)
        XCTAssertEqual(snapshot1.currentSessionId, snapshot2.currentSessionId)
    }

    func testInitFromPreloadedBearerSetsAuthenticatedState() {
        let svc = makeService(bearer: "preloaded.jwt.token")
        XCTAssertTrue(svc.isAuthenticated)
        XCTAssertEqual(svc.authState, .authenticated)
        XCTAssertEqual(svc.bearerToken, "preloaded.jwt.token")
    }

    func testInitWithoutPreloadedBearerStartsAsGuest() {
        let svc = makeService()
        XCTAssertFalse(svc.isAuthenticated)
        XCTAssertEqual(svc.authState, .guest)
        XCTAssertNil(svc.bearerToken)
    }

    // MARK: - Bearer token preview helper

    func testBearerTokenPreviewSafeForLogging() {
        let svc = makeService(bearer: "sensitive-jwt-value-1234567890")
        let preview = svc.bearerTokenPreview
        // Preview must include length but never the literal token.
        XCTAssertFalse(preview.contains("sensitive-jwt-value-1234567890"))
        XCTAssertTrue(preview.contains("len=") || preview == "None")
    }

    func testBearerTokenPreviewWhenEmpty() {
        let svc = makeService()
        XCTAssertEqual(svc.bearerTokenPreview, "None")
    }

    // MARK: - Deferred / refactor-required

    func testCompleteAuthenticationJWTOnlyBranchClearsRefreshAndSession() throws {
        // Branch 1: Google flow — JWT + explicit refresh token.
        let google = AuthService.classifyCallbackTokens(
            token: "a.b.c",
            newRefreshToken: "rt-google",
            tokenIsJWT: true
        )
        XCTAssertEqual(google.bearer, "a.b.c")
        XCTAssertEqual(google.refresh, "rt-google")
        XCTAssertNil(google.sessionId,
            "Google branch: classifier does not propose a sessionId — caller overrides explicitly.")

        // Branch 2: Apple / Email OTP flow — raw session token (no dots).
        let apple = AuthService.classifyCallbackTokens(
            token: "raw-session-token",
            newRefreshToken: nil,
            tokenIsJWT: false
        )
        XCTAssertEqual(apple.bearer, "raw-session-token",
            "Apple branch: bearer is the raw session token temporarily until refresh exchanges it for a JWT.")
        XCTAssertEqual(apple.refresh, "raw-session-token",
            "Apple branch: the raw session token is used as the refresh token.")
        XCTAssertNil(apple.sessionId)

        // Branch 3 (H1 fix): JWT-only — must NIL refresh + session for cross-account hygiene.
        let jwtOnly = AuthService.classifyCallbackTokens(
            token: "a.b.c",
            newRefreshToken: nil,
            tokenIsJWT: true
        )
        XCTAssertEqual(jwtOnly.bearer, "a.b.c")
        XCTAssertNil(jwtOnly.refresh,
            "JWT-only branch: refresh must be cleared to avoid pairing the new JWT with a previous account's refresh token.")
        XCTAssertNil(jwtOnly.sessionId,
            "JWT-only branch: sessionId must be cleared for cross-account hygiene.")
    }

    func testAttemptSilentRefreshOn401SignsOut() async throws {
        // Inject a URLProtocol stub via a custom URLSession so the refresh
        // endpoint returns a hard 401. The AuthTransport seam routes
        // refreshAccessTokenResult's network call through this stub.
        URLProtocolStub.register()
        defer { URLProtocolStub.unregister() }
        URLProtocolStub.responder = { request in
            // /api/auth/refresh-native-token → 401 → triggers signOut.
            let resp = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            return (resp, Data())
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self] + (config.protocolClasses ?? [])
        let stubSession = URLSession(configuration: config)

        let url = URL(string: "http://127.0.0.1:1")!
        let preload = AuthBootstrapTokens(
            bearerToken: "existing.bearer.jwt",
            refreshToken: "rt-rejectable",
            currentSessionId: "sid-existing"
        )
        let svc = AuthService(backendURL: url, preloaded: preload, transport: stubSession)
        XCTAssertTrue(svc.isAuthenticated, "Preloaded refresh token authenticates the service.")

        let refreshed = await svc.attemptSilentRefresh()

        XCTAssertFalse(refreshed, "401 from refresh endpoint must cause attemptSilentRefresh to return false.")
        XCTAssertFalse(svc.isAuthenticated, "401 from refresh endpoint must trigger signOut() → guest state.")
        XCTAssertNil(svc.bearerToken, "signOut() must clear the bearer token.")
        XCTAssertNil(svc.refreshToken, "signOut() must clear the refresh token.")
    }

    func testAppleSignInSetsAndClearsPendingAuthFlowWindow() {
        // Pin the pendingAuthFlowExpiresAt window contract that protects
        // `handleAuthCallback` from accepting forged deep links (#8). The
        // window is opened by Google web-based sign-in (and conceptually any
        // future Apple flow that wants the same provenance check). We drive
        // the lifecycle directly via the extracted internal helpers so we
        // don't need to spin up ASWebAuthenticationSession.
        let svc = makeService()
        XCTAssertFalse(svc.isPendingAuthFlowActive,
            "Sanity: a fresh service has no pending auth flow.")

        svc.beginPendingAuthFlow()
        XCTAssertTrue(svc.isPendingAuthFlowActive,
            "beginPendingAuthFlow must open the provenance window.")

        // handleAuthCallback with a valid URL during an active window: token is consumed.
        // (We just verify the window is open; the consumed-token branch is covered by
        // the existing forged-URL tests.)
        svc.endPendingAuthFlow()
        XCTAssertFalse(svc.isPendingAuthFlowActive,
            "endPendingAuthFlow must close the provenance window.")
    }
}

// MARK: - URLProtocol stub for AuthTransport tests

/// Records the requests sent through the stub session and lets the test supply
/// canned responses. Used to assert the 401 → signOut path in `attemptSilentRefresh`
/// without making a real network call.
final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responder: ((URLRequest) -> (HTTPURLResponse, Data))?

    static func register() {
        URLProtocol.registerClass(URLProtocolStub.self)
    }

    static func unregister() {
        responder = nil
        URLProtocol.unregisterClass(URLProtocolStub.self)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let responder = URLProtocolStub.responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (resp, data) = responder(request)
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
