import SwiftUI
import SwiftData
import AppKit

/// macOS Settings panel — presented as a full-window overlay with dimmed backdrop.
/// Click outside or press Escape to dismiss.
///
/// Design: "Refined Editorial" — monochrome with whisper of accent.
/// Soft rounded cards, left-aligned labels, restrained spacing.
/// Feature-parity with iOS SettingsView.
struct MacSettingsView: View {
    private enum PrivacyPreference: String {
        case analytics
        case crashReports
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(MacAppServices.self) private var services

    @State private var showsLogoutConfirmation = false
    @State private var showsLocalModels = false
    @State private var showsDesignSystem = false
    @State private var showsDeleteConfirmation = false
    @State private var showsDeleteAlert = false
    @State private var deleteConfirmText = ""
    @State private var showsDisconnectGmail = false
    @State private var activeSessions: [ActiveSessionRecord] = []
    @State private var isLoadingSessions = false
    @State private var isRevokingAllSessions = false
    @State private var revokingSessionIDs: Set<String> = []
    @State private var sessionsLoadError: String? = nil
    @State private var settingsError: String?
    @State private var showAutoSendConfirmation = false
    @State private var showApplyRecommendedConfirmation = false
    @State private var excludedSenderPatternsText = ""
    @State private var isConnectingReminders = false
    @State private var isOpeningBillingPortal = false
    @State private var isCancelingSubscription = false
    @State private var showCancelSubscriptionConfirm = false
    @State private var billingError: String?

    // Preferences
    @AppStorage("preferredColorScheme") private var preferredColorScheme = "system"
    @AppStorage("taskRemindersEnabled") private var taskRemindersEnabled = true
    @AppStorage("calendarRemindersEnabled") private var calendarRemindersEnabled = true
    // NOTE: Swipe gestures are an iOS-only concept. The previous toggle here was
    // never wired into anything on macOS, so the row is intentionally removed
    // from the UI rather than left dead. Re-add the @AppStorage + the row in
    // emailPreferencesSection if/when trackpad swipe gestures are implemented.
    @AppStorage("threadGroupingEnabled") private var threadGroupingEnabled = true

    // Accent color — stored key, resolved via MacTheme.accentColor(for:)
    @AppStorage("mac_accent_color") private var accentColorKey = "blue"

    // Default tasks view — shared with MacTasksView via the existing AppStorage key.
    @AppStorage("TaskApp.selectedViewMode") private var defaultTaskViewModeRaw = TaskViewMode.list.rawValue

    // General preferences
    @AppStorage("mac_compact_sidebar") private var compactSidebar = false
    @AppStorage("mac_show_unread_badge") private var showUnreadBadge = true
    @AppStorage("mac_focus_mode_enabled") private var focusModeEnabled = false

    // Privacy
    @AppStorage("mac_analytics_enabled") private var analyticsEnabled = false
    @AppStorage("mac_crash_reports_enabled") private var crashReportsEnabled = false
    @AppStorage("mac_privacy_consent_accepted") private var privacyConsentAccepted = false
    @State private var pendingPrivacyPreference: PrivacyPreference?
    @State private var showsPrivacyConsentDialog = false

    // AI permissions — keys match iOS for cross-device parity once we sync settings.
    @AppStorage("mac_ai_can_read_tasks") private var aiCanReadTasks = true
    @AppStorage("mac_ai_can_write_tasks") private var aiCanWriteTasks = true
    @AppStorage("ai_can_read_calendar") private var aiCanReadCalendar = true
    @AppStorage("ai_can_write_calendar") private var aiCanWriteCalendar = true
    @AppStorage("ai_can_read_email") private var aiCanReadEmail = true
    @AppStorage("ai_can_send_email") private var aiCanSendEmail = true
    @AppStorage("mac_ai_tone") private var aiTone = "professional"

    private var calendarAccessGranted: Bool {
        services.calendarService.canReadEvents()
    }

    private var isLikelyEURegion: Bool {
        let region = Locale.current.region?.identifier.uppercased() ?? ""
        return Self.europeanPrivacyRegions.contains(region)
    }

    private var needsPrivacyConsentBanner: Bool {
        isLikelyEURegion && !privacyConsentAccepted
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().opacity(0.2)
            ScrollView {
                VStack(alignment: .leading, spacing: MacTheme.settingsSectionSpacing) {
                    accountSection
                    activeSessionsSection
                    connectedServicesSection
                    calendarAccountsSection
                    generalSection
                    appearanceSection
                    aiAssistantSection
                    emailPreferencesSection
                    signaturesSection
                    voiceAssistantSection
                    billingSection
                    notificationsSection
                    privacySection
                    if services.isDeveloperModeUIAvailable {
                        developerModeToggleSection
                    }
                    if services.effectiveDeveloperModeEnabled {
                        authDebugSection
                        designSystemSection
                    }
                    aboutAndLegalSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.never)
        }
        .background(MacTheme.contentBackground)
        // Sync settings changes to the backend so iOS / macOS / web stay aligned.
        .onChange(of: aiCanReadTasks) { _, value in
            Task { await services.syncSetting("aiCanReadTasks", value) }
        }
        .onChange(of: aiCanWriteTasks) { _, value in
            Task { await services.syncSetting("aiCanWriteTasks", value) }
        }
        .onChange(of: aiCanReadCalendar) { _, value in
            Task { await services.syncSetting("aiCanReadCalendar", value) }
        }
        .onChange(of: aiCanWriteCalendar) { _, value in
            Task { await services.syncSetting("aiCanWriteCalendar", value) }
        }
        .onChange(of: aiCanReadEmail) { _, value in
            Task { await services.syncSetting("aiCanReadEmail", value) }
        }
        .onChange(of: aiCanSendEmail) { _, value in
            Task { await services.syncSetting("aiCanSendEmail", value) }
        }
        .onChange(of: accentColorKey) { _, value in
            Task { await services.syncSetting("accentColor", value) }
        }
        .onChange(of: defaultTaskViewModeRaw) { _, value in
            Task { await services.syncSetting("defaultTaskView", value) }
        }
        .onChange(of: compactSidebar) { _, value in
            Task { await services.syncSetting("compactSidebar", value) }
        }
        .onChange(of: showUnreadBadge) { _, value in
            Task { await services.syncSetting("showUnreadBadge", value) }
        }
        .onChange(of: focusModeEnabled) { _, value in
            Task { await services.syncSetting("focusModeEnabled", value) }
        }
        .onChange(of: threadGroupingEnabled) { _, value in
            Task { await services.syncSetting("groupByThread", value) }
        }
        .task { await services.emailService.checkConnection() }
        .task {
            // Refresh profile data (name, avatar) when settings opens — matches iOS SettingsView
            await services.authService.fetchUserProfile()
            await services.loadSharedAIProfile()
            excludedSenderPatternsText = services.assistantAutomationPolicy.excludedSenderPatterns
                .joined(separator: "\n")
        }
        .task {
            await loadActiveSessions()
        }
        .task {
            await services.subscriptionService.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .todusRequestConnectGmail)) { _ in
            Task { await services.emailService.connectGmail(authService: services.authService) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .todusRequestReconnectGmail)) { _ in
            Task { await services.emailService.connectGmail(authService: services.authService) }
        }
        .confirmationDialog(
            "Enable low-risk auto-send?",
            isPresented: $showAutoSendConfirmation,
            titleVisibility: .visible
        ) {
            Button("Enable") {
                services.assistantAutomationPolicy.autoSendExperimentEnabled = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only narrow, high-confidence acknowledgements and confirmations become eligible. Review the experiment notes before turning this on.")
        }
        .confirmationDialog(
            "Replace all Mail Assistant settings with the recommended defaults?",
            isPresented: $showApplyRecommendedConfirmation,
            titleVisibility: .visible
        ) {
            Button("Apply recommended", role: .destructive) {
                services.assistantAutomationPolicy = .recommended
                excludedSenderPatternsText = services.assistantAutomationPolicy
                    .excludedSenderPatterns
                    .joined(separator: "\n")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This overwrites every Mail Assistant toggle, workday hours, quiet hours, and excluded sender patterns with the recommended values. Your custom values will be lost.")
        }
        .confirmationDialog(
            privacyConsentTitle,
            isPresented: $showsPrivacyConsentDialog,
            titleVisibility: .visible
        ) {
            Button("Allow") {
                privacyConsentAccepted = true
                applyPrivacyPreferenceSelection(true)
            }
            Button("Not now", role: .cancel) {
                pendingPrivacyPreference = nil
            }
        } message: {
            Text(privacyConsentMessage)
        }
        // Logout confirmation
        .confirmationDialog(
            "Are you sure you want to log out?",
            isPresented: $showsLogoutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Log out", role: .destructive) { services.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can sign back in anytime.")
        }
        // Cancel subscription
        .confirmationDialog(
            "Cancel your Pro subscription?",
            isPresented: $showCancelSubscriptionConfirm,
            titleVisibility: .visible
        ) {
            Button("Cancel subscription", role: .destructive) {
                Task { await performCancelSubscription() }
            }
            Button("Keep Pro", role: .cancel) {}
        } message: {
            Text("You'll keep access until the end of the current billing period.")
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
        .alert("Error", isPresented: Binding(
            get: { settingsError != nil },
            set: { if !$0 { settingsError = nil } }
        )) {
            Button("OK", role: .cancel) { settingsError = nil }
        } message: {
            Text(settingsError ?? "")
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
                Task { @MainActor in
                    await services.saveSharedAIProfile()
                    dismiss()
                }
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

                    // Hard separation between Log out (recoverable) and Delete
                    // (irreversible) so a stray click can't slide between them.
                    Spacer().frame(minWidth: 24)
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

    private var activeSessionsSection: some View {
        settingsGroup(title: "Security") {
            settingsCard {
                HStack(spacing: 12) {
                    sessionHeader("Device", width: 170)
                    sessionHeader("Location", width: 140)
                    sessionHeader("Created", width: 140)
                    sessionHeader("Updated", width: 140)
                    sessionHeader("Action", width: 80)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                cardDivider

                if isLoadingSessions {
                    rowContainer {
                        Text("Loading active sessions…")
                            .font(.system(size: 12.5))
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                } else if let error = sessionsLoadError {
                    rowContainer {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Couldn't load sessions")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(MacTheme.textPrimary)
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundStyle(MacTheme.textSecondary)
                            Button("Try again") {
                                Task { await loadActiveSessions() }
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                        }
                    }
                } else if activeSessions.isEmpty {
                    rowContainer {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No active sessions found")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(MacTheme.textPrimary)
                            Text("New sign-ins will appear here automatically.")
                                .font(.system(size: 11))
                                .foregroundStyle(MacTheme.textSecondary)
                        }
                    }
                } else {
                    ForEach(activeSessions) { activeSession in
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                sessionValue(
                                    activeSession.device + ((activeSession.isCurrent ?? false) ? " (Current)" : ""),
                                    width: 170,
                                    emphasized: true
                                )
                                sessionValue(activeSession.location, width: 140)
                                sessionValue(formatSessionDate(activeSession.createdAt), width: 140)
                                sessionValue(formatSessionDate(activeSession.updatedAt), width: 140)

                                Button(role: .destructive) {
                                    Task { await revokeSession(activeSession.id) }
                                } label: {
                                    if revokingSessionIDs.contains(activeSession.id) {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Text("Log out")
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(isRevokingAllSessions || revokingSessionIDs.contains(activeSession.id))
                                .frame(width: 80, alignment: .leading)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)

                            if activeSession.id != activeSessions.last?.id {
                                cardDivider
                            }
                        }
                    }
                }

                cardDivider

                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        Task { await revokeAllSessions() }
                    } label: {
                        if isRevokingAllSessions {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Log out all devices")
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isRevokingAllSessions || activeSessions.isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - General

    private var generalSection: some View {
        settingsGroup(title: "General") {
            settingsCard {
                // Startup view — which tab opens when the app launches
                rowContainer {
                    Image(systemName: "house")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                        .frame(width: 18)
                    Text("Open on Launch")
                        .font(.system(size: 12.5))
                        .foregroundStyle(MacTheme.textPrimary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { services.startupView },
                        set: { services.startupView = $0 }
                    )) {
                        Text("Home").tag("home")
                        Text("Inbox").tag("inbox")
                        Text("Tasks").tag("tasks")
                        Text("Meetings").tag("meetings")
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 110)
                }

                cardDivider

                rowContainer {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Resume Last Viewed Page")
                            .font(.system(size: 12.5))
                            .foregroundStyle(MacTheme.textPrimary)
                        Text("When off, Todus always opens on the launch page above.")
                            .font(.system(size: 11))
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                    Spacer()
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { services.restoreLastViewedPage },
                            set: { services.restoreLastViewedPage = $0 }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .tint(MacTheme.switchTint)
                }

                cardDivider

                settingsToggle(icon: "sidebar.left", label: "Compact Sidebar", isOn: $compactSidebar)

                cardDivider

                settingsToggle(icon: "app.badge", label: "Show Unread Badge", isOn: $showUnreadBadge)

                cardDivider

                settingsToggle(icon: "moon.zzz", label: "Focus Mode (hide AI nudges)", isOn: $focusModeEnabled)
            }
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        settingsGroup(title: "Privacy") {
            settingsCard {
                if needsPrivacyConsentBanner {
                    privacyConsentBanner
                    cardDivider
                }

                settingsToggle(
                    icon: "chart.bar",
                    label: "Send Usage Analytics",
                    isOn: privacyToggleBinding(.analytics)
                )

                cardDivider

                settingsToggle(
                    icon: "exclamationmark.triangle",
                    label: "Send Crash Reports",
                    isOn: privacyToggleBinding(.crashReports)
                )

                cardDivider

                linkRow(icon: "lock.shield", label: "Privacy Policy") {
                    openURL("https://todus.app/privacy")
                }
            }
        }
    }

    // MARK: - Voice Assistant

    /// Phase-1 voice settings. Two switches:
    ///   • Master: registers the global ⌘⇧Space push-to-talk hotkey.
    ///   • Wake word: opt-in always-listening (Phase 1 ships a fail-soft
    ///     stub; full Porcupine support arrives in Phase 1.5).
    private var voiceAssistantSection: some View {
        settingsGroup(title: "Voice Assistant") {
            settingsCard {
                rowContainer {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Voice assistant")
                            .font(.system(size: 12.5))
                            .foregroundStyle(MacTheme.textPrimary)
                        Text("Press ⌘⇧Space to talk to Todus from anywhere.")
                            .font(.system(size: 11))
                            .foregroundStyle(MacTheme.mutedText)
                    }
                    Spacer()
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { services.voiceAssistantEnabled },
                            set: { services.voiceAssistantEnabled = $0 }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                }
                cardDivider
                rowContainer {
                    Image(systemName: "ear")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Always-listening (wake word) (Coming soon)")
                            .font(.system(size: 12.5))
                            .foregroundStyle(MacTheme.textPrimary)
                        Text("Listen for \"Hey computer\" in the background. Requires Porcupine integration — currently disabled.")
                            .font(.system(size: 11))
                            .foregroundStyle(MacTheme.mutedText)
                    }
                    Spacer()
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { services.voiceWakeWordEnabled },
                            set: { services.voiceWakeWordEnabled = $0 }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    // Disabled until the Phase 1.5 Porcupine integration ships;
                    // toggling this had no functional effect (stub fail-soft).
                    .disabled(true)
                    .help("Coming soon — wake-word detector not yet shipped.")
                }
            }
        }
    }

    // MARK: - Developer (allowlisted users only)

    private var developerModeToggleSection: some View {
        settingsGroup(title: "Developer") {
            settingsCard {
                rowContainer {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                        .frame(width: 18)
                    Text("Developer Mode")
                        .font(.system(size: 12.5))
                        .foregroundStyle(MacTheme.textPrimary)
                    Spacer()
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { services.developerModeEnabled },
                            set: { services.developerModeEnabled = $0 }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .tint(.orange)
                }
            }
        }
    }

    private var authDebugSection: some View {
        settingsGroup(title: "Auth Debug") {
            settingsCard {
                infoRow(icon: "person.crop.circle.badge.checkmark", label: "Auth state",
                        value: services.authService.isAuthenticated ? "Authenticated" : "Guest")
                cardDivider
                infoRow(icon: "key.fill", label: "Bearer token",
                        value: services.authService.bearerTokenPreview)
                cardDivider
                infoRow(icon: "exclamationmark.shield", label: "Session expired",
                        value: services.authService.isSessionExpired ? "Yes" : "No")
                cardDivider
                infoRow(icon: "at", label: "Profile email",
                        value: services.authService.userEmail ?? "—")
            }
        }
    }

    /// Live macOS design-token viewer — gated to developer mode (which already
    /// requires the allowlist via `effectiveDeveloperModeEnabled`).
    private var designSystemSection: some View {
        settingsGroup(title: "Design System") {
            settingsCard {
                Button {
                    showsDesignSystem = true
                } label: {
                    rowContainer {
                        Image(systemName: "paintbrush.pointed")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MacTheme.mutedText)
                            .frame(width: 18)
                        Text("Design System")
                            .font(.system(size: 12.5))
                            .foregroundStyle(MacTheme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MacTheme.mutedText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .macClickablePointer()
            }
        }
        .sheet(isPresented: $showsDesignSystem) {
            MacDesignSystemView()
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
                            .macClickablePointer()
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
                    status: services.remindersSyncEnabled ? "Connected" : "Not connected",
                    isConnected: services.remindersSyncEnabled
                ) {
                    if services.remindersSyncEnabled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green.opacity(0.7))
                            .font(.system(size: 13))
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
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(MacTheme.accent)
                        }
                        .buttonStyle(.plain)
                        .macClickablePointer()
                        .disabled(isConnectingReminders)
                    }
                }
            }
        }
    }

    // MARK: - Calendar Accounts

    private var calendarAccountsSection: some View {
        settingsGroup(title: "Calendars") {
            settingsCard {
                MacCalendarAccountsList()
                    .environment(services)
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
                                withAnimation(MacTheme.Motion.fast) {
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
                            .help(key.capitalized)
                        }
                    }
                }

                cardDivider

                // Default tasks view — parity with iOS Settings → Preferences → Default View.
                rowContainer {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                        .frame(width: 18)
                    Text("Default View")
                        .font(.system(size: 12.5))
                        .foregroundStyle(MacTheme.textPrimary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { TaskViewMode(rawValue: defaultTaskViewModeRaw) ?? .list },
                        set: { defaultTaskViewModeRaw = $0.rawValue }
                    )) {
                        ForEach(TaskViewMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 130)
                }
            }
        }
    }

    // MARK: - Email & Preferences

    private var emailPreferencesSection: some View {
        settingsGroup(title: "Email") {
            settingsCard {
                settingsToggle(icon: "text.bubble", label: "Group by Thread", isOn: $threadGroupingEnabled)
            }
        }
    }

    // MARK: - Signatures
    //
    // Per-connection email signatures persisted in `MacSignatureStore`.
    // Each connected mailbox gets its own multi-line editor so multi-account
    // users can keep distinct sign-offs. Saves are debounced (500ms) so we
    // don't slam UserDefaults on every keystroke.

    private var signaturesSection: some View {
        settingsGroup(title: "Signatures") {
            settingsCard {
                if services.connectionsService.connections.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No connected accounts")
                            .font(.system(size: 12.5))
                            .foregroundStyle(MacTheme.textPrimary)
                        Text("Connect a Gmail account above to set a signature.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                } else {
                    ForEach(Array(services.connectionsService.connections.enumerated()), id: \.element.id) { index, connection in
                        if index > 0 {
                            cardDivider
                        }
                        MacSignatureEditorRow(connection: connection)
                    }
                }
            }
        }
        .task {
            // Pull the connection list so the editors render even on a cold
            // settings open. Mirrors the calendar accounts list behaviour.
            if services.connectionsService.connections.isEmpty {
                await services.connectionsService.loadConnections()
            }
        }
    }

    // MARK: - AI Assistant

    private var aiAssistantSection: some View {
        @Bindable var ai = services.aiChatService
        return settingsGroup(title: "AI Assistant") {
            settingsCard {
                settingsToggle(icon: "checklist", label: "Read my tasks", isOn: $aiCanReadTasks)

                cardDivider

                settingsToggle(icon: "square.and.pencil", label: "Create & edit tasks", isOn: $aiCanWriteTasks)

                cardDivider

                settingsToggle(icon: "calendar", label: "Read calendar", isOn: $aiCanReadCalendar)

                cardDivider

                settingsToggle(icon: "calendar.badge.plus", label: "Create calendar events", isOn: $aiCanWriteCalendar)

                cardDivider

                settingsToggle(icon: "envelope", label: "Read email", isOn: $aiCanReadEmail)

                cardDivider

                settingsToggle(icon: "paperplane", label: "Send email", isOn: $aiCanSendEmail)

                cardDivider

                VStack(alignment: .leading, spacing: 6) {
                    Text("Location")
                        .font(.system(size: 12.5))
                        .foregroundStyle(MacTheme.textPrimary)
                    TextField(
                        "e.g. Oslo, Norway",
                        text: Binding(
                            get: { services.location },
                            set: { services.location = $0 }
                        )
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MacTheme.inputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous))
                    Text("City and country (e.g. \"Oslo, Norway\"). Optional — gives the AI location context.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(MacTheme.textSecondary)
                }
                .padding(.horizontal, MacTheme.settingsRowHorizontalPadding)
                .padding(.vertical, MacTheme.settingsRowVerticalPadding)

                cardDivider

                VStack(alignment: .leading, spacing: 8) {
                    Text("Context about you")
                        .font(.system(size: 12.5))
                        .foregroundStyle(MacTheme.textPrimary)
                    MacPlaceholderTextEditor(
                        text: Binding(
                            get: { services.contextAboutYou },
                            set: { services.contextAboutYou = $0 }
                        ),
                        placeholder: "Anything the assistant should know about you — your role, projects, tone, communication style…"
                    )
                }
                .padding(.horizontal, MacTheme.settingsRowHorizontalPadding)
                .padding(.vertical, MacTheme.settingsRowVerticalPadding)

                cardDivider

                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom instructions")
                        .font(.system(size: 12.5))
                        .foregroundStyle(MacTheme.textPrimary)
                    MacPlaceholderTextEditor(
                        text: Binding(
                            get: { services.customInstructions },
                            set: { services.customInstructions = $0 }
                        ),
                        placeholder: "e.g. Keep replies under 3 sentences. Never use emojis. Always end with “— Ludvig”."
                    )
                }
                .padding(.horizontal, MacTheme.settingsRowHorizontalPadding)
                .padding(.vertical, MacTheme.settingsRowVerticalPadding)

                cardDivider

                rowContainer {
                    Text("Mail Assistant")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(MacTheme.textPrimary)
                    Spacer()
                    Button("Apply recommended defaults") {
                        showApplyRecommendedConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                cardDivider

                settingsToggle(
                    icon: "rectangle.stack.badge.person.crop",
                    label: "Enable assistant briefing engine",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.briefingEnabled },
                        set: { services.assistantAutomationPolicy.briefingEnabled = $0 }
                    )
                )

                cardDivider

                settingsToggle(
                    icon: "house",
                    label: "Show Home briefing",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.showHomeBriefing },
                        set: { services.assistantAutomationPolicy.showHomeBriefing = $0 }
                    )
                )

                cardDivider

                settingsToggle(
                    icon: "text.append",
                    label: "Auto summarize long threads",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.autoSummarizeLongThreads },
                        set: { services.assistantAutomationPolicy.autoSummarizeLongThreads = $0 }
                    )
                )

                cardDivider

                settingsToggle(
                    icon: "checklist",
                    label: "Suggest tasks from email",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.suggestTasksFromEmail },
                        set: { services.assistantAutomationPolicy.suggestTasksFromEmail = $0 }
                    )
                )

                cardDivider

                settingsToggle(
                    icon: "calendar.badge.plus",
                    label: "Suggest events from email",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.suggestEventsFromEmail },
                        set: { services.assistantAutomationPolicy.suggestEventsFromEmail = $0 }
                    )
                )

                cardDivider

                settingsToggle(
                    icon: "arrowshape.turn.up.left",
                    label: "Auto draft replies",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.autoDraftReplies },
                        set: { services.assistantAutomationPolicy.autoDraftReplies = $0 }
                    )
                )

                cardDivider

                settingsToggle(
                    icon: "tray.full",
                    label: "Smart reply nudges",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.smartReplyNudges },
                        set: { services.assistantAutomationPolicy.smartReplyNudges = $0 }
                    )
                )

                cardDivider

                settingsToggle(
                    icon: "clock.badge.exclamationmark",
                    label: "Smart deadline nudges",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.smartDeadlineNudges },
                        set: { services.assistantAutomationPolicy.smartDeadlineNudges = $0 }
                    )
                )

                cardDivider

                settingsToggle(
                    icon: "sparkles",
                    label: "Show thread assistant controls",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.assistantThreadActionsVisible },
                        set: { services.assistantAutomationPolicy.assistantThreadActionsVisible = $0 }
                    )
                )

                cardDivider

                settingsToggle(
                    icon: "arrow.triangle.branch",
                    label: "Track waiting-on threads",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.trackWaitingOnThreads },
                        set: { services.assistantAutomationPolicy.trackWaitingOnThreads = $0 }
                    )
                )

                cardDivider

                settingsToggle(
                    icon: "person.2",
                    label: "Build people memory",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.peopleMemoryEnabled },
                        set: { services.assistantAutomationPolicy.peopleMemoryEnabled = $0 }
                    )
                )

                cardDivider

                settingsToggle(
                    icon: "square.stack.3d.up",
                    label: "Batch prepared approvals",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.batchApprovalEnabled },
                        set: { services.assistantAutomationPolicy.batchApprovalEnabled = $0 }
                    )
                )

                cardDivider

                VStack(alignment: .leading, spacing: 6) {
                    settingsToggle(
                        icon: "paperplane",
                        label: "Enable low-risk auto-send experiment",
                        isOn: Binding(
                            get: { services.assistantAutomationPolicy.autoSendExperimentEnabled },
                            set: { newValue in
                                if newValue {
                                    if services.assistantAutomationPolicy.autoSendExperimentEnabled {
                                        return
                                    }
                                    showAutoSendConfirmation = true
                                } else {
                                    services.assistantAutomationPolicy.autoSendExperimentEnabled = false
                                }
                            }
                        )
                    )

                    HStack(spacing: 6) {
                        Text("Only narrow, high-confidence acknowledgements and confirmations become eligible for automatic send.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(MacTheme.textSecondary)
                        Spacer()
                        Button("Experiment notes") {
                            guard let url = URL(string: "https://todus.app/blog/ai-email-assistant-guide") else { return }
                            NSWorkspace.shared.open(url)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(MacTheme.accent)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 2)
                }

                cardDivider

                rowContainer {
                    Image(systemName: "sun.max")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                        .frame(width: 18)
                    Text("Workday starts")
                        .font(.system(size: 12.5))
                        .foregroundStyle(MacTheme.textPrimary)
                    Spacer()
                    Picker(
                        "",
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
                    .frame(minWidth: 90)
                }

                cardDivider

                rowContainer {
                    Image(systemName: "moon")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                        .frame(width: 18)
                    Text("Workday ends")
                        .font(.system(size: 12.5))
                        .foregroundStyle(MacTheme.textPrimary)
                    Spacer()
                    Picker(
                        "",
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
                    .frame(minWidth: 90)
                }

                cardDivider

                VStack(alignment: .leading, spacing: 8) {
                    Text("Excluded senders and topics")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(MacTheme.textPrimary)

                    MacPlaceholderTextEditor(
                        text: Binding(
                            get: { excludedSenderPatternsText },
                            set: { newValue in
                                excludedSenderPatternsText = newValue
                                services.assistantAutomationPolicy.excludedSenderPatterns = newValue
                                    .split(separator: "\n")
                                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                    .filter { !$0.isEmpty }
                            }
                        ),
                        placeholder: "One pattern per line. e.g. @newsletter., *@noreply.*",
                        minHeight: 88
                    )

                    Text("One pattern per line. Use this to suppress newsletters, no-reply mail, and other low-value automation from the assistant queues.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(MacTheme.textSecondary)
                }
                .padding(.horizontal, MacTheme.settingsRowHorizontalPadding)
                .padding(.vertical, MacTheme.settingsRowVerticalPadding)

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
                        Text("GPT-5.4").tag("openai/gpt-5.4")
                        Text("GPT-5.4 Mini").tag("openai/gpt-5.4-mini")
                        Text("GPT-5.4 Chat").tag("openai/gpt-5.4-chat")
                        Text("GPT-5.4 Nano").tag("openai/gpt-5.4-nano")
                        Text("Claude Sonnet 4.5").tag("anthropic/claude-sonnet-4-5")
                        Text("Claude Haiku 4.5").tag("anthropic/claude-haiku-4-5")
                        Text("Kimi K2.5").tag("moonshotai/kimi-k2.5")
                        Text("Gemini 3.1 Pro").tag("google/gemini-3.1-pro-preview")
                        Text("Gemini 3.1 Flash Lite").tag("google/gemini-3.1-flash-lite-preview")
                        Text("Gemini 3 Flash").tag("google/gemini-3-flash-preview")
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 120)
                }

                cardDivider

                // Local models — opens the on-device catalog. Local models run
                // on this Mac and never use plan credits.
                rowContainer {
                    Image(systemName: "cpu")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Local Models")
                            .font(.system(size: 12.5))
                            .foregroundStyle(MacTheme.textPrimary)
                        Text("Download and manage on-device models. No plan credits used.")
                            .font(.system(size: 11))
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                    Spacer()
                    Button("Manage") { showsLocalModels = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .sheet(isPresented: $showsLocalModels) {
            NavigationStack { MacLocalModelsView() }
                .frame(minWidth: 600, minHeight: 600)
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

    /// Section title — matches iOS Settings header weight/size for visual parity.
    private func settingsGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(MacTheme.settingsSectionHeaderFont())
                .foregroundStyle(MacTheme.textSecondary)
                .padding(.leading, 4)
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
        Divider().opacity(0.12).padding(.horizontal, MacTheme.settingsRowHorizontalPadding)
    }

    /// Generic row container — icon + label + trailing content.
    private func rowContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
        }
        .padding(.horizontal, MacTheme.settingsRowHorizontalPadding)
        .padding(.vertical, MacTheme.settingsRowVerticalPadding)
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
                .tint(MacTheme.switchTint)
        }
    }

    private var privacyConsentBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Privacy consent required")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(MacTheme.textPrimary)
            Text(
                "Analytics and crash reports stay off until you explicitly allow them. This is especially important for EU users."
            )
            .font(.system(size: 11.5))
            .foregroundStyle(MacTheme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func privacyToggleBinding(_ preference: PrivacyPreference) -> Binding<Bool> {
        Binding(
            get: {
                switch preference {
                case .analytics:
                    return analyticsEnabled
                case .crashReports:
                    return crashReportsEnabled
                }
            },
            set: { newValue in
                if newValue {
                    if privacyConsentAccepted {
                        applyPrivacyPreferenceSelection(true, preference: preference)
                    } else {
                        pendingPrivacyPreference = preference
                        showsPrivacyConsentDialog = true
                    }
                } else {
                    applyPrivacyPreferenceSelection(false, preference: preference)
                }
            }
        )
    }

    private func applyPrivacyPreferenceSelection(_ enabled: Bool, preference: PrivacyPreference? = nil) {
        guard let preference else {
            return
        }
        switch preference {
        case .analytics:
            analyticsEnabled = enabled
        case .crashReports:
            crashReportsEnabled = enabled
        }
    }

    private func applyPrivacyPreferenceSelection(_ enabled: Bool) {
        applyPrivacyPreferenceSelection(enabled, preference: pendingPrivacyPreference)
        pendingPrivacyPreference = nil
    }

    private var privacyConsentTitle: String {
        guard let pendingPrivacyPreference else {
            return "Allow privacy features?"
        }
        switch pendingPrivacyPreference {
        case .analytics:
            return "Allow usage analytics?"
        case .crashReports:
            return "Allow crash reports?"
        }
    }

    private var privacyConsentMessage: String {
        switch pendingPrivacyPreference {
        case .analytics:
            return "Usage analytics help us understand feature usage and improve the app. We only turn them on after you confirm."
        case .crashReports:
            return "Crash reports help us diagnose failures and stability issues. They stay off until you confirm."
        case nil:
            return "This feature remains off until you explicitly confirm."
        }
    }

    private static let europeanPrivacyRegions: Set<String> = [
        "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU",
        "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES",
        "SE", "IS", "LI", "NO",
    ]

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

    private func sessionHeader(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(MacTheme.mutedText)
            .frame(width: width, alignment: .leading)
    }

    private func sessionValue(_ text: String, width: CGFloat, emphasized: Bool = false) -> some View {
        Text(text)
            .font(.system(size: emphasized ? 12.5 : 11.5, weight: emphasized ? .medium : .regular))
            .foregroundStyle(emphasized ? MacTheme.textPrimary : MacTheme.textSecondary)
            .frame(width: width, alignment: .leading)
            .lineLimit(2)
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
        .macClickablePointer()
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
        .macClickablePointer()
    }

    // MARK: - Helpers

    private func openURL(_ string: String) {
        if let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Billing & Subscription

    private static let billingPlanIncludes: [MacSubscriptionService.Plan: [String]] = [
        .free: [
            "1 email connection",
            "7.5 credits / month of AI chat",
            "Basic AI email assistance",
        ],
        .pro: [
            "Unlimited email connections",
            "15 credits / month of AI chat & voice",
            "Auto-labeling, thread summaries, priority models",
            "Manage payment & cancel anytime",
        ],
        .team: [
            "Everything in Pro",
            "Shared inbox + collaboration",
            "Org-level billing",
        ],
        .enterprise: [
            "Custom limits and SLAs",
            "SSO + advanced security controls",
            "Dedicated account support",
        ],
    ]

    private func formatCredits(_ value: Double) -> String {
        if value == 0 { return "0" }
        if value < 1 { return String(format: "%.2f", value) }
        if value < 10 { return String(format: "%.1f", value) }
        return String(Int(value.rounded()))
    }

    private func formatUsageTotal(_ value: Double, unlimited: Bool) -> String {
        unlimited ? "Unlimited" : formatCredits(value)
    }

    private var billingPercentRemaining: Int {
        let sub = services.subscriptionService
        guard !sub.aiUsageUnlimited else { return 100 }
        guard sub.aiUsageLimit > 0 else { return 0 }
        return max(0, 100 - Int((sub.aiUsagePercent * 100).rounded()))
    }

    private var billingResetLabel: String? {
        guard let date = services.subscriptionService.aiUsageResetAt else { return nil }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    private var billingSection: some View {
        let sub = services.subscriptionService
        return settingsGroup(title: "Subscription") {
            settingsCard {
                // Plan + actions row
                rowContainer {
                    Image(systemName: "creditcard")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(sub.plan.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MacTheme.textPrimary)
                        Text(sub.status == "active" ? (sub.plan.isPaid ? "Active" : "Free plan") : sub.status.capitalized)
                            .font(.system(size: 10.5))
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                    Spacer()
                    if sub.plan.isPaid {
                        Button {
                            Task { await openBillingPortal() }
                        } label: {
                            HStack(spacing: 4) {
                                if isOpeningBillingPortal {
                                    ProgressView().controlSize(.small)
                                }
                                Text("Manage")
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(MacTheme.accent)
                        .disabled(isOpeningBillingPortal)
                        .macClickablePointer()

                        Button(role: .destructive) {
                            showCancelSubscriptionConfirm = true
                        } label: {
                            if isCancelingSubscription {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Cancel")
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red.opacity(0.85))
                        .disabled(isCancelingSubscription)
                        .macClickablePointer()
                    } else {
                        Button {
                            openURL(upgradePricingURL())
                        } label: {
                            Text("Upgrade")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(MacTheme.accent)
                        .macClickablePointer()
                    }
                }

                cardDivider

                // Big-number usage row — credits remaining headline + big bar.
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .lastTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(sub.aiUsageUnlimited ? "Unlimited" : formatCredits(sub.aiUsageRemaining))
                                    .font(.system(size: 28, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(MacTheme.textPrimary)
                                Text(sub.aiUsageUnlimited
                                     ? "AI credits"
                                     : "of \(formatCredits(sub.aiUsageLimit))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(MacTheme.textSecondary)
                                    .monospacedDigit()
                            }
                            Text(sub.aiUsageUnlimited
                                 ? "Unlimited AI usage on this plan"
                                 : sub.aiUsageLimit > 0
                                 ? "\(billingPercentRemaining)% remaining this period"
                                 : "No credits on this plan")
                                .font(.system(size: 10.5))
                                .foregroundStyle(MacTheme.textSecondary)
                        }
                        Spacer()
                        if let billingResetLabel {
                            Text("Resets \(billingResetLabel)")
                                .font(.system(size: 10.5))
                                .foregroundStyle(MacTheme.textSecondary)
                        }
                    }

                    ProgressView(value: sub.aiUsageLimit > 0 ? sub.aiUsagePercent : 0)
                        .tint(billingProgressTint)
                        .scaleEffect(x: 1, y: 1.7, anchor: .center)

                    HStack {
                        Text("Used: \(formatCredits(sub.aiUsageUsed))")
                            .monospacedDigit()
                        Spacer()
                        Text("Total: \(formatUsageTotal(sub.aiUsageLimit, unlimited: sub.aiUsageUnlimited))")
                            .monospacedDigit()
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(MacTheme.textSecondary)

                    if !sub.aiUsageUnlimited && sub.aiUsagePercent >= 1 && sub.aiUsageLimit > 0 {
                        HStack(spacing: 10) {
                            Text("Out of AI credits this period.")
                                .font(.system(size: 11))
                                .foregroundStyle(.red.opacity(0.85))
                            if !sub.plan.isPaid {
                                Button {
                                    openURL(upgradePricingURL())
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "arrow.up.circle.fill")
                                            .font(.system(size: 10, weight: .semibold))
                                        Text("Upgrade to Pro")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(MacTheme.accent)
                                .macClickablePointer()
                            }
                        }
                    } else if !sub.aiUsageUnlimited && sub.aiUsagePercent >= 0.8 && sub.aiUsageLimit > 0 {
                        Text("You've used \(Int(sub.aiUsagePercent * 100))% of your AI credits.")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                cardDivider

                // Plan-includes block — shows what the user's current plan covers.
                let includes = Self.billingPlanIncludes[sub.plan] ?? Self.billingPlanIncludes[.free] ?? []
                VStack(alignment: .leading, spacing: 4) {
                    Text("Includes")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                        .padding(.leading, 25)
                    ForEach(includes, id: \.self) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(sub.plan.isPaid ? MacTheme.accent : MacTheme.mutedText)
                                .frame(width: 12, alignment: .leading)
                            Text(item)
                                .font(.system(size: 12))
                                .foregroundStyle(MacTheme.textPrimary)
                            Spacer()
                        }
                        .padding(.leading, 25)
                    }
                }
                .padding(.vertical, 8)
                .padding(.trailing, 12)

                if let billingError {
                    cardDivider
                    rowContainer {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.red.opacity(0.85))
                            .frame(width: 18)
                        Text(billingError)
                            .font(.system(size: 11))
                            .foregroundStyle(.red.opacity(0.85))
                        Spacer()
                    }
                }
            }
        }
    }

    private var billingProgressTint: Color {
        let pct = services.subscriptionService.aiUsagePercent
        if pct >= 1 { return .red }
        if pct >= 0.8 { return .orange }
        return MacTheme.accent
    }

    private func upgradePricingURL() -> String {
        // The web app lives at todus.app — strip the `api.` subdomain when
        // it's set as the backend, fall back to the prod root.
        let backend = services.apiClient.baseURL.absoluteString
        if let host = URL(string: backend)?.host, host.hasPrefix("api.") {
            return "https://\(String(host.dropFirst("api.".count)))/pricing"
        }
        return "https://todus.app/pricing"
    }

    private func openBillingPortal() async {
        billingError = nil
        isOpeningBillingPortal = true
        defer { isOpeningBillingPortal = false }
        do {
            if let url = try await services.subscriptionService.getBillingPortalUrl() {
                NSWorkspace.shared.open(url)
            } else {
                billingError = "Couldn't open the billing portal."
            }
        } catch {
            billingError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func performCancelSubscription() async {
        billingError = nil
        isCancelingSubscription = true
        defer { isCancelingSubscription = false }
        do {
            try await services.subscriptionService.cancel(productId: "pro_monthly")
        } catch {
            billingError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func formatSessionDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func loadActiveSessions() async {
        isLoadingSessions = true
        sessionsLoadError = nil
        defer { isLoadingSessions = false }

        do {
            let response = try await services.apiClient.listSessions()
            activeSessions = response.sessions
        } catch {
            AppLogger.shared.log("[Settings] Load sessions failed: \(error)")
            sessionsLoadError = error.localizedDescription
        }
    }

    // MARK: - Actions

    private func performDeleteAccount() async {
        do {
            try await services.apiClient.deleteAccount()
        } catch {
            AppLogger.shared.log("[Settings] Delete account failed: \(error)")
        }
        deleteConfirmText = ""
        services.signOut()
        try? modelContext.delete(model: TaskRecord.self)
        try? modelContext.delete(model: FolderItemRecord.self)
        try? modelContext.delete(model: FolderRecord.self)
        try? modelContext.save()
        dismiss()
    }

    private func performDisconnectGmail() async {
        do {
            try await services.apiClient.disconnectEmail()
            await services.emailService.checkConnection()
        } catch {
            AppLogger.shared.log("[Settings] Disconnect Gmail failed: \(error)")
        }
    }

    private func revokeSession(_ sessionId: String) async {
        revokingSessionIDs.insert(sessionId)
        defer { revokingSessionIDs.remove(sessionId) }

        do {
            let response = try await services.apiClient.revokeSession(sessionId: sessionId)
            await loadActiveSessions()
            if response.revokedCurrent {
                services.signOut()
                dismiss()
            } else {
                await services.authService.fetchUserProfile()
            }
        } catch {
            settingsError = "Could not revoke session. Please try again."
            AppLogger.shared.log("[Settings] Revoke session failed: \(error)")
        }
    }

    private func revokeAllSessions() async {
        isRevokingAllSessions = true
        defer { isRevokingAllSessions = false }

        do {
            let response = try await services.apiClient.revokeAllSessions()
            activeSessions = []
            if response.revokedCurrent {
                services.signOut()
                dismiss()
            } else {
                await services.authService.fetchUserProfile()
            }
        } catch {
            settingsError = "Could not revoke sessions. Please try again."
            AppLogger.shared.log("[Settings] Revoke all sessions failed: \(error)")
        }
    }
}

// MARK: - MacSignatureEditorRow

/// One row inside the Signatures card. Owns the local draft so each editor
/// can debounce its own saves into `MacSignatureStore` without polluting
/// the parent settings view's state.
private struct MacSignatureEditorRow: View {
    let connection: ConnectionAccount

    @State private var draft: String = ""
    /// Tracks the currently scheduled debounce so a fast typist's older save
    /// can be cancelled before it overwrites a fresher value.
    @State private var pendingSave: Task<Void, Never>? = nil

    /// 500ms debounce — matches the typical "user paused typing" threshold
    /// used elsewhere in the app and keeps UserDefaults writes batched.
    private let debounceNanos: UInt64 = 500_000_000

    @State private var showPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "signature")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MacTheme.mutedText)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(connection.email)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(MacTheme.textPrimary)
                    Text("Appended to new messages from this account.")
                        .font(.system(size: 11))
                        .foregroundStyle(MacTheme.textSecondary)
                }
                Spacer()
            }
            TextEditor(text: $draft)
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .font(.system(size: 12))
                .padding(8)
                .background(MacTheme.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous))

            DisclosureGroup(isExpanded: $showPreview) {
                // Render the signature with the exact prefix used in real drafts
                // so users can see the trailing separator and spacing.
                Text(previewText)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(MacTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(MacTheme.surfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous))
                    .padding(.top, 4)
            } label: {
                Text("Preview")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(MacTheme.mutedText)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .onAppear {
            // Hydrate from disk on first render. Each row has its own onAppear
            // because the parent ForEach recreates them when connections load.
            draft = MacSignatureStore.shared.signature(for: connection.id)
        }
        .onChange(of: draft) { _, newValue in
            pendingSave?.cancel()
            let connectionId = connection.id
            pendingSave = Task { @MainActor in
                try? await Task.sleep(nanoseconds: debounceNanos)
                if Task.isCancelled { return }
                MacSignatureStore.shared.setSignature(newValue, for: connectionId)
            }
        }
        .onDisappear {
            // Flush any in-flight debounce so the Settings window closing
            // mid-typing doesn't lose the last edit.
            pendingSave?.cancel()
            MacSignatureStore.shared.setSignature(draft, for: connection.id)
        }
    }

    private var previewText: String {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "(empty — no signature will be appended)" }
        return "\n\n-- \n\(trimmed)"
    }
}

/// Multi-line text input with a placeholder overlay. SwiftUI's `TextEditor` has no native
/// placeholder, so we render one as an inert overlay when the bound text is empty.
fileprivate struct MacPlaceholderTextEditor: View {
    @Binding var text: String
    let placeholder: String
    var minHeight: CGFloat = 96

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(size: 12))
                .frame(minHeight: minHeight)
                .scrollContentBackground(.hidden)
                .padding(8)

            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.textSecondary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
        .background(MacTheme.inputBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous))
    }
}
