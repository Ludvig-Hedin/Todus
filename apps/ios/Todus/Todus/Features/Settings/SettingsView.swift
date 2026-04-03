import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @State private var showsLogoutConfirmation = false
    @State private var showsDeleteConfirmation = false
    @State private var showsDeleteAlert = false
    @State private var deleteConfirmText = ""
    @State private var isDeletingAccount = false
    @State private var showsDisconnectGmail = false
    @State private var isConnectingCalendar = false
    @State private var isConnectingReminders = false
    @State private var activeSessions: [ActiveSessionRecord] = []
    @State private var isLoadingSessions = false
    // revokingSessionIDs and isRevokingAllSessions live in SessionsSettingsView now

    private var calendarAccessGranted: Bool {
        services.calendarService.canReadEvents()
    }

    var body: some View {
        NavigationStack {
            List {
                accountSection
                sessionsNavigationSection
                connectedServicesSection

                // Appearance sub-page + small preferences inline
                preferencesSection

                // Tab bar customization — which pages appear in the floating bar
                tabBarSection

                // Email preferences — separate from AI to reduce cognitive load
                emailSection

                // AI Assistant — dedicated sub-page (contains large TextEditors)
                aiAssistantNavigationSection

                // Notifications + Privacy
                notificationsAndPrivacySection

                aboutSection

                if services.developerModeEnabled {
                    developerSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.backgroundBottom)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            Task { @MainActor in
                                await services.saveSharedAIProfile()
                                dismiss()
                            }
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
        .presentationDragIndicator(.visible)
        .task {
            // Refresh profile data (name, avatar) when settings opens
            await services.authService.fetchUserProfile()
            await services.loadSharedAIProfile()
        }
        .task {
            await services.emailService.checkConnection()
        }
        .task {
            await loadActiveSessions()
        }
        .confirmationDialog(
            "Are you sure you want to log out?",
            isPresented: $showsLogoutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Log out", role: .destructive) {
                performLogout()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can sign back in anytime.")
        }
        // Delete account — first confirmation step
        .confirmationDialog(
            "Delete your account?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                showsDeleteAlert = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete your account, tasks, email connections, and all data. This cannot be undone.")
        }
        // Delete account — second confirmation: type "DELETE"
        .alert("Type DELETE to confirm", isPresented: $showsDeleteAlert) {
            TextField("DELETE", text: $deleteConfirmText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
            Button("Delete Account", role: .destructive) {
                guard deleteConfirmText == "DELETE" else { return }
                Task { await performDeleteAccount() }
            }
            Button("Cancel", role: .cancel) {
                deleteConfirmText = ""
            }
        } message: {
            Text("This action is irreversible. Type DELETE to proceed.")
        }
        // Disconnect Gmail confirmation
        .confirmationDialog(
            "Disconnect Gmail?",
            isPresented: $showsDisconnectGmail,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                Task { await performDisconnectGmail() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll stop receiving emails in Todus. You can reconnect anytime.")
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section {
            // Profile row — avatar, name, email
            HStack(spacing: 12) {
                // Avatar — Google profile image or letter initial fallback
                if let imageURLString = services.authService.userImage,
                   let imageURL = URL(string: imageURLString) {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                        default:
                            avatarFallback
                        }
                    }
                } else {
                    avatarFallback
                }

                VStack(alignment: .leading, spacing: 2) {
                    // Display name from Google profile, or "Account" fallback
                    if let name = services.authService.userName, !name.isEmpty {
                        Text(name)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                    } else {
                        Text("Account")
                            .font(.system(size: 16, weight: .semibold))
                    }

                    // Email address shown below the name
                    if let email = services.authService.userEmail ?? services.authStore.accountEmail {
                        Text(email)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)

            // Sign in button — only when not authenticated
            if !services.authService.isAuthenticated {
                Button {
                    services.authService.hasSeenOnboarding = false
                    services.signOut()
                    dismiss()
                } label: {
                    Label("Sign in to your account", systemImage: "person.crop.circle.badge.plus")
                        .foregroundStyle(.blue)
                }
            }

            // Log out button — inside the account card
            if services.authService.isAuthenticated {
                Button(role: .destructive) {
                    showsLogoutConfirmation = true
                } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(.red)
                }

                // Delete account — double confirmation required
                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Label("Delete account", systemImage: "trash")
                        .foregroundStyle(.red.opacity(0.7))
                }
            }
        } header: {
            Text("Account")
        }
    }

    // MARK: - Sessions (NavigationLink → sub-view)

    /// Compact NavigationLink row replacing the old inline sessions table.
    /// Session count badge gives users at-a-glance info without cluttering the main list.
    private var sessionsNavigationSection: some View {
        Section {
            NavigationLink {
                SessionsSettingsView()
            } label: {
                HStack {
                    Label("Active Sessions", systemImage: "desktopcomputer.and.arrow.down")
                    Spacer()
                    if isLoadingSessions {
                        ProgressView().scaleEffect(0.7)
                    } else if !activeSessions.isEmpty {
                        Text("\(activeSessions.count)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Security")
        } footer: {
            Text("Review signed-in devices and revoke access without changing your password.")
        }
    }

    /// Fallback avatar with first-letter initial
    private var avatarFallback: some View {
        ZStack {
            Circle()
                .fill(services.authService.isAuthenticated
                      ? Color.blue.opacity(0.15)
                      : Color.secondary.opacity(0.12))
                .frame(width: 48, height: 48)
            if let email = services.authService.userEmail ?? services.authStore.accountEmail,
               let first = email.first {
                Text(String(first).uppercased())
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(services.authService.isAuthenticated ? .blue : .secondary)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Connected Services

    private var connectedServicesSection: some View {
        Section {
            // Gmail
            HStack(spacing: 12) {
                GmailIconView(size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gmail")
                        .font(.system(size: 15))
                    Text(services.emailService.hasConnection ? "Connected" : "Not connected")
                        .font(.system(size: 12))
                        .foregroundStyle(services.emailService.hasConnection ? .green : .secondary)
                }
                Spacer()
                if services.emailService.hasConnection {
                    Button(role: .destructive) {
                        showsDisconnectGmail = true
                    } label: {
                        Text("Disconnect")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.red.opacity(0.8))
                    }
                }
            }
            .padding(.vertical, 2)

            // Apple Calendar
            HStack(spacing: 12) {
                AppleCalendarIconView(size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Calendar")
                        .font(.system(size: 15))
                    Text(calendarAccessGranted ? "Connected" : "Not connected")
                        .font(.system(size: 12))
                        .foregroundStyle(calendarAccessGranted ? .green : .secondary)
                }
                Spacer()
                if calendarAccessGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 16))
                } else {
                    Button {
                        guard !isConnectingCalendar else { return }
                        isConnectingCalendar = true
                        Task {
                            _ = await services.calendarService.requestAccess()
                            isConnectingCalendar = false
                        }
                    } label: {
                        Text(isConnectingCalendar ? "Connecting…" : "Connect")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(isConnectingCalendar)
                }
            }
            .padding(.vertical, 2)

            // Apple Reminders
            HStack(spacing: 12) {
                AppleRemindersIconView(size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Reminders")
                        .font(.system(size: 15))
                    Text(services.remindersSyncEnabled ? "Connected" : "Not connected")
                        .font(.system(size: 12))
                        .foregroundStyle(services.remindersSyncEnabled ? .green : .secondary)
                }
                Spacer()
                if services.remindersSyncEnabled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 16))
                } else {
                    Button {
                        guard !isConnectingReminders else { return }
                        isConnectingReminders = true
                        Task {
                            services.remindersSyncEnabled = true
                            let granted = await services.requestRemindersPermissionIfNeeded()
                            if granted {
                                await services.importFromReminders(in: modelContext)
                                services.syncExistingTasksToReminders(in: modelContext)
                            } else {
                                services.remindersSyncEnabled = false
                            }
                            isConnectingReminders = false
                        }
                    } label: {
                        Text(isConnectingReminders ? "Connecting…" : "Connect")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(isConnectingReminders)
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text("Connected Services")
        }
    }


    // MARK: - Preferences (trimmed — Appearance moved to sub-page)

    private var preferencesSection: some View {
        Section {
            // Appearance sub-page — theme picker lives there to avoid the wide three-column
            // layout being awkward in a scrollable List
            NavigationLink {
                AppearanceSettingsView()
            } label: {
                HStack {
                    Label("Appearance", systemImage: "paintbrush")
                    Spacer()
                    Text(services.appearancePreference.title)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            Picker(selection: Binding(
                get: { services.preferredStartViewMode },
                set: {
                    services.preferredStartViewMode = $0
                    services.selectedViewMode = $0
                }
            )) {
                ForEach(TaskViewMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                Label("Default View", systemImage: "square.grid.2x2")
            }
            .pickerStyle(.menu)

            NavigationLink {
                FolderManagementView()
            } label: {
                Label("Manage Folders", systemImage: "folder")
            }

            Toggle(isOn: Binding(
                get: { services.developerModeEnabled },
                set: { services.developerModeEnabled = $0 }
            )) {
                Label("Developer Mode", systemImage: "wrench.and.screwdriver")
            }
            .tint(.orange)
        } header: {
            Text("Preferences")
        }
    }

    // MARK: - Tab Bar Customization

    private var tabBarSection: some View {
        Section {
            NavigationLink {
                TabBarCustomizationView()
            } label: {
                HStack {
                    Label("Tab Bar", systemImage: "square.bottomhalf.filled")
                    Spacer()
                    // Preview of current tab count
                    Text("\(services.tabBarTabs.count) tabs")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Navigation")
        } footer: {
            Text("Choose which pages appear in the floating tab bar (max 4). Pages not shown here are accessible from the Home tab.")
        }
    }

    // MARK: - AI Assistant (NavigationLink → sub-view)

    /// Single NavigationLink row — the two large TextEditors moved to AIAssistantSettingsView
    private var aiAssistantNavigationSection: some View {
        Section {
            NavigationLink {
                AIAssistantSettingsView()
            } label: {
                Label("AI Assistant", systemImage: "sparkles")
            }
        } header: {
            Text("AI Assistant")
        } footer: {
            Text("Configure what the AI can read, write, and how it responds.")
        }
    }

    // MARK: - Email

    private var emailSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { services.swipeGesturesEnabled },
                set: { services.swipeGesturesEnabled = $0 }
            )) {
                Label("Swipe Gestures", systemImage: "hand.draw")
            }
            .tint(.blue)

            NavigationLink {
                SignaturesView()
            } label: {
                HStack {
                    Label("Signatures", systemImage: "signature")
                    Spacer()
                    Text(services.activeSignature?.name ?? "Off")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: Binding(
                get: { services.threadGroupingEnabled },
                set: { services.threadGroupingEnabled = $0 }
            )) {
                Label("Group by Thread", systemImage: "text.bubble")
            }
            .tint(.blue)
        } header: {
            Text("Email")
        }
    }


    // MARK: - Combined: Notifications + Privacy

    private var notificationsAndPrivacySection: some View {
        Section {
            // Notification toggles
            Toggle(isOn: Binding(
                get: { services.taskRemindersEnabled },
                set: { services.taskRemindersEnabled = $0 }
            )) {
                Label("Task Due Reminders", systemImage: "checklist")
            }
            .tint(.blue)

            Toggle(isOn: Binding(
                get: { services.calendarRemindersEnabled },
                set: { services.calendarRemindersEnabled = $0 }
            )) {
                Label("Calendar Reminders", systemImage: "calendar.badge.clock")
            }
            .tint(.blue)

            // System notification settings link
            Button {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Label("System Settings", systemImage: "bell.badge")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            // Privacy items
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Label("App Permissions", systemImage: "hand.raised")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Label("Data Sync", systemImage: "lock.shield")
                Spacer()
                Text("End-to-end")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Notifications & Privacy")
        }
    }

    // MARK: - Developer

    @State private var useLocalBackend = AppConfiguration.useLocalBackend

    private var developerSection: some View {
        @Bindable var ai = services.aiChatService
        return Section {
            Toggle("Local Backend", isOn: $useLocalBackend)
                .onChange(of: useLocalBackend) { _, newValue in
                    AppConfiguration.useLocalBackend = newValue
                }
                .tint(.orange)

            LabeledContent("Backend", value: services.configuration.effectiveBackendURL.host ?? "unknown")
            LabeledContent("Auth state", value: authStateLabel)
            LabeledContent("Bearer token", value: services.authService.bearerToken != nil
                           ? "Present (\(services.authService.bearerToken!.prefix(8))...)" : "None")

            Picker("AI Model", selection: $ai.selectedModel) {
                ForEach(services.configuration.preferredModels, id: \.self) { model in
                    Text(simplifiedModelName(model))
                        .tag(model)
                }
            }
            .pickerStyle(.menu)

            LabeledContent("Install ID", value: String(services.authStore.installID.prefix(12)) + "...")

            ShareLink(
                item: AppLogger.shared.logFileURL,
                preview: SharePreview("app.log", image: Image(systemName: "doc.text"))
            ) {
                Label("Share Debug Logs", systemImage: "square.and.arrow.up")
            }

            Button("Clear Logs", role: .destructive) {
                AppLogger.shared.clear()
            }
        } header: {
            Text("Developer")
        } footer: {
            Text("Local backend: http://localhost:8787. Restart app after toggling.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                Label("Version", systemImage: "info.circle")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label("Build", systemImage: "hammer")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("About")
        }
    }

    // MARK: - Helpers

    private var authStateLabel: String {
        switch services.authService.authState {
        case .guest:          return "Guest"
        case .authenticating: return "Authenticating..."
        case .otpPending:     return "OTP Pending"
        case .authenticated:  return "Authenticated"
        }
    }

    private func simplifiedModelName(_ model: String) -> String {
        model.split(separator: "/").last.map(String.init) ?? model
    }

    private func loadActiveSessions() async {
        isLoadingSessions = true
        defer { isLoadingSessions = false }

        do {
            let response = try await services.apiClient.listSessions()
            activeSessions = response.sessions
        } catch {
            AppLogger.shared.log("Load sessions failed: \(error.localizedDescription)")
        }
    }

    private func performLogout() {
        services.authService.hasSeenOnboarding = false
        services.signOut()
        dismiss()
    }

    /// Deletes the user's account on the backend, clears local auth state, and dismisses settings.
    private func performDeleteAccount() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            // Call backend to delete account and all associated data
            try await services.apiClient.deleteAccount()
        } catch {
            // Even if the backend call fails, sign out locally so the user isn't stuck
            AppLogger.shared.log("Delete account failed: \(error.localizedDescription)")
        }

        // Clear local state — Keychain token, auth flags, SwiftData
        deleteConfirmText = ""
        services.authService.hasSeenOnboarding = false
        services.signOut()

        // Wipe all local SwiftData records (tasks + folders)
        try? modelContext.delete(model: TaskRecord.self)
        try? modelContext.delete(model: FolderRecord.self)
        try? modelContext.save()

        dismiss()
    }

    /// Disconnects Gmail by removing the email connection on the backend.
    private func performDisconnectGmail() async {
        do {
            try await services.apiClient.disconnectEmail()
            await services.emailService.checkConnection()
        } catch {
            AppLogger.shared.log("Disconnect Gmail failed: \(error.localizedDescription)")
        }
    }

}

// MARK: - SessionsSettingsView

/// Dedicated sub-page for Active Sessions — replaces the inline sessions table.
/// Much cleaner on mobile: the main settings page now shows just a count badge.
struct SessionsSettingsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var activeSessions: [ActiveSessionRecord] = []
    @State private var isLoadingSessions = false
    @State private var isRevokingAllSessions = false
    @State private var revokingSessionIDs: Set<String> = []

    var body: some View {
        List {
            if isLoadingSessions {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Loading sessions…")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else if activeSessions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No active sessions found")
                        .font(.system(size: 15, weight: .medium))
                    Text("New sign-ins will appear here automatically.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                Section {
                    ForEach(activeSessions) { session in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "laptopcomputer")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text(session.device)
                                    .font(.system(size: 14, weight: .semibold))
                                    .lineLimit(1)
                                if session.isCurrent == true {
                                    Text("This device")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue, in: Capsule())
                                }
                                Spacer()
                                if session.isCurrent != true {
                                    Button(role: .destructive) {
                                        Task { await revokeSession(session.id) }
                                    } label: {
                                        if revokingSessionIDs.contains(session.id) {
                                            ProgressView().scaleEffect(0.7)
                                        } else {
                                            Text("Log out")
                                                .font(.system(size: 13, weight: .medium))
                                        }
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(isRevokingAllSessions || revokingSessionIDs.contains(session.id))
                                }
                            }

                            HStack(spacing: 16) {
                                if !session.location.isEmpty {
                                    Label(session.location, systemImage: "location")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Label(formatDate(session.updatedAt), systemImage: "clock")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Signed-in Devices")
                }

                if activeSessions.count > 1 {
                    Section {
                        Button(role: .destructive) {
                            Task { await revokeAllSessions() }
                        } label: {
                            HStack {
                                if isRevokingAllSessions { ProgressView().scaleEffect(0.8) }
                                Text(isRevokingAllSessions ? "Signing out…" : "Log out all other devices")
                            }
                        }
                        .disabled(isRevokingAllSessions)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.backgroundBottom)
        .navigationTitle("Active Sessions")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSessions() }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
        return f.string(from: date)
    }

    private func loadSessions() async {
        isLoadingSessions = true
        defer { isLoadingSessions = false }
        do {
            let response = try await services.apiClient.listSessions()
            activeSessions = response.sessions
        } catch {
            AppLogger.shared.log("Load sessions failed: \(error.localizedDescription)")
        }
    }

    private func revokeSession(_ sessionId: String) async {
        revokingSessionIDs.insert(sessionId)
        defer { revokingSessionIDs.remove(sessionId) }
        do {
            let response = try await services.apiClient.revokeSession(sessionId: sessionId)
            await loadSessions()
            if response.revokedCurrent {
                // Current device was logged out — pop back and sign out
                services.authService.hasSeenOnboarding = false
                services.signOut()
                dismiss()
            } else {
                await services.authService.fetchUserProfile()
            }
        } catch {
            AppLogger.shared.log("Revoke session failed: \(error.localizedDescription)")
        }
    }

    private func revokeAllSessions() async {
        isRevokingAllSessions = true
        defer { isRevokingAllSessions = false }
        do {
            let response = try await services.apiClient.revokeAllSessions()
            activeSessions = []
            if response.revokedCurrent {
                services.authService.hasSeenOnboarding = false
                services.signOut()
                dismiss()
            } else {
                await services.authService.fetchUserProfile()
            }
        } catch {
            AppLogger.shared.log("Revoke all sessions failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - AIAssistantSettingsView

/// Dedicated sub-page for AI settings — removes the two large TextEditors from the
/// main settings list, where they caused awkward inline scrolling on iPhone.
struct AIAssistantSettingsView: View {
    @Environment(AppServices.self) private var services
    @State private var showsAutoSendConfirm = false

    private var excludedSenderPatternsText: Binding<String> {
        Binding(
            get: { services.assistantAutomationPolicy.excludedSenderPatterns.joined(separator: "\n") },
            set: { newValue in
                services.assistantAutomationPolicy.excludedSenderPatterns = newValue
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    var body: some View {
        @Bindable var ai = services.aiChatService
        return List {
            Section {
                Toggle(isOn: $ai.aiCanReadTasks) {
                    Label("Read my tasks", systemImage: "eye")
                }
                .tint(.blue)

                Toggle(isOn: $ai.aiCanWriteTasks) {
                    Label("Create & edit tasks", systemImage: "pencil")
                }
                .tint(.blue)

                Picker(selection: Binding(
                    get: { services.aiTonePreference },
                    set: { services.aiTonePreference = $0 }
                )) {
                    ForEach(AITonePreference.allCases) { tone in
                        Text(tone.title).tag(tone)
                    }
                } label: {
                    Label("Response Tone", systemImage: "text.quote")
                }
                .pickerStyle(.menu)
            } header: {
                Text("Permissions & Tone")
            }

            Section {
                Button("Apply recommended assistant defaults") {
                    services.assistantAutomationPolicy = .recommended
                }

                Toggle(
                    "Enable assistant briefing engine",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.briefingEnabled },
                        set: { services.assistantAutomationPolicy.briefingEnabled = $0 }
                    )
                )

                Toggle(
                    "Show Home briefing",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.showHomeBriefing },
                        set: { services.assistantAutomationPolicy.showHomeBriefing = $0 }
                    )
                )

                Toggle(
                    "Auto summarize long threads",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.autoSummarizeLongThreads },
                        set: { services.assistantAutomationPolicy.autoSummarizeLongThreads = $0 }
                    )
                )

                Toggle(
                    "Suggest tasks from email",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.suggestTasksFromEmail },
                        set: { services.assistantAutomationPolicy.suggestTasksFromEmail = $0 }
                    )
                )

                Toggle(
                    "Suggest events from email",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.suggestEventsFromEmail },
                        set: { services.assistantAutomationPolicy.suggestEventsFromEmail = $0 }
                    )
                )

                Toggle(
                    "Auto draft replies",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.autoDraftReplies },
                        set: { services.assistantAutomationPolicy.autoDraftReplies = $0 }
                    )
                )

                Toggle(
                    "Smart reply nudges",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.smartReplyNudges },
                        set: { services.assistantAutomationPolicy.smartReplyNudges = $0 }
                    )
                )

                Toggle(
                    "Smart deadline nudges",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.smartDeadlineNudges },
                        set: { services.assistantAutomationPolicy.smartDeadlineNudges = $0 }
                    )
                )

                Toggle(
                    "Show thread assistant controls",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.assistantThreadActionsVisible },
                        set: { services.assistantAutomationPolicy.assistantThreadActionsVisible = $0 }
                    )
                )

                Toggle(
                    "Track waiting-on threads",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.trackWaitingOnThreads },
                        set: { services.assistantAutomationPolicy.trackWaitingOnThreads = $0 }
                    )
                )

                Toggle(
                    "Build people memory",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.peopleMemoryEnabled },
                        set: { services.assistantAutomationPolicy.peopleMemoryEnabled = $0 }
                    )
                )

                Toggle(
                    "Batch prepared approvals",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.batchApprovalEnabled },
                        set: { services.assistantAutomationPolicy.batchApprovalEnabled = $0 }
                    )
                )

                // Auto-send requires explicit opt-in confirmation before enabling
                Toggle(
                    "Enable low-risk auto-send experiment",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.autoSendExperimentEnabled },
                        set: { newValue in
                            if newValue {
                                showsAutoSendConfirm = true
                            } else {
                                services.assistantAutomationPolicy.autoSendExperimentEnabled = false
                            }
                        }
                    )
                )
                .confirmationDialog(
                    "Enable Auto-Send?",
                    isPresented: $showsAutoSendConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Enable Auto-Send", role: .destructive) {
                        services.assistantAutomationPolicy.autoSendExperimentEnabled = true
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The assistant may send low-risk replies on your behalf without further confirmation. You can turn this off at any time.")
                }
            } header: {
                Text("Mail Assistant")
            } footer: {
                Text("Todus can brief, prepare, and track for you by default. Auto-send stays off unless you opt in.")
            }

            Section {
                Picker(
                    "Workday starts",
                    selection: Binding(
                        get: { services.assistantAutomationPolicy.workdayStartHour },
                        set: { services.assistantAutomationPolicy.workdayStartHour = $0 }
                    )
                ) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(String(format: "%02d:00", hour)).tag(hour)
                    }
                }
                .pickerStyle(.menu)

                Picker(
                    "Workday ends",
                    selection: Binding(
                        get: { services.assistantAutomationPolicy.workdayEndHour },
                        set: { services.assistantAutomationPolicy.workdayEndHour = $0 }
                    )
                ) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(String(format: "%02d:00", hour)).tag(hour)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Assistant timing")
            } footer: {
                Text("Used for urgency, waiting-on tracking, and when Home should surface the most important prepared work.")
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Excluded senders and topics")
                        .font(.system(size: 15, weight: .medium))
                    TextEditor(text: excludedSenderPatternsText)
                        .frame(minHeight: 100)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text("One pattern per line. Use this to suppress noisy automation, newsletters, and low-value system mail from the assistant queues.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Noise filtering")
            } footer: {
                Text("Examples: notifications@, no-reply@, calendar-notification@")
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Context about you")
                        .font(.system(size: 15, weight: .medium))
                    TextEditor(
                        text: Binding(
                            get: { services.contextAboutYou },
                            set: { services.contextAboutYou = $0 }
                        )
                    )
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.vertical, 4)
            } header: {
                Text("Context about you")
            } footer: {
                Text("Tell the AI about your role, goals, or preferences so it can give more relevant responses.")
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Custom instructions")
                        .font(.system(size: 15, weight: .medium))
                    TextEditor(
                        text: Binding(
                            get: { services.customInstructions },
                            set: { services.customInstructions = $0 }
                        )
                    )
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.vertical, 4)
            } header: {
                Text("Custom instructions")
            } footer: {
                Text("Instructions the AI follows on every response — e.g. tone, format, or topics to avoid.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.backgroundBottom)
        .navigationTitle("AI Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            // Save shared AI profile when leaving the AI settings page
            Task { @MainActor in await services.saveSharedAIProfile() }
        }
    }
}

// MARK: - AppearanceSettingsView

/// Dedicated sub-page for theme selection — removes the three-column theme picker
/// from the main settings list where it was visually heavy and hard to tap precisely.
struct AppearanceSettingsView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        List {
            Section {
                ForEach(AppAppearancePreference.allCases) { preference in
                    Button {
                        services.appearancePreference = preference
                    } label: {
                        HStack(spacing: 14) {
                            // Compact swatch preview
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(previewBackground(for: preference))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(
                                            services.appearancePreference == preference
                                                ? Color.blue
                                                : Color(UIColor.separator).opacity(0.4),
                                            lineWidth: services.appearancePreference == preference ? 2 : 1
                                        )
                                )
                                .overlay {
                                    Image(systemName: preferenceIcon(preference))
                                        .font(.system(size: 18, weight: .light))
                                        .foregroundStyle(previewAccent(for: preference).opacity(0.6))
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(preference.title)
                                    .font(.system(size: 15, weight: services.appearancePreference == preference ? .semibold : .regular))
                                    .foregroundStyle(.primary)
                                Text(preferenceSubtitle(preference))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if services.appearancePreference == preference {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Theme")
            } footer: {
                Text("System follows your iPhone's Dark Mode setting.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.backgroundBottom)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func previewBackground(for preference: AppAppearancePreference) -> Color {
        switch preference {
        case .system: return Color(UIColor.systemBackground)
        case .light:  return Color(UIColor(white: 0.98, alpha: 1))
        case .dark:   return Color(UIColor(white: 0.08, alpha: 1))
        }
    }

    private func previewAccent(for preference: AppAppearancePreference) -> Color {
        preference == .dark ? .white : .black
    }

    private func preferenceIcon(_ preference: AppAppearancePreference) -> String {
        switch preference {
        case .system: return "iphone"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    private func preferenceSubtitle(_ preference: AppAppearancePreference) -> String {
        switch preference {
        case .system: return "Follows iPhone Dark Mode"
        case .light:  return "Always light interface"
        case .dark:   return "Always dark interface"
        }
    }
}
