import Foundation
import Observation
import SwiftData
import SwiftUI


/// AI response tone preference — injected into the system prompt.
enum AITonePreference: String, CaseIterable, Identifiable, Sendable {
    case professional
    case casual
    case concise

    var id: String { rawValue }

    var title: String {
        switch self {
        case .professional: return "Professional"
        case .casual: return "Casual"
        case .concise: return "Concise"
        }
    }

    /// Instruction appended to the AI system prompt to set the response tone.
    var systemPromptInstruction: String {
        switch self {
        case .professional: return "Respond in a professional, clear tone."
        case .casual: return "Respond in a friendly, casual tone."
        case .concise: return "Respond as concisely as possible. Use short sentences and bullet points."
        }
    }
}

enum AppAppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

@MainActor
@Observable
final class AppServices {
    private enum Keys {
        static let appearancePreference = "TaskApp.appearancePreference"
        static let developerModeEnabled = "TaskApp.developerModeEnabled"
        static let preferredStartViewMode = "TaskApp.preferredStartViewMode"
        static let remindersSyncEnabled = "TaskApp.remindersSyncEnabled"
        static let hasConfiguredRemindersPrompt = "TaskApp.hasConfiguredRemindersPrompt"
        static let hasConfiguredGmailPrompt = "TaskApp.hasConfiguredGmailPrompt"
        static let remindersSyncDirection = "TaskApp.remindersSyncDirection"
        // Legacy keys — kept for migration only (v1 had a single text field)
        static let signatureEnabled = "TaskApp.signatureEnabled"
        static let signatureText = "TaskApp.signatureText"
        // New keys (v2 — array of signatures + selected ID)
        static let emailSignatures = "TaskApp.emailSignatures"
        static let selectedSignatureID = "TaskApp.selectedSignatureID"
        static let swipeGesturesEnabled = "TaskApp.swipeGesturesEnabled"
        static let threadGroupingEnabled = "TaskApp.threadGroupingEnabled"
        static let aiTonePreference = "TaskApp.aiTonePreference"
        static let taskRemindersEnabled = "TaskApp.taskRemindersEnabled"
        static let calendarRemindersEnabled = "TaskApp.calendarRemindersEnabled"
        static let contextAboutYou = "TaskApp.contextAboutYou"
        static let customInstructions = "TaskApp.customInstructions"
        static let assistantAutomationPolicy = "TaskApp.assistantAutomationPolicy"
        static let calendarPreferences = "TaskApp.calendarPreferences"
        static let tabBarTabs = "TaskApp.tabBarTabs"
        static let hasConfiguredTabBarPrompt = "TaskApp.hasConfiguredTabBarPrompt"
        static let hasConfiguredNotificationsPrompt = "TaskApp.hasConfiguredNotificationsPrompt"
        static let hasConfiguredDefaultMailPrompt = "TaskApp.hasConfiguredDefaultMailPrompt"
        static let emailNotificationsEnabled = "TaskApp.emailNotificationsEnabled"
    }

    let configuration: AppConfiguration

    // Unified auth — replaces old AuthSessionStore for new Better-Auth flow
    let authService: AuthService
    // Unified HTTP client for all backend API calls
    let apiClient: TodosAPIClient

    let emailService: EmailService
    let calendarService: CalendarService
    /// Multi-account connections service — manages connected email accounts and filter state
    let connectionsService: ConnectionsService
    /// Backend Google Calendar integration — fetches per-connection calendars and events.
    let googleCalendarService: GoogleCalendarService
    /// Aggregator that merges Apple (EventKit) + Google (backend) events with
    /// per-source visibility from `calendarPreferences`.
    let unifiedCalendarService: UnifiedCalendarService
    let networkMonitor: NetworkMonitor
    let notificationService: NotificationService

    /// Set by the app entry point after SwiftData container initialisation.
    /// Used by reconnect handlers that need a ModelContext without a SwiftUI environment.
    var modelContainer: ModelContainer?

    // Legacy services — kept during migration, will be removed once task sync is fully on new backend
    let authStore: AuthSessionStore
    let syncService: SupabaseSyncService
    let remindersSyncService: AppleRemindersSyncService
    let remindersSyncState: RemindersSyncState
    let captureService: TaskCaptureService
    /// AI chat service — manages streaming conversation and task mutations
    let aiChatService: AIChatService
    /// Share conversation service — creates and manages public/protected share links
    let shareConversationService: ShareConversationService
    /// Group chat service — multi-user rooms with AI participation
    let groupChatService: GroupChatService
    /// Voice endpoint service — provides the backend WS proxy URL (API key stays server-side)
    let voiceTokenService: VoiceTokenService
    /// Meetings service — fetches/syncs meetings from backend
    let meetingsService: MeetingsService
    /// Cached subscription / AI-usage state. Refreshed on app launch and after billing actions.
    let subscriptionService: SubscriptionService
    /// Wraps drafts.update + mail.send for the AI chat's InlineComposeCard.
    let draftService: DraftService
    /// Tracks per-model install state for the Local Models settings screen and
    /// the chat composer's local-runtime routing. Disk scan runs on init.
    let localModelStateStore: LocalModelStateStore
    /// Apple Intelligence on-device LLM (iOS 26+). Routed to when the
    /// selected model has `runtime == .appleFM`.
    let appleFoundationModelService: AppleFoundationModelService
    /// MLX-Swift inference (Apple Silicon). Loads quantized weights from the
    /// HuggingFace cache populated by `modelDownloadService`.
    let mlxInferenceService: MLXInferenceService
    /// Orchestrates HuggingFace downloads + deletions for MLX models. Bridges
    /// progress into `localModelStateStore` for the Settings UI.
    let modelDownloadService: ModelDownloadService
    /// Offline-capable queue for folder create/update/delete mutations.
    let folderSyncService: FolderSyncService
    private let defaults: UserDefaults
    private var isLoadingSharedProfile = false
    private var lastSharedProfileLoadAt: Date?
    private let sharedProfileRefreshInterval: TimeInterval = 60

    var selectedViewMode: TaskViewMode
    var selectedFolderID: UUID?
    var showsSettings = false

    /// Current tab — updated by MainTabView so AI suggestions can be context-aware.
    var currentTab: AppTab = .home

    /// Set this to navigate the tab bar from any view (e.g. HomeView → tasks tab).
    /// MainTabView observes this and resets it to nil after switching.
    var navigateTo: AppTab? = nil

    /// Set by child views (e.g. HomeView) to request opening CreateSheet with a specific type.
    /// MainTabView observes this and resets it to nil after presenting.
    var requestCreateSheet: CreateItemType? = nil

    /// Surfaced when a notification action (complete / snooze) fails on the next app open.
    /// Cleared by views once shown to the user. Plain text — render in a banner or alert.
    var pendingNotificationActionError: String? = nil

    /// Set true to trigger the global email compose sheet from MainTabView.
    var showsComposeEmail = false
    var composeEmailSeedBody: String? = nil
    var composeEmailSeedTo: String? = nil
    var composeEmailSeedSubject: String? = nil
    /// Filenames (already saved by AttachmentService) carried into a fresh
    /// EmailComposeView. Surfaced as chips so the user keeps a record even
    /// though the send pipeline does not yet upload binary attachments.
    var composeEmailSeedAttachments: [String] = []
    var showsAIChat = false

    /// Set by detail views (e.g. EmailThreadView) to hide the custom floating tab bar
    /// so their own bottom bar is visible. Reset to false on dismiss.
    var hideTabBar = false

    // MARK: - Header Menu Signals
    // Tick counters incremented by the AppTopHeader ellipsis menu so each tab's view
    // can react to a contextual action (refresh, sync, etc.) it owns local state for.
    var homeRefreshTick: Int = 0
    var tasksSyncRemindersTick: Int = 0
    var tasksClearCompletedTick: Int = 0
    var emailRefreshTick: Int = 0
    var emailMarkAllReadTick: Int = 0
    var calendarRefreshTick: Int = 0
    var calendarGoToTodayTick: Int = 0
    /// Set by the header to request a calendar view-mode switch from outside CalendarTabView.
    /// CalendarTabView observes and resets to nil after applying.
    var calendarRequestedViewMode: CalendarViewMode? = nil

    // MARK: - Deep Navigation (from AI chat cards → specific items)
    /// Set by AI chat card taps to navigate to a specific email thread after dismissing the sheet.
    var pendingEmailThreadId: String? = nil
    /// Set by AI chat card taps to navigate to a specific task after dismissing the sheet.
    var pendingTaskId: UUID? = nil
    var appearancePreference: AppAppearancePreference {
        didSet {
            defaults.set(appearancePreference.rawValue, forKey: Keys.appearancePreference)
        }
    }
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

    var preferredStartViewMode: TaskViewMode {
        didSet {
            defaults.set(preferredStartViewMode.rawValue, forKey: Keys.preferredStartViewMode)
        }
    }
    var remindersSyncEnabled: Bool {
        didSet {
            remindersSyncState.isEnabled = remindersSyncEnabled
            defaults.set(remindersSyncEnabled, forKey: Keys.remindersSyncEnabled)
        }
    }
    /// Whether the user has dismissed the "Connect Apple Reminders" onboarding prompt.
    var hasConfiguredRemindersPrompt: Bool {
        didSet { defaults.set(hasConfiguredRemindersPrompt, forKey: Keys.hasConfiguredRemindersPrompt) }
    }

    /// Whether the user has been shown the "Connect Gmail" onboarding step (after Reminders).
    var hasConfiguredGmailPrompt: Bool {
        didSet { defaults.set(hasConfiguredGmailPrompt, forKey: Keys.hasConfiguredGmailPrompt) }
    }

    /// Legacy onboarding flag for the hidden floating tab-bar customization step.
    /// Forced to `true` so users never see the retired step again.
    var hasConfiguredTabBarPrompt: Bool {
        didSet { defaults.set(hasConfiguredTabBarPrompt, forKey: Keys.hasConfiguredTabBarPrompt) }
    }

    /// Whether the user has seen the notifications permission onboarding step.
    var hasConfiguredNotificationsPrompt: Bool {
        didSet { defaults.set(hasConfiguredNotificationsPrompt, forKey: Keys.hasConfiguredNotificationsPrompt) }
    }

    /// Whether the user has seen the "set as default mail app" onboarding step.
    var hasConfiguredDefaultMailPrompt: Bool {
        didSet { defaults.set(hasConfiguredDefaultMailPrompt, forKey: Keys.hasConfiguredDefaultMailPrompt) }
    }

    /// Whether to show local notifications for new incoming emails.
    var emailNotificationsEnabled: Bool {
        didSet { defaults.set(emailNotificationsEnabled, forKey: Keys.emailNotificationsEnabled) }
    }

    /// Legacy configuration for the hidden floating tab bar. Max 4, home is always first.
    /// Persisted so the retired UI can be restored later without losing state.
    var tabBarTabs: [AppTab] {
        didSet {
            let raw = tabBarTabs.map(\.rawValue)
            if let data = try? JSONEncoder().encode(raw) {
                defaults.set(data, forKey: Keys.tabBarTabs)
            }
        }
    }

    /// Present a non-tab-bar page as a full-screen sheet from MainTabView.
    /// Set this from any child view (e.g. HomeView "View all" → .meetings).
    var navigateToSheet: AppTab? = nil

    /// Reminders sync direction: "twoWay" (default), "toReminders", "fromReminders"
    var remindersSyncDirection: RemindersSyncDirection {
        didSet {
            remindersSyncState.direction = remindersSyncDirection
            defaults.set(remindersSyncDirection.rawValue, forKey: Keys.remindersSyncDirection)
        }
    }

    /// All user-created signatures, persisted as JSON.
    var signatures: [EmailSignature] {
        didSet {
            do {
                let data = try JSONEncoder().encode(signatures)
                defaults.set(data, forKey: Keys.emailSignatures)
            } catch {
                // Log encoding failure so we can diagnose signature persistence issues
                print("[AppServices] Failed to encode signatures: \(error)")
            }
        }
    }

    /// ID of the currently active signature (nil = no signature).
    var selectedSignatureID: UUID? {
        didSet {
            defaults.set(selectedSignatureID?.uuidString, forKey: Keys.selectedSignatureID)
        }
    }

    /// The currently active signature, if any. Used by the email composer.
    var activeSignature: EmailSignature? {
        signatures.first { $0.id == selectedSignatureID }
    }

    /// Backward-compat computed: true when any signature is selected.
    var signatureEnabled: Bool { selectedSignatureID != nil }

    var swipeGesturesEnabled: Bool {
        didSet { defaults.set(swipeGesturesEnabled, forKey: Keys.swipeGesturesEnabled) }
    }

    var threadGroupingEnabled: Bool {
        didSet { defaults.set(threadGroupingEnabled, forKey: Keys.threadGroupingEnabled) }
    }

    /// AI response tone — injected into the AI system prompt
    var aiTonePreference: AITonePreference {
        didSet {
            defaults.set(aiTonePreference.rawValue, forKey: Keys.aiTonePreference)
            aiChatService.toneInstruction = aiTonePreference.systemPromptInstruction
        }
    }

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

    /// Calendar visibility prefs — synced from `settings.get` and persisted
    /// locally for offline launches. Mutate in-memory and call
    /// `saveCalendarPreferences()` to push to the server.
    var calendarPreferences: CalendarPreferences {
        didSet {
            if let data = try? JSONEncoder().encode(calendarPreferences) {
                defaults.set(data, forKey: Keys.calendarPreferences)
            }
        }
    }

    /// Whether local notifications are scheduled for task due dates
    var taskRemindersEnabled: Bool {
        didSet {
            defaults.set(taskRemindersEnabled, forKey: Keys.taskRemindersEnabled)
            captureService.taskRemindersEnabled = taskRemindersEnabled
        }
    }

    /// Whether local notifications are scheduled for calendar events
    var calendarRemindersEnabled: Bool {
        didSet { defaults.set(calendarRemindersEnabled, forKey: Keys.calendarRemindersEnabled) }
    }

    init(configuration: AppConfiguration = .load(), defaults: UserDefaults = .standard) {
        let trace = PerformanceTrace.beginInterval(PerformanceTrace.appServicesInit, message: "AppServices.init start")
        defer {
            PerformanceTrace.endInterval(
                PerformanceTrace.appServicesInit,
                trace,
                message: "AppServices.init end"
            )
        }

        self.configuration = configuration
        self.defaults = defaults

        // New unified services — Better-Auth backend
        // Uses local dev server (localhost:8787) when useLocalBackend is enabled
        let backendURL = configuration.effectiveBackendURL
        let authService = AuthService(backendURL: backendURL)
        self.authService = authService
        let apiClient = TodosAPIClient(baseURL: backendURL, authService: authService)
        self.apiClient = apiClient
        self.emailService = EmailService(api: apiClient)
        let calendarService = CalendarService()
        self.calendarService = calendarService
        let connectionsService = ConnectionsService(api: apiClient)
        self.connectionsService = connectionsService
        let googleCalendarService = GoogleCalendarService(api: apiClient)
        self.googleCalendarService = googleCalendarService
        self.unifiedCalendarService = UnifiedCalendarService(
            calendarService: calendarService,
            googleService: googleCalendarService,
            connectionsService: connectionsService
        )
        self.networkMonitor = NetworkMonitor()
        self.notificationService = NotificationService()

        // Legacy services — still used for task sync during migration
        self.authStore = AuthSessionStore(configuration: configuration)
        self.syncService = SupabaseSyncService(configuration: configuration, authStore: authStore)
        self.remindersSyncService = AppleRemindersSyncService()
        self.remindersSyncState = RemindersSyncState()

        let folderSyncService = FolderSyncService(apiClient: apiClient)
        self.folderSyncService = folderSyncService

        let captureService = TaskCaptureService(
            parser: RemoteFirstTaskParsingService(configuration: configuration),
            syncService: syncService,
            authStore: authStore,
            remindersSyncService: remindersSyncService,
            remindersSyncState: remindersSyncState,
            apiClient: apiClient,
            folderSyncService: folderSyncService
        )
        self.captureService = captureService
        captureService.notificationService = self.notificationService
        self.aiChatService = AIChatService(
            configuration: configuration,
            captureService: captureService,
            authService: authService,
            apiClient: apiClient,
            calendarService: calendarService,
            emailService: emailService
        )
        self.shareConversationService = ShareConversationService(apiClient: apiClient)
        self.groupChatService = GroupChatService(apiClient: apiClient)
        self.voiceTokenService = VoiceTokenService(authService: authService, backendURL: backendURL)
        self.meetingsService = MeetingsService(apiClient: apiClient)
        self.subscriptionService = SubscriptionService(apiClient: apiClient)
        self.draftService = DraftService(api: apiClient)
        self.localModelStateStore = LocalModelStateStore()
        self.appleFoundationModelService = AppleFoundationModelService()
        self.mlxInferenceService = MLXInferenceService()
        self.modelDownloadService = ModelDownloadService(
            stateStore: self.localModelStateStore,
            inferenceService: self.mlxInferenceService
        )
        // Wire local runtimes into the chat service so it can short-circuit
        // /api/ai/chat when the selected model is on-device.
        self.aiChatService.appleFoundationModelService = self.appleFoundationModelService
        self.aiChatService.mlxInferenceService = self.mlxInferenceService

        let storedAppearance = defaults.string(forKey: Keys.appearancePreference)
            .flatMap(AppAppearancePreference.init(rawValue:))
            ?? .system
        let storedStartView = defaults.string(forKey: Keys.preferredStartViewMode)
            .flatMap(TaskViewMode.init(rawValue:))
            ?? .list

        self.appearancePreference = storedAppearance
        self.developerModeEnabled = defaults.bool(forKey: Keys.developerModeEnabled)
        self.preferredStartViewMode = storedStartView
        self.remindersSyncEnabled = defaults.object(forKey: Keys.remindersSyncEnabled) as? Bool ?? false
        self.hasConfiguredRemindersPrompt = defaults.bool(forKey: Keys.hasConfiguredRemindersPrompt)
        self.hasConfiguredGmailPrompt = defaults.bool(forKey: Keys.hasConfiguredGmailPrompt)
        self.remindersSyncDirection = defaults.string(forKey: Keys.remindersSyncDirection)
            .flatMap(RemindersSyncDirection.init(rawValue:)) ?? .twoWay
        // Initialize selectedViewMode early — needed before self can be used in signature migration below
        self.selectedViewMode = storedStartView
        self.swipeGesturesEnabled = defaults.object(forKey: Keys.swipeGesturesEnabled) as? Bool ?? true
        self.threadGroupingEnabled = defaults.object(forKey: Keys.threadGroupingEnabled) as? Bool ?? true
        self.aiTonePreference = defaults.string(forKey: Keys.aiTonePreference)
            .flatMap(AITonePreference.init(rawValue:)) ?? .professional
        self.contextAboutYou = defaults.string(forKey: Keys.contextAboutYou) ?? ""
        self.customInstructions = defaults.string(forKey: Keys.customInstructions) ?? ""
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
        self.taskRemindersEnabled = defaults.object(forKey: Keys.taskRemindersEnabled) as? Bool ?? true
        self.calendarRemindersEnabled = defaults.object(forKey: Keys.calendarRemindersEnabled) as? Bool ?? true

        // Load signatures — migrate from old single-text format if no v2 data exists
        let loadedSignatures: [EmailSignature]
        if let data = defaults.data(forKey: Keys.emailSignatures),
           let saved = try? JSONDecoder().decode([EmailSignature].self, from: data) {
            loadedSignatures = saved
        } else {
            let oldText = defaults.string(forKey: Keys.signatureText) ?? ""
            let oldEnabled = defaults.bool(forKey: Keys.signatureEnabled)
            if oldEnabled && !oldText.isEmpty {
                let migrated = [EmailSignature(name: "Default", body: oldText)]
                loadedSignatures = migrated
                // Persist migrated signatures so we don't re-run migration on next launch
                if let data = try? JSONEncoder().encode(migrated) {
                    defaults.set(data, forKey: Keys.emailSignatures)
                }
            } else {
                loadedSignatures = []
            }
        }

        // Load selected signature ID — migrate from old signatureEnabled if needed
        let loadedSelectedSignatureID: UUID?
        if let uuidStr = defaults.string(forKey: Keys.selectedSignatureID),
           let uuid = UUID(uuidString: uuidStr) {
            loadedSelectedSignatureID = uuid
        } else {
            let oldEnabled = defaults.bool(forKey: Keys.signatureEnabled)
            let migratedID = (oldEnabled && !loadedSignatures.isEmpty) ? loadedSignatures.first?.id : nil
            loadedSelectedSignatureID = migratedID
            // Persist migrated selected ID so we don't re-run migration on next launch
            if let migratedID {
                defaults.set(migratedID.uuidString, forKey: Keys.selectedSignatureID)
            }
        }

        // Load tab bar tabs — decode from JSON [String] back to [AppTab]
        // Default to the 4-tab layout (home, tasks, email, calendar) on first launch.
        if let data = defaults.data(forKey: Keys.tabBarTabs),
           let rawValues = try? JSONDecoder().decode([String].self, from: data) {
            let decoded = rawValues.compactMap(AppTab.init(rawValue:))
            // Always ensure home is first and present; exclude action-only tabs; clamp to max 4
            var tabs = decoded.filter { $0 != .home && $0 != .create && $0 != .ai }
            tabs.insert(.home, at: 0)
            if decoded.isEmpty || tabs.count < 2 {
                self.tabBarTabs = AppTab.defaultNavTabs
            } else {
                // Burger is a fixed extra slot; max configurable tabs = 4
                self.tabBarTabs = Array(tabs.prefix(4))
            }
        } else {
            self.tabBarTabs = AppTab.defaultNavTabs
        }
        self.hasConfiguredTabBarPrompt = true
        defaults.set(true, forKey: Keys.hasConfiguredTabBarPrompt)
        self.hasConfiguredNotificationsPrompt = defaults.bool(forKey: Keys.hasConfiguredNotificationsPrompt)
        self.hasConfiguredDefaultMailPrompt = defaults.bool(forKey: Keys.hasConfiguredDefaultMailPrompt)
        self.emailNotificationsEnabled = defaults.object(forKey: Keys.emailNotificationsEnabled) as? Bool ?? true

        // Now assign to stored properties relying on self.
        self.signatures = loadedSignatures
        self.selectedSignatureID = loadedSelectedSignatureID
        self.remindersSyncState.isEnabled = self.remindersSyncEnabled
        self.remindersSyncState.direction = self.remindersSyncDirection

        Task { @MainActor [weak self] in
            guard let self else { return }
            // Defer AI prompt loading until after the initial shell is interactive.
            await Task.yield()
            self.aiChatService.loadSavedPrompts()
            self.aiChatService.toneInstruction = self.aiTonePreference.systemPromptInstruction
            self.aiChatService.contextAboutYou = self.contextAboutYou
            self.aiChatService.customInstructions = self.customInstructions
        }

        self.captureService.taskRemindersEnabled = self.taskRemindersEnabled
    }

    func selectFolder(_ folder: FolderRecord?) {
        selectedFolderID = folder?.id
    }

    func signOut() {
        // Clear in-memory sync queues so a reconnect after re-login does not
        // replay the previous user's offline mutations under the new session.
        folderSyncService.clearQueue()
        emailService.resetForSignOut()
        authService.signOut()
        authStore.signOutToGuest()
    }

    func setupNetworkSync() {
        networkMonitor.onReconnect = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let context = self.modelContainer?.mainContext else { return }
                await self.syncService.retryUnsyncedTasks(in: context)
                await self.folderSyncService.retryPending()
                await self.draftService.flushPending(in: context)
            }
        }
    }

    func loadSharedAIProfile() async {
        guard authService.isAuthenticated else { return }
        let now = Date()
        if isLoadingSharedProfile {
            return
        }
        if let lastSharedProfileLoadAt,
           now.timeIntervalSince(lastSharedProfileLoadAt) < sharedProfileRefreshInterval {
            return
        }

        isLoadingSharedProfile = true
        defer { isLoadingSharedProfile = false }
        do {
            let response: MailAssistantSettingsResponse = try await apiClient.trpcQuery("settings.get")
            contextAboutYou = response.settings.contextAboutYou
            customInstructions = response.settings.customPrompt
            assistantAutomationPolicy = response.settings.assistantAutomationPolicy
            if let prefs = response.settings.calendarPreferences {
                calendarPreferences = prefs
            }
            lastSharedProfileLoadAt = now
        } catch {
            print("[AppServices] Failed to load shared AI profile: \(error)")
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
            print("[AppServices] Failed to save shared AI profile: \(error)")
        }
    }

    /// Push the current `calendarPreferences` to the backend via `settings.save`.
    /// Optimistic updates: callers can mutate `calendarPreferences` in-place,
    /// then call this to sync — UI doesn't wait on the server.
    func saveCalendarPreferences() async {
        guard authService.isAuthenticated else { return }
        do {
            struct Input: Encodable {
                let calendarPreferences: CalendarPreferences
            }
            let _: SharedAIProfileSaveResponse = try await apiClient.trpcMutation(
                "settings.save",
                input: Input(calendarPreferences: calendarPreferences)
            )
        } catch {
            print("[AppServices] Failed to save calendar preferences: \(error)")
        }
    }

    /// Toggle a calendar's visibility (composite id like `apple:{...}` or `google:{...}:{...}`)
    /// and push the change to the server.
    func toggleCalendarVisibility(_ id: String) {
        var prefs = calendarPreferences
        var hidden = prefs.hiddenIdSet
        if hidden.contains(id) {
            hidden.remove(id)
        } else {
            hidden.insert(id)
        }
        prefs.hiddenCalendarIds = Array(hidden)
        calendarPreferences = prefs
        Task { await saveCalendarPreferences() }
    }

    /// Set the user's preferred default calendar id for a given account key
    /// (`apple` or `google:{connectionId}`). Pass nil to clear.
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

    func completeAuthUpgradeIfNeeded(in context: ModelContext) async {
        guard case .authenticated(let email) = authStore.authState else {
            return
        }
        await syncService.upgradeAnonymousUserIfNeeded(email: email, in: context)
    }

    func requestRemindersPermissionIfNeeded() async -> Bool {
        guard remindersSyncEnabled else { return false }
        switch remindersSyncService.authorizationState() {
        case .authorized:
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
        let trace = PerformanceTrace.beginInterval(
            PerformanceTrace.remindersSync,
            message: "Sync existing tasks to reminders begin"
        )
        let descriptor = FetchDescriptor<TaskRecord>()
        let tasks = (try? context.fetch(descriptor)) ?? []
        remindersSyncService.syncAllTasks(tasks, in: context)
        PerformanceTrace.endInterval(
            PerformanceTrace.remindersSync,
            trace,
            message: "Sync existing tasks to reminders end count=\(tasks.count)"
        )
    }

    /// Imports any Apple Reminders that aren't yet tracked as app tasks.
    /// Safe to call multiple times — skips reminders already linked via reminderIdentifier.
    func importFromReminders(in context: ModelContext) async {
        guard remindersSyncEnabled else { return }
        guard remindersSyncDirection != .toReminders else { return }
        let trace = PerformanceTrace.beginInterval(
            PerformanceTrace.remindersImport,
            message: "Import reminders begin"
        )
        await remindersSyncService.importFromReminders(in: context)
        PerformanceTrace.endInterval(
            PerformanceTrace.remindersImport,
            trace,
            message: "Import reminders end"
        )
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
