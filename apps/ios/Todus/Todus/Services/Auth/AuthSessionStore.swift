import Foundation
import Observation

@MainActor
@Observable
final class AuthSessionStore {
    enum AuthState: Equatable {
        case guest
        case magicLinkPending(email: String)
        case authenticated(email: String)
    }

    private enum Keys {
        static let installID = "TaskApp.installID"
        static let anonymousID = "TaskApp.anonymousID"
        static let authEmail = "TaskApp.authEmail"
        static let hasSeenOnboarding = "TaskApp.hasSeenOnboarding"
        static let accessToken = "TaskApp.accessToken"
    }

    // Supabase Auth response structures
    private struct SupabaseSession: Decodable {
        let access_token: String?
        let user: SupabaseUser?

        struct SupabaseUser: Decodable {
            let id: String
            let email: String?
        }
    }

    private struct SupabaseError: Decodable {
        let message: String?
        let error_description: String?
        let error: String?

        var displayMessage: String {
            message ?? error_description ?? "An error occurred. Please try again."
        }
    }

    // Map HTTP status codes to user-friendly error messages
    private func friendlyErrorMessage(for statusCode: Int, supabaseError: SupabaseError) -> String {
        let apiMessage = supabaseError.displayMessage

        switch statusCode {
        case 429:
            // Rate limited — likely hit email quota
            return "Too many attempts. You've exceeded the daily email limit. Try again tomorrow, or configure a custom email provider in Supabase."
        case 402, 403:
            // Payment required or forbidden
            return "Email service quota exceeded. Upgrade your Supabase plan or configure a custom email provider (AWS SES, SendGrid, etc.)."
        case 404:
            return "Email service not configured. Enable Email OTP in Supabase Dashboard → Auth → Email."
        case 500...599:
            // For server errors, include the actual Supabase message for debugging
            if apiMessage.contains("error") || apiMessage.count > 10 {
                return "Server error: \(apiMessage)"
            }
            return "Supabase server error. Check your SMTP configuration and try again."
        default:
            // Return Supabase's own message for other errors
            return apiMessage
        }
    }

    let configuration: AppConfiguration
    private let defaults: UserDefaults

    var installID: String
    var anonymousID: String
    var authState: AuthState
    var showsOnboarding: Bool
    var lastErrorMessage: String?
    /// Stored Supabase JWT — available after successful OTP verification.
    /// Currently used for identification; future: pass to edge functions for RLS.
    private(set) var accessToken: String?

    init(configuration: AppConfiguration, defaults: UserDefaults = .standard) {
        self.configuration = configuration
        self.defaults = defaults

        let persistedInstallID = defaults.string(forKey: Keys.installID) ?? UUID().uuidString.lowercased()
        let persistedAnonymousID = defaults.string(forKey: Keys.anonymousID) ?? "anon_\(UUID().uuidString.lowercased())"
        let persistedEmail = defaults.string(forKey: Keys.authEmail)

        installID = persistedInstallID
        anonymousID = persistedAnonymousID
        authState = persistedEmail.map(AuthState.authenticated(email:)) ?? .guest
        showsOnboarding = !defaults.bool(forKey: Keys.hasSeenOnboarding)
        accessToken = defaults.string(forKey: Keys.accessToken)

        defaults.set(persistedInstallID, forKey: Keys.installID)
        defaults.set(persistedAnonymousID, forKey: Keys.anonymousID)
    }

    var currentUserID: String? {
        switch authState {
        case .authenticated(let email):
            return email.lowercased()
        case .guest, .magicLinkPending:
            return nil
        }
    }

    var isAuthenticated: Bool {
        if case .authenticated = authState {
            return true
        }
        return false
    }

    var pendingEmail: String? {
        guard case .magicLinkPending(let email) = authState else {
            return nil
        }
        return email
    }

    var accountEmail: String? {
        switch authState {
        case .guest:
            return nil
        case .magicLinkPending(let email), .authenticated(let email):
            return email
        }
    }

    func continueAsGuest() {
        defaults.set(true, forKey: Keys.hasSeenOnboarding)
        showsOnboarding = false
        lastErrorMessage = nil
    }

    func markOnboardingVisible() {
        showsOnboarding = true
    }

    /// Calls Supabase Auth OTP endpoint to send a 6-digit code to the user's email.
    /// Requires "Email OTP" enabled in Supabase dashboard → Auth → Email.
    func sendMagicLink(email: String) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedEmail.isEmpty else {
            lastErrorMessage = "Enter an email address first."
            return
        }

        lastErrorMessage = nil

        guard configuration.hasRemoteBackend, let supabaseURL = configuration.supabaseURL else {
            // No backend configured — development mode fallback
            authState = .magicLinkPending(email: trimmedEmail)
            lastErrorMessage = "No backend configured. Enter any 6-digit code to continue."
            AppLogger.shared.log("sendMagicLink: no backend, dev mode fallback for \(AppLogger.mask(trimmedEmail))")
            return
        }

        AppLogger.shared.log("sendMagicLink: calling Supabase OTP for \(AppLogger.mask(trimmedEmail))")

        // POST /auth/v1/otp — Supabase sends a 6-digit OTP to the email address.
        // `create_user: true` allows new users to sign up (matches "Allow new users to sign up" in dashboard).
        let url = supabaseURL.appending(path: "auth/v1/otp")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(configuration.supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        struct OTPBody: Encodable {
            let email: String
            let create_user: Bool
        }
        request.httpBody = try? JSONEncoder().encode(OTPBody(email: trimmedEmail, create_user: true))

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let supabaseError: SupabaseError = (try? JSONDecoder().decode(SupabaseError.self, from: data)) ?? SupabaseError(message: nil, error_description: nil, error: nil)
                let msg = friendlyErrorMessage(for: status, supabaseError: supabaseError)

                // Log full response body for debugging
                if let responseStr = String(data: data, encoding: .utf8) {
                    AppLogger.shared.log("sendMagicLink: HTTP \(status) error response: \(responseStr)")
                } else {
                    AppLogger.shared.log("sendMagicLink: HTTP \(status) error — \(msg)")
                }
                lastErrorMessage = msg
                return
            }

            authState = .magicLinkPending(email: trimmedEmail)
            AppLogger.shared.log("sendMagicLink: success — code sent to \(AppLogger.mask(trimmedEmail))")
        } catch {
            AppLogger.shared.log("sendMagicLink: network error — \(error.localizedDescription)")
            lastErrorMessage = "Network error. Check your connection and try again."
        }
    }

    /// Verifies the 6-digit OTP code with Supabase. On success, completes authentication.
    func verifyMagicLinkCode(_ code: String) async {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let email = pendingEmail else {
            lastErrorMessage = "Start with your email first."
            return
        }

        guard trimmedCode.count >= 6 else {
            lastErrorMessage = "Enter the 6-digit code."
            return
        }

        lastErrorMessage = nil

        guard configuration.hasRemoteBackend, let supabaseURL = configuration.supabaseURL else {
            // Dev mode — accept any code without verification
            AppLogger.shared.log("verifyMagicLinkCode: no backend, accepting any code")
            defaults.set(true, forKey: Keys.hasSeenOnboarding)
            showsOnboarding = false
            completeAuthentication(email: email, accessToken: nil)
            return
        }

        AppLogger.shared.log("verifyMagicLinkCode: verifying OTP for \(AppLogger.mask(email))")

        // POST /auth/v1/verify — validates the OTP token and returns a session JWT.
        let url = supabaseURL.appending(path: "auth/v1/verify")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(configuration.supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        struct VerifyBody: Encodable {
            let type: String
            let email: String
            let token: String
        }
        request.httpBody = try? JSONEncoder().encode(VerifyBody(type: "email", email: email, token: trimmedCode))

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let supabaseError: SupabaseError = (try? JSONDecoder().decode(SupabaseError.self, from: data)) ?? SupabaseError(message: nil, error_description: nil, error: nil)
                let msg = (status == 401 || status == 400) ? "Invalid or expired code. Request a new one." : friendlyErrorMessage(for: status, supabaseError: supabaseError)

                // Log full response body for debugging
                if let responseStr = String(data: data, encoding: .utf8) {
                    AppLogger.shared.log("verifyMagicLinkCode: HTTP \(status) error response: \(responseStr)")
                } else {
                    AppLogger.shared.log("verifyMagicLinkCode: HTTP \(status) error — \(msg)")
                }
                lastErrorMessage = msg
                return
            }

            // Parse session to store the JWT access token for future authenticated requests
            let session = try? JSONDecoder().decode(SupabaseSession.self, from: data)
            AppLogger.shared.log("verifyMagicLinkCode: success — user authenticated")
            defaults.set(true, forKey: Keys.hasSeenOnboarding)
            showsOnboarding = false
            completeAuthentication(email: email, accessToken: session?.access_token)
        } catch {
            AppLogger.shared.log("verifyMagicLinkCode: network error — \(error.localizedDescription)")
            lastErrorMessage = "Network error. Check your connection and try again."
        }
    }

    func returnToLogin() {
        authState = .guest
        lastErrorMessage = nil
    }

    func completeAuthentication(email: String, accessToken: String? = nil) {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        defaults.set(normalized, forKey: Keys.authEmail)
        if let token = accessToken {
            defaults.set(token, forKey: Keys.accessToken)
            self.accessToken = token
        }
        authState = .authenticated(email: normalized)
    }

    func signOutToGuest() {
        defaults.removeObject(forKey: Keys.authEmail)
        defaults.removeObject(forKey: Keys.accessToken)
        accessToken = nil
        authState = .guest
    }

    func handleIncomingAuthCallback(url: URL) {
        // Better Auth deep links are handled by AuthService; legacy Supabase magic-link
        // path skipped here to avoid hijacking state. Without this early-return, a
        // todus://auth-callback?email=... or todus://link-callback would flip this
        // store into the magicLinkPending state and force the onboarding sheet,
        // overwriting AuthService's in-progress sign-in.
        let host = url.host?.lowercased()
        if host == "auth-callback" || host == "link-callback" {
            return
        }
        let firstPath = url.pathComponents.dropFirst().first?.lowercased()
        if firstPath == "auth-callback" || firstPath == "link-callback" {
            return
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return
        }

        let email = components.queryItems?.first(where: { $0.name == "email" })?.value
        if let email {
            authState = .magicLinkPending(email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            showsOnboarding = true
            lastErrorMessage = "Enter the verification code to continue."
        }
    }
}

