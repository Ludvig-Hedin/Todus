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
                appearanceSection
                remindersSection
                preferencesSection
                aiSection

                if services.developerModeEnabled {
                    developerSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.backgroundTop)
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

    private var accountSection: some View {
        Section {
            if let email = services.authStore.accountEmail {
                LabeledContent("Email", value: email)
            } else {
                LabeledContent("Email", value: "Not signed in")
            }

            LabeledContent("Status", value: accountStatusTitle)

            Button(accountButtonTitle) {
                services.authStore.markOnboardingVisible()
                dismiss()
            }

            if case .authenticated = services.authStore.authState {
                Button("Log out", role: .destructive) {
                    services.authStore.signOutToGuest()
                    dismiss()
                }
            }
        } header: {
            Text("Account")
        } footer: {
            if case .guest = services.authStore.authState {
                Text("You can keep using the app as a guest and sign in later when you want sync tied to your email.")
            } else if case .magicLinkPending = services.authStore.authState {
                Text("Your email is saved. Finish verification from the login page to complete sign-in.")
            }
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("Theme", selection: Binding(
                get: { services.appearancePreference },
                set: { services.appearancePreference = $0 }
            )) {
                ForEach(AppAppearancePreference.allCases) { preference in
                    Label(preference.title, systemImage: preference == .system ? "circle.lefthalf.filled" : (preference == .light ? "sun.max" : "moon.fill"))
                        .tag(preference)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Appearance")
        }
    }

    // Issue #12: Reminders now has its own dedicated page
    private var remindersSection: some View {
        Section {
            NavigationLink {
                RemindersSetupView()
            } label: {
                HStack {
                    Label("Apple Reminders", systemImage: "bell.badge")
                    Spacer()
                    Text(services.remindersSyncEnabled ? "On" : "Off")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.mutedText)
                }
            }
        } header: {
            Text("Reminders")
        }
    }

    private var preferencesSection: some View {
        Section {
            Picker("Start in", selection: Binding(
                get: { services.preferredStartViewMode },
                set: {
                    services.preferredStartViewMode = $0
                    services.selectedViewMode = $0
                }
            )) {
                ForEach(TaskViewMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)

            // Issue #11: Folder management now has its own dedicated page
            NavigationLink {
                FolderManagementView()
            } label: {
                Label("Manage Folders", systemImage: "folder")
            }

            Toggle("Developer mode", isOn: Binding(
                get: { services.developerModeEnabled },
                set: { services.developerModeEnabled = $0 }
            ))
            .tint(Color.blue)
        } header: {
            Text("Preferences")
        } footer: {
            Text("Choose how the app should look and where you want to land when it opens.")
        }
    }

    private var aiSection: some View {
        Section {
            LabeledContent("Primary model", value: simplifiedModelName(services.configuration.primaryModel))
            LabeledContent("Fallbacks", value: "\(services.configuration.fallbackModels.count)")
            LabeledContent("Backend", value: services.configuration.hasRemoteBackend ? "Connected" : "Local only")
        } header: {
            Text("AI")
        } footer: {
            Text("Tasks save instantly on-device. AI parsing runs after save and falls back locally when the backend is unavailable.")
        }
    }

    @State private var useLocalBackend = AppConfiguration.useLocalBackend

    private var developerSection: some View {
        Section {
            // Local backend toggle — connects to localhost:8787 for dev with hot reload
            Toggle("Use Local Backend", isOn: $useLocalBackend)
                .onChange(of: useLocalBackend) { _, newValue in
                    AppConfiguration.useLocalBackend = newValue
                }

            LabeledContent("Backend URL", value: services.configuration.effectiveBackendURL.absoluteString)
            LabeledContent("Install ID", value: services.authStore.installID)
            LabeledContent("Anonymous ID", value: services.authStore.anonymousID)
            LabeledContent("Model chain", value: services.configuration.preferredModels.joined(separator: " -> "))

            Button("Retry account upgrade") {
                Task {
                    await services.completeAuthUpgradeIfNeeded(in: modelContext)
                }
            }

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
            Text("Local backend connects to http://localhost:8787 (run `pnpm dev` in apps/server). Restart the app after toggling.")
        }
    }

    private var accountStatusTitle: String {
        switch services.authStore.authState {
        case .guest:
            return "Guest"
        case .magicLinkPending:
            return "Verification pending"
        case .authenticated:
            return "Signed in"
        }
    }

    private var accountButtonTitle: String {
        switch services.authStore.authState {
        case .guest:
            return "Open login page"
        case .magicLinkPending:
            return "Continue login"
        case .authenticated:
            return "Switch account"
        }
    }

    private func simplifiedModelName(_ model: String) -> String {
        model.split(separator: "/").last.map(String.init) ?? model
    }


}
