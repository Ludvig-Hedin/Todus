import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    var body: some View {
        NavigationStack {
            List {
                accountSection
                connectedServicesSection
                appearanceSection
                notificationsSection
                preferencesSection

                if services.developerModeEnabled {
                    developerSection
                }

                aboutSection
                signOutSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.backgroundBottom)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Account

    private var accountSection: some View {
        Section {
            // Email — from new auth service, fallback to legacy
            HStack {
                Label {
                    Text("Email")
                } icon: {
                    Image(systemName: "envelope")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let email = services.authService.userEmail ?? services.authStore.accountEmail {
                    Text(email)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Not signed in")
                        .foregroundStyle(.tertiary)
                }
            }

            // Auth status
            HStack {
                Label {
                    Text("Status")
                } icon: {
                    Image(systemName: services.authService.isAuthenticated ? "checkmark.shield.fill" : "xmark.shield")
                        .foregroundStyle(services.authService.isAuthenticated ? .green : .secondary)
                }
                Spacer()
                Text(services.authService.isAuthenticated ? "Signed in" : "Not signed in")
                    .foregroundStyle(services.authService.isAuthenticated ? .primary : .tertiary)
            }

            // If not signed in, show a sign in button
            if !services.authService.isAuthenticated {
                Button {
                    // Return to login screen by clearing onboarding flag
                    services.authService.signOut()
                    services.authStore.signOutToGuest()
                    UserDefaults.standard.set(false, forKey: "Todus.hasSeenOnboarding")
                    UserDefaults.standard.set(false, forKey: "TaskApp.hasSeenOnboarding")
                    dismiss()
                } label: {
                    Label("Sign in", systemImage: "person.crop.circle.badge.plus")
                }
            }
        } header: {
            Text("Account")
        }
    }

    // MARK: - Connected Services

    private var connectedServicesSection: some View {
        Section {
            // Email provider connection
            HStack {
                Label {
                    Text("Gmail")
                } icon: {
                    Image(systemName: "envelope.fill")
                        .foregroundStyle(.red)
                }
                Spacer()
                // TODO: Check actual connection status from email service
                Text(services.authService.isAuthenticated ? "Connected" : "Not connected")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
            }

            HStack {
                Label {
                    Text("Apple Calendar")
                } icon: {
                    Image(systemName: "calendar")
                        .foregroundStyle(.red)
                }
                Spacer()
                Text(services.remindersSyncEnabled ? "Connected" : "Not connected")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
            }

            // Apple Reminders
            NavigationLink {
                RemindersSetupView()
            } label: {
                HStack {
                    Label {
                        Text("Apple Reminders")
                    } icon: {
                        Image(systemName: "checklist")
                            .foregroundStyle(.blue)
                    }
                    Spacer()
                    Text(services.remindersSyncEnabled ? "On" : "Off")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                }
            }
        } header: {
            Text("Connected Services")
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            Picker("Theme", selection: Binding(
                get: { services.appearancePreference },
                set: { services.appearancePreference = $0 }
            )) {
                ForEach(AppAppearancePreference.allCases) { preference in
                    Text(preference.title).tag(preference)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Appearance")
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            // Placeholder for future notification settings
            HStack {
                Label("Push Notifications", systemImage: "bell.badge")
                Spacer()
                Text("System Settings")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
            }
            .onTapGesture {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } header: {
            Text("Notifications")
        }
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        Section {
            Picker("Default view", selection: Binding(
                get: { services.preferredStartViewMode },
                set: {
                    services.preferredStartViewMode = $0
                    services.selectedViewMode = $0
                }
            )) {
                ForEach(TaskViewMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            NavigationLink {
                FolderManagementView()
            } label: {
                Label("Manage Folders", systemImage: "folder")
            }

            Toggle("Developer mode", isOn: Binding(
                get: { services.developerModeEnabled },
                set: { services.developerModeEnabled = $0 }
            ))
            .tint(.blue)
        } header: {
            Text("Preferences")
        }
    }

    // MARK: - Developer

    @State private var useLocalBackend = AppConfiguration.useLocalBackend

    private var developerSection: some View {
        Section {
            Toggle("Local Backend", isOn: $useLocalBackend)
                .onChange(of: useLocalBackend) { _, newValue in
                    AppConfiguration.useLocalBackend = newValue
                }
                .tint(.orange)

            LabeledContent("Backend", value: services.configuration.effectiveBackendURL.host ?? "unknown")
            LabeledContent("Auth state", value: authStateLabel)
            LabeledContent("Bearer token", value: services.authService.bearerToken != nil ? "Present (\(services.authService.bearerToken!.prefix(8))...)" : "None")
            LabeledContent("Model", value: simplifiedModelName(services.configuration.primaryModel))
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
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
            LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
        } header: {
            Text("About")
        }
    }

    // MARK: - Sign Out (always visible)

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                // Sign out from both auth systems and return to login
                services.authService.signOut()
                services.authStore.signOutToGuest()
                // Reset onboarding flag so the login screen shows
                UserDefaults.standard.set(false, forKey: "Todus.hasSeenOnboarding")
                UserDefaults.standard.set(false, forKey: "TaskApp.hasSeenOnboarding")
                dismiss()
            } label: {
                HStack {
                    Spacer()
                    Text(services.authService.isAuthenticated ? "Log out" : "Return to Login")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                }
            }
        }
    }

    // MARK: - Helpers

    private var authStateLabel: String {
        switch services.authService.authState {
        case .guest: return "Guest"
        case .authenticating: return "Authenticating..."
        case .otpPending: return "OTP Pending"
        case .authenticated: return "Authenticated"
        }
    }

    private func simplifiedModelName(_ model: String) -> String {
        model.split(separator: "/").last.map(String.init) ?? model
    }
}
