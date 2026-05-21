import SwiftUI

/// Focused settings sub-page for the email-automation policy.
///
/// Mirrors the macOS `emailPreferencesSection` knobs that are most relevant to
/// iOS: excluded sender patterns, the auto-send experiment toggle, and the
/// workday start/end hours that drive when prepared work is surfaced.
///
/// Persistence is handled by `AppServices.assistantAutomationPolicy` — the view
/// just mutates that struct and AppServices' `didSet` writes it back to defaults
/// and (via `saveSharedAIProfile`) the backend.
struct EmailAutomationPolicyView: View {
    @Environment(AppServices.self) private var services

    @State private var newPattern: String = ""
    @State private var showAutoSendConfirm = false
    /// Debounced server push so mid-edit crashes don't lose changes the user
    /// already committed locally. Cancelled + restarted on every mutation;
    /// `.onDisappear` flushes any pending push synchronously.
    @State private var pushTask: Task<Void, Never>?

    var body: some View {
        List {
            // MARK: Excluded senders
            Section {
                if services.assistantAutomationPolicy.excludedSenderPatterns.isEmpty {
                    Text("No excluded patterns yet.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(services.assistantAutomationPolicy.excludedSenderPatterns, id: \.self) { pattern in
                        Text(pattern)
                            .font(.system(size: 15))
                            .lineLimit(2)
                    }
                    .onDelete(perform: deletePatterns)
                }

                HStack(spacing: 8) {
                    TextField("e.g. notifications@", text: $newPattern)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(addPattern)
                        .accessibilityIdentifier("email.automationPolicy.excludedSenderField")
                    Button(action: addPattern) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                    }
                    .disabled(trimmedNewPattern.isEmpty)
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Excluded senders")
            } footer: {
                Text("One pattern per row. Suppresses noisy automation, newsletters, and low-value system mail from the assistant queues. Examples: notifications@, no-reply@, calendar-notification@")
            }

            // MARK: Auto-send experiment
            Section {
                Toggle(isOn: Binding(
                    get: { services.assistantAutomationPolicy.autoSendExperimentEnabled },
                    set: { newValue in
                        if newValue {
                            // Confirm before enabling — auto-sending email is high-risk.
                            showAutoSendConfirm = true
                        } else {
                            services.assistantAutomationPolicy.autoSendExperimentEnabled = false
                        }
                    }
                )) {
                    Label("Auto-send experiment", systemImage: "paperplane")
                }
                .tint(AppTheme.switchTint)
            } header: {
                Text("Auto-send")
            } footer: {
                Text("Only narrow, high-confidence acknowledgements become eligible. You can always review the experiment notes before turning this on.")
            }

            // MARK: Workday window
            Section {
                Picker(
                    selection: Binding(
                        get: { services.assistantAutomationPolicy.workdayStartHour },
                        set: { services.assistantAutomationPolicy.workdayStartHour = $0 }
                    )
                ) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(String(format: "%02d:00", hour)).tag(hour)
                    }
                } label: {
                    Label("Workday starts", systemImage: "sunrise")
                }
                .pickerStyle(.menu)

                Picker(
                    selection: Binding(
                        get: { services.assistantAutomationPolicy.workdayEndHour },
                        set: { services.assistantAutomationPolicy.workdayEndHour = $0 }
                    )
                ) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(String(format: "%02d:00", hour)).tag(hour)
                    }
                } label: {
                    Label("Workday ends", systemImage: "sunset")
                }
                .pickerStyle(.menu)
            } header: {
                Text("Workday")
            } footer: {
                Text("Used for urgency and to decide when Home should surface the most important prepared work.")
            }

            // MARK: Reset
            Section {
                Button(role: .destructive) {
                    services.assistantAutomationPolicy = .recommended
                    newPattern = ""
                } label: {
                    Label("Reset to recommended", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("Email automation")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Enable auto-send experiment?",
            isPresented: $showAutoSendConfirm,
            titleVisibility: .visible
        ) {
            Button("Enable") {
                services.assistantAutomationPolicy.autoSendExperimentEnabled = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only high-confidence acknowledgements become eligible. You can disable this at any time.")
        }
        .task {
            // Push any local edits back to the server when the user navigates away —
            // matches the macOS settings save pattern.
        }
        .onChange(of: services.assistantAutomationPolicy) { _, _ in
            schedulePush()
        }
        .onDisappear {
            // Flush any pending push synchronously so a crash on the next view
            // doesn't strand the local edit.
            pushTask?.cancel()
            Task { await services.saveSharedAIProfile() }
        }
    }

    // MARK: - Helpers

    /// Debounce server pushes by 300ms — collapses bursts of edits (typing
    /// patterns, stepper presses) into one network call while still saving
    /// soon enough that a crash mid-session preserves recent changes.
    private func schedulePush() {
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await services.saveSharedAIProfile()
        }
    }

    private var trimmedNewPattern: String {
        newPattern.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addPattern() {
        let trimmed = trimmedNewPattern
        guard !trimmed.isEmpty else { return }
        var patterns = services.assistantAutomationPolicy.excludedSenderPatterns
        // De-dupe case-insensitively to match what the backend filtering does.
        guard !patterns.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            newPattern = ""
            return
        }
        patterns.append(trimmed)
        services.assistantAutomationPolicy.excludedSenderPatterns = patterns
        newPattern = ""
    }

    private func deletePatterns(at offsets: IndexSet) {
        var patterns = services.assistantAutomationPolicy.excludedSenderPatterns
        patterns.remove(atOffsets: offsets)
        services.assistantAutomationPolicy.excludedSenderPatterns = patterns
    }
}
