import Foundation
import Observation

/// Centralized service container for the macOS app.
/// Holds auth, API client, email, calendar, and network services.
/// Injected into views via @Environment(MacAppServices.self).
@MainActor
@Observable
final class MacAppServices {
    private enum Keys {
        static let contextAboutYou = "MacApp.contextAboutYou"
        static let customInstructions = "MacApp.customInstructions"
    }

    let authService: AuthService
    let apiClient: TodosAPIClient
    let emailService: EmailService
    let calendarService: CalendarService
    let networkMonitor: NetworkMonitor
    let aiChatService: MacAIChatService
    private let defaults = UserDefaults.standard

    var contextAboutYou: String {
        didSet {
            defaults.set(contextAboutYou, forKey: Keys.contextAboutYou)
            aiChatService.contextAboutYou = contextAboutYou
        }
    }

    var customInstructions: String {
        didSet {
            defaults.set(customInstructions, forKey: Keys.customInstructions)
            aiChatService.customInstructions = customInstructions
        }
    }

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
        self.contextAboutYou = defaults.string(forKey: Keys.contextAboutYou) ?? ""
        self.customInstructions = defaults.string(forKey: Keys.customInstructions) ?? ""
        self.aiChatService = MacAIChatService(
            backendURL: backendURL,
            apiClient: api,
            authService: auth,
            emailService: email,
            calendarService: calendar
        )
        self.aiChatService.contextAboutYou = contextAboutYou
        self.aiChatService.customInstructions = customInstructions
    }

    func loadSharedAIProfile() async {
        guard authService.isAuthenticated else { return }

        do {
            let response: SharedAIProfileResponse = try await apiClient.trpcQuery("settings.get")
            contextAboutYou = response.settings.contextAboutYou
            customInstructions = response.settings.customPrompt
        } catch {
            print("[MacAppServices] Failed to load shared AI profile: \(error)")
        }
    }

    func saveSharedAIProfile() async {
        guard authService.isAuthenticated else { return }

        do {
            let _: SharedAIProfileSaveResponse = try await apiClient.trpcMutation(
                "settings.save",
                input: SharedAIProfileSaveInput(
                    contextAboutYou: contextAboutYou,
                    customPrompt: customInstructions
                )
            )
        } catch {
            print("[MacAppServices] Failed to save shared AI profile: \(error)")
        }
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

private struct SharedAIProfileResponse: Decodable {
    struct Settings: Decodable {
        let contextAboutYou: String
        let customPrompt: String
    }

    let settings: Settings
}

private struct SharedAIProfileSaveInput: Encodable {
    let contextAboutYou: String
    let customPrompt: String
}

private struct SharedAIProfileSaveResponse: Decodable {
    let success: Bool
}
