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

private struct _DynamicCodingKeys: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private struct _OneFieldInput<V: Encodable>: Encodable {
    let key: String
    let value: V
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: _DynamicCodingKeys.self)
        try container.encode(value, forKey: _DynamicCodingKeys(stringValue: key)!)
    }
}

@MainActor
@Observable
final class AppServices {
    private enum Keys {
        static let appearancePreference = "TaskApp.appearancePreference"
        static let accentPreference = "TaskApp.accentPreference"
        static let developerModeEnabled = "TaskApp.developerModeEnabled"
        static let preferredStartViewMode = "TaskApp.preferredStartViewMode"
        static let selectedViewMode = "TaskApp.selectedViewMode"
        static let taskSortOrder = "TaskApp.taskSortOrder"
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
        static let location = "TaskApp.location"
        static let assistantAutomationPolicy = "TaskApp.assistantAutomationPolicy"
        static let calendarPreferences = "TaskApp.calendarPreferences"
        static let tabBarTabs = "TaskApp.tabBarTabs"
        static let hasConfiguredTabBarPrompt = "TaskApp.hasConfiguredTabBarPrompt"
        static let hasConfiguredNotificationsPrompt = "TaskApp.hasConfiguredNotificationsPrompt"
        static let hasConfiguredDefaultMailPrompt = "TaskApp.hasConfiguredDefaultMailPrompt"
        static let emailNotificationsEnabled = "TaskApp.emailNotificationsEnabled"
        /// One-shot flag — true after the user has dismissed the branded startup card.
        /// Stored under a short key (no "TaskApp." prefix) because the task spec pins
        /// the UserDefaults key as `"hasSeenStartupCard"` exactly.
        static let hasSeenStartupCard = "hasSeenStartupCard"
        /// Positive proof the user reached the main tab at least once. Set in
        /// `MainTabView.onAppear`. Used by the startup-card migration as a
        /// reliable "returning user" signal — more trustworthy than checking
        /// any prior onboarding flag (which could be a transient skip) or a
        /// persisted Keychain bearer (Keychain survives uninstall on iOS).
        static let hasReachedMainTab = "TaskApp.hasReachedMainTab"
        /// One-shot flag — true after the user has either taken or skipped the
        /// optional product tour shown right before the tab-bar onboarding step.
        /// Stored separately from `hasSeenStartupCard` so the tour can be
        /// reintroduced without re-triggering the branded entry view.
        static let hasSeenWelcomeTour = "TaskApp.hasSeenWelcomeTour"
    }

    let configuration: AppConfiguration

    /// True when the host process was launched with `--ui-testing`. Guards
    /// background network bootstrap calls (refreshSession, loadConnections,
    /// AI snapshot fetches, shared profile load) so XCUITests get a
    /// deterministic launch without hitting the backend. Read by feature
    /// views via `services.isUITestingMode`.
    let isUITestingMode: Bool

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
    /// Voice endpoint service — provides the backend WS proxy URL (API key stays server-side)
    let voiceTokenService: VoiceTokenService
    /// Server-rendered system prompt (persona + Mem0 memories) for Gemini Live.
    /// Mirrors macOS — shared between the modal view-model and the AppIntent
    /// coordinator so both surfaces send the same context to the model.
    let voiceSystemPromptClient: VoiceSystemPromptClient
    /// Modal-less voice session driver, used by the Siri Shortcut intent and
    /// surfaced in Settings. The existing in-app modal still uses its own
    /// `VoiceChatViewModel`; both coordinate microphone ownership via
    /// `voiceMicLock` so a Shortcut firing while the modal is open does not
    /// start a second AVAudioEngine.
    let voiceSessionCoordinator: VoiceSessionCoordinator
    /// Cooperative mic lock shared by `voiceSessionCoordinator` and
    /// `VoiceChatViewModel`. Same class of fix as H17 (AVAudioEngine double-
    /// attach). Both call `acquire(owner:)` before starting capture and
    /// `release(owner:)` on stop.
    let voiceMicLock: VoiceMicLock
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
    /// Server-backed docs (`docs.*` tRPC). Used by the native iOS Docs shell.
    let docsService: DocsService
    private let defaults: UserDefaults
    private var isLoadingSharedProfile = false
    private var lastSharedProfileLoadAt: Date?
    private let sharedProfileRefreshInterval: TimeInterval = 60

    var selectedViewMode: TaskViewMode {
        didSet {
            defaults.set(selectedViewMode.rawValue, forKey: Keys.selectedViewMode)
        }
    }
    /// Persisted sort order for the Tasks tab list / board / table.
    /// Default is `.smart` (urgency-aware) — see `TaskSmartSort`.
    var taskSortOrder: TaskSortOrder {
        didSet {
            defaults.set(taskSortOrder.rawValue, forKey: Keys.taskSortOrder)
        }
    }
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

    /// Start date seeded into CreateSheet's event form when the user taps a
    /// specific time slot in the calendar grid. CreateSheet consumes it in
    /// onAppear and resets it to nil.
    var createSheetSeedDate: Date? = nil

    /// Search query carried from global search's "See all N in Mail" into the
    /// Email tab. EmailInboxView consumes it on appear and resets it to nil.
    var pendingEmailSearchQuery: String? = nil

    /// Search query carried from global search's "See all N in Tasks" into the
    /// Tasks tab. TasksTabView consumes it on appear and resets it to nil.
    var tasksSearchSeed: String? = nil

    /// Surfaced when a notification action (complete / snooze) fails on the next app open.
    /// Cleared by views once shown to the user. Plain text — render in a banner or alert.
    var pendingNotificationActionError: String? = nil

    /// Transient confirmation shown after a successful create from CreateSheet
    /// (e.g. "Task added to Inbox"). MainTabView observes this, shows an
    /// auto-dismissing banner, and resets it to nil. Without it a dateless task
    /// capture gives no visible feedback and is invisible on Home.
    var captureSuccessMessage: String? = nil

    /// Set true to trigger the global email compose sheet from MainTabView.
    var showsComposeEmail = false
    var composeEmailSeedBody: String? = nil
    var composeEmailSeedTo: String? = nil
    var composeEmailSeedCc: String? = nil
    var composeEmailSeedBcc: String? = nil
    var composeEmailSeedSubject: String? = nil
    /// Filenames (already saved by AttachmentService) carried into a fresh
    /// EmailComposeView. Surfaced as chips and uploaded inline with the send.
    var composeEmailSeedAttachments: [String] = []
    /// Connection ID pre-selected in CreateSheet's From picker, forwarded to EmailComposeView.
    var composeEmailSeedFromConnectionId: String? = nil
    var showsAIChat = false

    /// Set by detail views (e.g. EmailThreadView) to hide the custom floating tab bar
    /// so their own bottom bar is visible. Reset to false on dismiss.
    var hideTabBar = false

    /// Thread IDs for which the verification code has already been auto-copied
    /// in this session. Prevents the EmailThreadView from re-copying (and
    /// re-toasting) every time the user re-opens the same verification email.
    /// Cleared when the app process restarts.
    var autoCopiedVerificationThreads: Set<String> = []

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
    /// User-picked brand accent (one of `AccentPreference`). Mirrors the
    /// macOS + web accent setting so all three platforms share the same colour
    /// when the user picks one. Default `.blue`.
    var accentPreference: AccentPreference {
        didSet {
            guard oldValue != accentPreference else { return }
            defaults.set(accentPreference.rawValue, forKey: Keys.accentPreference)
            // Keep the server-synced `ios_accent_color` key in lockstep and push to
            // the server, so the Preferences and Appearance pickers (and other
            // devices) never disagree. Single source of truth = accentPreference.
            defaults.set(accentPreference.rawValue, forKey: "ios_accent_color")
            Task { await syncSetting("accentColor", accentPreference.rawValue) }
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

    /// Whether the user has finished (or skipped) the iOS tab-bar customization
    /// step. Re-introduced as an explicit onboarding screen: iOS exposes only 4
    /// configurable slots (+1 for the create FAB), so giving the user an early
    /// chance to pick their main pages is the only realistic surface to do so.
    /// Returning users (`hasReachedMainTab == true`) get this flag set to true
    /// at boot time so the step never appears for them.
    var hasConfiguredTabBarPrompt: Bool {
        didSet { defaults.set(hasConfiguredTabBarPrompt, forKey: Keys.hasConfiguredTabBarPrompt) }
    }

    /// One-shot flag — true after the user has either taken or skipped the
    /// product tour. Defaulted to true for returning users so the new tour
    /// doesn't ambush anyone mid-session.
    var hasSeenWelcomeTour: Bool {
        didSet { defaults.set(hasSeenWelcomeTour, forKey: Keys.hasSeenWelcomeTour) }
    }

    /// Whether the user has seen the notifications permission onboarding step.
    var hasConfiguredNotificationsPrompt: Bool {
        didSet { defaults.set(hasConfiguredNotificationsPrompt, forKey: Keys.hasConfiguredNotificationsPrompt) }
    }

    /// Whether the user has seen the "set as default mail app" onboarding step.
    var hasConfiguredDefaultMailPrompt: Bool {
        didSet { defaults.set(hasConfiguredDefaultMailPrompt, forKey: Keys.hasConfiguredDefaultMailPrompt) }
    }

    /// Whether the user has dismissed the branded startup card. One-shot —
    /// after the first tap on either CTA we never show the card again. Existing
    /// installs are migrated to `true` in `init` so the card only appears for
    /// genuinely new users.
    var hasSeenStartupCard: Bool {
        didSet { defaults.set(hasSeenStartupCard, forKey: Keys.hasSeenStartupCard) }
    }
    /// Positive signal: the user has reached the main tab at least once. Set
    /// to `true` from `MainTabView.onAppear` the first time the tab shell
    /// becomes visible. Used by the startup-card migration so a fresh install
    /// with a stale Keychain bearer (Keychain survives uninstall on iOS)
    /// can't silently skip the startup card.
    var hasReachedMainTab: Bool {
        didSet { defaults.set(hasReachedMainTab, forKey: Keys.hasReachedMainTab) }
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

    init(configuration: AppConfiguration = .load(), defaults: UserDefaults = .standard, preloadedAuthTokens: AuthBootstrapTokens? = nil) {
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
        // Surfaced to feature views so they can skip lazy network bootstrap
        // when the test harness drives the UI. Also flips a fresh-install
        // path below that wipes onboarding flags before AppServices reads
        // them, so `--ui-testing-fresh-install` lands on StartupOnboardingView.
        let uiTestingMode = CommandLine.arguments.contains("--ui-testing")
        self.isUITestingMode = uiTestingMode
        if uiTestingMode && CommandLine.arguments.contains("--ui-testing-fresh-install") {
            // Wipe every onboarding/auth flag we read below so the routing in
            // RootView resolves to the brand StartupOnboardingView. We can't
            // remove Keychain bearer tokens synchronously here without going
            // through AuthService, so the fresh-install path also asks the
            // auth service to clear in-memory state below.
            for key in [
                Keys.hasSeenStartupCard,
                Keys.hasReachedMainTab,
                Keys.hasConfiguredRemindersPrompt,
                Keys.hasConfiguredGmailPrompt,
                Keys.hasConfiguredNotificationsPrompt,
                Keys.hasConfiguredDefaultMailPrompt,
                Keys.hasConfiguredTabBarPrompt,
                Keys.hasSeenWelcomeTour,
            ] {
                defaults.removeObject(forKey: key)
            }
        }

        // New unified services — Better-Auth backend
        // Uses local dev server (localhost:8787) when useLocalBackend is enabled
        let backendURL = configuration.effectiveBackendURL
        let authService = AuthService(backendURL: backendURL, preloaded: preloadedAuthTokens)
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

        // Docs service depends only on the API client — initialise alongside other
        // tRPC-backed services so it's ready before the first view appears.
        self.docsService = DocsService(apiClient: apiClient)

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
        self.voiceTokenService = VoiceTokenService(authService: authService, backendURL: backendURL)
        let voiceSystemPromptClient = VoiceSystemPromptClient(
            authService: authService,
            backendURL: backendURL
        )
        self.voiceSystemPromptClient = voiceSystemPromptClient
        let voiceMicLock = VoiceMicLock()
        self.voiceMicLock = voiceMicLock
        self.voiceSessionCoordinator = VoiceSessionCoordinator(
            tokenService: self.voiceTokenService,
            systemPromptClient: voiceSystemPromptClient,
            chatService: self.aiChatService,
            apiClient: apiClient,
            micLock: voiceMicLock
        )
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
        // Single source of truth for the brand accent. Fall back to the
        // server-synced `ios_accent_color` key (written by the settings response)
        // so a cross-device accent choice is adopted on a fresh local install.
        let storedAccent = defaults.string(forKey: Keys.accentPreference)
            .flatMap(AccentPreference.init(rawValue:))
            ?? defaults.string(forKey: "ios_accent_color").flatMap(AccentPreference.init(rawValue:))
            ?? .blue
        let storedStartView = defaults.string(forKey: Keys.preferredStartViewMode)
            .flatMap(TaskViewMode.init(rawValue:))
            ?? .list

        self.appearancePreference = storedAppearance
        self.accentPreference = storedAccent
        self.developerModeEnabled = defaults.bool(forKey: Keys.developerModeEnabled)
        self.preferredStartViewMode = storedStartView
        self.remindersSyncEnabled = defaults.object(forKey: Keys.remindersSyncEnabled) as? Bool ?? false
        self.hasConfiguredRemindersPrompt = defaults.bool(forKey: Keys.hasConfiguredRemindersPrompt)
        self.hasConfiguredGmailPrompt = defaults.bool(forKey: Keys.hasConfiguredGmailPrompt)
        self.remindersSyncDirection = defaults.string(forKey: Keys.remindersSyncDirection)
            .flatMap(RemindersSyncDirection.init(rawValue:)) ?? .twoWay
        // Initialize selectedViewMode early — needed before self can be used in signature migration below.
        // Prefer the last view-mode the user actually picked; fall back to their start preference.
        let storedActiveView = defaults.string(forKey: Keys.selectedViewMode)
            .flatMap(TaskViewMode.init(rawValue:))
            ?? storedStartView
        self.selectedViewMode = storedActiveView
        self.taskSortOrder = defaults.string(forKey: Keys.taskSortOrder)
            .flatMap(TaskSortOrder.init(rawValue:))
            ?? .smart
        self.swipeGesturesEnabled = defaults.object(forKey: Keys.swipeGesturesEnabled) as? Bool ?? true
        self.threadGroupingEnabled = defaults.object(forKey: Keys.threadGroupingEnabled) as? Bool ?? true
        self.aiTonePreference = defaults.string(forKey: Keys.aiTonePreference)
            .flatMap(AITonePreference.init(rawValue:)) ?? .professional
        self.contextAboutYou = defaults.string(forKey: Keys.contextAboutYou) ?? ""
        self.customInstructions = defaults.string(forKey: Keys.customInstructions) ?? ""
        self.location = defaults.string(forKey: Keys.location) ?? ""
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
        // Tab-bar onboarding gate.
        //   • If the user previously dismissed (or completed) the step, honor that.
        //   • Returning users who already reached MainTabView are migrated to "done"
        //     so the new prompt never ambushes them mid-session.
        //   • Fresh installs land on the prompt as part of the onboarding chain.
        let storedTabBarFlag = defaults.bool(forKey: Keys.hasConfiguredTabBarPrompt)
        let reachedMainTabBefore = defaults.bool(forKey: Keys.hasReachedMainTab)
        self.hasConfiguredTabBarPrompt = storedTabBarFlag || reachedMainTabBefore
        if !storedTabBarFlag && reachedMainTabBefore {
            defaults.set(true, forKey: Keys.hasConfiguredTabBarPrompt)
        }

        // Welcome tour gate — same migration story: returning users skip it; new
        // installs see the consent screen as part of the onboarding chain.
        let storedTourFlag = defaults.bool(forKey: Keys.hasSeenWelcomeTour)
        self.hasSeenWelcomeTour = storedTourFlag || reachedMainTabBefore
        if !storedTourFlag && reachedMainTabBefore {
            defaults.set(true, forKey: Keys.hasSeenWelcomeTour)
        }

        self.hasConfiguredNotificationsPrompt = defaults.bool(forKey: Keys.hasConfiguredNotificationsPrompt)
        self.hasConfiguredDefaultMailPrompt = defaults.bool(forKey: Keys.hasConfiguredDefaultMailPrompt)
        self.emailNotificationsEnabled = defaults.object(forKey: Keys.emailNotificationsEnabled) as? Bool ?? true

        // Always read hasReachedMainTab so the migration check below can use it
        // as a positive returning-user signal. Set true the first time the
        // user actually lands on MainTabView (see MainTabView.onAppear).
        self.hasReachedMainTab = defaults.bool(forKey: Keys.hasReachedMainTab)

        // hasSeenStartupCard migration — anyone who already lived in the app
        // (reached the main tab OR finished an onboarding step while
        // authenticated) should not get a brand-new welcome card on the next
        // launch. The previous heuristic also trusted `hasPersistedBearerToken`
        // which is unreliable on iOS: Keychain survives uninstall by default,
        // so a fresh reinstall after a previous user signed out could trip the
        // bearer check and incorrectly skip the card. Drop that signal and
        // require either an explicit prior MainTab visit OR (onboarding step
        // AND active session).
        if let stored = defaults.object(forKey: Keys.hasSeenStartupCard) as? Bool {
            self.hasSeenStartupCard = stored
        } else {
            let hasPriorOnboarding =
                defaults.bool(forKey: Keys.hasConfiguredRemindersPrompt)
                || defaults.bool(forKey: Keys.hasConfiguredGmailPrompt)
                || defaults.bool(forKey: Keys.hasConfiguredNotificationsPrompt)
                || defaults.bool(forKey: Keys.hasConfiguredDefaultMailPrompt)
            let reachedTabBefore = defaults.bool(forKey: Keys.hasReachedMainTab)
            let migrated = reachedTabBefore || (hasPriorOnboarding && authService.isAuthenticated)
            self.hasSeenStartupCard = migrated
            // Persist the migration verdict so it's stable across launches and
            // we don't recompute the heuristic every cold start.
            defaults.set(migrated, forKey: Keys.hasSeenStartupCard)
        }

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

        // MARK: UI testing seed
        // When the host is launched with `--ui-testing` we put the app into a
        // deterministic post-auth, post-onboarding state so XCUITests can drive
        // the main tab shell without hitting the backend. Two variants:
        // - default: signed-in + all onboarding flags set, lands on MainTabView
        // - `--ui-testing-fresh-install`: defaults already cleared above,
        //   skip the auth seed so RootView routes to StartupOnboardingView
        if uiTestingMode && !CommandLine.arguments.contains("--ui-testing-fresh-install") {
            self.hasSeenStartupCard = true
            self.hasConfiguredGmailPrompt = true
            self.hasConfiguredRemindersPrompt = true
            self.hasConfiguredNotificationsPrompt = true
            self.hasConfiguredDefaultMailPrompt = true
            self.hasReachedMainTab = true
            // Welcome tour + tab-bar prompt must be seeded explicitly. They are
            // otherwise only migrated to "done" when `hasReachedMainTab` was
            // persisted by a PREVIOUS launch — on a fresh test container the
            // first XCUITest run landed on the tour instead of MainTabView.
            self.hasSeenWelcomeTour = true
            self.hasConfiguredTabBarPrompt = true
            authService._uiTesting_seedAuthenticatedSession(
                bearer: "TEST_TOKEN",
                email: "uitest@todus.app"
            )
        }
    }

    func selectFolder(_ folder: FolderRecord?) {
        selectedFolderID = folder?.id
    }

    func signOut() {
        // Clear in-memory sync queues so a reconnect after re-login does not
        // replay the previous user's offline mutations under the new session.
        folderSyncService.clearQueue()
        emailService.resetForSignOut()
        clearProfileScopedPreferences()
        // Compose drafts live in UserDefaults under `email_compose_autosave_v1.*`.
        // They contain recipient addresses, subject lines, and body text — PII for
        // the prior account. Wipe every key so the next signed-in user cannot
        // resume the prior user's drafts on the same device.
        wipeComposeDraftAutosaves()
        // Wipe SwiftData rows from the previous account BEFORE clearing auth —
        // otherwise the previous user's tasks/folders remain on disk and would
        // be presented to whoever signs in next on the same device.
        wipeLocalAccountData()
        authService.signOut()
        authStore.signOutToGuest()
    }

    /// Removes every autosaved compose draft from UserDefaults so a different
    /// account signing in on this device can't resume the previous user's
    /// in-progress emails. Matches every key prefixed with the autosave prefix
    /// used by `EmailComposeView` — historical bare-`compose.*` keys (pre user
    /// scoping) are also caught.
    private func wipeComposeDraftAutosaves() {
        let defaults = UserDefaults.standard
        let composePrefix = "email_compose_autosave_v1."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(composePrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    /// Deletes SwiftData TaskRecord/FolderRecord rows so a sign-in by a
    /// different user on this device starts with a clean local store. Local
    /// rows are not authoritative — they re-sync from the backend on first
    /// authenticated load — so this is safe to call on every sign-out.
    private func wipeLocalAccountData() {
        guard let context = modelContainer?.mainContext else { return }
        do {
            try context.delete(model: TaskRecord.self)
            try context.delete(model: FolderRecord.self)
            try context.save()
        } catch {
            print("[AppServices] wipeLocalAccountData failed: \(error)")
        }
    }

    /// Reset every UserDefaults-backed setting that belongs to the signed-in
    /// account (signatures, AI personalization, onboarding flags) so the next
    /// user on the same device does not inherit them. Display preferences
    /// (theme, sort order, gesture toggles) and device-level integration
    /// prefs (Reminders, notifications) survive — those are not user-private.
    private func clearProfileScopedPreferences() {
        // Onboarding prompts — new user must see them again.
        hasConfiguredRemindersPrompt = false
        hasConfiguredGmailPrompt = false
        hasConfiguredNotificationsPrompt = false
        hasConfiguredDefaultMailPrompt = false
        // Tab-bar customization step is per-account — a new user should see it
        // again with the default layout.
        hasConfiguredTabBarPrompt = false
        hasSeenWelcomeTour = false

        // Profile content — outgoing-mail signatures and AI prompts.
        signatures = []
        selectedSignatureID = nil
        contextAboutYou = ""
        customInstructions = ""
        location = ""
        aiTonePreference = .professional
        assistantAutomationPolicy = .recommended
        calendarPreferences = .default
        tabBarTabs = []

        // Drop the legacy v1 signature keys outright so they don't migrate
        // back into a fresh account on next launch.
        defaults.removeObject(forKey: Keys.signatureEnabled)
        defaults.removeObject(forKey: Keys.signatureText)

        // Mirror the cleared values into AI chat so an already-loaded
        // service instance stops sending the previous user's prompt context.
        aiChatService.contextAboutYou = ""
        aiChatService.customInstructions = ""
        aiChatService.toneInstruction = AITonePreference.professional.systemPromptInstruction
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
            location = response.settings.location ?? ""
            assistantAutomationPolicy = response.settings.assistantAutomationPolicy
            if let prefs = response.settings.calendarPreferences {
                calendarPreferences = prefs
            }
            // Hydrate cross-device synced fields into UserDefaults so @AppStorage
            // bindings in SettingsView reflect the server state on next render.
            let defaults = UserDefaults.standard
            if let value = response.settings.aiCanReadTasks {
                defaults.set(value, forKey: "ai_can_read_tasks")
            }
            if let value = response.settings.aiCanWriteTasks {
                defaults.set(value, forKey: "ai_can_write_tasks")
            }
            if let value = response.settings.aiCanReadCalendar {
                defaults.set(value, forKey: "ai_can_read_calendar")
            }
            if let value = response.settings.aiCanWriteCalendar {
                defaults.set(value, forKey: "ai_can_write_calendar")
            }
            if let value = response.settings.aiCanReadEmail {
                defaults.set(value, forKey: "ai_can_read_email")
            }
            if let value = response.settings.aiCanSendEmail {
                defaults.set(value, forKey: "ai_can_send_email")
            }
            if let value = response.settings.accentColor {
                defaults.set(value, forKey: "ios_accent_color")
            }
            if let value = response.settings.defaultTaskView,
               let mode = TaskViewMode(rawValue: value) {
                preferredStartViewMode = mode
                selectedViewMode = mode
            }
            if let value = response.settings.groupByThread {
                threadGroupingEnabled = value
            }
            if let value = response.settings.aiTone,
               let tone = AITonePreference(rawValue: value) {
                aiTonePreference = tone
            }
            if let value = response.settings.taskRemindersEnabled {
                taskRemindersEnabled = value
            }
            if let value = response.settings.calendarRemindersEnabled {
                calendarRemindersEnabled = value
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
                    location: location,
                    assistantAutomationPolicy: assistantAutomationPolicy
                )
            )
        } catch {
            print("[AppServices] Failed to save shared AI profile: \(error)")
        }
    }

    /// Push a single user-settings field to the backend via `settings.save`.
    /// Used by per-toggle bindings in `SettingsView` that mirror @AppStorage values
    /// to the server so iOS / macOS / web stay in sync.
    func syncSetting<T: Encodable>(_ key: String, _ value: T) async {
        guard authService.isAuthenticated else { return }
        do {
            let _: SharedAIProfileSaveResponse = try await apiClient.trpcMutation(
                "settings.save",
                input: _OneFieldInput(key: key, value: value)
            )
        } catch {
            print("[AppServices] Failed to sync setting \(key): \(error)")
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
    let location: String
    let assistantAutomationPolicy: AssistantAutomationPolicy
}

private struct SharedAIProfileSaveResponse: Decodable {
    let success: Bool
}
