import AuthenticationServices
import Foundation
import Observation
import OSLog
import Security

private let authLog = Logger(subsystem: "com.todus.auth", category: "AuthService")

/// Unified auth service for the Todus app.
/// Talks to the Better-Auth backend (Cloudflare Workers) and supports:
/// - Apple Sign In (native ASAuthorizationAppleIDProvider → backend validates ID token)
/// - Google Sign In (ASWebAuthenticationSession → Google OAuth → /auth/mobile-token → deep link)
///
/// Replaces the old Supabase-based AuthSessionStore.
@MainActor
@Observable
final class AuthService: NSObject {

    // MARK: - State

    enum AuthState: Equatable {
        case guest
        case authenticating
        case otpPending(email: String)
        case authenticated
    }

    var authState: AuthState = .guest
    var lastErrorMessage: String?
    var isLoading = false

    /// Whether the onboarding screen should be shown
    var showsOnboarding: Bool {
        !hasSeenOnboarding && !isAuthenticated
    }

    var isAuthenticated: Bool {
        if case .authenticated = authState { return true }
        return false
    }

    var userEmail: String? {
        KeychainHelper.read(key: Keys.userEmail)
    }

    private var hasSeenOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.hasSeenOnboarding) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.hasSeenOnboarding) }
    }

    // MARK: - Keys

    private enum Keys {
        static let bearerToken = "com.todus.auth.bearerToken"
        static let userEmail = "com.todus.auth.userEmail"
        static let hasSeenOnboarding = "Todus.hasSeenOnboarding"
    }

    // MARK: - Configuration

    private let backendURL: URL

    /// Keep a strong reference to the web auth session so iOS doesn't deallocate it mid-flow.
    /// Without this, ASWebAuthenticationSession can be garbage-collected and the callback never fires.
    private var webAuthSession: ASWebAuthenticationSession?

    /// The current Bearer token, read from Keychain
    var bearerToken: String? {
        KeychainHelper.read(key: Keys.bearerToken)
    }

    // MARK: - Init

    init(backendURL: URL) {
        self.backendURL = backendURL
        super.init()

        // Restore auth state from Keychain
        if KeychainHelper.read(key: Keys.bearerToken) != nil {
            authState = .authenticated
        }
    }

    // MARK: - Apple Sign In

    /// Performs native Apple Sign In and sends the ID token to the backend.
    /// Better-Auth validates the ID token using the configured appBundleIdentifier.
    func signInWithApple() async {
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

            authLog.info("Apple sign-in response: status=\(http.statusCode)")

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
            } else {
                // Log the response for debugging
                let bodyString = String(data: data, encoding: .utf8) ?? "(empty)"
                authLog.error("Apple sign-in: failed to extract token. Status=\(http.statusCode), body=\(bodyString)")
                lastErrorMessage = "Apple Sign In failed. Please try again."
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

        isLoading = false
    }

    // MARK: - Google Sign In (Web-based OAuth)

    /// Opens the backend's Google OAuth flow via ASWebAuthenticationSession.
    /// Flow: Browser → Google OAuth → backend callback → /auth/mobile-token → todus://auth-callback?token=JWT
    func signInWithGoogle() async {
        isLoading = true
        lastErrorMessage = nil
        authState = .authenticating

        // Build the OAuth initiation URL. Better-Auth handles GET requests for social sign-in
        // by redirecting to the OAuth provider. After Google consent, Better-Auth creates the
        // session and redirects to callbackURL (/auth/mobile-token), which converts the session
        // cookie into a JWT and redirects via JS to todus://auth-callback?token=JWT.
        let callbackScheme = "todus"
        let authURL = backendURL
            .appending(path: "api/auth/sign-in/social")
            .appending(queryItems: [
                URLQueryItem(name: "provider", value: "google"),
                URLQueryItem(name: "callbackURL", value: "/auth/mobile-token"),
            ])

        authLog.info("Starting Google OAuth: \(authURL.absoluteString)")

        do {
            let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(
                    url: authURL,
                    callbackURLScheme: callbackScheme
                ) { url, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: AuthError.cancelled)
                    }
                }
                // Share cookies with Safari so /auth/mobile-token can read the session cookie
                session.prefersEphemeralWebBrowserSession = false
                // Hold a strong reference so the session isn't deallocated mid-flow
                self.webAuthSession = session
                session.start()
            }

            authLog.info("Google OAuth callback received: \(callbackURL.absoluteString)")

            // Parse token from callback URL: todus://auth-callback?token=...
            handleAuthCallback(url: callbackURL)

        } catch {
            let nsError = error as NSError
            if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
               nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                // User cancelled — no error message
                authLog.info("Google sign-in cancelled by user")
            } else {
                authLog.error("Google sign-in error: domain=\(nsError.domain) code=\(nsError.code) desc=\(error.localizedDescription)")
                // Show descriptive error for debugging
                lastErrorMessage = "Google Sign In failed: \(error.localizedDescription)"
            }
            if !isAuthenticated {
                authState = .guest
            }
        }

        webAuthSession = nil
        isLoading = false
    }

    // MARK: - Email OTP

    /// Sends a 6-digit OTP code to the given email via Better-Auth's emailOTP plugin.
    /// Backend: POST /api/auth/email-otp/send-verification-otp { email, type }
    func sendEmailOTP(email: String) async {
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
                    // Show the actual backend error for debugging
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

    /// Verifies the 6-digit OTP code and completes authentication.
    /// Backend: POST /api/auth/email-otp/verify-email { email, otp }
    func verifyEmailOTP(code: String) async {
        guard case .otpPending(let email) = authState else { return }
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCode.count >= 6 else {
            lastErrorMessage = "Enter the 6-digit code."
            return
        }

        isLoading = true
        lastErrorMessage = nil

        let url = backendURL.appending(path: "api/auth/email-otp/verify-email")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Origin must match a trustedOrigin with a valid hostname — the CORS middleware
// parses the hostname and checks against allowed domains (todus.app, localhost).
// Using the web app URL ensures it passes both CORS and Better-Auth CSRF checks.
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
    func returnToLogin() {
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
    func handleAuthCallback(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

        if let token = components.queryItems?.first(where: { $0.name == "token" })?.value {
            let email = components.queryItems?.first(where: { $0.name == "email" })?.value
            authLog.info("Auth callback: token received (length=\(token.count))")
            completeAuthentication(token: token, email: email)
        } else {
            authLog.error("Auth callback: no token in URL — \(url.absoluteString)")
            lastErrorMessage = "Sign in failed. No token received."
            authState = .guest
        }
    }

    // MARK: - Sign Out

    func signOut() {
        KeychainHelper.delete(key: Keys.bearerToken)
        KeychainHelper.delete(key: Keys.userEmail)
        authState = .guest
        lastErrorMessage = nil
    }

    func continueAsGuest() {
        hasSeenOnboarding = true
    }

    // MARK: - Private Helpers

    private func completeAuthentication(token: String, email: String?) {
        KeychainHelper.save(key: Keys.bearerToken, value: token)
        if let email {
            KeychainHelper.save(key: Keys.userEmail, value: email)
        }
        hasSeenOnboarding = true
        authState = .authenticated
    }

    /// Attempts to extract a Bearer token from the backend response.
    /// Better-Auth can return tokens in multiple formats depending on the plugin configuration.
    /// Returns true if a token was found and stored.
    @discardableResult
    private func extractToken(from data: Data, response: HTTPURLResponse, email: String?) -> Bool {
        // 1. Check for set-auth-token header (Better-Auth bearer plugin)
        if let headerToken = response.value(forHTTPHeaderField: "set-auth-token"), !headerToken.isEmpty {
            completeAuthentication(token: headerToken, email: email)
            return true
        }

        // 2. Check for token in JSON response body
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

    enum AuthError: Error {
        case cancelled
        case invalidResponse
    }
}

// MARK: - No-Redirect URL Session Delegate

/// Prevents URLSession from following redirects, so we can inspect 3xx responses directly.
/// Used for Apple sign-in where Better-Auth may return a redirect with the token.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = NoRedirectDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Check if the redirect URL contains our token (Better-Auth redirect-with-token pattern)
        if let redirectURL = request.url,
           let components = URLComponents(url: redirectURL, resolvingAgainstBaseURL: false),
           components.queryItems?.contains(where: { $0.name == "token" }) == true {
            // Don't follow — we'll extract the token from the redirect Location
            completionHandler(nil)
        } else {
            // Follow non-token redirects (e.g., OAuth provider redirects)
            completionHandler(request)
        }
    }
}

// MARK: - Apple Sign In Delegate

/// Async wrapper around ASAuthorizationControllerDelegate
private class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate {
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    func performRequest(controller: ASAuthorizationController) async throws -> ASAuthorizationAppleIDCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
            continuation?.resume(returning: credential)
        } else {
            continuation?.resume(throwing: AuthService.AuthError.invalidResponse)
        }
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

// MARK: - Keychain Helper

/// Simple Keychain wrapper for storing auth tokens securely.
enum KeychainHelper {
    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
