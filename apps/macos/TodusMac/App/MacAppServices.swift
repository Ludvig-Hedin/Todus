import Foundation
import Observation

/// Centralized service container for the macOS app.
/// Holds auth, API client, email, calendar, and network services.
/// Injected into views via @Environment(MacAppServices.self).
@MainActor
@Observable
final class MacAppServices {

    let authService: AuthService
    let apiClient: TodosAPIClient
    let emailService: EmailService
    let calendarService: CalendarService
    let networkMonitor: NetworkMonitor
    let aiChatService: MacAIChatService

    init() {
        let backendURL = Self.loadBackendURL()
        let auth = AuthService(backendURL: backendURL)
        let api = TodosAPIClient(baseURL: backendURL, authService: auth)
        let email = EmailService(api: api)
        let calendar = CalendarService()

        self.authService = auth
        self.apiClient = api
        self.emailService = email
        self.calendarService = calendar
        self.networkMonitor = NetworkMonitor()
        self.aiChatService = MacAIChatService(
            backendURL: backendURL,
            apiClient: api,
            authService: auth,
            emailService: email,
            calendarService: calendar
        )
    }

    func signOut() {
        emailService.resetForSignOut()
        authService.signOut()
    }

    /// Loads the backend URL from TodosConfig.plist.
    /// Falls back to production URL if plist is missing or malformed.
    private static func loadBackendURL() -> URL {
        if let path = Bundle.main.path(forResource: "TodosConfig", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path),
           let urlString = dict["BACKEND_URL"] as? String,
           let url = URL(string: urlString) {
            return url
        }
        // Fallback to production backend
        return URL(string: "https://api.todus.app")!
    }
}
