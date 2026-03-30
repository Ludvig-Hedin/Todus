import SwiftUI
import SwiftData

/// macOS Settings panel — presented as a full-window overlay with dimmed backdrop.
/// Click outside or press Escape to dismiss.
///
/// Design: "Refined Editorial" — monochrome with whisper of accent.
/// Soft rounded cards, left-aligned labels, restrained spacing.
/// Feature-parity with iOS SettingsView.
struct MacSettingsView: View {
    @Binding var isPresented: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(MacAppServices.self) private var services

    @State private var showsLogoutConfirmation = false
    @State private var showsDeleteConfirmation = false
    @State private var showsDeleteAlert = false
    @State private var deleteConfirmText = ""
    @State private var showsDisconnectGmail = false

    // Preferences
    @AppStorage("preferredColorScheme") private var preferredColorScheme = "system"
    @AppStorage("taskRemindersEnabled") private var taskRemindersEnabled = true
    @AppStorage("calendarRemindersEnabled") private var calendarRemindersEnabled = true
    @AppStorage("swipeGesturesEnabled") private var swipeGesturesEnabled = true
    @AppStorage("threadGroupingEnabled") private var threadGroupingEnabled = true
    @AppStorage("mac_reminders_enabled") private var remindersEnabled = false

    // Accent color — stored key, resolved via MacTheme.accentColor(for:)
    @AppStorage("mac_accent_color") private var accentColorKey = "blue"

    // AI permissions
    @AppStorage("mac_ai_can_read_tasks") private var aiCanReadTasks = true
    @AppStorage("mac_ai_can_write_tasks") private var aiCanWriteTasks = true
    @AppStorage("mac_ai_tone") private var aiTone = "professional"

    private var calendarAccessGranted: Bool {
        services.calendarService.canReadEvents()
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().opacity(0.2)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    accountSection
                    connectedServicesSection
                    appearanceSection
                    emailPreferencesSection
                    aiAssistantSection
                    notificationsSection
                    aboutAndLegalSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.never)
        }
        .background(Color(light: Color(white: 0.96), dark: Color(white: 0.11)))
        .task { await services.emailService.checkConnection() }
        .task {
            // Refresh profile data (name, avatar) when settings opens — matches iOS SettingsView
            await services.authService.fetchUserProfile()
        }
        // Logout confirmation
        .confirmationDialog(
            "Are you sure you want to log out?",
            isPresented: $showsLogoutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Log out", role: .destructive) { services.authService.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can sign back in anytime.")
        }
        // Delete account — first confirmation
        .confirmationDialog(
            "Delete your account?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) { showsDeleteAlert = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete your account, tasks, email connections, and all data. This cannot be undone.")
        }
        // Delete account — type DELETE
        .alert("Type DELETE to confirm", isPresented: $showsDeleteAlert) {
            TextField("DELETE", text: $deleteConfirmText)
            Button("Delete Account", role: .destructive) {
                guard deleteConfirmText == "DELETE" else { return }
                Task { await performDeleteAccount() }
            }
            Button("Cancel", role: .cancel) { deleteConfirmText = "" }
        } message: {
            Text("This action is irreversible.")
        }
        // Disconnect Gmail
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

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MacTheme.textPrimary)
            Spacer()
            Button {
                withAnimation(.snappy(duration: 0.2)) { isPresented = false }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(MacTheme.mutedText)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .help("Close (Esc)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Account

    private var accountSection: some View {
        settingsCard {
            HStack(spacing: 10) {
                avatarView
                VStack(alignment: .leading, spacing: 1) {
                    if let name = services.authService.userName, !name.isEmpty {
                        Text(name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MacTheme.textPrimary)
                    }
                    if let email = services.authService.userEmail {
                        Text(email)
                            .font(.system(size: 11.5))
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if services.authService.isAuthenticated {
                cardDivider

                HStack {
                    Button(role: .destructive) {
                        showsLogoutConfirmation = true
                    } label: {
                        Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color(red: 0.82, green: 0.32, blue: 0.32))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(role: .destructive) {
                        showsDeleteConfirmation = true
                    } label: {
                        Text("Delete account")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(red: 0.82, green: 0.32, blue: 0.32).opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
        }
    }

    private var avatarView: some View {
        Group {
            if let imageURLString = services.authService.userImage,
               let imageURL = URL(string: imageURLString) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                            .frame(width: 36, height: 36).clipShape(Circle())
                    default:
                        avatarFallback
                    }
                }
            } else {
                avatarFallback
            }
        }
    }

    private var avatarFallback: some View {
        ZStack {
            Circle()
                .fill(MacTheme.accent.opacity(0.1))
                .frame(width: 36, height: 36)
            if let name = services.authService.userName ?? services.authService.userEmail,
               let first = name.first {
                Text(String(first).uppercased())
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(MacTheme.accent)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(MacTheme.mutedText)
            }
        }
    }

    // MARK: - Connected Services

    private var connectedServicesSection: some View {
        settingsGroup(title: "Connected Services") {
            settingsCard {
                // Gmail — uses real Gmail logo
                brandServiceRow(
                    icon: { GmailIconView(size: 26) },
                    name: "Gmail",
                    status: services.emailService.hasConnection ? "Connected" : "Not connected",
                    isConnected: services.emailService.hasConnection
                ) {
                    if services.emailService.hasConnection {
                        Button("Disconnect") { showsDisconnectGmail = true }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(red: 0.82, green: 0.32, blue: 0.32).opacity(0.7))
                            .buttonStyle(.plain)
                    } else {
                        connectButton {
                            Task { await services.emailService.connectGmail(authService: services.authService) }
                        }
                    }
                }

                cardDivider

                // Apple Calendar — uses real Calendar logo
                brandServiceRow(
                    icon: { AppleCalendarIconView(size: 26) },
                    name: "Apple Calendar",
                    status: calendarAccessGranted ? "Connected" : "Not connected",
                    isConnected: calendarAccessGranted
                ) {
                    if calendarAccessGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green.opacity(0.7))
                            .font(.system(size: 13))
                    } else {
                        connectButton {
                            Task { await services.calendarService.requestAccess() }
                        }
                    }
                }

                cardDivider

                // Apple Reminders — uses real Reminders logo
                brandServiceRow(
                    icon: { AppleRemindersIconView(size: 26) },
                    name: "Apple Reminders",
                    status: remindersEnabled ? "Connected" : "Not connected",
                    isConnected: remindersEnabled
                ) {
                    if remindersEnabled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green.opacity(0.7))
                            .font(.system(size: 13))
                    } else {
                        connectButton {
                            remindersEnabled = true
                        }
                    }
                }
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        settingsGroup(title: "Appearance") {
            settingsCard {
                // Theme picker
                rowContainer {
                    Image(systemName: "moon.stars")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                        .frame(width: 18)
                    Text("Theme")
                        .font(.system(size: 12.5))
                        .foregroundStyle(MacTheme.textPrimary)
                    Spacer()
                    Picker("", selection: $preferredColorScheme) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }

                cardDivider

                // Accent color picker
                rowContainer {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                        .frame(width: 18)
                    Text("Accent")
                        .font(.system(size: 12.5))
                        .foregroundStyle(MacTheme.textPrimary)
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(MacTheme.accentColorKeys, id: \.self) { key in
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    accentColorKey = key
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(MacTheme.accentColor(for: key))
                                        .frame(width: 18, height: 18)
                                    if accentColorKey == key {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 8.5, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Email & Preferences

    private var emailPreferencesSection: some View {
        settingsGroup(title: "Email") {
            settingsCard {
                settingsToggle(icon: "hand.draw", label: "Swipe Gestures", isOn: $swipeGesturesEnabled)
                cardDivider
                settingsToggle(icon: "text.bubble", label: "Group by Thread", isOn: $threadGroupingEnabled)
            }
        }
    }

    // MARK: - AI Assistant

    private var aiAssistantSection: some View {
        @Bindable var ai = services.aiChatService
        return settingsGroup(title: "AI Assistant") {
            settingsCard {
                settingsToggle(icon: "eye", label: "Read my tasks", isOn: $aiCanReadTasks)

                cardDivider

                settingsToggle(icon: "pencil", label: "Create & edit tasks", isOn: $aiCanWriteTasks)

                cardDivider

                // Response tone — matches iOS AITonePreference cases
                rowContainer {
                    Image(systemName: "text.quote")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                        .frame(width: 18)
                    Text("Response Tone")
                        .font(.system(size: 12.5))
                        .foregroundStyle(MacTheme.textPrimary)
                    Spacer()
                    Picker("", selection: $aiTone) {
                        Text("Professional").tag("professional")
                        Text("Casual").tag("casual")
                        Text("Concise").tag("concise")
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 110)
                }

                cardDivider

                // AI model — live-bound to MacAIChatService
                rowContainer {
                    Image(systemName: "cpu")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                        .frame(width: 18)
                    Text("AI Model")
                        .font(.system(size: 12.5))
                        .foregroundStyle(MacTheme.textPrimary)
                    Spacer()
                    Picker("", selection: $ai.selectedModel) {
                        Text("GPT-5.4 mini").tag("openai/gpt-5.4-mini")
                        Text("GPT-5.4").tag("openai/gpt-5.4-chat")
                        Text("Gemini 3 Flash").tag("google/gemini-3-flash-preview")
                        Text("Claude Haiku").tag("anthropic/claude-haiku-4-5")
                        Text("Kimi K2.5").tag("moonshotai/kimi-k2.5")
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 120)
                }
            }
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        settingsGroup(title: "Notifications") {
            settingsCard {
                settingsToggle(icon: "checklist", label: "Task Due Reminders", isOn: $taskRemindersEnabled)

                cardDivider

                settingsToggle(icon: "calendar.badge.clock", label: "Calendar Reminders", isOn: $calendarRemindersEnabled)

                cardDivider

                // Open macOS System Settings > Notifications
                rowContainer {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                        .frame(width: 18)
                    Text("System Settings")
                        .font(.system(size: 12.5))
                        .foregroundStyle(MacTheme.textPrimary)
                    Spacer()
                    Button {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10.5))
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - About & Legal

    private var aboutAndLegalSection: some View {
        settingsGroup(title: "About") {
            settingsCard {
                infoRow(icon: "info.circle", label: "Version",
                        value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                cardDivider
                infoRow(icon: "hammer", label: "Build",
                        value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                cardDivider
                infoRow(icon: "desktopcomputer", label: "Platform", value: "macOS")
                cardDivider
                infoRow(icon: "lock.shield", label: "Data Sync", value: "End-to-end")
            }

            // Legal links — separate card for visual distinction
            settingsCard {
                linkRow(icon: "doc.text", label: "Privacy Policy") {
                    openURL("https://todus.app/privacy")
                }
                cardDivider
                linkRow(icon: "doc.text", label: "Terms of Service") {
                    openURL("https://todus.app/terms")
                }
                cardDivider
                linkRow(icon: "envelope", label: "Contact Us") {
                    openURL("mailto:hello@todus.app")
                }
            }
        }
    }

    // MARK: - Shared Components

    /// Section title — sentence case, soft muted weight.
    private func settingsGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MacTheme.mutedText)
                .padding(.leading, 2)
            content()
        }
    }

    /// Rounded card container with soft border.
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
    }

    /// Thin divider between rows within a card.
    private var cardDivider: some View {
        Divider().opacity(0.12).padding(.horizontal, 12)
    }

    /// Generic row container — icon + label + trailing content.
    private func rowContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 7) {
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    /// Toggle row — icon left, label, spacer, switch right.
    /// Labels are always left-aligned; switch is always right-aligned.
    private func settingsToggle(icon: String, label: String, isOn: Binding<Bool>) -> some View {
        rowContainer {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MacTheme.mutedText)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(MacTheme.textPrimary)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }

    /// Info row — icon + label on left, value text on right.
    private func infoRow(icon: String, label: String, value: String) -> some View {
        rowContainer {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MacTheme.mutedText)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(MacTheme.textPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 11.5))
                .foregroundStyle(MacTheme.textSecondary)
        }
    }

    /// Tappable link row — icon + label on left, arrow on right.
    private func linkRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowContainer {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MacTheme.mutedText)
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 12.5))
                    .foregroundStyle(MacTheme.textPrimary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MacTheme.mutedText)
            }
        }
        .buttonStyle(.plain)
    }

    /// Branded service row — custom icon view, name, status, trailing action.
    private func brandServiceRow<Icon: View, Trailing: View>(
        @ViewBuilder icon: () -> Icon,
        name: String,
        status: String,
        isConnected: Bool,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 8) {
            icon()
                .frame(width: 26, height: 26)
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(MacTheme.textPrimary)
                Text(status)
                    .font(.system(size: 10.5))
                    .foregroundStyle(isConnected ? .green.opacity(0.7) : MacTheme.mutedText)
            }

            Spacer()
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Small "Connect" button used in service rows.
    private func connectButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Connect")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MacTheme.accent)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func openURL(_ string: String) {
        if let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Actions

    private func performDeleteAccount() async {
        do {
            try await services.apiClient.deleteAccount()
        } catch {
            print("[Settings] Delete account failed: \(error)")
        }
        deleteConfirmText = ""
        services.authService.signOut()
        try? modelContext.delete(model: TaskRecord.self)
        try? modelContext.delete(model: FolderRecord.self)
        try? modelContext.save()
        isPresented = false
    }

    private func performDisconnectGmail() async {
        do {
            try await services.apiClient.disconnectEmail()
            await services.emailService.checkConnection()
        } catch {
            print("[Settings] Disconnect Gmail failed: \(error)")
        }
    }
}
