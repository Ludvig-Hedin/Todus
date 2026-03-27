import SwiftUI
import SwiftData

// MARK: - Onboarding Variant

/// Shown once after sign-up to introduce Apple Reminders sync.
/// Tapping "Connect" requests permission and imports existing reminders immediately.
/// "Skip" dismisses without enabling sync — user can always enable later in Settings.
struct RemindersOnboardingView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @State private var isConnecting = false

    var body: some View {
        ZStack {
            AppTheme.backgroundTop
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                AppleRemindersIconView(size: 88)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Apple Reminders icon")

                Spacer().frame(height: 24)

                Text("Connect Apple Reminders")
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(-0.4)
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 12)

                Text("Keep your tasks in sync with Apple Reminders.\nExisting reminders will be imported automatically.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AppTheme.mutedText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer().frame(height: 40)

                VStack(spacing: 12) {
                    // Connect button — requests permission, enables sync, imports reminders
                    Button {
                        Task { await connect() }
                    } label: {
                        HStack(spacing: 8) {
                            AppleRemindersIconView(size: 20)
                            if isConnecting {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.85)
                            }
                            Text(isConnecting ? "Connecting…" : "Connect Apple Reminders")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .disabled(isConnecting)

                    // Skip — marks prompt as seen without enabling sync
                    Button("Skip for now") {
                        services.hasConfiguredRemindersPrompt = true
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)

                Spacer()
            }
        }
    }

    private func connect() async {
        isConnecting = true
        // Enable the flag first so requestRemindersPermissionIfNeeded proceeds
        services.remindersSyncEnabled = true
        let granted = await services.requestRemindersPermissionIfNeeded()
        if granted {
            // Import any existing reminders from Apple Reminders into the app
            await services.importFromReminders(in: modelContext)
            // Sync new app tasks back out to Reminders
            services.syncExistingTasksToReminders(in: modelContext)
        } else {
            // Permission denied — roll back the enabled flag
            services.remindersSyncEnabled = false
        }
        isConnecting = false
        // Dismiss the onboarding step regardless of permission outcome
        services.hasConfiguredRemindersPrompt = true
    }
}

// MARK: - Settings Variant

/// Issue #12: Standalone Reminders setup page accessible from Settings.
/// Moved out of onboarding to reduce decision fatigue during auth.
struct RemindersSetupView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @State private var isEnabled: Bool = false
    @State private var permissionDenied = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: $isEnabled) {
                    Label("Sync with Reminders", systemImage: "arrow.triangle.2.circlepath")
                }
                .font(.system(size: 14, weight: .medium))
                .tint(Color.blue)
            } footer: {
                Text("Keep your tasks in sync with Apple Reminders.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.mutedText)
            }

            // Sync direction picker — only shown when sync is enabled
            if isEnabled {
                Section {
                    Picker(selection: Binding(
                        get: { services.remindersSyncDirection },
                        set: { services.remindersSyncDirection = $0 }
                    )) {
                        ForEach(RemindersSyncDirection.allCases) { direction in
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(direction.title)
                                    Text(direction.subtitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: direction.icon)
                            }
                            .tag(direction)
                        }
                    } label: {
                        Label("Sync Direction", systemImage: "arrow.left.arrow.right")
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("Sync Direction")
                } footer: {
                    Text(services.remindersSyncDirection.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.mutedText)
                }
            }

            if permissionDenied {
                Section {
                    Label("Permission denied. Please enable Reminders access in iOS Settings.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.danger)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.backgroundTop)
        .navigationTitle("Apple Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isEnabled = services.remindersSyncEnabled
        }
        .onChange(of: isEnabled) { _, newValue in
            services.remindersSyncEnabled = newValue
            if newValue {
                Task {
                    let granted = await services.requestRemindersPermissionIfNeeded()
                    if granted {
                        await services.importFromReminders(in: modelContext)
                    } else {
                        permissionDenied = true
                        isEnabled = false
                        services.remindersSyncEnabled = false
                    }
                }
            }
        }
    }
}
