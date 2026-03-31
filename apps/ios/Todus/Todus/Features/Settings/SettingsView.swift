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
    @State private var isRevokingAllSessions = false
    @State private var revokingSessionIDs: Set<String> = []

    private var calendarAccessGranted: Bool {
        services.calendarService.canReadEvents()
    }

    var body: some View {
        NavigationStack {
            List {
                accountSection
                activeSessionsSection
                connectedServicesSection

                // Appearance + Preferences
                preferencesAndAppearanceSection

                // Email preferences — separate from AI to reduce cognitive load
                emailSection

                // AI Assistant — separate section for clarity
                aiAssistantSection

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

    private var activeSessionsSection: some View {
        Section {
            if isLoadingSessions {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
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
                // Vertical session cards — much more readable on mobile than a horizontal table
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
                            // Log out button — only for non-current sessions
                            if session.isCurrent != true {
                                Button(role: .destructive) {
                                    Task { await revokeSession(session.id) }
                                } label: {
                                    if revokingSessionIDs.contains(session.id) {
                                        ProgressView()
                                            .scaleEffect(0.7)
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
                            Label(formatSessionDate(session.updatedAt), systemImage: "clock")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Log out all other devices
                if activeSessions.count > 1 {
                    Button(role: .destructive) {
                        Task { await revokeAllSessions() }
                    } label: {
                        HStack {
                            if isRevokingAllSessions {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(isRevokingAllSessions ? "Signing out…" : "Log out all other devices")
                        }
                    }
                    .disabled(isRevokingAllSessions)
                }
            }
        } header: {
            Text("Active Sessions")
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

    // MARK: - Appearance Helpers

    @ViewBuilder
    private func appearanceOption(_ preference: AppAppearancePreference) -> some View {
        let isSelected = services.appearancePreference == preference

        Button {
            services.appearancePreference = preference
        } label: {
            VStack(spacing: 8) {
                // Mini preview swatch
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(previewBackground(for: preference))
                        .frame(height: 52)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    isSelected ? Color.blue : Color(UIColor.separator).opacity(0.4),
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )

                    VStack(spacing: 4) {
                        Capsule()
                            .fill(previewAccent(for: preference).opacity(0.3))
                            .frame(width: 28, height: 5)
                        Capsule()
                            .fill(previewAccent(for: preference).opacity(0.15))
                            .frame(width: 38, height: 4)
                        Capsule()
                            .fill(previewAccent(for: preference).opacity(0.10))
                            .frame(width: 30, height: 4)
                    }

                    if isSelected {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.blue)
                                    .padding(4)
                            }
                            Spacer()
                        }
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: preferenceIcon(preference))
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? .blue : .secondary)
                    Text(preference.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .blue : .primary)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func previewBackground(for preference: AppAppearancePreference) -> Color {
        switch preference {
        case .system:
            return Color(UIColor.systemBackground)
        case .light:
            return Color(UIColor(white: 0.98, alpha: 1))
        case .dark:
            return Color(UIColor(white: 0.08, alpha: 1))
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

    // Old individual sections removed — replaced by combined sections above
    // (preferencesAndAppearanceSection, emailAndAISection, notificationsAndPrivacySection)

    // MARK: - Combined: Preferences + Appearance

    private var preferencesAndAppearanceSection: some View {
        Section {
            // Theme picker (from Appearance)
            VStack(alignment: .leading, spacing: 12) {
                Text("Theme")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    ForEach(AppAppearancePreference.allCases) { preference in
                        appearanceOption(preference)
                    }
                }
            }
            .padding(.vertical, 6)

            // Default View picker (from Preferences)
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

    // MARK: - AI Assistant

    private var aiAssistantSection: some View {
        @Bindable var ai = services.aiChatService
        return Section {
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

            VStack(alignment: .leading, spacing: 10) {
                Text("Context about you")
                    .font(.system(size: 15, weight: .medium))
                TextEditor(
                    text: Binding(
                        get: { services.contextAboutYou },
                        set: { services.contextAboutYou = $0 }
                    )
                )
                .frame(minHeight: 100)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Custom instructions")
                    .font(.system(size: 15, weight: .medium))
                TextEditor(
                    text: Binding(
                        get: { services.customInstructions },
                        set: { services.customInstructions = $0 }
                    )
                )
                .frame(minHeight: 100)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        } header: {
            Text("AI Assistant")
        } footer: {
            Text("Controls what the AI can read and modify, and how it responds to you.")
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

    private func headerCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
    }

    private func valueCell(_ text: String, width: CGFloat, emphasized: Bool = false) -> some View {
        Text(text)
            .font(.system(size: emphasized ? 13 : 12, weight: emphasized ? .medium : .regular))
            .frame(width: width, alignment: .leading)
            .lineLimit(2)
    }

    private func formatSessionDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
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

    private func revokeSession(_ sessionId: String) async {
        revokingSessionIDs.insert(sessionId)
        defer { revokingSessionIDs.remove(sessionId) }

        do {
            let response = try await services.apiClient.revokeSession(sessionId: sessionId)
            await loadActiveSessions()
            if response.revokedCurrent {
                performLogout()
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
                performLogout()
            } else {
                await services.authService.fetchUserProfile()
            }
        } catch {
            AppLogger.shared.log("Revoke all sessions failed: \(error.localizedDescription)")
        }
    }
}
