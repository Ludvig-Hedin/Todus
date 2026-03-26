import Foundation
import Observation
import SwiftData
import SwiftUI

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
        // Tracks whether the user has seen the "Connect Apple Reminders" onboarding prompt.
        // Defaults to false so new installs see the prompt after sign-up.
        static let hasConfiguredRemindersPrompt = "TaskApp.hasConfiguredRemindersPrompt"
    }

    let configuration: AppConfiguration

    // Unified auth — replaces old AuthSessionStore for new Better-Auth flow
    let authService: AuthService
    // Unified HTTP client for all backend API calls
    let apiClient: TodosAPIClient
    // Email service — manages inbox state and email actions
    let emailService: EmailService
    // Calendar service — shared EKEventStore access
    let calendarService: CalendarService

    // Legacy services — kept during migration, will be removed once task sync is fully on new backend
    let authStore: AuthSessionStore
    let syncService: SupabaseSyncService
    let captureService: TaskCaptureService
    let remindersSyncService: AppleRemindersSyncService
    let remindersSyncState: RemindersSyncState
    /// AI chat service — manages streaming conversation and task mutations
    let aiChatService: AIChatService
    private let defaults: UserDefaults

    var selectedViewMode: TaskViewMode
    var selectedFolderID: UUID?
    var showsSettings = false
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
    /// Whether the user has dismissed the "Connect Apple Reminders" onboarding prompt
    /// (either by connecting or skipping). False on fresh installs → prompt is shown once.
    var hasConfiguredRemindersPrompt: Bool {
        didSet {
            defaults.set(hasConfiguredRemindersPrompt, forKey: Keys.hasConfiguredRemindersPrompt)
        }
    }

    init(configuration: AppConfiguration = .load(), defaults: UserDefaults = .standard) {
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
        self.aiChatService = AIChatService(
            configuration: configuration,
            captureService: captureService
        )

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
        self.selectedViewMode = storedStartView
        self.remindersSyncState.isEnabled = self.remindersSyncEnabled
    }

    func selectFolder(_ folder: FolderRecord?) {
        selectedFolderID = folder?.id
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
        let descriptor = FetchDescriptor<TaskRecord>()
        let tasks = (try? context.fetch(descriptor)) ?? []
        remindersSyncService.syncAllTasks(tasks, in: context)
    }

    /// Imports any Apple Reminders that aren't yet tracked as app tasks.
    /// Safe to call multiple times — skips reminders already linked via reminderIdentifier.
    func importFromReminders(in context: ModelContext) async {
        guard remindersSyncEnabled else { return }
        await remindersSyncService.importFromReminders(in: context)
    }
}
