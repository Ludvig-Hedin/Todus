import AppKit
import Foundation
import Observation
import SwiftData

private struct MacSingleSettingInput<Value: Encodable>: Encodable {
    let key: String
    let value: Value

    func encode(to encoder: Encoder) throws {
        guard let codingKey = MacDynamicCodingKey(stringValue: key) else { return }
        var container = encoder.container(keyedBy: MacDynamicCodingKey.self)
        try container.encode(value, forKey: codingKey)
    }
}

private struct MacDynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

/// Centralized service container for the macOS app.
/// Holds auth, API client, email, calendar, and network services.
/// Injected into views via @Environment(MacAppServices.self).
@MainActor
@Observable
final class MacAppServices {
    private enum Keys {
        static let contextAboutYou = "MacApp.contextAboutYou"
        static let customInstructions = "MacApp.customInstructions"
        static let location = "MacApp.location"
        static let assistantAutomationPolicy = "MacApp.assistantAutomationPolicy"
        static let calendarPreferences = "MacApp.calendarPreferences"
        static let startupView = "MacApp.startupView"
        static let restoreLastViewedPage = "MacApp.restoreLastViewedPage"
        static let hasConfiguredGmailPrompt = "MacApp.hasConfiguredGmailPrompt"
        static let hasConfiguredCalendarPrompt = "MacApp.hasConfiguredCalendarPrompt"
        static let hasConfiguredRemindersPrompt = "MacApp.hasConfiguredRemindersPrompt"
        static let hasConfiguredStartupViewPrompt = "MacApp.hasConfiguredStartupViewPrompt"
        static let hasConfiguredNotificationsPrompt = "MacApp.hasConfiguredNotificationsPrompt"
        static let hasConfiguredDefaultMailPrompt = "MacApp.hasConfiguredDefaultMailPrompt"
        /// One-shot flag — true after the user has taken or skipped the optional
        /// product tour shown right before the main shell. Defaulted to true for
        /// returning users via the migration in `init` so the tour never
        /// ambushes an existing session.
        static let hasSeenWelcomeTour = "MacApp.hasSeenWelcomeTour"
        /// Positive proof the user reached the main shell at least once. Used
        /// by the welcome-tour migration the same way iOS uses `hasReachedMainTab`.
        static let hasReachedMainShell = "MacApp.hasReachedMainShell"
        static let emailNotificationsEnabled = "MacApp.emailNotificationsEnabled"
        static let remindersSyncEnabled = "mac_reminders_enabled"
        static let remindersSyncDirection = "MacApp.remindersSyncDirection"
        /// Shared with iOS so one account’s preference can match across devices if desired.
        static let developerModeEnabled = "TaskApp.developerModeEnabled"
        /// Voice assistant: always-listening wake-word toggle. Defaults to OFF —
        /// the always-on mic is opt-in to keep the first-launch experience
        /// non-creepy and to avoid a permission prompt the user didn't ask for.
        static let voiceWakeWordEnabled = "Voice.WakeWordEnabled"
        /// Voice assistant: master enable. Hotkey and wake registration only run
        /// when this is true.
        static let voiceAssistantEnabled = "Voice.AssistantEnabled"
    }

    let authService: AuthService
    let apiClient: TodosAPIClient
    let emailService: EmailService
    let calendarService: CalendarService
    /// Backend Google Calendar integration — fetches per-connection calendars and events.
    let googleCalendarService: GoogleCalendarService
    /// Aggregator that merges Apple (EventKit) + Google (backend) events with
    /// per-source visibility from `calendarPreferences`.
    let unifiedCalendarService: UnifiedCalendarService
    let networkMonitor: NetworkMonitor
    let notificationService: MacNotificationService
    let aiChatService: MacAIChatService
    let voiceTokenService: VoiceTokenService
    let voiceSystemPromptClient: VoiceSystemPromptClient
    let audioInputBroker: AudioInputBroker
    let hotkeyService: HotkeyService
    let wakeWordService: WakeWordService
    let voiceCoordinator: VoiceSessionCoordinator
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
    /// Apple Intelligence on-device LLM (macOS 26+). Always present; service
    /// reports `isReady` based on OS + Apple Intelligence enablement.
    let appleFoundationModelService: AppleFoundationModelService
    /// Probes a locally-running Ollama daemon and lists installed tags. The
    /// "Connected (Ollama)" section in Settings → Local Models reads from
    /// this; routing for chat goes through `ollamaInferenceService`.
    let ollamaConnector: OllamaConnector
    /// Streams chat completions from the user's local Ollama daemon.
    let ollamaInferenceService: OllamaInferenceService
    /// Scans the user's HuggingFace caches (app + `~/.cache/huggingface/hub`) and
    /// surfaces every MLX-shaped model it finds. Lets users adopt models they
    /// already downloaded via `huggingface_hub` / `mlx_lm` without re-pulling.
    let huggingFaceCacheConnector: HuggingFaceCacheConnector
    /// MLX-Swift inference (Apple Silicon). Loads quantized weights from the
    /// HuggingFace cache populated by `modelDownloadService`.
    let mlxInferenceService: MLXInferenceService
    /// Orchestrates HuggingFace downloads + deletions for MLX models.
    let modelDownloadService: ModelDownloadService
    /// Queues task mutations and flushes them via tRPC `tasks.sync`.
    let taskSyncService: TaskSyncService
    /// Queues folder create/update/delete mutations and flushes them via tRPC `folders.sync`.
    let folderSyncService: FolderSyncService
    /// Retained here so `setupNetworkSync()` can reach `mainContext` on reconnect.
    var modelContainer: ModelContainer?
    private let defaults = UserDefaults.standard
    let remindersSyncService = AppleRemindersSyncService()
    let remindersSyncState = RemindersSyncState()
    var showsAssistantPanel = false
    var isSyncingSharedFolders = false

    /// Thread IDs for which the verification code has already been auto-copied
    /// in this session. Prevents `MacEmailThreadView` from re-copying every
    /// time the user re-opens the same verification email. Resets on relaunch.
    var autoCopiedVerificationThreads: Set<String> = []

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

    /// City/country (e.g. "Oslo, Norway") — piped into the server-side AI profile
    /// so the assistant has location context without the user repeating it.
    var location: String {
        didSet {
            defaults.set(location, forKey: Keys.location)
        }
    }

    var assistantAutomationPolicy: AssistantAutomationPolicy {
        didSet {
            if let data = try? JSONEncoder().encode(assistantAutomationPolicy) {
                defaults.set(data, forKey: Keys.assistantAutomationPolicy)
            }
        }
    }

    /// Calendar visibility prefs — synced from `settings.get` and persisted
    /// locally for offline launches. Mirrors the iOS counterpart.
    var calendarPreferences: CalendarPreferences {
        didSet {
            if let data = try? JSONEncoder().encode(calendarPreferences) {
                defaults.set(data, forKey: Keys.calendarPreferences)
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

    /// True after the user has taken or skipped the optional product tour.
    /// Persists to UserDefaults so the tour appears exactly once per fresh install.
    var hasSeenWelcomeTour: Bool {
        didSet { defaults.set(hasSeenWelcomeTour, forKey: Keys.hasSeenWelcomeTour) }
    }

    /// True after the user has landed on the main app shell at least once.
    /// Returning users skip the welcome tour based on this flag.
    var hasReachedMainShell: Bool {
        didSet { defaults.set(hasReachedMainShell, forKey: Keys.hasReachedMainShell) }
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

    /// User-facing master switch for the voice assistant. Off → no hotkey
    /// registration, no wake-word listener, no global mic. On → at minimum
    /// the global hotkey is registered.
    var voiceAssistantEnabled: Bool {
        didSet {
            defaults.set(voiceAssistantEnabled, forKey: Keys.voiceAssistantEnabled)
            applyVoiceAssistantState()
        }
    }

    /// Whether the always-listening wake word is enabled. Independent of the
    /// hotkey: a user can keep voice on with hotkey-only and never enable wake.
    var voiceWakeWordEnabled: Bool {
        didSet {
            defaults.set(voiceWakeWordEnabled, forKey: Keys.voiceWakeWordEnabled)
            applyVoiceAssistantState()
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
        self.location = defaults.string(forKey: Keys.location) ?? ""
        self.startupView = defaults.string(forKey: Keys.startupView) ?? "home"
        self.restoreLastViewedPage = defaults.object(forKey: Keys.restoreLastViewedPage) as? Bool ?? false
        self.hasConfiguredGmailPrompt = defaults.bool(forKey: Keys.hasConfiguredGmailPrompt)
        self.hasConfiguredCalendarPrompt = defaults.bool(forKey: Keys.hasConfiguredCalendarPrompt)
        self.hasConfiguredRemindersPrompt = defaults.bool(forKey: Keys.hasConfiguredRemindersPrompt)
        self.hasConfiguredStartupViewPrompt = defaults.bool(forKey: Keys.hasConfiguredStartupViewPrompt)
        self.hasConfiguredNotificationsPrompt = defaults.bool(forKey: Keys.hasConfiguredNotificationsPrompt)
        self.hasConfiguredDefaultMailPrompt = defaults.bool(forKey: Keys.hasConfiguredDefaultMailPrompt)
        // Welcome-tour gate — returning users (who already reached the main
        // shell) get migrated to "seen" so the new tour doesn't ambush them.
        let reachedShellBefore = defaults.bool(forKey: Keys.hasReachedMainShell)
        let storedTourFlag = defaults.bool(forKey: Keys.hasSeenWelcomeTour)
        self.hasSeenWelcomeTour = storedTourFlag || reachedShellBefore
        if !storedTourFlag && reachedShellBefore {
            defaults.set(true, forKey: Keys.hasSeenWelcomeTour)
        }
        self.hasReachedMainShell = reachedShellBefore
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
        if let data = defaults.data(forKey: Keys.calendarPreferences),
           let saved = try? JSONDecoder().decode(CalendarPreferences.self, from: data) {
            self.calendarPreferences = saved
        } else {
            self.calendarPreferences = .default
        }
        self.developerModeEnabled = defaults.bool(forKey: Keys.developerModeEnabled)
        // Voice assistant prefs default OFF — the always-on mic is opt-in.
        self.voiceAssistantEnabled = defaults.object(forKey: Keys.voiceAssistantEnabled) as? Bool ?? false
        // Wake-word toggle is "Coming soon" — `WakeWordService` is a Phase 1
        // stub that fails soft and never actually fires. We force the
        // persisted preference to false on launch so users who toggled it on
        // before the deprecation don't see a stale "on" state in Settings.
        // Restore the real preference once Porcupine integration ships.
        self.voiceWakeWordEnabled = false
        defaults.set(false, forKey: Keys.voiceWakeWordEnabled)
        self.aiChatService = MacAIChatService(
            backendURL: backendURL,
            apiClient: api,
            authService: auth,
            emailService: email,
            calendarService: calendar
        )
        self.voiceTokenService = VoiceTokenService(authService: auth, backendURL: backendURL)
        let promptClient = VoiceSystemPromptClient(authService: auth, backendURL: backendURL)
        self.voiceSystemPromptClient = promptClient
        let broker = AudioInputBroker()
        self.audioInputBroker = broker
        let hotkey = HotkeyService()
        self.hotkeyService = hotkey
        let wake = WakeWordService(broker: broker)
        self.wakeWordService = wake
        self.voiceCoordinator = VoiceSessionCoordinator(
            tokenService: self.voiceTokenService,
            systemPromptClient: promptClient,
            chatService: self.aiChatService,
            apiClient: api,
            inputBroker: broker,
            hotkey: hotkey,
            wakeService: wake
        )
        self.shareConversationService = ShareConversationService(apiClient: api)
        self.groupChatService = GroupChatService(apiClient: api)
        self.meetingsService = MeetingsService(apiClient: api)
        let connections = ConnectionsService(api: api)
        self.connectionsService = connections
        let googleCalendar = GoogleCalendarService(api: api)
        self.googleCalendarService = googleCalendar
        self.unifiedCalendarService = UnifiedCalendarService(
            calendarService: calendar,
            googleService: googleCalendar,
            connectionsService: connections
        )
        self.subscriptionService = MacSubscriptionService(apiClient: api)
        self.docsService = MacDocsService(apiClient: api)
        self.draftService = MacDraftService(api: api)
        self.localModelStateStore = LocalModelStateStore()
        self.appleFoundationModelService = AppleFoundationModelService()
        let ollamaConnector = OllamaConnector()
        self.ollamaConnector = ollamaConnector
        self.ollamaInferenceService = OllamaInferenceService(connector: ollamaConnector)
        self.huggingFaceCacheConnector = HuggingFaceCacheConnector()
        let mlxService = MLXInferenceService()
        self.mlxInferenceService = mlxService
        self.modelDownloadService = ModelDownloadService(
            stateStore: self.localModelStateStore,
            inferenceService: mlxService
        )
        // Wire local runtimes into the chat service so it can short-circuit
        // /api/ai/chat when the selected model is on-device.
        self.aiChatService.appleFoundationModelService = self.appleFoundationModelService
        self.aiChatService.mlxInferenceService = mlxService
        self.aiChatService.ollamaInferenceService = self.ollamaInferenceService
        self.taskSyncService = TaskSyncService(apiClient: api)
        self.folderSyncService = FolderSyncService(apiClient: api)
        self.aiChatService.contextAboutYou = contextAboutYou
        self.aiChatService.customInstructions = customInstructions
        self.remindersSyncState.isEnabled = self.remindersSyncEnabled
        self.remindersSyncState.direction = self.remindersSyncDirection

        // Hydrate the avatar URL cache off-main so the first inbox row body
        // evaluation doesn't synchronously decode up to 5000 JSON entries.
        // Without this, avatars on cold start stall behind the disk read and
        // every row paints initials → real avatar instead of going straight to
        // the cached URL.
        Task { @MainActor in await MacAvatarCache.shared.bootstrap() }
    }

    /// Reflect the current `voiceAssistantEnabled` / `voiceWakeWordEnabled`
    /// settings into the live coordinator. Called from the prefs setters AND
    /// once at the end of init so the user's saved state is restored on
    /// launch.
    ///
    /// Hotkey is registered whenever the master switch is on, regardless of
    /// the wake-word toggle — push-to-talk is the always-available baseline.
    /// Wake registration only runs when both flags are on.
    func applyVoiceAssistantState() {
        // Guard against early defaults-driven invocations that happen before
        // `TodusMacApp.initializeApp()` has wired the SwiftData container into the
        // coordinator. Starting voice without a context means tool calls
        // (create_task, complete_task, etc.) can't mutate anything — and the
        // hotkey/wake-word listeners would fire into a half-initialized session.
        // `initializeApp` calls this again once `modelContext` is set, so we don't
        // miss the user's saved state.
        guard voiceCoordinator.modelContext != nil else { return }
        if voiceAssistantEnabled {
            voiceCoordinator.start(enableWakeWord: voiceWakeWordEnabled)
        } else {
            Task { await voiceCoordinator.stop() }
        }
    }

    func loadSharedAIProfile() async {
        guard authService.isAuthenticated else { return }

        do {
            let response: MailAssistantSettingsResponse = try await apiClient.trpcQuery("settings.get")
            contextAboutYou = response.settings.contextAboutYou
            customInstructions = response.settings.customPrompt
            location = response.settings.location ?? ""
            assistantAutomationPolicy = response.settings.assistantAutomationPolicy
            if let prefs = response.settings.calendarPreferences {
                calendarPreferences = prefs
            }
            // Hydrate cross-device synced fields into UserDefaults so @AppStorage
            // bindings in MacSettingsView reflect the server state on next render.
            let defaults = UserDefaults.standard
            if let v = response.settings.aiCanReadTasks       { defaults.set(v, forKey: "mac_ai_can_read_tasks") }
            if let v = response.settings.aiCanWriteTasks      { defaults.set(v, forKey: "mac_ai_can_write_tasks") }
            if let v = response.settings.aiCanReadCalendar    { defaults.set(v, forKey: "ai_can_read_calendar") }
            if let v = response.settings.aiCanWriteCalendar   { defaults.set(v, forKey: "ai_can_write_calendar") }
            if let v = response.settings.aiCanReadEmail       { defaults.set(v, forKey: "ai_can_read_email") }
            if let v = response.settings.aiCanSendEmail       { defaults.set(v, forKey: "ai_can_send_email") }
            if let v = response.settings.accentColor          { defaults.set(v, forKey: "mac_accent_color") }
            if let v = response.settings.defaultTaskView      { defaults.set(v, forKey: "TaskApp.selectedViewMode") }
            if let v = response.settings.compactSidebar       { defaults.set(v, forKey: "mac_compact_sidebar") }
            if let v = response.settings.showUnreadBadge      { defaults.set(v, forKey: "mac_show_unread_badge") }
            if let v = response.settings.focusModeEnabled     { defaults.set(v, forKey: "mac_focus_mode_enabled") }
            if let v = response.settings.groupByThread        { defaults.set(v, forKey: "threadGroupingEnabled") }
            if let v = response.settings.aiTone               { defaults.set(v, forKey: "mac_ai_tone") }
            if let v = response.settings.taskRemindersEnabled  { defaults.set(v, forKey: "taskRemindersEnabled") }
            if let v = response.settings.calendarRemindersEnabled { defaults.set(v, forKey: "calendarRemindersEnabled") }
        } catch {
            AppLogger.shared.log("[MacAppServices] Failed to load shared AI profile: \(error)")
        }
    }

    /// Push a single user-settings field to the backend via `settings.save`.
    /// Mirrors iOS AppServices.syncSetting; used by per-toggle bindings in
    /// MacSettingsView to keep all surfaces aligned.
    func syncSetting<T: Encodable>(_ key: String, _ value: T) async {
        guard authService.isAuthenticated else { return }
        do {
            let _: SharedAIProfileSaveResponse = try await apiClient.trpcMutation(
                "settings.save",
                input: MacSingleSettingInput(key: key, value: value)
            )
        } catch {
            AppLogger.shared.log("[MacAppServices] Failed to sync setting \(key): \(error)")
        }
    }

    /// Builds the full settings shape from the current in-memory state. Both
    /// `saveSharedAIProfile()` and `saveCalendarPreferences()` send the SAME full
    /// shape, so a save of one section can never partial-wipe another section that
    /// the user has separately edited (e.g. saving `calendarPreferences` no longer
    /// loses an in-flight `customInstructions` edit, and vice versa).
    private func currentSettingsInput() -> SettingsSaveInput {
        SettingsSaveInput(
            contextAboutYou: contextAboutYou,
            customPrompt: customInstructions,
            location: location,
            assistantAutomationPolicy: assistantAutomationPolicy,
            calendarPreferences: calendarPreferences
        )
    }

    func saveSharedAIProfile() async {
        guard authService.isAuthenticated else { return }

        do {
            let _: SharedAIProfileSaveResponse = try await apiClient.trpcMutation(
                "settings.save",
                input: currentSettingsInput()
            )
        } catch {
            AppLogger.shared.log("[MacAppServices] Failed to save shared AI profile: \(error)")
        }
    }

    /// Push current `calendarPreferences` to the backend.
    func saveCalendarPreferences() async {
        guard authService.isAuthenticated else { return }
        do {
            let _: SharedAIProfileSaveResponse = try await apiClient.trpcMutation(
                "settings.save",
                input: currentSettingsInput()
            )
        } catch {
            AppLogger.shared.log("[MacAppServices] Failed to save calendar preferences: \(error)")
        }
    }

    /// Toggle a calendar's visibility (composite id) and push to server.
    func toggleCalendarVisibility(_ id: String) {
        var prefs = calendarPreferences
        var hidden = prefs.hiddenIdSet
        if hidden.contains(id) { hidden.remove(id) } else { hidden.insert(id) }
        prefs.hiddenCalendarIds = Array(hidden)
        calendarPreferences = prefs
        Task { await saveCalendarPreferences() }
    }

    /// Set the default calendar for a given account key (`apple` or `google:{connId}`).
    func setDefaultCalendar(_ id: String?, forAccountKey accountKey: String) {
        var prefs = calendarPreferences
        if let id {
            prefs.defaultCalendarByAccount[accountKey] = id
        } else {
            prefs.defaultCalendarByAccount.removeValue(forKey: accountKey)
        }
        calendarPreferences = prefs
        Task { await saveCalendarPreferences() }
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
                // Preserve `createdAt` from the local record. Overwriting from remote
                // caused sidebar flicker on every sync because the SwiftData diff
                // touched the field on every refresh (servers may return a
                // re-serialized timestamp with sub-second drift).
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
            // API failed (offline or transient error) — enqueue an upsert so the
            // folders.sync endpoint retries this on the next reconnect.
            await folderSyncService.enqueue(.upsert(
                id: folder.id.uuidString,
                name: folder.name,
                color: folder.colorHex,
                icon: folder.iconName,
                position: folder.position
            ))
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
            // API failed — enqueue an upsert so folders.sync retries on reconnect.
            await folderSyncService.enqueue(.upsert(
                id: folder.id.uuidString,
                name: folder.name,
                color: folder.colorHex,
                icon: folder.iconName,
                position: folder.position
            ))
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
            // API failed — enqueue a delete so folders.sync retries on reconnect.
            await folderSyncService.enqueue(.delete(id: id))
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

    /// Wires the network reconnect callback to flush any pending/failed task, folder, and
    /// draft mutations. Call this once after both `MacAppServices` and the `ModelContainer`
    /// are ready.
    func setupNetworkSync() {
        networkMonitor.onReconnect = { [weak self] in
            self?.flushPendingSync()
        }
        // Run per-user teardown for EVERY sign-out, including the automatic
        // session-expiry paths inside AuthService that call `authService.signOut()`
        // directly (those previously bypassed this cleanup, leaving stale email
        // threads / queued mutations / AI history under the next account).
        authService.onSignOut = { [weak self] in
            self?.performSignOutCleanup()
        }
    }

    /// Flushes any pending/failed task, folder, and draft mutations to the
    /// backend. Previously this only ran on network reconnect — so a task
    /// created or edited during a normal, already-online session was marked
    /// `.pendingUpload` and then never uploaded (silent data loss, and the
    /// "changes sync when reconnected" banner was a false promise). Now also
    /// called on app launch and when the app returns to the foreground.
    func flushPendingSync() {
        guard let context = modelContainer?.mainContext else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.taskSyncService.retryUnsyncedTasks(in: context)
            await self.folderSyncService.retryPending()
            await self.draftService.flushPending(in: context)
        }
    }

    /// Applies task completions queued from a widget's "complete" button (handed
    /// off via the App Group) to SwiftData and queues them for sync. The widget
    /// AppIntent can't touch SwiftData directly, so this is where the tap takes
    /// effect. Called on launch + foreground.
    func drainWidgetTaskCompletions() {
        guard let context = modelContainer?.mainContext else { return }
        let ids = WidgetSnapshotStore.shared.consumePendingCompletions()
        guard !ids.isEmpty else { return }
        var changed = false
        for idString in ids {
            guard let uuid = UUID(uuidString: idString) else { continue }
            let descriptor = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == uuid })
            guard let task = (try? context.fetch(descriptor))?.first, !task.completed else { continue }
            task.status = .done
            task.completed = true
            task.updatedAt = .now
            task.syncState = .pendingUpload
            changed = true
        }
        if changed {
            try? context.save()
            flushPendingSync()
        }
    }

    /// Reconciles all local task reminders against the current SwiftData task set and
    /// (re)builds the due-today digest. macOS has no central task-capture service (tasks
    /// are mutated directly across views), so we reconcile the whole set at launch and on
    /// foreground rather than hooking every mutation site. Gated by the "Task Due
    /// Reminders" setting (`taskRemindersEnabled`, default on). Requests notification
    /// authorization on first run when reminders are enabled but permission is undetermined.
    func reconcileTaskReminders() {
        guard let context = modelContainer?.mainContext else { return }
        // Default true mirrors the Settings toggle (`@AppStorage("taskRemindersEnabled") = true`).
        let enabled = defaults.object(forKey: "taskRemindersEnabled") as? Bool ?? true
        let tasks: [TaskRecord]
        do {
            tasks = try context.fetch(FetchDescriptor<TaskRecord>())
        } catch {
            AppLogger.shared.log("[MacAppServices] reconcileTaskReminders fetch failed: \(error)")
            return
        }
        let snapshots = tasks.map { task in
            MacNotificationService.TaskReminderSnapshot(
                taskID: task.id.uuidString,
                title: task.title,
                dueDate: task.dueDate,
                completed: task.completed
            )
        }
        Task { @MainActor [notificationService] in
            // First-run permission: if reminders are on but we've never asked, request now
            // so the very first scheduled reminder can actually fire.
            if enabled {
                await notificationService.checkAuthorization()
                if !notificationService.isAuthorized {
                    _ = await notificationService.requestPermission()
                }
            }
            await notificationService.reconcileTaskReminders(snapshots, enabled: enabled)
        }
    }

    func signOut() {
        // Cleanup runs via `authService.onSignOut` (wired in setupNetworkSync) so
        // both this manual path and AuthService's automatic session-expiry
        // sign-outs get the same teardown. `onSignOut` fires at the start of
        // `authService.signOut()`, before auth state is cleared.
        authService.signOut()
        closeSettingsWindowIfPresent()
    }

    /// Per-user teardown shared by manual and automatic sign-out. Idempotent.
    private func performSignOutCleanup() {
        // Clear in-memory sync queues so a reconnect after re-login does not
        // replay the previous user's offline mutations under the new session.
        taskSyncService.clearQueue()
        folderSyncService.clearQueue()
        emailService.resetForSignOut()
        aiChatService.resetForSignOut()
        // Tear down voice triggers so the new user's hotkey/wake start fresh.
        Task { await voiceCoordinator.stop() }
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

/// Full settings shape sent to `settings.save`. Always send every field we know
/// about so that a save of one section (e.g. calendar prefs) can never partial-wipe
/// another section (e.g. AI custom instructions) on the backend.
private struct SettingsSaveInput: Encodable {
    let contextAboutYou: String
    let customPrompt: String
    let location: String
    let assistantAutomationPolicy: AssistantAutomationPolicy
    let calendarPreferences: CalendarPreferences
}

private struct SharedAIProfileSaveResponse: Decodable {
    let success: Bool
}
