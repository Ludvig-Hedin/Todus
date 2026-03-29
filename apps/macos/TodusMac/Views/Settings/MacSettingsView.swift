import SwiftUI
import SwiftData

/// Settings view — account, connected services, preferences, notifications, about.
/// Matches iOS feature set with desktop-optimized layout.
struct MacSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(MacAppServices.self) private var services

    @State private var showsLogoutConfirmation = false
    @State private var showsDeleteConfirmation = false
    @State private var showsDeleteAlert = false
    @State private var deleteConfirmText = ""
    @State private var showsDisconnectGmail = false

    // Preferences state
    @AppStorage("preferredColorScheme") private var preferredColorScheme = "system"
    @AppStorage("taskRemindersEnabled") private var taskRemindersEnabled = true
    @AppStorage("calendarRemindersEnabled") private var calendarRemindersEnabled = true
    @AppStorage("swipeGesturesEnabled") private var swipeGesturesEnabled = true
    @AppStorage("threadGroupingEnabled") private var threadGroupingEnabled = true

    private var calendarAccessGranted: Bool {
        services.calendarService.canReadEvents()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(size: 13, weight: .medium))
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(MacTheme.spacing16)

            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: MacTheme.spacing24) {
                    accountSection
                    connectedServicesSection
                    preferencesSection
                    emailSection
                    notificationsSection
                    aboutSection
                }
                .padding(MacTheme.spacing24)
            }
        }
        .frame(minWidth: 500, minHeight: 480)
        .task {
            await services.emailService.checkConnection()
        }
        // Logout confirmation
        .confirmationDialog(
            "Are you sure you want to log out?",
            isPresented: $showsLogoutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Log out", role: .destructive) {
                services.authService.signOut()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        // Delete account — first confirmation
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
            Text("This will permanently delete your account, tasks, email connections, and all data.")
        }
        // Delete account — type DELETE
        .alert("Type DELETE to confirm", isPresented: $showsDeleteAlert) {
            TextField("DELETE", text: $deleteConfirmText)
            Button("Delete Account", role: .destructive) {
                guard deleteConfirmText == "DELETE" else { return }
                Task { await performDeleteAccount() }
            }
            Button("Cancel", role: .cancel) {
                deleteConfirmText = ""
            }
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
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        settingsSection(title: "ACCOUNT") {
            HStack(spacing: MacTheme.spacing12) {
                avatarView

                VStack(alignment: .leading, spacing: 2) {
                    if let name = services.authService.userName, !name.isEmpty {
                        Text(name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MacTheme.textPrimary)
                    }
                    if let email = services.authService.userEmail {
                        Text(email)
                            .font(MacTheme.cardSubtitleFont())
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                }

                Spacer()
            }
            .padding(MacTheme.spacing12)

            Divider().opacity(0.15).padding(.horizontal, MacTheme.spacing12)

            if services.authService.isAuthenticated {
                HStack(spacing: MacTheme.spacing12) {
                    Button(role: .destructive) {
                        showsLogoutConfirmation = true
                    } label: {
                        Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(red: 0.85, green: 0.3, blue: 0.3))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(role: .destructive) {
                        showsDeleteConfirmation = true
                    } label: {
                        Text("Delete account")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(red: 0.85, green: 0.3, blue: 0.3).opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, MacTheme.spacing12)
                .padding(.vertical, MacTheme.spacing8)
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
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
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
                .fill(MacTheme.accent.opacity(0.12))
                .frame(width: 40, height: 40)
            if let name = services.authService.userName, let first = name.first {
                Text(String(first).uppercased())
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(MacTheme.accent)
            } else if let email = services.authService.userEmail, let first = email.first {
                Text(String(first).uppercased())
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(MacTheme.accent)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(MacTheme.mutedText)
            }
        }
    }

    // MARK: - Connected Services

    private var connectedServicesSection: some View {
        settingsSection(title: "CONNECTED SERVICES") {
            // Gmail
            serviceRow(
                icon: "envelope.fill",
                iconColor: Color(red: 0.85, green: 0.3, blue: 0.3),
                name: "Gmail",
                status: services.emailService.hasConnection ? "Connected" : "Not connected",
                isConnected: services.emailService.hasConnection
            ) {
                if services.emailService.hasConnection {
                    Button("Disconnect") {
                        showsDisconnectGmail = true
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(red: 0.85, green: 0.3, blue: 0.3).opacity(0.8))
                    .buttonStyle(.plain)
                } else {
                    Button("Connect") {
                        Task { await services.emailService.connectGmail(authService: services.authService) }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MacTheme.accent)
                    .buttonStyle(.plain)
                }
            }

            Divider().opacity(0.15).padding(.horizontal, MacTheme.spacing12)

            // Calendar
            serviceRow(
                icon: "calendar",
                iconColor: Color(red: 0.85, green: 0.3, blue: 0.2),
                name: "Apple Calendar",
                status: calendarAccessGranted ? "Connected" : "Not connected",
                isConnected: calendarAccessGranted
            ) {
                if calendarAccessGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green.opacity(0.7))
                        .font(.system(size: 14))
                } else {
                    Button("Connect") {
                        Task { await services.calendarService.requestAccess() }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MacTheme.accent)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func serviceRow<Trailing: View>(
        icon: String,
        iconColor: Color,
        name: String,
        status: String,
        isConnected: Bool,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: MacTheme.spacing8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MacTheme.textPrimary)
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(isConnected ? .green.opacity(0.7) : MacTheme.mutedText)
            }

            Spacer()

            trailing()
        }
        .padding(.horizontal, MacTheme.spacing12)
        .padding(.vertical, MacTheme.spacing8)
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        settingsSection(title: "PREFERENCES") {
            // Theme picker
            settingsRow(icon: "paintbrush", label: "Appearance") {
                Picker("", selection: $preferredColorScheme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            Divider().opacity(0.15).padding(.horizontal, MacTheme.spacing12)

            // Email preferences
            settingsToggleRow(icon: "hand.draw", label: "Swipe Gestures", isOn: $swipeGesturesEnabled)

            Divider().opacity(0.15).padding(.horizontal, MacTheme.spacing12)

            settingsToggleRow(icon: "text.bubble", label: "Group by Thread", isOn: $threadGroupingEnabled)
        }
    }

    // MARK: - Email Section

    private var emailSection: some View {
        settingsSection(title: "EMAIL") {
            // Gmail connect button when not connected
            if !services.emailService.hasConnection {
                HStack(spacing: MacTheme.spacing8) {
                    Image(systemName: "envelope.badge")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                        .frame(width: 20)
                    Text("Connect Gmail to enable email features")
                        .font(.system(size: 12))
                        .foregroundStyle(MacTheme.textSecondary)
                    Spacer()
                    Button("Connect") {
                        Task { await services.emailService.connectGmail(authService: services.authService) }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MacTheme.accent)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, MacTheme.spacing12)
                .padding(.vertical, MacTheme.spacing8)
            } else {
                settingsRow(icon: "envelope.open", label: "Gmail") {
                    Text("Connected")
                        .font(.system(size: 12))
                        .foregroundStyle(.green.opacity(0.7))
                }
            }
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        settingsSection(title: "NOTIFICATIONS") {
            settingsToggleRow(icon: "checklist", label: "Task Due Reminders", isOn: $taskRemindersEnabled)

            Divider().opacity(0.15).padding(.horizontal, MacTheme.spacing12)

            settingsToggleRow(icon: "calendar.badge.clock", label: "Calendar Reminders", isOn: $calendarRemindersEnabled)

            Divider().opacity(0.15).padding(.horizontal, MacTheme.spacing12)

            // System notification settings link
            HStack(spacing: MacTheme.spacing8) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MacTheme.mutedText)
                    .frame(width: 20)
                Text("System Settings")
                    .font(.system(size: 13))
                    .foregroundStyle(MacTheme.textPrimary)
                Spacer()
                Button {
                    // Open macOS System Settings > Notifications
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                        .foregroundStyle(MacTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, MacTheme.spacing12)
            .padding(.vertical, MacTheme.spacing8)

            Divider().opacity(0.15).padding(.horizontal, MacTheme.spacing12)

            // Data privacy row
            HStack(spacing: MacTheme.spacing8) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MacTheme.mutedText)
                    .frame(width: 20)
                Text("Data Sync")
                    .font(.system(size: 13))
                    .foregroundStyle(MacTheme.textPrimary)
                Spacer()
                Text("End-to-end")
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.textSecondary)
            }
            .padding(.horizontal, MacTheme.spacing12)
            .padding(.vertical, MacTheme.spacing8)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        settingsSection(title: "ABOUT") {
            aboutRow(icon: "info.circle", label: "Version",
                     value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
            Divider().opacity(0.15).padding(.horizontal, MacTheme.spacing12)
            aboutRow(icon: "hammer", label: "Build",
                     value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
            Divider().opacity(0.15).padding(.horizontal, MacTheme.spacing12)
            aboutRow(icon: "desktopcomputer", label: "Platform", value: "macOS")
        }
    }

    private func aboutRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: MacTheme.spacing8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MacTheme.mutedText)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(MacTheme.textPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(MacTheme.textSecondary)
        }
        .padding(.horizontal, MacTheme.spacing12)
        .padding(.vertical, MacTheme.spacing6)
    }

    // MARK: - Shared Components

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing8) {
            Text(title)
                .font(MacTheme.sectionHeaderFont())
                .foregroundStyle(MacTheme.mutedText)
                .tracking(0.8)

            VStack(spacing: 0) {
                content()
            }
            .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
        }
    }

    private func settingsRow<Trailing: View>(icon: String, label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: MacTheme.spacing8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MacTheme.mutedText)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(MacTheme.textPrimary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, MacTheme.spacing12)
        .padding(.vertical, MacTheme.spacing8)
    }

    private func settingsToggleRow(icon: String, label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: MacTheme.spacing8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MacTheme.mutedText)
                .frame(width: 20)
            Toggle(label, isOn: isOn)
                .font(.system(size: 13))
                .foregroundStyle(MacTheme.textPrimary)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, MacTheme.spacing12)
        .padding(.vertical, MacTheme.spacing6)
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

        dismiss()
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
