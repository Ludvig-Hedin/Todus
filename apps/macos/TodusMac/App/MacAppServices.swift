import AppKit
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
        static let restoreLastViewedPage = "MacApp.restoreLastViewedPage"
        static let hasConfiguredGmailPrompt = "MacApp.hasConfiguredGmailPrompt"
        static let hasConfiguredCalendarPrompt = "MacApp.hasConfiguredCalendarPrompt"
        static let hasConfiguredRemindersPrompt = "MacApp.hasConfiguredRemindersPrompt"
        static let hasConfiguredStartupViewPrompt = "MacApp.hasConfiguredStartupViewPrompt"
        static let hasConfiguredNotificationsPrompt = "MacApp.hasConfiguredNotificationsPrompt"
        static let hasConfiguredDefaultMailPrompt = "MacApp.hasConfiguredDefaultMailPrompt"
        static let emailNotificationsEnabled = "MacApp.emailNotificationsEnabled"
        static let remindersSyncEnabled = "mac_reminders_enabled"
        static let remindersSyncDirection = "MacApp.remindersSyncDirection"
        /// Shared with iOS so one account’s preference can match across devices if desired.
        static let developerModeEnabled = "TaskApp.developerModeEnabled"
    }

    let authService: AuthService
    let apiClient: TodosAPIClient
    let emailService: EmailService
    let calendarService: CalendarService
    let networkMonitor: NetworkMonitor
    let notificationService: MacNotificationService
    let aiChatService: MacAIChatService
    let voiceTokenService: VoiceTokenService
    let shareConversationService: ShareConversationService
    let groupChatService: GroupChatService
    let meetingsService: MeetingsService
    let connectionsService: ConnectionsService
    let subscriptionService: MacSubscriptionService
    let docsService: MacDocsService
    /// Wraps drafts.update + mail.send for the AI chat's InlineComposeCard.
    let draftService: MacDraftService
    /// Tracks per-model install state for the Local Models settings screen and
    /// the chat composer's local-runtime routing. Disk scan runs on init.
    let localModelStateStore: LocalModelStateStore
    /// Queues task mutations and flushes them via tRPC `tasks.sync`.
    let taskSyncService: TaskSyncService
    /// Retained here so `setupNetworkSync()` can reach `mainContext` on reconnect.
    var modelContainer: ModelContainer?
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

    var restoreLastViewedPage: Bool {
        didSet {
            defaults.set(restoreLastViewedPage, forKey: Keys.restoreLastViewedPage)
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

    var hasConfiguredNotificationsPrompt: Bool {
        didSet { defaults.set(hasConfiguredNotificationsPrompt, forKey: Keys.hasConfiguredNotificationsPrompt) }
    }

    var hasConfiguredDefaultMailPrompt: Bool {
        didSet { defaults.set(hasConfiguredDefaultMailPrompt, forKey: Keys.hasConfiguredDefaultMailPrompt) }
    }

    var emailNotificationsEnabled: Bool {
        didSet { defaults.set(emailNotificationsEnabled, forKey: Keys.emailNotificationsEnabled) }
    }

    /// Single pending `mailto:` payload — set when the OS routes a link to Todus.
    /// Any of `to` / `subject` / `body` may be non-nil; MacRootView observes this
    /// and opens compose (observing the whole value fixes subject-only / body-only links).
    struct PendingMailto: Equatable {
        var to: String?
        var subject: String?
        var body: String?
    }

    var pendingMailto: PendingMailto? = nil

    var developerModeEnabled: Bool {
        didSet {
            defaults.set(developerModeEnabled, forKey: Keys.developerModeEnabled)
        }
    }

    /// Whether the signed-in user may see the Developer Mode toggle (allowlisted accounts only).
    var isDeveloperModeUIAvailable: Bool {
        TodusDeveloperAccess.isAllowlisted(email: authService.userEmail)
    }

    /// Developer features: allowlisted email and toggle on.
    var effectiveDeveloperModeEnabled: Bool {
        developerModeEnabled && isDeveloperModeUIAvailable
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
        self.notificationService = MacNotificationService()
        self.contextAboutYou = defaults.string(forKey: Keys.contextAboutYou) ?? ""
        self.customInstructions = defaults.string(forKey: Keys.customInstructions) ?? ""
        self.startupView = defaults.string(forKey: Keys.startupView) ?? "home"
        self.restoreLastViewedPage = defaults.object(forKey: Keys.restoreLastViewedPage) as? Bool ?? false
        self.hasConfiguredGmailPrompt = defaults.bool(forKey: Keys.hasConfiguredGmailPrompt)
        self.hasConfiguredCalendarPrompt = defaults.bool(forKey: Keys.hasConfiguredCalendarPrompt)
        self.hasConfiguredRemindersPrompt = defaults.bool(forKey: Keys.hasConfiguredRemindersPrompt)
        self.hasConfiguredStartupViewPrompt = defaults.bool(forKey: Keys.hasConfiguredStartupViewPrompt)
        self.hasConfiguredNotificationsPrompt = defaults.bool(forKey: Keys.hasConfiguredNotificationsPrompt)
        self.hasConfiguredDefaultMailPrompt = defaults.bool(forKey: Keys.hasConfiguredDefaultMailPrompt)
        self.emailNotificationsEnabled = defaults.object(forKey: Keys.emailNotificationsEnabled) as? Bool ?? true
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
        self.developerModeEnabled = defaults.bool(forKey: Keys.developerModeEnabled)
        self.aiChatService = MacAIChatService(
            backendURL: backendURL,
            apiClient: api,
            authService: auth,
            emailService: email,
            calendarService: calendar
        )
        self.voiceTokenService = VoiceTokenService(authService: auth, backendURL: backendURL)
        self.shareConversationService = ShareConversationService(apiClient: api)
        self.groupChatService = GroupChatService(apiClient: api)
        self.meetingsService = MeetingsService(apiClient: api)
        self.connectionsService = ConnectionsService(api: api)
        self.subscriptionService = MacSubscriptionService(apiClient: api)
        self.docsService = MacDocsService(apiClient: api)
        self.draftService = MacDraftService(api: api)
        self.localModelStateStore = LocalModelStateStore()
        self.taskSyncService = TaskSyncService(apiClient: api)
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
                local.colorHex = remote.color
                local.iconName = remote.icon
                local.position = remote.position ?? local.position
                local.createdAt = remote.createdAt
                local.updatedAt = remote.updatedAt ?? local.updatedAt
            } else {
                let folder = FolderRecord(
                    id: uuid,
                    name: remote.name,
                    colorHex: remote.color,
                    iconName: remote.icon,
                    position: remote.position ?? 0,
                    createdAt: remote.createdAt,
                    updatedAt: remote.updatedAt ?? remote.createdAt
                )
                context.insert(folder)
                foldersByID[normalizedID] = folder
            }
        }

        try context.save()
    }

    /// Pull the folder summary (counts, breakdowns, recent items) and update the
    /// local FolderRecord caches so cards render instantly.
    func fetchFolderSummary(in context: ModelContext) async {
        guard authService.isAuthenticated else { return }
        do {
            let response: MacFolderSummaryResponse = try await apiClient.trpcQuery("folders.summary")
            let localFolders = try context.fetch(FetchDescriptor<FolderRecord>())
            let byID = Dictionary(
                uniqueKeysWithValues: localFolders.map { ($0.id.uuidString.lowercased(), $0) }
            )

            for remote in response.folders {
                guard let local = byID[remote.folder.id.lowercased()] else { continue }
                local.cachedItemCount = remote.itemCount
                local.setBreakdown(FolderTypeBreakdown(
                    tasks: remote.breakdown.tasks,
                    chats: remote.breakdown.chats,
                    emails: remote.breakdown.emails,
                    events: remote.breakdown.events,
                    docs: remote.breakdown.docs
                ))
                local.setRecentItems(remote.recentItems.map {
                    FolderRecentItem(
                        type: $0.type,
                        id: $0.id,
                        title: $0.title,
                        subtitle: $0.subtitle,
                        sortAt: $0.sortAt
                    )
                })
            }
            try? context.save()
        } catch {
            // Best-effort — cards keep showing previous cached values.
        }
    }

    func createSharedFolder(
        name: String,
        colorHex: String?,
        iconName: String?,
        in context: ModelContext
    ) async -> FolderRecord? {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        let existing = (try? context.fetch(FetchDescriptor<FolderRecord>())) ?? []
        let nextPosition = (existing.map { $0.position }.max() ?? -1) + 1
        let folder = FolderRecord(
            name: cleaned,
            colorHex: colorHex,
            iconName: iconName,
            position: nextPosition
        )
        context.insert(folder)
        try? context.save()

        struct CreateInput: Encodable {
            let id: String
            let name: String
            let color: String?
            let icon: String?
            let position: Int
        }
        do {
            let _: EmptyResponse = try await apiClient.trpcMutation(
                "folders.create",
                input: CreateInput(
                    id: folder.id.uuidString,
                    name: folder.name,
                    color: folder.colorHex,
                    icon: folder.iconName,
                    position: folder.position
                )
            )
        } catch {
            // Best-effort — keeps locally; will be re-tried on next sync.
        }
        return folder
    }

    func updateSharedFolder(
        _ folder: FolderRecord,
        name: String? = nil,
        colorHex: String?? = nil,
        iconName: String?? = nil,
        position: Int? = nil,
        in context: ModelContext
    ) async {
        if let name { folder.name = name }
        if case let .some(value) = colorHex { folder.colorHex = value }
        if case let .some(value) = iconName { folder.iconName = value }
        if let position { folder.position = position }
        folder.updatedAt = .now
        try? context.save()

        struct UpdateInput: Encodable {
            let id: String
            let name: String?
            let color: String?
            let icon: String?
            let position: Int?
        }
        do {
            let _: EmptyResponse = try await apiClient.trpcMutation(
                "folders.update",
                input: UpdateInput(
                    id: folder.id.uuidString,
                    name: folder.name,
                    color: folder.colorHex,
                    icon: folder.iconName,
                    position: folder.position
                )
            )
        } catch {
            // Best-effort sync only.
        }
    }

    func deleteSharedFolder(_ folder: FolderRecord, in context: ModelContext) async {
        let id = folder.id.uuidString
        // Unlink tasks
        let allTasks = (try? context.fetch(FetchDescriptor<TaskRecord>())) ?? []
        for task in allTasks where task.folder?.id == folder.id {
            task.folder = nil
            task.updatedAt = .now
        }
        context.delete(folder)
        try? context.save()

        struct DeleteInput: Encodable { let id: String }
        do {
            let _: EmptyResponse = try await apiClient.trpcMutation(
                "folders.delete",
                input: DeleteInput(id: id)
            )
        } catch {
            // Best-effort sync only.
        }
    }

    func addItemToSharedFolder(
        kind: FolderItemKind,
        itemId: String,
        title: String?,
        subtitle: String?,
        folder: FolderRecord,
        in context: ModelContext
    ) async {
        guard kind == .email || kind == .event || kind == .doc else { return }

        let item = FolderItemRecord(
            folder: folder,
            itemType: kind.rawValue,
            itemId: itemId,
            titleCache: title,
            subtitleCache: subtitle,
            position: 0,
            createdAt: .now
        )
        context.insert(item)
        folder.cachedItemCount += 1
        folder.updatedAt = .now
        try? context.save()

        struct Metadata: Encodable {
            let title: String?
            let subtitle: String?
        }
        struct AddInput: Encodable {
            let folderId: String
            let itemType: String
            let itemId: String
            let metadata: Metadata?
        }
        let metadata: Metadata? = (title != nil || subtitle != nil)
            ? Metadata(title: title, subtitle: subtitle)
            : nil
        do {
            let _: EmptyResponse = try await apiClient.trpcMutation(
                "folders.addItem",
                input: AddInput(
                    folderId: folder.id.uuidString,
                    itemType: kind.rawValue,
                    itemId: itemId,
                    metadata: metadata
                )
            )
        } catch {
            // Best-effort sync only.
        }
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

    /// Wires the network reconnect callback to flush any pending/failed task mutations.
    /// Call this once after both `MacAppServices` and the `ModelContainer` are ready.
    func setupNetworkSync() {
        networkMonitor.onReconnect = { [weak self] in
            guard let self, let context = self.modelContainer?.mainContext else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.taskSyncService.retryUnsyncedTasks(in: context)
            }
        }
    }

    func signOut() {
        emailService.resetForSignOut()
        authService.signOut()
        closeSettingsWindowIfPresent()
    }

    /// Closes the dedicated Settings window (`Window(id: "settings")`) if it is open.
    /// Used when signing out or when the login screen is shown so prefs do not stack on sign-in.
    func closeSettingsWindowIfPresent() {
        DispatchQueue.main.async {
            let settingsAutosave = NSWindow.FrameAutosaveName("TodusMacSettingsWindow")
            for window in NSApplication.shared.windows {
                if window.title == "Settings"
                    || window.frameAutosaveName == settingsAutosave {
                    window.close()
                }
            }
        }
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
