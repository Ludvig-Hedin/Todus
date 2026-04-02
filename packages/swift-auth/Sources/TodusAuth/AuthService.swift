import AuthenticationServices
import Foundation
import Observation
import OSLog

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private let authLog = Logger(subsystem: "com.todus.auth", category: "AuthService")

private func debugAuthLog(_ message: String) {
#if DEBUG
    authLog.debug("\(message)")
#endif
}

private actor KeychainPersistenceActor {
    func persist(key: String, value: String?) {
        if let value {
            if !KeychainHelper.save(key: key, value: value) {
                authLog.error("Keychain persistence failed for key \(key, privacy: .public)")
            }
        } else {
            KeychainHelper.delete(key: key)
        }
    }
}

/// Unified auth service for the Todus app (iOS + macOS).
/// Talks to the Better-Auth backend (Cloudflare Workers) and supports:
/// - Apple Sign In (native ASAuthorizationAppleIDProvider → backend validates ID token)
/// - Google Sign In (ASWebAuthenticationSession → Google OAuth → /api/auth/mobile-token → deep link)
/// - Email OTP (6-digit code via Resend)
///
/// Shared across iOS and macOS via the TodusAuth package.
@MainActor
@Observable
public final class AuthService: NSObject {
    private static let keychainPersistence = KeychainPersistenceActor()
    private static let freshLoginValidationAttempts = 5
    private static let refreshValidationAttempts = 2
    private static let callbackDeduplicationWindow: TimeInterval = 2

    // MARK: - State

    public enum AuthState: Equatable, Sendable {
        case guest
        case authenticating
        case otpPending(email: String)
        case authenticated
    }

    public var authState: AuthState = .guest
    public var lastErrorMessage: String?
    public var isLoading = false

    /// Set by the API client when a 401 is received and silent refresh fails.
    /// UI shows a "Session expired" banner when true.
    public var isSessionExpired = false

    /// Whether the onboarding/login screen should be shown
    public var showsOnboarding: Bool {
        !hasSeenOnboarding && !isAuthenticated
    }

    public var isAuthenticated: Bool {
        if case .authenticated = authState { return true }
        return false
    }

    /// User's email — stored property so @Observable triggers SwiftUI re-renders.
    /// Previously a computed property reading from Keychain, which meant SwiftUI
    /// never detected changes after fetchUserProfile updated the Keychain.
    public var userEmail: String? {
        didSet { persistStringToKeychain(key: Keys.userEmail, value: userEmail) }
    }

    /// User's display name from Google / Better Auth profile.
    /// Stored property so SwiftUI observation triggers re-renders when updated.
    public var userName: String? {
        didSet { persistStringToKeychain(key: Keys.userName, value: userName) }
    }

    /// User's avatar URL string from Google profile.
    /// Stored property so SwiftUI observation triggers re-renders when updated.
    public var userImage: String? {
        didSet { persistStringToKeychain(key: Keys.userImage, value: userImage) }
    }

    /// Stored as an @Observable property so SwiftUI detects changes and root view re-renders.
    public var hasSeenOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasSeenOnboarding, forKey: Keys.hasSeenOnboarding)
        }
    }

    // MARK: - Keys

    private enum Keys {
        static let bearerToken = "com.todus.auth.bearerToken"
        static let currentSessionId = "com.todus.auth.currentSessionId"
        static let userEmail = "com.todus.auth.userEmail"
        static let userName = "com.todus.auth.userName"
        static let userImage = "com.todus.auth.userImage"
        static let hasSeenOnboarding = "Todus.hasSeenOnboarding"
        static let hasLaunchedBefore = "Todus.hasLaunchedBefore"
    }

    // MARK: - Configuration

    private let backendURL: URL

    /// Keep a strong reference to the web auth session so the system doesn't deallocate it mid-flow.
    /// Without this, ASWebAuthenticationSession can be garbage-collected and the callback never fires.
    private var webAuthSession: ASWebAuthenticationSession?
    private var isCompletingAuthentication = false
    private var lastHandledCallbackToken: String?
    private var lastHandledCallbackAt: Date?

    /// The current Bearer token, cached in memory to avoid repeated synchronous Keychain reads.
    public private(set) var bearerToken: String? {
        didSet { persistStringToKeychain(key: Keys.bearerToken, value: bearerToken) }
    }

    public private(set) var currentSessionId: String? {
        didSet { persistStringToKeychain(key: Keys.currentSessionId, value: currentSessionId) }
    }

    public var hasPersistedBearerToken: Bool {
        bearerToken != nil
    }

    public var bearerTokenPreview: String {
        guard let token = bearerToken, !token.isEmpty else { return "None" }
        let prefix = token.prefix(6)
        let suffix = token.suffix(4)
        return "\(prefix)...\(suffix) (\(token.count))"
    }

    // MARK: - Init

    public init(backendURL: URL) {
        debugAuthLog("AuthService bootstrap begin")
        self.backendURL = backendURL
        // Initialize stored properties from persisted state before super.init()
        self.hasSeenOnboarding = UserDefaults.standard.bool(forKey: Keys.hasSeenOnboarding)
        self.userEmail = nil
        self.userName = nil
        self.userImage = nil
        self.currentSessionId = KeychainHelper.read(key: Keys.currentSessionId)
        self.bearerToken = KeychainHelper.read(key: Keys.bearerToken)
        super.init()

        if !UserDefaults.standard.bool(forKey: Keys.hasLaunchedBefore) {
            clearPersistedAuthState()
            UserDefaults.standard.set(true, forKey: Keys.hasLaunchedBefore)
        }

        if bearerToken != nil {
            authState = .authenticated
        }

        Task {
            await restoreCachedProfileMetadata()
        }
        debugAuthLog("AuthService bootstrap end")
    }

    // MARK: - Apple Sign In

    /// Performs native Apple Sign In and sends the ID token to the backend.
    /// Better-Auth validates the ID token using the configured appBundleIdentifier.
    public func signInWithApple() async {
        isLoading = true
        lastErrorMessage = nil
        authState = .authenticating

        let provider = ASAuthorizationAppleIDProvider()
        let appleRequest = provider.createRequest()
        appleRequest.requestedScopes = [.email, .fullName]

        let delegate = AppleSignInDelegate()

        let controller = ASAuthorizationController(authorizationRequests: [appleRequest])
        controller.delegate = delegate

        do {
            let credential = try await delegate.performRequest(controller: controller)

            guard let idTokenData = credential.identityToken,
                  let idToken = String(data: idTokenData, encoding: .utf8) else {
                lastErrorMessage = "Failed to get Apple ID token."
                authState = .guest
                isLoading = false
                return
            }

            authLog.info("Apple ID token obtained, sending to backend...")

            // Send ID token to backend — Better-Auth validates via Apple provider config.
            // Format matches what the RN app sends: { idToken: { token: "..." } }
            let url = backendURL.appending(path: "api/auth/sign-in/social")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // Origin header required by Better-Auth CSRF check (must match trustedOrigins)
            // Origin must match a trustedOrigin with a valid hostname — the CORS middleware
            // parses the hostname and checks against allowed domains (todus.app, localhost).
            // Using the web app URL ensures it passes both CORS and Better-Auth CSRF checks.
            request.setValue("https://todus.app", forHTTPHeaderField: "Origin")

            // Better-Auth expects idToken as { token: "..." } for native Apple sign-in
            let body: [String: Any] = [
                "provider": "apple",
                "idToken": ["token": idToken],
                "callbackURL": "/",
                "disableRedirect": true,
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            // Don't follow redirects — we want the response directly
            let config = URLSessionConfiguration.default
            let session = URLSession(configuration: config, delegate: NoRedirectDelegate.shared, delegateQueue: nil)
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                lastErrorMessage = "Apple Sign In failed. Invalid response."
                authState = .guest
                isLoading = false
                return
            }

            debugAuthLog("Apple sign-in response status=\(http.statusCode)")

            // For 3xx redirects, check the Location header for a token URL
            if (300..<400).contains(http.statusCode),
               let location = http.value(forHTTPHeaderField: "Location"),
               let locationURL = URL(string: location),
               let comps = URLComponents(url: locationURL, resolvingAgainstBaseURL: false),
               let token = comps.queryItems?.first(where: { $0.name == "token" })?.value {
                authLog.info("Apple sign-in: token found in redirect Location header")
                completeAuthentication(token: token, email: credential.email)
            }
            // For 2xx responses, extract token from body/headers
            else if (200..<300).contains(http.statusCode),
                    extractToken(from: data, response: http, email: credential.email) {
                authLog.info("Apple sign-in: authenticated successfully")
            }
            // For 3xx without token in Location — the redirect itself may contain cookie-based session.
            // Try to extract token from Set-Cookie or body.
            else if (300..<400).contains(http.statusCode),
                    extractToken(from: data, response: http, email: credential.email) {
                authLog.info("Apple sign-in: token extracted from redirect response")
            } else {
                authLog.error("Apple sign-in: failed to extract token. Status=\(http.statusCode)")
                lastErrorMessage = "Apple Sign In: no token in response (HTTP \(http.statusCode)). Check debug logs."
                authState = .guest
            }

        } catch {
            authLog.error("Apple sign-in error: \(error.localizedDescription)")
            if (error as NSError).domain == ASAuthorizationError.errorDomain,
               (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                // User cancelled — no error message needed
            } else {
                lastErrorMessage = "Apple Sign In was cancelled or failed."
            }
            authState = .guest
        }

        if !isCompletingAuthentication {
            isLoading = false
        }
    }

    // MARK: - Google Sign In (Web-based OAuth)

    /// Two-step Google OAuth flow:
    /// 1. POST to backend to get the Google OAuth redirect URL
    /// 2. Open that URL in ASWebAuthenticationSession (system browser)
    /// 3. After Google consent, backend creates session + redirects to /api/auth/mobile-token
    /// 4. /api/auth/mobile-token converts the browser session cookie into a JWT bearer token
    ///    and redirects to todus://auth-callback?token=<jwt>
    public func signInWithGoogle() async {
        isLoading = true
        lastErrorMessage = nil
        authState = .authenticating

        do {
            // Step 1: POST to get the Google OAuth redirect URL from Better-Auth.
            // Better-Auth's social sign-in is POST-only — returns { url: "https://accounts.google.com/..." }
            let signInURL = backendURL.appending(path: "api/auth/sign-in/social")
            var request = URLRequest(url: signInURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("https://todus.app", forHTTPHeaderField: "Origin")

            // callbackURL must be the FULL path including /api prefix because:
            // 1. Better-Auth stores and redirects to callbackURL as-is (no resolution)
            // 2. The mobile-token route is inside the Hono `api` sub-router mounted at /api
            // 3. So the full route is /api/auth/mobile-token, not /auth/mobile-token
            let body: [String: Any] = [
                "provider": "google",
                "callbackURL": "/api/auth/mobile-token",
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            // Use no-redirect delegate to catch the redirect URL instead of following it
            let config = URLSessionConfiguration.default
            let session = URLSession(configuration: config, delegate: NoRedirectDelegate.shared, delegateQueue: nil)
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }

            authLog.info("Google social sign-in POST response: status=\(http.statusCode)")

            // Better-Auth returns either:
            // - 200 with { url: "..." } (the Google OAuth URL)
            // - 302 redirect to the Google OAuth URL
            var googleAuthURL: URL?

            if (300..<400).contains(http.statusCode),
               let location = http.value(forHTTPHeaderField: "Location"),
               let url = URL(string: location) {
                googleAuthURL = url
            } else if (200..<300).contains(http.statusCode),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let urlString = json["url"] as? String,
                      let url = URL(string: urlString) {
                googleAuthURL = url
            }

            guard let oauthURL = googleAuthURL else {
                let bodyStr = String(data: data, encoding: .utf8) ?? "(empty)"
                authLog.error("Google sign-in: no redirect URL. status=\(http.statusCode), body=\(bodyStr)")
                lastErrorMessage = "Google Sign In failed (HTTP \(http.statusCode))."
                authState = .guest
                isLoading = false
                return
            }

            authLog.info("Opening Google OAuth URL: \(oauthURL.absoluteString.prefix(80))...")

            // Step 2: Open the Google OAuth URL in ASWebAuthenticationSession.
            // The browser handles the full OAuth flow: Google consent → backend callback →
            // /auth/mobile-token → JS redirect to todus://auth-callback?token=<jwt>
            let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                // CRASH FIX: Explicitly type the completion handler as @Sendable to prevent
                // Swift 6 from inheriting @MainActor isolation from the enclosing context.
                // Without this, ASWebAuthenticationSession calls the handler on a background
                // XPC queue (com.apple.SafariLaunchAgent), but Swift's runtime enforces
                // MainActor isolation → _swift_task_checkIsolatedSwift → EXC_BREAKPOINT.
                // By marking @Sendable, the closure becomes nonisolated and safe to call
                // from any queue. It only captures `continuation` which is Sendable.
                let completionHandler: @Sendable (URL?, (any Error)?) -> Void = { url, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: AuthError.cancelled)
                    }
                }

                let webSession = ASWebAuthenticationSession(
                    url: oauthURL,
                    callbackURLScheme: "todus",
                    completionHandler: completionHandler
                )
                // Share cookies with Safari so /auth/mobile-token can read the session cookie
                webSession.prefersEphemeralWebBrowserSession = false
                webSession.presentationContextProvider = self
                self.webAuthSession = webSession
                webSession.start()
            }

            debugAuthLog("Google OAuth callback received for scheme \(callbackURL.scheme ?? "unknown")")
            handleAuthCallback(url: callbackURL)

        } catch {
            let nsError = error as NSError
            if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
               nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                authLog.info("Google sign-in cancelled by user")
            } else {
                authLog.error("Google sign-in error: domain=\(nsError.domain) code=\(nsError.code) desc=\(error.localizedDescription)")
                lastErrorMessage = "Google Sign In failed: \(error.localizedDescription)"
            }
            if !isAuthenticated {
                authState = .guest
            }
        }

        webAuthSession = nil
        if !isCompletingAuthentication {
            isLoading = false
        }
    }

    // MARK: - Email OTP

    /// Sends a 6-digit OTP code to the given email via Better-Auth's emailOTP plugin.
    /// Backend: POST /api/auth/email-otp/send-verification-otp { email, type }
    public func sendEmailOTP(email: String) async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            lastErrorMessage = "Enter an email address."
            return
        }

        isLoading = true
        lastErrorMessage = nil

        let url = backendURL.appending(path: "api/auth/email-otp/send-verification-otp")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Origin must match a trustedOrigin with a valid hostname — the CORS middleware
        // parses the hostname and checks against allowed domains (todus.app, localhost).
        // Using the web app URL ensures it passes both CORS and Better-Auth CSRF checks.
        request.setValue("https://todus.app", forHTTPHeaderField: "Origin")

        let body: [String: String] = ["email": trimmed, "type": "sign-in"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                lastErrorMessage = "Failed to send code."
                isLoading = false
                return
            }

            let bodyStr = String(data: data, encoding: .utf8) ?? "(empty)"
            authLog.info("Email OTP send response: status=\(http.statusCode), body=\(bodyStr)")

            if (200..<300).contains(http.statusCode) {
                authState = .otpPending(email: trimmed)
            } else {
                let errorMsg = parseErrorMessage(from: data)
                switch http.statusCode {
                case 429:
                    lastErrorMessage = "Too many attempts. Try again later."
                default:
                    lastErrorMessage = errorMsg ?? "Failed to send code (HTTP \(http.statusCode))."
                }
                authLog.error("Email OTP send failed: status=\(http.statusCode), error=\(errorMsg ?? "unknown"), body=\(bodyStr)")
            }
        } catch {
            authLog.error("Email OTP send error: \(error.localizedDescription)")
            lastErrorMessage = "Network error. Check your connection."
        }

        isLoading = false
    }

    /// Verifies the 6-digit OTP code and signs in.
    /// Better-Auth's sign-in/email-otp endpoint verifies the code AND creates a session in one call.
    public func verifyEmailOTP(code: String) async {
        guard case .otpPending(let email) = authState else { return }
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCode.count >= 6 else {
            lastErrorMessage = "Enter the 6-digit code."
            return
        }

        isLoading = true
        lastErrorMessage = nil

        // Use /sign-in/email-otp which verifies OTP + creates session in one step
        let url = backendURL.appending(path: "api/auth/sign-in/email-otp")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Origin must match a trustedOrigin with a valid hostname — CORS middleware
        // parses hostname and checks against allowed domains (todus.app, localhost).
        request.setValue("https://todus.app", forHTTPHeaderField: "Origin")

        let body: [String: String] = ["email": email, "otp": trimmedCode]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                lastErrorMessage = "Verification failed."
                isLoading = false
                return
            }

            authLog.info("Email OTP verify response: status=\(http.statusCode)")

            if (200..<300).contains(http.statusCode) {
                if extractToken(from: data, response: http, email: email) {
                    authLog.info("Email OTP: authenticated successfully")
                } else {
                    // Token not in response — try fetching session
                    lastErrorMessage = "Verification succeeded but session failed. Try signing in again."
                    authState = .guest
                }
            } else {
                let errorMsg = parseErrorMessage(from: data)
                switch http.statusCode {
                case 400, 401:
                    lastErrorMessage = "Invalid or expired code. Request a new one."
                default:
                    lastErrorMessage = errorMsg ?? "Verification failed. Try again."
                }
            }
        } catch {
            authLog.error("Email OTP verify error: \(error.localizedDescription)")
            lastErrorMessage = "Network error. Check your connection."
        }

        isLoading = false
    }

    /// Returns to the email input stage from OTP verification
    public func returnToLogin() {
        authState = .guest
        lastErrorMessage = nil
    }

    /// Parse error message from Better-Auth JSON error response
    private func parseErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let message = json["message"] as? String { return message }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String { return message }
        return nil
    }

    // MARK: - Deep Link Handling

    /// Handle the todus://auth-callback?token=... deep link from OAuth flows.
    public func handleAuthCallback(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

        if let token = components.queryItems?.first(where: { $0.name == "token" })?.value {
            if shouldIgnoreCallbackToken(token) {
                debugAuthLog("Auth callback: ignoring duplicate token \(tokenPreview(token))")
                return
            }
            let email = components.queryItems?.first(where: { $0.name == "email" })?.value
            let sessionId = components.queryItems?.first(where: { $0.name == "sessionId" })?.value
            authLog.info("Auth callback: token received \(self.tokenPreview(token))")
            completeAuthentication(token: token, email: email, sessionId: sessionId)
        } else {
            authLog.error("Auth callback: no token in URL — \(url.absoluteString)")
            lastErrorMessage = "Sign in failed. No token received."
            authState = .guest
        }
    }

    // MARK: - Session Management

    public enum SessionRestoreResult: Sendable {
        case restored
        case invalid
        case deferred
        case missingToken
    }

    @discardableResult
    public func restorePersistedSession() async -> SessionRestoreResult {
        guard let token = bearerToken else {
            return .missingToken
        }

        switch await validateUserProfile(
            token: token,
            fallbackEmail: userEmail,
            attempts: Self.refreshValidationAttempts
        ) {
        case .verified(let profile):
            applyVerifiedProfile(profile, fallbackEmail: userEmail)
            hasSeenOnboarding = true
            authState = .authenticated
            isSessionExpired = false
            return .restored
        case .invalidSession:
            authLog.warning("restorePersistedSession: token no longer valid")
            signOut()
            isSessionExpired = true
            lastErrorMessage = "Your saved session expired. Please sign in again."
            return .invalid
        case .transientFailure(let reason):
            debugAuthLog("restorePersistedSession: deferred due to \(reason)")
            authState = .authenticated
            return .deferred
        }
    }

    /// Attempt a silent session refresh by calling /auth/me with the current token.
    /// Returns true if the session is still valid, false if it's expired.
    /// Uses /auth/me instead of /auth/get-session because the latter doesn't resolve
    /// bearer tokens — it only works with cookie-based sessions.
    public func attemptSilentRefresh() async -> Bool {
        guard let token = bearerToken else { return false }
        let url = backendURL.appendingPathComponent("api/auth/me")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Origin required by Better Auth CSRF middleware on all requests
        request.setValue("https://todus.app", forHTTPHeaderField: "Origin")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                // Capture rotated token if the server issued a new one
                captureRotatedToken(from: http)
                isSessionExpired = false
                return true
            }
        } catch {
            // Network error — don't mark as expired, might just be offline
        }
        return false
    }

    /// Check an HTTP response for a rotated Bearer token from Better Auth's bearer plugin.
    /// When updateAge triggers a session extension, the server returns a fresh token in the
    /// `set-auth-token` header. Without capturing this, the app keeps using the old token
    /// which eventually expires, causing "Session expired" errors despite the user appearing
    /// logged in. Call this on any authenticated API response.
    public func captureRotatedToken(from response: HTTPURLResponse) {
        if let newToken = response.value(forHTTPHeaderField: "set-auth-token"),
           !newToken.isEmpty,
           newToken != bearerToken {
            debugAuthLog("Captured rotated token \(tokenPreview(newToken)) from set-auth-token header")
            bearerToken = newToken
        }
    }

    public func signOut() {
        clearPersistedAuthState()
        authState = .guest
        lastErrorMessage = nil
        // Clear session-expired flag so the banner doesn't persist after sign-out
        isSessionExpired = false
    }

    private func clearPersistedAuthState() {
        bearerToken = nil
        currentSessionId = nil
        // Clear stored properties — didSet handles Keychain deletion
        userEmail = nil
        userName = nil
        userImage = nil
        hasSeenOnboarding = false
    }

    /// Fetches the current user's profile from the /auth/me endpoint.
    /// Uses /auth/me instead of Better Auth's /auth/get-session because the latter
    /// doesn't resolve bearer tokens — it returns `null` for bearer-authenticated
    /// requests. The /auth/me endpoint uses the Hono middleware's auth context which
    /// properly handles bearer tokens via auth.api.getSession() + JWT fallback.
    /// Stores name and image URL in Keychain so they persist across app launches.
    /// Safe to call multiple times — silently no-ops if not authenticated.
    public func fetchUserProfile() async {
        guard let token = bearerToken else {
            debugAuthLog("fetchUserProfile: no bearer token, skipping")
            return
        }
        switch await validateUserProfile(
            token: token,
            fallbackEmail: userEmail,
            attempts: Self.refreshValidationAttempts
        ) {
        case .verified(let profile):
            applyVerifiedProfile(profile, fallbackEmail: userEmail) // Changed fallbackEmail to userEmail here
            authState = .authenticated
            isSessionExpired = false
        case .invalidSession:
            authLog.warning("fetchUserProfile: token rejected, signing out")
            signOut()
            isSessionExpired = true
            lastErrorMessage = "Your sign-in session could not be verified. Please sign in again."
        case .transientFailure(let reason):
            authLog.warning("fetchUserProfile deferred: \(reason)")
        }
    }

    public func continueAsGuest() {
        hasSeenOnboarding = true  // triggers @Observable observation → root view re-renders
    }

    // MARK: - Private Helpers

    private func completeAuthentication(token: String, email: String?, sessionId: String? = nil) {
        bearerToken = token
        currentSessionId = sessionId?.isEmpty == false ? sessionId : nil
        if let email {
            self.userEmail = email
        }
        isCompletingAuthentication = true
        isLoading = true

        Task { @MainActor in
            defer {
                self.isCompletingAuthentication = false
                self.isLoading = false
            }

            switch await validateUserProfile(
                token: token,
                fallbackEmail: email,
                attempts: Self.freshLoginValidationAttempts
            ) {
            case .verified(let profile):
                self.applyVerifiedProfile(profile, fallbackEmail: email)
                self.hasSeenOnboarding = true
                self.authState = .authenticated
                self.isSessionExpired = false
                self.lastErrorMessage = nil
            case .invalidSession:
                authLog.error("completeAuthentication: token rejected after callback")
                self.signOut()
                self.lastErrorMessage = "Sign in completed, but Todus could not verify your session. Please try again."
            case .transientFailure(let reason):
                authLog.error("completeAuthentication: verification failed due to \(reason)")
                self.signOut()
                self.lastErrorMessage = "Sign in completed, but Todus could not reach the server to verify your session."
            }
        }
    }

    private func persistStringToKeychain(key: String, value: String?) {
        Task(priority: .utility) {
            await Self.keychainPersistence.persist(key: key, value: value)
        }
    }

    private func restoreCachedProfileMetadata() async {
        let snapshot = await Task.detached(priority: .utility) {
            (
                KeychainHelper.read(key: Keys.userEmail),
                KeychainHelper.read(key: Keys.userName),
                KeychainHelper.read(key: Keys.userImage)
            )
        }.value

        if userEmail == nil {
            userEmail = snapshot.0
        }
        if userName == nil {
            userName = snapshot.1
        }
        if userImage == nil {
            userImage = snapshot.2
        }
    }

    private enum ProfileValidationResult {
        case verified(VerifiedProfile)
        case invalidSession
        case transientFailure(String)
    }

    private struct VerifiedProfile {
        let email: String?
        let name: String?
        let image: String?
    }

    private func validateUserProfile(
        token: String,
        fallbackEmail: String?,
        attempts: Int
    ) async -> ProfileValidationResult {
        let maxAttempts = max(1, attempts)

        for attempt in 1...maxAttempts {
            let result = await requestUserProfile(token: token)
            switch result {
            case .verified(let profile):
                return .verified(profile)
            case .invalidSession:
                if attempt == maxAttempts {
                    return .invalidSession
                }
            case .transientFailure(let reason):
                if attempt == maxAttempts {
                    return .transientFailure(reason)
                }
            }

            let delay = UInt64(250_000_000 * attempt)
            try? await Task.sleep(nanoseconds: delay)
        }

        return .invalidSession
    }

    private func requestUserProfile(token: String) async -> ProfileValidationResult {
        let url = backendURL.appendingPathComponent("api/auth/me")
        debugAuthLog("fetchUserProfile: GET \(url.absoluteString) with \(tokenPreview(token))")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("https://todus.app", forHTTPHeaderField: "Origin")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .transientFailure("invalid_response")
            }

            captureRotatedToken(from: http)

            if http.statusCode == 401 {
                let body = String(data: data, encoding: .utf8) ?? "(empty)"
                authLog.warning("fetchUserProfile: HTTP 401, body=\(body)")
                return .invalidSession
            }

            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "(empty)"
                authLog.warning("fetchUserProfile: HTTP \(http.statusCode), body=\(body)")
                return .transientFailure("http_\(http.statusCode)")
            }

            let bodyStr = String(data: data, encoding: .utf8) ?? "(empty)"
            debugAuthLog("fetchUserProfile: 200 OK, body=\(String(bodyStr.prefix(500)))")

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let user = json["user"] as? [String: Any] else {
                debugAuthLog("fetchUserProfile: JSON parse failed or no 'user' key")
                return .transientFailure("invalid_json")
            }

            return .verified(
                VerifiedProfile(
                    email: (user["email"] as? String) ?? self.userEmail,
                    name: user["name"] as? String,
                    image: user["image"] as? String
                )
            )
        } catch {
            authLog.warning("fetchUserProfile failed: \(error.localizedDescription)")
            return .transientFailure("network_\(error.localizedDescription)")
        }
    }

    private func applyVerifiedProfile(_ profile: VerifiedProfile, fallbackEmail: String?) {
        if let email = profile.email ?? fallbackEmail, !email.isEmpty {
            userEmail = email
            debugAuthLog("fetchUserProfile: set userEmail=\(email)")
        }
        if let name = profile.name, !name.isEmpty {
            userName = name
            debugAuthLog("fetchUserProfile: set userName=\(name)")
        }
        if let image = profile.image, !image.isEmpty {
            userImage = image
            debugAuthLog("fetchUserProfile: set userImage=\(image.prefix(60))...")
        }
    }

    private func shouldIgnoreCallbackToken(_ token: String) -> Bool {
        let now = Date()
        defer {
            lastHandledCallbackToken = token
            lastHandledCallbackAt = now
        }

        guard lastHandledCallbackToken == token,
              let lastHandledCallbackAt,
              now.timeIntervalSince(lastHandledCallbackAt) < Self.callbackDeduplicationWindow else {
            return false
        }

        return true
    }

    private func tokenPreview(_ token: String) -> String {
        let prefix = token.prefix(6)
        let suffix = token.suffix(4)
        return "\(prefix)...\(suffix) (len=\(token.count))"
    }

    /// Attempts to extract a Bearer token from the backend response.
    /// Better-Auth can return tokens in multiple formats depending on the plugin configuration.
    /// Returns true if a token was found and stored.
    @discardableResult
    private func extractToken(from data: Data, response: HTTPURLResponse, email: String?) -> Bool {
        // 1. Check for set-auth-token header (Better-Auth bearer plugin)
        if let headerToken = response.value(forHTTPHeaderField: "set-auth-token"), !headerToken.isEmpty {
            authLog.info("extractToken: found set-auth-token header")
            completeAuthentication(token: headerToken, email: email)
            return true
        }

        // 2. Check Set-Cookie for better-auth session token (fallback when bearer plugin
        //    doesn't return the header — e.g. when the response is a redirect with cookies)
        if let cookies = response.allHeaderFields["Set-Cookie"] as? String {
            // Better-Auth cookie name: better-auth.session_token or better-auth-dev.session_token
            let patterns = ["better-auth.session_token=", "better-auth-dev.session_token="]
            for pattern in patterns {
                if let range = cookies.range(of: pattern) {
                    let afterPrefix = cookies[range.upperBound...]
                    let tokenEnd = afterPrefix.firstIndex(of: ";") ?? afterPrefix.endIndex
                    let token = String(afterPrefix[..<tokenEnd])
                    if !token.isEmpty && token != "deleted" {
                        authLog.info("extractToken: found session token in Set-Cookie")
                        completeAuthentication(token: token, email: email)
                        return true
                    }
                }
            }
        }

        // 3. Check for token in JSON response body
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }

        // Direct token field
        if let token = json["token"] as? String, !token.isEmpty {
            let responseEmail = json["email"] as? String ?? email
            completeAuthentication(token: token, email: responseEmail)
            return true
        }

        // Nested session.token (some Better-Auth responses)
        if let session = json["session"] as? [String: Any],
           let token = session["token"] as? String, !token.isEmpty {
            let user = json["user"] as? [String: Any]
            let responseEmail = user?["email"] as? String ?? email
            completeAuthentication(token: token, email: responseEmail)
            return true
        }

        // Redirect URL with token (Better-Auth may return { url: "todus://auth-callback?token=..." })
        if let urlString = json["url"] as? String, let url = URL(string: urlString),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let token = components.queryItems?.first(where: { $0.name == "token" })?.value {
            completeAuthentication(token: token, email: email)
            return true
        }

        return false
    }

    // MARK: - Error Type

    public enum AuthError: Error {
        case cancelled
        case invalidResponse
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

/// Platform-specific presentation anchor for ASWebAuthenticationSession.
/// iOS: returns the key UIWindow from the foreground scene.
/// macOS: returns the key NSWindow from the application.
#if canImport(UIKit)
extension AuthService: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first ?? ASPresentationAnchor()
        }
        return window
    }
}
#elseif canImport(AppKit)
extension AuthService: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSWindow()
    }
}
#endif
