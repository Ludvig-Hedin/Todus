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
    @State private var deleteConfirmError: String?
    @State private var isDeletingAccount = false
    /// True while `performLogout` is running — drives a small "Signing out…" HUD so
    /// the user sees feedback during the network round-trip before the auth state
    /// flips and the sheet dismisses.
    @State private var isSigningOut = false
    @State private var showsDisconnectGmail = false
    /// ID of the connection selected for disconnection — used by the confirmation dialog
    @State private var disconnectingConnectionId: String?
    /// True briefly after a successful disconnect — drives the confirmation alert
    /// so the user sees feedback for an otherwise silent server-side action (#25).
    @State private var showDisconnectSuccess: Bool = false
    @State private var isConnectingCalendar = false
    @State private var isConnectingReminders = false
    @State private var isConnectingGmail = false
    @State private var connectGmailError: String?
    /// Inline error when Reminders permission is denied — paired with an "Open Settings"
    /// shortcut so users can fix the system permission without leaving Todus context.
    @State private var remindersPermissionError: String?
    @State private var activeSessions: [ActiveSessionRecord] = []
    @State private var isLoadingSessions = false
    // revokingSessionIDs and isRevokingAllSessions live in SessionsSettingsView now

    // AI permission flags — backed by the same UserDefaults keys read by AIChatService
    // so toggling these here updates the AI behaviour for the next request (#6).
    @AppStorage("ios_accent_color") private var accentColorKey: String = "blue"
    @AppStorage("ai_can_read_tasks") private var aiCanReadTasks: Bool = true
    @AppStorage("ai_can_write_tasks") private var aiCanWriteTasks: Bool = true
    @AppStorage("ai_can_read_calendar") private var aiCanReadCalendar: Bool = true
    @AppStorage("ai_can_write_calendar") private var aiCanWriteCalendar: Bool = true
    @AppStorage("ai_can_read_email") private var aiCanReadEmail: Bool = true
    @AppStorage("ai_can_send_email") private var aiCanSendEmail: Bool = true

    private var calendarAccessGranted: Bool {
        services.calendarService.canReadEvents()
    }

    var body: some View {
        NavigationStack {
            List {
                accountSection
                connectedServicesSection
                calendarAccountsSection

                // Appearance sub-page + small preferences inline
                preferencesSection

                // Email preferences — separate from AI to reduce cognitive load
                emailSection

                // AI Assistant — dedicated sub-page (contains large TextEditors)
                aiAssistantNavigationSection

                // Quick AI permission toggles surfaced at the top-level so users
                // can flip read/write access without diving into the sub-page (#6).
                aiPermissionsSection

                // Billing & subscription — plan + AI usage credits + manage portal
                billingNavigationSection

                // Notifications + Privacy
                notificationsAndPrivacySection

                // Security (Active Sessions) — moved near the bottom: it's an important
                // but rarely-touched control, so it lives below the daily-use settings.
                sessionsNavigationSection

                aboutSection

                if services.effectiveDeveloperModeEnabled {
                    developerSection
                }

                // Destructive actions live at the very bottom so they aren't
                // adjacent to the user's name/avatar at the top of the list.
                if services.authService.isAuthenticated {
                    dangerZoneSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.sheetBackground)
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
        .modifier(SettingsSyncModifier(services: services))
        .task {
            // Refresh profile data (name, avatar) when settings opens
            await services.authService.fetchUserProfile()
            await services.loadSharedAIProfile()
        }
        .task {
            await services.emailService.checkConnection()
        }
        .task {
            // Load connected email accounts for the dynamic connections list
            await services.connectionsService.loadConnections()
        }
        .task {
            await loadActiveSessions()
        }
        .task {
            await services.subscriptionService.refresh()
        }
        // Connect a new Gmail account (also brings calendars). Triggered by
        // the "Add Calendar Account" CTA in the picker / Calendar Accounts.
        .onReceive(NotificationCenter.default.publisher(for: .todusRequestConnectGmail)) { _ in
            Task { await performConnectGmail() }
        }
        // Re-OAuth an existing Gmail connection to lift the calendar scope so
        // editing works. Wires through the same `performConnectGmail` flow today —
        // Better Auth's linkSocial dedupes by email and re-prompts with the new scope.
        .onReceive(NotificationCenter.default.publisher(for: .todusRequestReconnectGmail)) { _ in
            Task { await performConnectGmail() }
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
                // Case-sensitive match — surface a helpful error instead of silently
                // no-op'ing if the user types "delete" or "Delete".
                guard deleteConfirmText == "DELETE" else {
                    deleteConfirmError = "Type DELETE in capital letters to confirm."
                    return
                }
                deleteConfirmError = nil
                Task { await performDeleteAccount() }
            }
            Button("Cancel", role: .cancel) {
                deleteConfirmText = ""
                deleteConfirmError = nil
            }
        } message: {
            Text("This action is irreversible. Type DELETE to proceed.")
        }
        // Inline error if the user typed something other than DELETE.
        .alert(
            "Confirmation didn't match",
            isPresented: Binding<Bool>(
                get: { deleteConfirmError != nil },
                set: { if !$0 { deleteConfirmError = nil } }
            ),
            presenting: deleteConfirmError
        ) { _ in
            Button("Try Again") {
                deleteConfirmError = nil
                deleteConfirmText = ""
                showsDeleteAlert = true
            }
            Button("Cancel", role: .cancel) {
                deleteConfirmText = ""
            }
        } message: { msg in
            Text(msg)
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
        // Transient success HUD after a Gmail account has been disconnected (#25).
        // Replaces the previous blocking alert — the operation is non-destructive
        // and trivially reversible, so a 1.5s overlay is the right weight. The
        // performDisconnectGmail() task flips `showDisconnectSuccess` back to false.
        .overlay(alignment: .bottom) {
            if showDisconnectSuccess {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.green)
                    Text("Gmail account disconnected")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(AppTheme.cardBorder, lineWidth: 0.5))
                .padding(.bottom, 32)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Gmail account disconnected")
            }
        }
        .animation(AppTheme.Motion.base, value: showDisconnectSuccess)
        // Sign-out HUD — non-interactive, centered overlay while `signOut()` runs.
        .overlay {
            if isSigningOut {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Signing out…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous).stroke(AppTheme.cardBorder, lineWidth: 0.5))
                .transition(.opacity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Signing out")
            }
        }
        .animation(AppTheme.Motion.fast, value: isSigningOut)
    }

    // MARK: - Account

    private var accountSection: some View {
        Section {
            // Profile row — avatar, name, email
            HStack(spacing: 12) {
                // Avatar — Google profile image or letter initial fallback
                CachedAvatarImage(urlString: services.authService.userImage, size: 48) {
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
                        .foregroundStyle(.primary)
                }
            }

            // Log out button — inside the account card. Delete account moved to the
            // bottom "Danger Zone" section so destructive actions aren't adjacent to
            // the user's profile.
            if services.authService.isAuthenticated {
                Button(role: .destructive) {
                    showsLogoutConfirmation = true
                } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Account")
        }
    }

    // MARK: - Danger Zone (bottom of the list)

    /// Bottom section for irreversible destructive actions — lives under About so it
    /// isn't accidentally tapped while scanning account info at the top of the list.
    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showsDeleteConfirmation = true
            } label: {
                Label("Delete Account", systemImage: "trash")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Danger Zone")
        } footer: {
            Text("Permanently deletes your account, tasks, email connections, and all data. This cannot be undone.")
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
                        ButtonInlineProgressView(tint: .secondary, side: AppTheme.Metrics.toolbarInlineSpinner)
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
                      ? Color.primary.opacity(0.12)
                      : Color.secondary.opacity(0.12))
                .frame(width: 48, height: 48)
            if let email = services.authService.userEmail ?? services.authStore.accountEmail,
               let first = email.first {
                Text(String(first).uppercased())
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(services.authService.isAuthenticated ? .primary : .secondary)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Connected Services

    /// Row for a single connected mail account (Google, Microsoft, …).
    /// Shows the user's profile picture, a provider-badge overlay, and a status pill.
    @ViewBuilder
    private func connectedAccountRow(_ connection: ConnectionAccount) -> some View {
        let isDisconnected = services.connectionsService.isDisconnected(connection.id)
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                // User profile picture (Google avatar) when available, else colored
                // initial fallback so the row remains identifiable while the image loads.
                if let urlString = connection.picture, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            connectionInitialBadge(for: connection)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                } else {
                    connectionInitialBadge(for: connection)
                        .frame(width: 36, height: 36)
                }

                // Small Gmail/provider mark in the corner so the user can tell at a
                // glance which service this account belongs to.
                if connection.providerId == "google" {
                    GmailIconView(size: 16)
                        .background(Circle().fill(Color(UIColor.systemBackground)).frame(width: 18, height: 18))
                        .offset(x: 2, y: 2)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.email)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                Text(connection.providerName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()

            if isDisconnected {
                statusPill(text: "Reconnect", color: .orange)
            } else {
                statusPill(text: "Connected", color: .green)
            }

            Button(role: .destructive) {
                disconnectingConnectionId = connection.id
                showsDisconnectGmail = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    /// Colored circle with the first letter of the email — fallback when no avatar URL.
    @ViewBuilder
    private func connectionInitialBadge(for connection: ConnectionAccount) -> some View {
        Circle()
            .fill(Color(hex: connection.displayColor))
            .overlay {
                Text(String(connection.email.prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }

    /// Compact status pill — green "Connected" or orange "Reconnect".
    @ViewBuilder
    private func statusPill(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var connectedServicesSection: some View {
        Section {
            // Dynamic email connections from backend — replaces the old hardcoded Gmail row.
            // Shows each connected account (Google, Microsoft, etc.) with provider icon,
            // email address, and connection status.
            if services.connectionsService.connections.isEmpty {
                // Fallback: show legacy Gmail row when connections haven't loaded yet
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        GmailIconView(size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Gmail")
                                .font(.system(size: 15, weight: .medium))
                            Text(services.emailService.hasConnection ? "Linked to your account" : "Not connected")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if services.emailService.hasConnection {
                            statusPill(text: "Connected", color: .green)
                            Button(role: .destructive) {
                                showsDisconnectGmail = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.secondary.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                guard !isConnectingGmail else { return }
                                Task { await performConnectGmail() }
                            } label: {
                                Text(isConnectingGmail ? "Connecting…" : "Connect")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(isConnectingGmail)
                        }
                    }
                    if let connectGmailError {
                        Text(connectGmailError)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 2)
            } else {
                ForEach(services.connectionsService.connections) { connection in
                    connectedAccountRow(connection)
                }

                // "Add Gmail account" — uses the same inline OAuth flow as the legacy
                // fallback so the user stays on the settings sheet. Toggling the
                // onboarding flag from inside the sheet wouldn't trigger anything
                // until the sheet is dismissed.
                Button {
                    guard !isConnectingGmail else { return }
                    Task { await performConnectGmail() }
                } label: {
                    HStack(spacing: 12) {
                        GmailIconView(size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isConnectingGmail ? "Connecting…" : "Add Gmail account")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("Sign in to connect another mailbox")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isConnectingGmail {
                            ButtonInlineProgressView(tint: .primary, side: AppTheme.Metrics.toolbarInlineSpinner)
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.primary.opacity(0.7))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isConnectingGmail)
                .padding(.vertical, 2)

                if let connectGmailError {
                    Text(connectGmailError)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
            }

            // Apple Calendar
            HStack(spacing: 12) {
                AppleCalendarIconView(size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Calendar")
                        .font(.system(size: 15, weight: .medium))
                    Text(calendarAccessGranted ? "Local calendar access" : "Read events from your iPhone")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if calendarAccessGranted {
                    statusPill(text: "Connected", color: .green)
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
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isConnectingCalendar)
                }
            }
            .padding(.vertical, 2)

            // Apple Reminders
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    AppleRemindersIconView(size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Reminders")
                            .font(.system(size: 15, weight: .medium))
                        Text(services.remindersSyncEnabled ? "Two-way sync enabled" : "Sync tasks with Reminders")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if services.remindersSyncEnabled {
                        statusPill(text: "Connected", color: .green)
                    } else {
                        Button {
                            guard !isConnectingReminders else { return }
                            isConnectingReminders = true
                            remindersPermissionError = nil
                            Task {
                                // Only flip the underlying toggle AFTER the system has
                                // granted permission — otherwise the UI shows
                                // "Connected" while the system prompt is still pending,
                                // and snaps back if the user denies (#23).
                                let granted = await services.requestRemindersPermissionIfNeeded()
                                if granted {
                                    services.remindersSyncEnabled = true
                                    await services.importFromReminders(in: modelContext)
                                    services.syncExistingTasksToReminders(in: modelContext)
                                } else {
                                    // Permission denied — keep the toggle in its
                                    // off state and surface an inline error with a
                                    // shortcut to system settings.
                                    services.remindersSyncEnabled = false
                                    remindersPermissionError = "Apple Reminders access denied. Enable it in Settings > Privacy > Reminders."
                                }
                                isConnectingReminders = false
                            }
                        } label: {
                            Text(isConnectingReminders ? "Connecting…" : "Connect")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.accentColor, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isConnectingReminders)
                    }
                }

                if let remindersPermissionError {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(remindersPermissionError)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Open Settings")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text("Connected Services")
        }
    }

    // MARK: - Calendar Accounts

    /// Lists every calendar source the user has — Apple (EventKit) calendars at
    /// the top, then one collapsible group per Google connection. Per-row toggle
    /// drives `calendarPreferences.hiddenCalendarIds` via AppServices.
    private var calendarAccountsSection: some View {
        Section {
            NavigationLink {
                CalendarAccountsView()
                    .environment(services)
            } label: {
                HStack {
                    Label("Calendar Accounts", systemImage: "calendar.badge.plus")
                    Spacer()
                    Text(calendarAccountsSubtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Calendars")
        } footer: {
            if !services.googleCalendarService.scopeMissingConnectionIds.isEmpty {
                Text("Reconnect Gmail to enable calendar editing.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var calendarAccountsSubtitle: String {
        let googleCount = services.connectionsService.connections.filter { $0.providerId == "google" }.count
        if googleCount == 0 {
            return "Apple"
        }
        return googleCount == 1 ? "Apple, 1 Gmail" : "Apple, \(googleCount) Gmail"
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

            // Accent color — synced across iOS / macOS / web via `accentColor` setting.
            HStack {
                Label("Accent", systemImage: "paintpalette")
                Spacer()
                HStack(spacing: 8) {
                    ForEach(AppTheme.accentColorKeys, id: \.self) { key in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                accentColorKey = key
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(AccentPreference(rawValue: key)?.color ?? AppTheme.Accents.blue)
                                    .frame(width: 22, height: 22)
                                if accentColorKey == key {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(key.capitalized)
                    }
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

            if services.isDeveloperModeUIAvailable {
                Toggle(isOn: Binding(
                    get: { services.developerModeEnabled },
                    set: { services.developerModeEnabled = $0 }
                )) {
                    Label("Developer Mode", systemImage: "wrench.and.screwdriver")
                }
                .tint(.orange)
            }
        } header: {
            Text("Preferences")
        } footer: {
            // Default view changes take effect on next Tasks open — clarify that so
            // users aren't confused when the current Tasks tab keeps its old layout.
            Text("Default View applies next time you open Tasks.")
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
            NavigationLink {
                LocalModelsView()
            } label: {
                Label("Local Models", systemImage: "cpu")
            }
            NavigationLink {
                VoiceAssistantSettingsView()
            } label: {
                Label("Voice Assistant", systemImage: "waveform")
            }
        } header: {
            Text("AI Assistant")
        } footer: {
            Text("Configure what the AI can read, write, and how it responds. Local models run on this device and don’t use plan credits. Voice assistant is available via Siri Shortcuts.")
        }
    }

    /// Quick read/write permission toggles for the AI assistant. Backed by the
    /// same UserDefaults keys AIChatService reads on init, so toggling here
    /// takes effect on the next request (#6).
    private var aiPermissionsSection: some View {
        Section {
            Toggle(isOn: $aiCanReadTasks) {
                Label("Read Tasks", systemImage: "checklist")
            }
            .tint(AppTheme.switchTint)

            Toggle(isOn: $aiCanWriteTasks) {
                Label("Create & Edit Tasks", systemImage: "square.and.pencil")
            }
            .tint(AppTheme.switchTint)

            Toggle(isOn: $aiCanReadCalendar) {
                Label("Read Calendar", systemImage: "calendar")
            }
            .tint(AppTheme.switchTint)

            Toggle(isOn: $aiCanWriteCalendar) {
                Label("Create Calendar Events", systemImage: "calendar.badge.plus")
            }
            .tint(AppTheme.switchTint)

            Toggle(isOn: $aiCanReadEmail) {
                Label("Read Email", systemImage: "envelope")
            }
            .tint(AppTheme.switchTint)

            Toggle(isOn: $aiCanSendEmail) {
                Label("Send Email", systemImage: "paperplane")
            }
            .tint(AppTheme.switchTint)
        } header: {
            Text("AI Permissions")
        } footer: {
            Text("Control what the AI can read and write on your behalf. Disabling a permission removes that capability from the assistant's tools.")
        }
    }

    // MARK: - Billing & Subscription (NavigationLink → sub-view)

    private var billingNavigationSection: some View {
        Section {
            NavigationLink {
                BillingSettingsView()
            } label: {
                HStack {
                    Label("Billing & Plan", systemImage: "creditcard")
                    Spacer()
                    if services.subscriptionService.plan.isPaid {
                        Text(services.subscriptionService.plan.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Free")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Subscription")
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
            .tint(AppTheme.switchTint)

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
            .tint(AppTheme.switchTint)

            NavigationLink {
                EmailAutomationPolicyView()
            } label: {
                HStack {
                    Label("Automation policy", systemImage: "wand.and.stars")
                    Spacer()
                    Text(automationSummary)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Email")
        }
    }

    /// Compact summary shown next to the "Automation policy" row.
    /// Reflects the most user-visible automation toggles without opening the sub-page.
    private var automationSummary: String {
        let policy = services.assistantAutomationPolicy
        if policy.autoSendExperimentEnabled { return "Auto-send on" }
        let excluded = policy.excludedSenderPatterns.count
        if excluded > 0 { return "\(excluded) excluded" }
        return "Recommended"
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
            .tint(AppTheme.switchTint)

            Toggle(isOn: Binding(
                get: { services.calendarRemindersEnabled },
                set: { services.calendarRemindersEnabled = $0 }
            )) {
                Label("Calendar Reminders", systemImage: "calendar.badge.clock")
            }
            .tint(AppTheme.switchTint)

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
            // Hidden Design System viewer — gated to the allowlisted email set
            // even inside the developer section so teammate devices that flip
            // developer mode on don't see it. Renders every token, surface,
            // and component the iOS app uses with "How to change" callouts
            // pointing at `AppTheme.swift` line ranges.
            if TodusDeveloperAccess.isAllowlisted(email: services.authService.userEmail) {
                NavigationLink {
                    DesignSystemView()
                } label: {
                    Label("Design System", systemImage: "swatchpalette")
                }
            }

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
        // Brief HUD overlay covers the sign-out call so the user gets feedback
        // instead of a blank pause between tap and sheet dismissal. signOut() can
        // do KeyChain + network work; we don't await but we also don't dismiss
        // until that's had a chance to run, so the HUD survives long enough to read.
        isSigningOut = true
        services.authService.hasSeenOnboarding = false
        services.signOut()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            isSigningOut = false
            dismiss()
        }
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

        // Wipe all local SwiftData records (tasks + folders + folder items)
        try? modelContext.delete(model: TaskRecord.self)
        try? modelContext.delete(model: FolderItemRecord.self)
        try? modelContext.delete(model: FolderRecord.self)
        try? modelContext.save()

        dismiss()
    }

    /// Links Gmail to the current account via the same OAuth flow as EmailConnectView,
    /// then refreshes connection state so the row flips to "Connected".
    private func performConnectGmail() async {
        isConnectingGmail = true
        connectGmailError = nil
        defer { isConnectingGmail = false }

        let didConnect = await services.emailService.connectGmail(authService: services.authService)

        await services.connectionsService.loadConnections()

        if !didConnect {
            connectGmailError = services.emailService.errorMessage
                ?? services.authService.lastErrorMessage
                ?? "Could not link Gmail. Make sure you granted access and try again."
        }
    }

    /// Disconnects an email connection on the backend.
    /// Uses disconnectingConnectionId if set (from the dynamic connections list),
    /// otherwise falls back to the legacy disconnectEmail() method.
    private func performDisconnectGmail() async {
        let connectionId = disconnectingConnectionId
        defer { disconnectingConnectionId = nil }

        var didSucceed = false
        do {
            if let connectionId {
                try await services.connectionsService.deleteConnection(connectionId: connectionId)
            } else {
                try await services.apiClient.disconnectEmail()
            }
            didSucceed = true
        } catch {
            AppLogger.shared.log("Disconnect email failed: \(error.localizedDescription)")
        }
        await services.emailService.checkConnection()

        // Show a brief confirmation so the user knows the disconnect succeeded.
        // Auto-dismiss after a few seconds so it doesn't block subsequent edits.
        if didSucceed {
            showDisconnectSuccess = true
            // 1.5s matches the standard transient-HUD dwell time used elsewhere; long
            // enough to register, short enough not to block subsequent edits.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                showDisconnectSuccess = false
            }
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
    @State private var loadError: String? = nil

    var body: some View {
        List {
            if isLoadingSessions {
                HStack(spacing: 8) {
                    ButtonInlineProgressView(tint: .secondary, side: AppTheme.Metrics.toolbarInlineSpinner)
                    Text("Loading sessions…")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else if let error = loadError {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Couldn't load sessions")
                        .font(.system(size: 15, weight: .medium))
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("Try again") {
                        Task { await loadSessions() }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .padding(.top, 2)
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
                                Image(systemName: session.deviceIcon)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text(session.device)
                                    .font(.system(size: 14, weight: .semibold))
                                    .lineLimit(1)
                                if session.isCurrent == true {
                                    Text("This device")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.primary.opacity(0.12), in: Capsule())
                                }
                                Spacer()
                                if session.isCurrent != true {
                                    Button(role: .destructive) {
                                        Task { await revokeSession(session.id) }
                                    } label: {
                                        if revokingSessionIDs.contains(session.id) {
                                            ButtonInlineProgressView(tint: .primary, side: AppTheme.Metrics.compactInlineSpinner)
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
                                if isRevokingAllSessions {
                                    ButtonInlineProgressView(tint: .primary, side: AppTheme.Metrics.toolbarInlineSpinner)
                                }
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
        .background(AppTheme.sheetBackground)
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
        loadError = nil
        defer { isLoadingSessions = false }
        do {
            let response = try await services.apiClient.listSessions()
            activeSessions = response.sessions
        } catch {
            AppLogger.shared.log("Load sessions failed: \(error.localizedDescription)")
            loadError = error.localizedDescription
        }
    }

    private func revokeSession(_ sessionId: String) async {
        revokingSessionIDs.insert(sessionId)
        defer { revokingSessionIDs.remove(sessionId) }
        do {
            let response = try await services.apiClient.revokeSession(sessionId: sessionId)
            if response.revokedCurrent {
                // Current device was revoked — sign out FIRST so the user can't
                // briefly interact with the still-visible sessions list with an
                // invalidated bearer token. Skip the post-action `loadSessions()`
                // refresh because the call would fail with 401 anyway.
                services.authService.hasSeenOnboarding = false
                services.signOut()
                dismiss()
                return
            }
            // Other device revoked: refresh the list so the row disappears.
            await loadSessions()
            await services.authService.fetchUserProfile()
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
    @State private var showApplyRecommendedConfirmation = false

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

                Toggle(isOn: $ai.aiCanWriteTasks) {
                    Label("Create & edit tasks", systemImage: "pencil")
                }

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
                    showApplyRecommendedConfirmation = true
                }
                .confirmationDialog(
                    "Replace all Mail Assistant settings?",
                    isPresented: $showApplyRecommendedConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Apply recommended", role: .destructive) {
                        services.assistantAutomationPolicy = .recommended
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This overwrites every toggle, workday hours, quiet hours, and excluded sender patterns with the recommended defaults. Your custom values will be lost.")
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
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("Location")
                        .font(.system(size: 15, weight: .medium))
                    TextField(
                        "e.g. Oslo, Norway",
                        text: Binding(
                            get: { services.location },
                            set: { services.location = $0 }
                        )
                    )
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
                }
                .padding(.vertical, 4)
            } header: {
                Text("Location")
            } footer: {
                Text("City and country (e.g. \"Oslo, Norway\"). Gives the AI location context for time zones, local references, and geographic follow-ups.")
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
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
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
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
                }
                .padding(.vertical, 4)
            } header: {
                Text("Custom instructions")
            } footer: {
                Text("Instructions the AI follows on every response — e.g. tone, format, or topics to avoid.")
            }
        }
        .tint(AppTheme.switchTint)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.sheetBackground)
        .navigationTitle("AI Assistant")
        .navigationBarTitleDisplayMode(.inline)
        // Note: AI profile is saved synchronously by the parent SettingsView "Done" button.
        // We intentionally do NOT save on .onDisappear here — that race could lose the most
        // recent edits when the sheet dismisses before the async save completes.
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
                            RoundedRectangle(cornerRadius: AppTheme.Radius.inline, style: .continuous)
                                .fill(previewBackground(for: preference))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.Radius.inline, style: .continuous)
                                        .strokeBorder(
                                            services.appearancePreference == preference
                                                ? Color.primary
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
                                    .foregroundStyle(.primary)
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

            // Brand accent — mirrors the macOS + web accent picker. The
            // selection is persisted in `AppServices.accentPreference` and is
            // available app-wide via `AppTheme.Accents.*` for future tint
            // surfaces (currently used by the design-system viewer preview).
            Section {
                accentPickerRow
                    .padding(.vertical, 6)
            } header: {
                Text("Accent")
            } footer: {
                Text("Brand accent used across the app. Some surfaces still use the system tint and will adopt the accent in a later release.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.sheetBackground)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Six round accent swatches in a single horizontal row. Selected swatch
    /// is wrapped in a ring at `AppTheme.Radius.chip` to stay consistent with
    /// the design-system spec.
    private var accentPickerRow: some View {
        HStack(spacing: 14) {
            ForEach(AccentPreference.allCases, id: \.rawValue) { preference in
                Button {
                    services.accentPreference = preference
                } label: {
                    accentSwatch(for: preference)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Accent \(preference.rawValue)")
                .accessibilityAddTraits(services.accentPreference == preference ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }

    private func accentSwatch(for preference: AccentPreference) -> some View {
        let isSelected = services.accentPreference == preference
        return ZStack {
            // Selection ring sits at chip-radius (rounded square) so a swatch
            // never reads as a stray system button. Stroke widens slightly when
            // selected to make the active accent unmistakable at a glance.
            RoundedRectangle(cornerRadius: AppTheme.Radius.chip, style: .continuous)
                .stroke(isSelected ? Color.primary : Color.clear, lineWidth: isSelected ? 2 : 0)
                .frame(width: 38, height: 38)
            Circle()
                .fill(preference.color)
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.chip, style: .continuous))
    }

    private func previewBackground(for preference: AppAppearancePreference) -> Color {
        switch preference {
        case .system: return Color(UIColor.systemBackground)
        case .light:  return Color(UIColor(white: 0.98, alpha: 1))
        case .dark:   return Color(UIColor(white: 0.109, alpha: 1))
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

// Extracted into a ViewModifier to keep the SettingsView body modifier chain short
// enough for Swift's type-checker (compiler times out with >~25 chained modifiers).
private struct SettingsSyncModifier: ViewModifier {
    let services: AppServices

    @AppStorage("ai_can_read_tasks")    private var aiCanReadTasks: Bool = true
    @AppStorage("ai_can_write_tasks")   private var aiCanWriteTasks: Bool = true
    @AppStorage("ai_can_read_calendar") private var aiCanReadCalendar: Bool = true
    @AppStorage("ai_can_write_calendar") private var aiCanWriteCalendar: Bool = true
    @AppStorage("ai_can_read_email")    private var aiCanReadEmail: Bool = true
    @AppStorage("ai_can_send_email")    private var aiCanSendEmail: Bool = true
    @AppStorage("ios_accent_color")     private var accentColorKey: String = "blue"

    func body(content: Content) -> some View {
        content
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
            .onChange(of: services.preferredStartViewMode) { _, value in
                Task { await services.syncSetting("defaultTaskView", value.rawValue) }
            }
            .onChange(of: services.threadGroupingEnabled) { _, value in
                Task { await services.syncSetting("groupByThread", value) }
            }
    }
}
