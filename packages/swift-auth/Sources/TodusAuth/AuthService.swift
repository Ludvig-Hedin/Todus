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
        static let refreshToken = "com.todus.auth.refreshToken"
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

    /// Short-lived JWT (15min) used as "access token" for all API calls.
    /// Verified stateless via JWKS — no DB lookup needed.
    public private(set) var bearerToken: String? {
        didSet { persistStringToKeychain(key: Keys.bearerToken, value: bearerToken) }
    }

    /// Long-lived raw session token (90-day sliding window) used as "refresh token".
    /// Stored in Keychain, used only to obtain fresh JWTs via /auth/refresh-native-token.
    /// The 90-day window extends daily on use via Better Auth's updateAge mechanism.
    public private(set) var refreshToken: String? {
        didSet { persistStringToKeychain(key: Keys.refreshToken, value: refreshToken) }
    }

    public private(set) var currentSessionId: String? {
        didSet { persistStringToKeychain(key: Keys.currentSessionId, value: currentSessionId) }
    }

    public var hasPersistedBearerToken: Bool {
        bearerToken != nil
    }

    /// Coalescing gate for concurrent token refreshes. When multiple API calls receive 401
    /// simultaneously, they all call refreshAccessToken(). This ensures only one network
    /// request fires; subsequent callers await the in-flight result.
    private var activeRefreshTask: Task<RefreshResult, Never>?

    public var bearerTokenPreview: String {
        guard let token = bearerToken, !token.isEmpty else { return "None" }
        return "(len=\(token.count))"
    }

    private func applyNativeClientHeaders(to request: inout URLRequest) {
        TodusHTTPClient.applyDefaultHeaders(to: &request)
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
        self.refreshToken = KeychainHelper.read(key: Keys.refreshToken)
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

        // Guarantee isLoading is cleared on every exit path so the UI never gets stuck on
        // a spinner when the OAuth flow errors mid-way. completeAuthentication() owns the
        // loading state once it's running (sets isCompletingAuthentication = true before
        // returning), so we only clear here when no completion task is in flight.
        defer {
            if !isCompletingAuthentication {
                isLoading = false
            }
        }

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
                authState = .guest
                lastErrorMessage = "Failed to get Apple ID token."
                return
            }

            authLog.info("Apple ID token obtained, sending to backend...")

            // Send ID token to backend — Better-Auth validates via Apple provider config.
            // Format matches what the RN app sends: { idToken: { token: "..." } }
            let url = backendURL.appending(path: "api/auth/sign-in/social")
            var request = URLRequest(url: url)
            applyNativeClientHeaders(to: &request)
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
            // URLSessions created with a delegate retain that delegate until invalidated,
            // so leaking the session leaks the delegate (and the underlying connections).
            defer { session.finishTasksAndInvalidate() }
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                authState = .guest
                lastErrorMessage = "Apple Sign In failed. Invalid response."
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
                // Surface the response body so the next failure is diagnosable from
                // the device log alone — without this, every backend rejection looks
                // identical and forces a full server-side debug session.
                let bodyPreview = String(data: data, encoding: .utf8)?.prefix(500) ?? ""
                let requestId = http.value(forHTTPHeaderField: "x-request-id") ?? "(none)"
                authLog.error(
                    "Apple sign-in: failed. status=\(http.statusCode) requestId=\(requestId) body=\(bodyPreview)"
                )
                // Set authState first, then the error message — any view-driven state mutation
                // observing the .guest transition won't clobber the message this way.
                authState = .guest
                lastErrorMessage = "Apple Sign In failed. Please try again."
            }

        } catch {
            authLog.error("Apple sign-in error: \(error.localizedDescription)")
            authState = .guest
            if (error as NSError).domain == ASAuthorizationError.errorDomain,
               (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                // User cancelled — no error message needed
            } else {
                // Set lastErrorMessage AFTER authState so it survives any state-driven reset
                lastErrorMessage = "Something went wrong during sign in. Please try again."
            }
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

        // Guarantee isLoading and webAuthSession are cleared on every exit path. Before
        // this defer, errors during the OAuth flow could leave isLoading=true forever
        // when handleAuthCallback raced with the function's normal exit.
        defer {
            webAuthSession = nil
            if !isCompletingAuthentication {
                isLoading = false
            }
        }

        do {
            // Step 1: POST to get the Google OAuth redirect URL from Better-Auth.
            // Better-Auth's social sign-in is POST-only — returns { url: "https://accounts.google.com/..." }
            let signInURL = backendURL.appending(path: "api/auth/sign-in/social")
            var request = URLRequest(url: signInURL)
            applyNativeClientHeaders(to: &request)
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
            defer { session.finishTasksAndInvalidate() }
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
                // authState first, then error — see signInWithApple for rationale
                authState = .guest
                lastErrorMessage = "Google Sign In failed. Please try again."
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
                if !webSession.start() {
                    continuation.resume(throwing: AuthError.failedToStartWebAuthentication)
                }
            }

            debugAuthLog("Google OAuth callback received for scheme \(callbackURL.scheme ?? "unknown")")
            handleAuthCallback(url: callbackURL)

        } catch {
            let nsError = error as NSError
            if !isAuthenticated {
                authState = .guest
            }
            if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
               nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                authLog.info("Google sign-in cancelled by user")
            } else {
                authLog.error("Google sign-in error: domain=\(nsError.domain) code=\(nsError.code) desc=\(error.localizedDescription)")
                // Set lastErrorMessage AFTER authState so it survives any state-driven reset
                lastErrorMessage = "Google Sign In failed. Please try again."
            }
        }
        // webAuthSession + isLoading reset handled in defer at top of function
    }

    // MARK: - Link Additional Account (Multi-Account)

    /// Links a new social account (Google) to the current authenticated user.
    /// Uses the same ASWebAuthenticationSession flow as sign-in but hits the
    /// Better-Auth link-social endpoint, which creates a new connection without
    /// creating a new user session.
    ///
    /// Flow:
    /// 1. POST /auth/native-link-social with current Bearer token (the backend
    ///    bridges the existing session and links instead of creating a new user)
    /// 2. Open the returned Google OAuth URL in ASWebAuthenticationSession
    /// 3. After consent, backend creates a new connection record and redirects
    ///    back to todus://link-callback
    public func linkSocialAccount(provider: String = "google") async throws {
        guard isAuthenticated else {
            throw AuthError.notAuthenticated
        }

        isLoading = true
        defer { isLoading = false }
        // Always release the ASWebAuthenticationSession reference, even if the await
        // below throws (cancellation, network error, etc). Without this, the session
        // ref leaks until the next link/sign-in attempt overwrites it.
        defer { webAuthSession = nil }

        // Step 1: Get the OAuth URL from the native link bridge, passing our
        // Bearer token so the backend knows which user to link the new account to.
        let linkURL = backendURL.appending(path: "api/auth/native-link-social")
        var request = URLRequest(url: linkURL)
        applyNativeClientHeaders(to: &request)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://todus.app", forHTTPHeaderField: "Origin")

        // Include Bearer token so backend links to existing user
        if let token = bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var payload: [String: Any] = [
            "provider": provider,
            // Better Auth's link-social endpoint expects the *final* post-link redirect,
            // not the provider callback route. The web client hands it an app URL directly;
            // native needs the custom scheme so ASWebAuthenticationSession can intercept it.
            "callbackURL": "todus://link-callback",
            // Native must receive the Google OAuth URL and open it itself. If Better Auth is
            // allowed to redirect immediately, URLSession follows the 302 and we end up trying
            // to decode Google's HTML login page instead of a JSON payload.
            "disableRedirect": true,
        ]
        if let refreshToken, !refreshToken.isEmpty {
            payload["refreshToken"] = refreshToken
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: NoRedirectDelegate.shared, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        var oauthURL: URL?
        if (300..<400).contains(http.statusCode),
           let location = http.value(forHTTPHeaderField: "Location"),
           let locationURL = URL(string: location) {
            oauthURL = locationURL
        } else if (200..<300).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let urlString = json["url"] as? String,
                  let decodedURL = URL(string: urlString) {
            oauthURL = decodedURL
        }

        guard let oauthURL else {
            let bodyStr = String(data: data, encoding: .utf8) ?? "(empty)"
            authLog.error("Link social: no redirect URL. status=\(http.statusCode), body=\(bodyStr)")
            throw AuthError.networkError
        }

        // Step 2: Open the OAuth URL in ASWebAuthenticationSession
        let _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
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
            webSession.prefersEphemeralWebBrowserSession = false
            webSession.presentationContextProvider = self
            self.webAuthSession = webSession
            if !webSession.start() {
                continuation.resume(throwing: AuthError.failedToStartWebAuthentication)
            }
        }

        debugAuthLog("Link account callback received — new connection should be available")
        // The caller should refresh the connections list after this completes
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
        applyNativeClientHeaders(to: &request)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Origin must match a trustedOrigin with a valid hostname — the CORS middleware
        // parses the hostname and checks against allowed domains (todus.app, localhost).
        // Using the web app URL ensures it passes both CORS and Better-Auth CSRF checks.
        request.setValue("https://todus.app", forHTTPHeaderField: "Origin")

        let body: [String: String] = ["email": trimmed, "type": "sign-in"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        // === DIAGNOSTIC: log everything we're about to send ===
        // type=sign-in stores the OTP under `sign-in-otp-${email}` in Better Auth's verification
        // table, which is the same key /sign-in/email-otp reads from on verify.
        authLog.info("[OTP_SEND] → POST \(url.absoluteString, privacy: .public)")
        authLog.info("[OTP_SEND] → body email=\(trimmed, privacy: .private) type=sign-in")
        let reqHeaders = (request.allHTTPHeaderFields ?? [:])
            .map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
        authLog.debug("[OTP_SEND] → headers \(reqHeaders, privacy: .private)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                authLog.error(
                    "[OTP_SEND] ← non-HTTP response: \(String(describing: response), privacy: .public)"
                )
                lastErrorMessage = "Failed to send code."
                isLoading = false
                return
            }

            let respHeaders = http.allHeaderFields
                .map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
            let bodyStr = String(data: data, encoding: .utf8) ?? "(non-utf8, \(data.count) bytes)"
            authLog.info(
                "[OTP_SEND] ← status=\(http.statusCode, privacy: .public) bodyBytes=\(data.count, privacy: .public)"
            )
            // Headers may contain Set-Cookie (session token); body may contain account state.
            // Keep redacted by default; OS log shows these only when stream is unsealed for the dev.
            authLog.debug("[OTP_SEND] ← headers \(respHeaders, privacy: .private)")
            authLog.debug("[OTP_SEND] ← body \(bodyStr, privacy: .private)")

            if (200..<300).contains(http.statusCode) {
                authState = .otpPending(email: trimmed)
            } else {
                let errorMsg = parseErrorMessage(from: data)
                switch http.statusCode {
                case 429:
                    lastErrorMessage = "Too many attempts. Try again later."
                default:
                    lastErrorMessage = errorMsg ?? "Failed to send code. Please try again."
                }
                authLog.error(
                    "[OTP_SEND] failure status=\(http.statusCode, privacy: .public) parsedMessage=\(errorMsg ?? "(none)", privacy: .public)"
                )
            }
        } catch {
            authLog.error(
                "[OTP_SEND] transport error: \(error.localizedDescription, privacy: .public)"
            )
            lastErrorMessage = "Network error. Check your connection."
        }

        isLoading = false
    }

    /// Verifies the 6-digit OTP code and signs in.
    /// Better-Auth's /sign-in/email-otp endpoint verifies the code AND creates a session in one
    /// call, returning a 200 JSON `{ token, user, ... }` body — there is no redirect to disable.
    public func verifyEmailOTP(code: String) async {
        guard case .otpPending(let email) = authState else { return }
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCode.count >= 6 else {
            lastErrorMessage = "Enter the 6-digit code."
            return
        }

        isLoading = true
        lastErrorMessage = nil

        // Use the native bridge instead of Better Auth's generic HTTP handler so iOS/macOS
        // receive a raw session token in a stable JSON response.
        let url = backendURL.appending(path: "api/auth/native-email-otp/verify")
        var request = URLRequest(url: url)
        applyNativeClientHeaders(to: &request)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Origin must match a trustedOrigin with a valid hostname — CORS middleware
        // parses hostname and checks against allowed domains (todus.app, localhost).
        request.setValue("https://todus.app", forHTTPHeaderField: "Origin")

        let body: [String: Any] = ["email": email, "otp": trimmedCode]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        // === DIAGNOSTIC: log everything we're about to send ===
        let codeMask: String = {
            guard !trimmedCode.isEmpty else { return "(empty)" }
            return "len=\(trimmedCode.count) leading=\(trimmedCode.prefix(1))"
        }()
        authLog.info("[OTP_VERIFY] → POST \(url.absoluteString, privacy: .public)")
        authLog.info(
            "[OTP_VERIFY] → body email=\(email, privacy: .private) otp=\(codeMask, privacy: .private)"
        )
        let reqHeaders = (request.allHTTPHeaderFields ?? [:])
            .map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
        authLog.debug("[OTP_VERIFY] → headers \(reqHeaders, privacy: .private)")
        authLog.info(
            "[OTP_VERIFY] → bodyBytes=\(request.httpBody?.count ?? 0, privacy: .public)"
        )

        do {
            // Don't follow redirects — we need the headers on the initial response.
            // If Better Auth still redirects (e.g. older server version), we handle the
            // Location header below rather than letting URLSession silently swallow it.
            let config = URLSessionConfiguration.default
            let noRedirectSession = URLSession(
                configuration: config, delegate: NoRedirectDelegate.shared, delegateQueue: nil)
            // URLSessions created with a delegate retain that delegate until invalidated;
            // mirror the pattern used in signInWithApple/signInWithGoogle (commit 945e1431).
            defer { noRedirectSession.finishTasksAndInvalidate() }
            let (data, response) = try await noRedirectSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                authLog.error(
                    "[OTP_VERIFY] ← non-HTTP response: \(String(describing: response), privacy: .public)"
                )
                lastErrorMessage = "Verification failed."
                isLoading = false
                return
            }

            // === DIAGNOSTIC: log the full server response ===
            let respHeaders = http.allHeaderFields
                .map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
            let bodyStr = String(data: data, encoding: .utf8) ?? "(non-utf8, \(data.count) bytes)"
            authLog.info(
                "[OTP_VERIFY] ← status=\(http.statusCode, privacy: .public) bodyBytes=\(data.count, privacy: .public)"
            )
            // Headers and body can carry the freshly-issued bearer/session token (set-auth-token,
            // Set-Cookie, JSON body). Never log them as `.public`.
            authLog.debug("[OTP_VERIFY] ← headers \(respHeaders, privacy: .private)")
            authLog.debug("[OTP_VERIFY] ← body \(bodyStr, privacy: .private)")

            // Check redirect Location for a token (defensive — Better Auth's /sign-in/email-otp
            // returns 200 JSON, not a redirect, but we keep this for older server versions).
            if (300..<400).contains(http.statusCode),
               let location = http.value(forHTTPHeaderField: "Location"),
               let locationURL = URL(string: location),
               let comps = URLComponents(url: locationURL, resolvingAgainstBaseURL: false),
               let token = comps.queryItems?.first(where: { $0.name == "token" })?.value {
                authLog.info("[OTP_VERIFY] token found in redirect Location header")
                completeAuthentication(token: token, email: email)
            } else if (200..<300).contains(http.statusCode) || (300..<400).contains(http.statusCode) {
                if extractToken(from: data, response: http, email: email) {
                    authLog.info("[OTP_VERIFY] authenticated successfully")
                } else {
                    authLog.error("[OTP_VERIFY] success status but no token extractable from response")
                    lastErrorMessage = "Verification succeeded but something went wrong. Please try again."
                    authState = .guest
                }
            } else {
                let errorMsg = parseErrorMessage(from: data)
                authLog.error(
                    "[OTP_VERIFY] failure status=\(http.statusCode, privacy: .public) parsedMessage=\(errorMsg ?? "(none)", privacy: .public)"
                )
                switch http.statusCode {
                case 400, 401:
                    lastErrorMessage = "Invalid or expired code. Request a new one."
                default:
                    lastErrorMessage = errorMsg ?? "Verification failed. Please try again."
                }
            }
        } catch {
            authLog.error(
                "[OTP_VERIFY] transport error: \(error.localizedDescription, privacy: .public)"
            )
            lastErrorMessage = "Network error. Check your connection."
        }

        if !isCompletingAuthentication {
            isLoading = false
        }
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
        // Validate scheme/host before parsing query items. A malformed URL (wrong
        // scheme, wrong host, missing components) used to silently return, which
        // left authState stuck at .authenticating and the UI on the spinner forever.
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            authLog.error("Auth callback: invalid URL components — \(url.absoluteString)")
            isCompletingAuthentication = false
            isLoading = false
            authState = .guest
            lastErrorMessage = "Sign-in failed. Please try again."
            return
        }

        if components.scheme == "todus", components.host == "link-callback" {
            debugAuthLog("Auth callback: received link-social callback")
            return
        }

        if let token = components.queryItems?.first(where: { $0.name == "token" })?.value, !token.isEmpty {
            if shouldIgnoreCallbackToken(token) {
                debugAuthLog("Auth callback: ignoring duplicate token \(tokenPreview(token))")
                return
            }
            let email = components.queryItems?.first(where: { $0.name == "email" })?.value
            let sessionId = components.queryItems?.first(where: { $0.name == "sessionId" })?.value
            // Extract refresh token (raw session token) for the access+refresh pattern.
            // Older backend versions may not include this — handled gracefully in completeAuthentication.
            let callbackRefreshToken = components.queryItems?.first(where: { $0.name == "refreshToken" })?.value
            authLog.info("Auth callback: token received \(self.tokenPreview(token)), refreshToken=\(callbackRefreshToken != nil ? "present" : "absent")")
            completeAuthentication(token: token, email: email, sessionId: sessionId, refreshToken: callbackRefreshToken)
        } else {
            // No token query param — malformed callback. Reset all in-flight state so the
            // UI returns to the email input screen instead of being stranded on a spinner.
            authLog.error("Auth callback: no token in URL — \(url.absoluteString)")
            isCompletingAuthentication = false
            isLoading = false
            authState = .guest
            lastErrorMessage = "Sign-in failed. Please try again."
        }
    }

    // MARK: - Session Management

    public enum SessionRestoreResult: Sendable {
        case restored
        case invalid
        case deferred
        case missingToken
    }

    private enum RefreshResult: Sendable {
        case refreshed
        case invalidSession
        case transientFailure
        case missingRefreshToken

        var didRefresh: Bool {
            if case .refreshed = self { return true }
            return false
        }
    }

    @discardableResult
    public func restorePersistedSession() async -> SessionRestoreResult {
        guard bearerToken != nil else {
            return .missingToken
        }

        // Proactively refresh the JWT if it's expired or about to expire.
        // This avoids a wasted round-trip to /auth/me that would fail with 401.
        if isJWTExpiredOrExpiring(bearerToken) {
            switch await refreshAccessTokenResult() {
            case .refreshed:
                debugAuthLog("restorePersistedSession: JWT refreshed successfully")
            case .missingRefreshToken:
                // No refresh token (legacy install) — fall through to direct validation
                debugAuthLog("restorePersistedSession: no refresh token, trying direct validation")
            case .invalidSession:
                authLog.warning("restorePersistedSession: refresh token rejected, signing out")
                signOut()
                lastErrorMessage = "Your session has expired. Please sign in again."
                return .invalid
            case .transientFailure:
                // Refresh failed — could be a real 401 OR a network blip on launch
                // (refreshAccessTokenResult distinguishes them). Keep the persisted
                // session and retry on the next interactive request.
                authLog.warning("restorePersistedSession: refresh failed transiently, deferring")
                authState = .authenticated
                return .deferred
            }
        }

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
            // JWT valid but rejected — try refreshing once more before giving up
            switch await refreshAccessTokenResult() {
            case .refreshed:
                debugAuthLog("restorePersistedSession: retrying after refresh")
                if let freshToken = bearerToken {
                    switch await validateUserProfile(
                        token: freshToken,
                        fallbackEmail: userEmail,
                        attempts: 1
                    ) {
                    case .verified(let profile):
                        applyVerifiedProfile(profile, fallbackEmail: userEmail)
                        hasSeenOnboarding = true
                        authState = .authenticated
                        isSessionExpired = false
                        return .restored
                    default:
                        break
                    }
                }
                authLog.warning("restorePersistedSession: refreshed token still failed validation, signing out")
                signOut()
                lastErrorMessage = "Your session has expired. Please sign in again."
                return .invalid
            case .invalidSession, .missingRefreshToken:
                authLog.warning("restorePersistedSession: token rejected after refresh, signing out")
                signOut()
                lastErrorMessage = "Your session has expired. Please sign in again."
                return .invalid
            case .transientFailure:
                authLog.warning("restorePersistedSession: retry refresh failed transiently, deferring")
                authState = .authenticated
                return .deferred
            }
        case .transientFailure(let reason):
            debugAuthLog("restorePersistedSession: deferred due to \(reason)")
            authState = .authenticated
            return .deferred
        }
    }

    /// Attempt a silent session refresh. First tries the access+refresh pattern
    /// (exchange refresh token for a new JWT). Falls back to direct /auth/me validation
    /// for legacy installs that don't have a refresh token.
    public func attemptSilentRefresh() async -> Bool {
        // Try the access+refresh pattern first
        switch await refreshAccessTokenResult() {
        case .refreshed:
            isSessionExpired = false
            return true
        case .invalidSession, .transientFailure, .missingRefreshToken:
            break
        }

        // Fallback for legacy installs: try /auth/me with the current token
        guard let token = bearerToken else { return false }
        let url = backendURL.appendingPathComponent("api/auth/me")
        var request = URLRequest(url: url)
        applyNativeClientHeaders(to: &request)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("https://todus.app", forHTTPHeaderField: "Origin")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                captureRotatedToken(from: http)
                isSessionExpired = false
                return true
            }
        } catch {
            // Network error — don't mark as expired, might just be offline
        }
        return false
    }

    /// Returns the best available bearer token for an authenticated request.
    /// If the stored JWT is expired or about to expire, refresh it first and
    /// fall back to the existing token if refresh is unavailable or fails.
    public func validBearerToken() async -> String? {
        guard let token = bearerToken, !token.isEmpty else {
            return nil
        }

        if !isJWTExpiredOrExpiring(token) {
            return token
        }

        switch await refreshAccessTokenResult() {
        case .refreshed:
            if let refreshed = bearerToken, !refreshed.isEmpty {
                return refreshed
            }
        case .transientFailure, .missingRefreshToken:
            break
        case .invalidSession:
            return nil
        }

        if let refreshed = bearerToken, !refreshed.isEmpty, !isJWTExpiredOrExpiring(refreshed) {
            return refreshed
        }

        return token
    }

    // MARK: - Access + Refresh Token Pattern

    /// Decode the JWT's `exp` claim to check if it's expired or about to expire.
    /// Does NOT verify the signature — that's the server's job. This is just a
    /// client-side optimization to avoid wasted 401 round-trips.
    private func isJWTExpiredOrExpiring(_ token: String?) -> Bool {
        guard let token, !token.isEmpty else { return true }
        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            // Not a JWT (might be a raw session token from legacy flow) — treat as expired
            // so the refresh mechanism kicks in
            return true
        }

        // Decode the base64url-encoded payload (middle segment)
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval else {
            return true
        }

        let expirationDate = Date(timeIntervalSince1970: exp)
        // Refresh if expiring within 2 minutes — gives buffer for network latency
        return expirationDate.timeIntervalSinceNow < 120
    }

    /// Exchange the refresh token (raw session token) for a fresh short-lived JWT.
    /// Calls /auth/refresh-native-token which validates the session and mints a new JWT.
    /// The session's 90-day sliding window is extended on each successful refresh.
    /// Returns true if a new JWT was obtained, false otherwise.
    @discardableResult
    public func refreshAccessToken() async -> Bool {
        await refreshAccessTokenResult().didRefresh
    }

    private func refreshAccessTokenResult() async -> RefreshResult {
        // Coalesce concurrent refresh attempts — only one network request fires at a time.
        // Subsequent callers await the in-flight result instead of firing duplicate requests.
        if let existing = activeRefreshTask {
            return await existing.value
        }

        let task = Task<RefreshResult, Never> { [weak self] in
            guard let self else { return .transientFailure }

            guard let rt = self.refreshToken, !rt.isEmpty else {
                debugAuthLog("refreshAccessToken: no refresh token available")
                return .missingRefreshToken
            }

            let url = self.backendURL.appendingPathComponent("api/auth/refresh-native-token")
            var request = URLRequest(url: url)
            self.applyNativeClientHeaders(to: &request)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("https://todus.app", forHTTPHeaderField: "Origin")

            let body: [String: String] = ["refreshToken": rt]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { return .transientFailure }

                if (200..<300).contains(http.statusCode),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let newToken = json["token"] as? String, !newToken.isEmpty {
                    debugAuthLog("refreshAccessToken: new JWT obtained")
                    self.bearerToken = newToken
                    // Capture session ID returned by the refresh endpoint so the
                    // X-Todus-Session-Id header is sent on subsequent API calls.
                    // This is the primary mechanism for Apple Sign-In / Email OTP
                    // users who don't go through the /auth/mobile-token deep-link flow.
                    if let sid = json["sessionId"] as? String, !sid.isEmpty {
                        self.currentSessionId = sid
                        debugAuthLog("refreshAccessToken: captured sessionId \(sid.prefix(8))…")
                    }
                    self.isSessionExpired = false
                    return .refreshed
                }

                if http.statusCode == 401 {
                    authLog.warning("refreshAccessToken: refresh token rejected (401)")
                    return .invalidSession
                }

                authLog.warning("refreshAccessToken: unexpected response \(http.statusCode)")
                return .transientFailure
            } catch {
                authLog.warning("refreshAccessToken: network error — \(error.localizedDescription)")
                return .transientFailure
            }
        }
        activeRefreshTask = task
        let result = await task.value
        activeRefreshTask = nil
        return result
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
        refreshToken = nil
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
    ///
    /// If the JWT is rejected, this attempts one silent refresh before deciding
    /// whether the session is truly gone. Confirmed-invalid sessions are cleared;
    /// transient refresh failures are left intact so the next request can retry.
    public func fetchUserProfile() async {
        // Proactively refresh the JWT if it's expiring. This avoids the common
        // post-idle race where the first /auth/me call ships an expired token,
        // gets 401, and tears down the session before the concurrent refresh path
        // can produce a fresh JWT.
        if isJWTExpiredOrExpiring(bearerToken), refreshToken != nil {
            switch await refreshAccessTokenResult() {
            case .refreshed, .transientFailure, .missingRefreshToken:
                break
            case .invalidSession:
                authLog.warning("fetchUserProfile: refresh token rejected before profile fetch, signing out")
                signOut()
                lastErrorMessage = "Your session has expired. Please sign in again."
                return
            }
        }

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
            applyVerifiedProfile(profile, fallbackEmail: userEmail)
            authState = .authenticated
            isSessionExpired = false
        case .invalidSession:
            // JWT was rejected — try refreshing once before giving up. The refresh
            // token has a 90-day sliding window, so a 401 here usually means the
            // short-lived JWT expired, not that the session is actually gone.
            switch await refreshAccessTokenResult() {
            case .refreshed:
                guard let freshToken = bearerToken else { return }
                switch await validateUserProfile(
                    token: freshToken,
                    fallbackEmail: userEmail,
                    attempts: 1
                ) {
                case .verified(let profile):
                    applyVerifiedProfile(profile, fallbackEmail: userEmail)
                    authState = .authenticated
                    isSessionExpired = false
                    return
                case .invalidSession:
                    authLog.warning("fetchUserProfile: rejected after refresh, signing out")
                    signOut()
                    lastErrorMessage = "Your session has expired. Please sign in again."
                    return
                case .transientFailure(let reason):
                    authLog.warning("fetchUserProfile deferred after refresh: \(reason)")
                    return
                }
            case .invalidSession, .missingRefreshToken:
                authLog.warning("fetchUserProfile: rejected and refresh unavailable, signing out")
                signOut()
                lastErrorMessage = "Your session has expired. Please sign in again."
            case .transientFailure:
                authLog.warning("fetchUserProfile: rejected but refresh failed transiently")
            }
        case .transientFailure(let reason):
            authLog.warning("fetchUserProfile deferred: \(reason)")
        }
    }

    public func continueAsGuest() {
        hasSeenOnboarding = true  // triggers @Observable observation → root view re-renders
    }

    // MARK: - Private Helpers

    private func completeAuthentication(token: String, email: String?, sessionId: String? = nil, refreshToken newRefreshToken: String? = nil) {
        // Determine if the token is a JWT (contains dots) or a raw session token.
        // Google Sign-In (via /auth/mobile-token): token=JWT, refreshToken=sessionToken
        // Apple Sign-In / Email OTP: token=sessionToken (from set-auth-token header or body)
        let tokenIsJWT = token.split(separator: ".").count == 3

        if let rt = newRefreshToken, !rt.isEmpty {
            // Google flow: explicit refresh token provided alongside the JWT
            bearerToken = token
            refreshToken = rt
        } else if !tokenIsJWT {
            // Apple/Email OTP flow: token is a raw session token — use it as refresh token.
            // A JWT will be obtained via refreshAccessToken() below.
            refreshToken = token
            bearerToken = token  // Temporary — will be replaced with JWT
        } else {
            // JWT without refresh token (legacy or unexpected) — store as-is
            bearerToken = token
        }

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

            // For Apple/Email OTP flows where we have a session token but no JWT,
            // exchange it for a proper JWT before validating the profile.
            if !tokenIsJWT, self.refreshToken != nil {
                if await self.refreshAccessToken() {
                    debugAuthLog("completeAuthentication: exchanged session token for JWT")
                } else {
                    debugAuthLog("completeAuthentication: JWT exchange failed, proceeding with session token")
                }
            }

            guard let currentToken = self.bearerToken else {
                self.signOut()
                self.lastErrorMessage = "Something went wrong during sign in. Please try again."
                return
            }

            switch await validateUserProfile(
                token: currentToken,
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
                self.lastErrorMessage = "Something went wrong during sign in. Please try again."
            case .transientFailure(let reason):
                authLog.error("completeAuthentication: verification failed due to \(reason)")
                self.signOut()
                self.lastErrorMessage = "Unable to connect to server. Check your internet and try again."
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
        applyNativeClientHeaders(to: &request)
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
        // Never log token bytes (even prefix/suffix) — JWT signatures are deterministic so
        // leaking even ~10 chars + length materially weakens the secret.
        return "(len=\(token.count))"
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
            let user = json["user"] as? [String: Any]
            let responseEmail = user?["email"] as? String ?? json["email"] as? String ?? email
            let responseSessionId = json["sessionId"] as? String
            completeAuthentication(token: token, email: responseEmail, sessionId: responseSessionId)
            return true
        }

        // Nested session.token (Better-Auth standard response for sign-in endpoints).
        // Also extract session.id so we can identify which session this device is running
        // in — used by the Active Sessions UI and the X-Todus-Session-Id request header.
        if let sessionObj = json["session"] as? [String: Any],
           let token = sessionObj["token"] as? String, !token.isEmpty {
            let user = json["user"] as? [String: Any]
            let responseEmail = user?["email"] as? String ?? email
            let responseSessionId = sessionObj["id"] as? String
            completeAuthentication(token: token, email: responseEmail, sessionId: responseSessionId)
            return true
        }

        // Redirect URL with token (Better-Auth may return { url: "todus://auth-callback?token=..." })
        if let urlString = json["url"] as? String, let url = URL(string: urlString),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let token = components.queryItems?.first(where: { $0.name == "token" })?.value {
            let sessionId = components.queryItems?.first(where: { $0.name == "sessionId" })?.value
            completeAuthentication(token: token, email: email, sessionId: sessionId)
            return true
        }

        return false
    }

    // MARK: - Error Type

    public enum AuthError: Error {
        case cancelled
        case invalidResponse
        case notAuthenticated
        case networkError
        case failedToStartWebAuthentication
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
