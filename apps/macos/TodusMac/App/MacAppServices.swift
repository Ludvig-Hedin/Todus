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
        static let startupView = "MacApp.startupView"
        static let hasConfiguredGmailPrompt = "MacApp.hasConfiguredGmailPrompt"
        static let hasConfiguredCalendarPrompt = "MacApp.hasConfiguredCalendarPrompt"
        static let hasConfiguredRemindersPrompt = "MacApp.hasConfiguredRemindersPrompt"
        static let hasConfiguredStartupViewPrompt = "MacApp.hasConfiguredStartupViewPrompt"
        static let remindersSyncEnabled = "mac_reminders_enabled"
        static let remindersSyncDirection = "MacApp.remindersSyncDirection"
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
    let connectionsService: ConnectionsService
    private let defaults = UserDefaults.standard
    let remindersSyncService = AppleRemindersSyncService()
    let remindersSyncState = RemindersSyncState()
    var showsAssistantPanel = false
    var isSyncingSharedFolders = false

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

    var startupView: String {
        didSet {
            defaults.set(startupView, forKey: Keys.startupView)
        }
    }

    var hasConfiguredGmailPrompt: Bool {
        didSet {
            defaults.set(hasConfiguredGmailPrompt, forKey: Keys.hasConfiguredGmailPrompt)
        }
    }

    var hasConfiguredCalendarPrompt: Bool {
        didSet {
            defaults.set(hasConfiguredCalendarPrompt, forKey: Keys.hasConfiguredCalendarPrompt)
        }
    }

    var hasConfiguredRemindersPrompt: Bool {
        didSet {
            defaults.set(hasConfiguredRemindersPrompt, forKey: Keys.hasConfiguredRemindersPrompt)
        }
    }

    /// When true, tasks sync with Apple Reminders (same key as Settings `mac_reminders_enabled`).
    var remindersSyncEnabled: Bool {
        didSet {
            remindersSyncState.isEnabled = remindersSyncEnabled
            defaults.set(remindersSyncEnabled, forKey: Keys.remindersSyncEnabled)
        }
    }

    var remindersSyncDirection: RemindersSyncDirection {
        didSet {
            remindersSyncState.direction = remindersSyncDirection
            defaults.set(remindersSyncDirection.rawValue, forKey: Keys.remindersSyncDirection)
        }
    }

    var hasConfiguredStartupViewPrompt: Bool {
        didSet {
            defaults.set(hasConfiguredStartupViewPrompt, forKey: Keys.hasConfiguredStartupViewPrompt)
        }
    }

    init() {
        if defaults.bool(forKey: Keys.hasConfiguredStartupViewPrompt),
           defaults.object(forKey: Keys.hasConfiguredRemindersPrompt) == nil {
            defaults.set(true, forKey: Keys.hasConfiguredRemindersPrompt)
        }

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
        self.startupView = defaults.string(forKey: Keys.startupView) ?? "home"
        self.hasConfiguredGmailPrompt = defaults.bool(forKey: Keys.hasConfiguredGmailPrompt)
        self.hasConfiguredCalendarPrompt = defaults.bool(forKey: Keys.hasConfiguredCalendarPrompt)
        self.hasConfiguredRemindersPrompt = defaults.bool(forKey: Keys.hasConfiguredRemindersPrompt)
        self.hasConfiguredStartupViewPrompt = defaults.bool(forKey: Keys.hasConfiguredStartupViewPrompt)
        if let dir = defaults.string(forKey: Keys.remindersSyncDirection),
           let parsed = RemindersSyncDirection(rawValue: dir) {
            self.remindersSyncDirection = parsed
        } else {
            self.remindersSyncDirection = .twoWay
        }
        self.remindersSyncEnabled = defaults.object(forKey: Keys.remindersSyncEnabled) as? Bool ?? false
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
        self.connectionsService = ConnectionsService(api: api)
        self.aiChatService.contextAboutYou = contextAboutYou
        self.aiChatService.customInstructions = customInstructions
        self.remindersSyncState.isEnabled = self.remindersSyncEnabled
        self.remindersSyncState.direction = self.remindersSyncDirection
    }

    func loadSharedAIProfile() async {
        guard authService.isAuthenticated else { return }

        do {
            let response: MailAssistantSettingsResponse = try await apiClient.trpcQuery("settings.get")
            contextAboutYou = response.settings.contextAboutYou
            customInstructions = response.settings.customPrompt
            assistantAutomationPolicy = response.settings.assistantAutomationPolicy
        } catch {
            AppLogger.shared.log("[MacAppServices] Failed to load shared AI profile: \(error)")
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
            AppLogger.shared.log("[MacAppServices] Failed to save shared AI profile: \(error)")
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

        isSyncingSharedFolders = true
        defer { isSyncingSharedFolders = false }

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

    func requestRemindersPermissionIfNeeded() async -> Bool {
        guard remindersSyncEnabled else { return false }
        switch remindersSyncService.authorizationState() {
        case .authorized, .writeOnly:
            // The sync workers (`upsert`, `delete`, `syncAllTasks`) accept either
            // `.authorized` or `.writeOnly`. Treat the gate the same way so users
            // who grant write-only access don't get falsely rejected here while
            // the underlying writes would succeed.
            return true
        case .notDetermined:
            return await remindersSyncService.requestAccess()
        case .restricted, .denied:
            return false
        }
    }

    func syncExistingTasksToReminders(in context: ModelContext) {
        guard remindersSyncEnabled else { return }
        guard remindersSyncDirection != .fromReminders else { return }
        let descriptor = FetchDescriptor<TaskRecord>()
        let tasks: [TaskRecord]
        do {
            tasks = try context.fetch(descriptor)
        } catch {
            AppLogger.shared.log("[MacAppServices] Failed to fetch tasks for reminders sync: \(error)")
            return
        }
        remindersSyncService.syncAllTasks(tasks, in: context)
    }

    func importFromReminders(in context: ModelContext) async {
        guard remindersSyncEnabled else { return }
        guard remindersSyncDirection != .toReminders else { return }
        await remindersSyncService.importFromReminders(in: context)
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

    /// Derives the web app URL from the backend URL.
    /// When the backend is local (localhost), the web dev server runs on port 3000.
    /// In production the web app lives at app.todus.app.
    static func loadAppURL() -> URL {
        let backend = loadBackendURL()
        if backend.host?.contains("localhost") == true || backend.host?.contains("127.0.0.1") == true {
            return URL(string: "http://localhost:3000")!
        }
        return URL(string: "https://app.todus.app")!
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
