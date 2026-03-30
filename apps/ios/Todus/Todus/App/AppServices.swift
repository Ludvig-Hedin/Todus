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
    }

    let configuration: AppConfiguration

    // Unified auth — replaces old AuthSessionStore for new Better-Auth flow
    let authService: AuthService
    // Unified HTTP client for all backend API calls
    let apiClient: TodosAPIClient

    let emailService: EmailService
    let calendarService: CalendarService
    let networkMonitor: NetworkMonitor
    let notificationService: NotificationService

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
    private let defaults: UserDefaults

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

    /// Set true to trigger the global email compose sheet from MainTabView.
    var showsComposeEmail = false
    var composeEmailSeedBody: String? = nil

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
        self.calendarService = CalendarService()
        self.networkMonitor = NetworkMonitor()
        self.notificationService = NotificationService()

        // Legacy services — still used for task sync during migration
        self.authStore = AuthSessionStore(configuration: configuration)
        self.syncService = SupabaseSyncService(configuration: configuration, authStore: authStore)
        self.remindersSyncService = AppleRemindersSyncService()
        self.remindersSyncState = RemindersSyncState()

        let captureService = TaskCaptureService(
            parser: RemoteFirstTaskParsingService(configuration: configuration),
            syncService: syncService,
            authStore: authStore,
            remindersSyncService: remindersSyncService,
            remindersSyncState: remindersSyncState
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
        self.taskRemindersEnabled = defaults.object(forKey: Keys.taskRemindersEnabled) as? Bool ?? true
        self.calendarRemindersEnabled = defaults.object(forKey: Keys.calendarRemindersEnabled) as? Bool ?? true
        // Load signatures — migrate from old single-text format if no v2 data exists
        if let data = defaults.data(forKey: Keys.emailSignatures),
           let saved = try? JSONDecoder().decode([EmailSignature].self, from: data) {
            self.signatures = saved
        } else {
            let oldText = defaults.string(forKey: Keys.signatureText) ?? ""
            let oldEnabled = defaults.bool(forKey: Keys.signatureEnabled)
            if oldEnabled && !oldText.isEmpty {
                let migrated = [EmailSignature(name: "Default", body: oldText)]
                self.signatures = migrated
                // Persist migrated signatures so we don't re-run migration on next launch
                if let data = try? JSONEncoder().encode(migrated) {
                    defaults.set(data, forKey: Keys.emailSignatures)
                }
            } else {
                self.signatures = []
            }
        }
        // Load selected signature ID — migrate from old signatureEnabled if needed
        if let uuidStr = defaults.string(forKey: Keys.selectedSignatureID),
           let uuid = UUID(uuidString: uuidStr) {
            self.selectedSignatureID = uuid
        } else {
            let oldEnabled = defaults.bool(forKey: Keys.signatureEnabled)
            let migratedID = (oldEnabled && !self.signatures.isEmpty) ? self.signatures.first?.id : nil
            self.selectedSignatureID = migratedID
            // Persist migrated selected ID so we don't re-run migration on next launch
            if let migratedID {
                defaults.set(migratedID.uuidString, forKey: Keys.selectedSignatureID)
            }
        }
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
        emailService.resetForSignOut()
        authService.signOut()
        authStore.signOutToGuest()
    }

    func loadSharedAIProfile() async {
        guard authService.isAuthenticated else { return }

        do {
            let response: SharedAIProfileResponse = try await apiClient.trpcQuery("settings.get")
            contextAboutYou = response.settings.contextAboutYou
            customInstructions = response.settings.customPrompt
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
                    customPrompt: customInstructions
                )
            )
        } catch {
            print("[AppServices] Failed to save shared AI profile: \(error)")
        }
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
