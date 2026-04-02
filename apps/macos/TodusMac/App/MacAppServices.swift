import Foundation
import Observation
import SwiftData

/// Centralized service container for the macOS app.
/// Holds auth, API client, email, calendar, and network services.
/// Injected into views via @Environment(MacAppServices.self).
@MainActor
@Observable
final class MacAppServices {
    private enum Keys {
        static let contextAboutYou = "MacApp.contextAboutYou"
        static let customInstructions = "MacApp.customInstructions"
        static let assistantAutomationPolicy = "MacApp.assistantAutomationPolicy"
    }

    let authService: AuthService
    let apiClient: TodosAPIClient
    let emailService: EmailService
    let calendarService: CalendarService
    let networkMonitor: NetworkMonitor
    let aiChatService: MacAIChatService
    let shareConversationService: ShareConversationService
    let groupChatService: GroupChatService
    let meetingsService: MeetingsService
    private let defaults = UserDefaults.standard
    var showsAssistantPanel = false

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

    var assistantAutomationPolicy: AssistantAutomationPolicy {
        didSet {
            if let data = try? JSONEncoder().encode(assistantAutomationPolicy) {
                defaults.set(data, forKey: Keys.assistantAutomationPolicy)
            }
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
        if let data = defaults.data(forKey: Keys.assistantAutomationPolicy),
           let savedPolicy = try? JSONDecoder().decode(AssistantAutomationPolicy.self, from: data) {
            self.assistantAutomationPolicy = savedPolicy
        } else {
            self.assistantAutomationPolicy = .recommended
        }
        self.aiChatService = MacAIChatService(
            backendURL: backendURL,
            apiClient: api,
            authService: auth,
            emailService: email,
            calendarService: calendar
        )
        self.shareConversationService = ShareConversationService(apiClient: api)
        self.groupChatService = GroupChatService(apiClient: api)
        self.meetingsService = MeetingsService(apiClient: api)
        self.aiChatService.contextAboutYou = contextAboutYou
        self.aiChatService.customInstructions = customInstructions
    }

    func loadSharedAIProfile() async {
        guard authService.isAuthenticated else { return }

        do {
            let response: MailAssistantSettingsResponse = try await apiClient.trpcQuery("settings.get")
            contextAboutYou = response.settings.contextAboutYou
            customInstructions = response.settings.customPrompt
            assistantAutomationPolicy = response.settings.assistantAutomationPolicy
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
                    customPrompt: customInstructions,
                    assistantAutomationPolicy: assistantAutomationPolicy
                )
            )
        } catch {
            print("[MacAppServices] Failed to save shared AI profile: \(error)")
        }
    }

    func syncSharedFolders(in context: ModelContext) async throws {
        guard authService.isAuthenticated else { return }

        struct FolderListResponse: Decodable {
            let folders: [RemoteFolder]
        }

        struct RemoteFolder: Decodable {
            let id: String
            let name: String
            let createdAt: Date
        }

        let response: FolderListResponse = try await apiClient.trpcQuery("folders.list")
        let remoteFolders = response.folders
        let localFolders = try context.fetch(FetchDescriptor<FolderRecord>())
        var foldersByID = Dictionary(
            uniqueKeysWithValues: localFolders.map { ($0.id.uuidString.lowercased(), $0) }
        )

        for remote in remoteFolders {
            let normalizedID = remote.id.lowercased()
            guard let uuid = UUID(uuidString: remote.id) else { continue }
            if let local = foldersByID[normalizedID] {
                local.name = remote.name
                local.createdAt = remote.createdAt
            } else {
                let folder = FolderRecord(id: uuid, name: remote.name, createdAt: remote.createdAt)
                context.insert(folder)
                foldersByID[normalizedID] = folder
            }
        }

        try context.save()
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

private struct SharedAIProfileSaveInput: Encodable {
    let contextAboutYou: String
    let customPrompt: String
    let assistantAutomationPolicy: AssistantAutomationPolicy
}

private struct SharedAIProfileSaveResponse: Decodable {
    let success: Bool
}
