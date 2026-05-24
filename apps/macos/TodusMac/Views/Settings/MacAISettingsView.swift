import SwiftUI

/// Full AI Assistant settings — extracted from MacSettingsView so the
/// monolithic 30+ item wall can be broken into navigable sub-groups.
/// Presented as a sheet from the single "AI Assistant" row in MacSettingsView.
struct MacAISettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(MacAppServices.self) private var services

    @Binding var aiTone: String
    @Binding var aiCanReadTasks: Bool
    @Binding var aiCanWriteTasks: Bool
    @Binding var aiCanReadCalendar: Bool
    @Binding var aiCanWriteCalendar: Bool
    @Binding var aiCanReadEmail: Bool
    @Binding var aiCanSendEmail: Bool
    @Binding var excludedSenderPatternsText: String

    @State private var showsLocalModels = false
    @State private var showAutoSendConfirmation = false
    @State private var showApplyRecommendedConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("AI Assistant")
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

            Divider().opacity(0.2)

            ScrollView {
                VStack(alignment: .leading, spacing: MacTheme.settingsSectionSpacing) {
                    permissionsSection
                    personalizationSection
                    mailAssistantSection
                    modelSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.never)
        }
        .background(MacTheme.contentBackground)
        .sheet(isPresented: $showsLocalModels) {
            NavigationStack { MacLocalModelsView() }
                .frame(minWidth: 600, minHeight: 600)
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
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        aiGroup(title: "Permissions", description: "What the assistant can read and act on.") {
            aiCard {
                aiToggle(icon: "checklist", label: "Read my tasks", isOn: $aiCanReadTasks)
                cardDivider
                aiToggle(icon: "square.and.pencil", label: "Create & edit tasks", isOn: $aiCanWriteTasks)
                cardDivider
                aiToggle(icon: "calendar", label: "Read calendar", isOn: $aiCanReadCalendar)
                cardDivider
                aiToggle(icon: "calendar.badge.plus", label: "Create calendar events", isOn: $aiCanWriteCalendar)
                cardDivider
                aiToggle(icon: "envelope", label: "Read email", isOn: $aiCanReadEmail)
                cardDivider
                aiToggle(icon: "paperplane", label: "Send email", isOn: $aiCanSendEmail)
            }
        }
    }

    // MARK: - Personalization

    private var personalizationSection: some View {
        aiGroup(title: "Personalization", description: "Context and tone for all AI responses.") {
            aiCard {
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
                    Text("City and country. Optional — gives the AI location context.")
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
                        placeholder: "Anything the assistant should know — your role, projects, tone, communication style…"
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
                        placeholder: "e.g. Keep replies under 3 sentences. Never use emojis."
                    )
                }
                .padding(.horizontal, MacTheme.settingsRowHorizontalPadding)
                .padding(.vertical, MacTheme.settingsRowVerticalPadding)

                cardDivider

                // Response tone
                aiRow {
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
            }
        }
    }

    // MARK: - Mail Assistant

    private var mailAssistantSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mail Assistant")
                        .font(MacTheme.settingsSectionHeaderFont())
                        .foregroundStyle(MacTheme.textSecondary)
                    Text("What Todus may prepare for you automatically.")
                        .font(.system(size: 11))
                        .foregroundStyle(MacTheme.textSecondary.opacity(0.7))
                }
                .padding(.leading, 4)
                Spacer()
                Button("Reset to recommended") {
                    showApplyRecommendedConfirmation = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.trailing, 4)
            }

            // Briefing
            sectionSubheader("Briefing")
            aiCard {
                aiToggle(
                    icon: "rectangle.stack.badge.person.crop",
                    label: "Enable briefing engine",
                    description: "Continuously prepare open loops, prepared actions, and daily priorities.",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.briefingEnabled },
                        set: { services.assistantAutomationPolicy.briefingEnabled = $0 }
                    )
                )
                cardDivider
                aiToggle(
                    icon: "house",
                    label: "Show briefing on Home",
                    description: "Surface Today, Needs You, Waiting On, Prepared, and Changed Since.",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.showHomeBriefing },
                        set: { services.assistantAutomationPolicy.showHomeBriefing = $0 }
                    )
                )
                cardDivider
                aiToggle(
                    icon: "text.append",
                    label: "Auto-summarize long threads",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.autoSummarizeLongThreads },
                        set: { services.assistantAutomationPolicy.autoSummarizeLongThreads = $0 }
                    )
                )
            }

            // Triage
            sectionSubheader("Triage")
            aiCard {
                aiToggle(
                    icon: "checklist",
                    label: "Suggest tasks from email",
                    description: "Turn actionable requests into proposed tasks.",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.suggestTasksFromEmail },
                        set: { services.assistantAutomationPolicy.suggestTasksFromEmail = $0 }
                    )
                )
                cardDivider
                aiToggle(
                    icon: "calendar.badge.plus",
                    label: "Suggest events from email",
                    description: "Detect scheduling and surface one-tap event creation.",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.suggestEventsFromEmail },
                        set: { services.assistantAutomationPolicy.suggestEventsFromEmail = $0 }
                    )
                )
                cardDivider
                aiToggle(
                    icon: "tray.full",
                    label: "Smart reply nudges",
                    description: "Highlight threads that likely need a response.",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.smartReplyNudges },
                        set: { services.assistantAutomationPolicy.smartReplyNudges = $0 }
                    )
                )
                cardDivider
                aiToggle(
                    icon: "clock.badge.exclamationmark",
                    label: "Smart deadline nudges",
                    description: "Warn about likely deadlines or stale commitments.",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.smartDeadlineNudges },
                        set: { services.assistantAutomationPolicy.smartDeadlineNudges = $0 }
                    )
                )
                cardDivider
                aiToggle(
                    icon: "arrow.triangle.branch",
                    label: "Track waiting-on threads",
                    description: "Keep a queue for commitments blocked on someone else.",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.trackWaitingOnThreads },
                        set: { services.assistantAutomationPolicy.trackWaitingOnThreads = $0 }
                    )
                )
            }

            // Drafts & Replies
            sectionSubheader("Drafts & Replies")
            aiCard {
                aiToggle(
                    icon: "arrowshape.turn.up.left",
                    label: "Auto-draft replies",
                    description: "Prepare high-confidence reply drafts for review.",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.autoDraftReplies },
                        set: { services.assistantAutomationPolicy.autoDraftReplies = $0 }
                    )
                )
                cardDivider
                aiToggle(
                    icon: "sparkles",
                    label: "Show thread assistant controls",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.assistantThreadActionsVisible },
                        set: { services.assistantAutomationPolicy.assistantThreadActionsVisible = $0 }
                    )
                )
            }

            // Memory
            sectionSubheader("Memory")
            aiCard {
                aiToggle(
                    icon: "person.2",
                    label: "Build people memory",
                    description: "Remember context about senders over time.",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.peopleMemoryEnabled },
                        set: { services.assistantAutomationPolicy.peopleMemoryEnabled = $0 }
                    )
                )
                cardDivider
                aiToggle(
                    icon: "square.stack.3d.up",
                    label: "Batch prepared approvals",
                    isOn: Binding(
                        get: { services.assistantAutomationPolicy.batchApprovalEnabled },
                        set: { services.assistantAutomationPolicy.batchApprovalEnabled = $0 }
                    )
                )
            }

            // Workday
            sectionSubheader("Workday")
            aiCard {
                aiRow {
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
                aiRow {
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
            }

            // Noise Filtering
            sectionSubheader("Noise Filtering")
            aiCard {
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
                    Text("Suppress newsletters, no-reply mail, and other low-value automation from assistant queues.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(MacTheme.textSecondary)
                }
                .padding(.horizontal, MacTheme.settingsRowHorizontalPadding)
                .padding(.vertical, MacTheme.settingsRowVerticalPadding)
            }

            // Auto-send
            sectionSubheader("Auto-send")
            aiCard {
                VStack(alignment: .leading, spacing: 6) {
                    aiToggle(
                        icon: "paperplane",
                        label: "Enable low-risk auto-send experiment",
                        isOn: Binding(
                            get: { services.assistantAutomationPolicy.autoSendExperimentEnabled },
                            set: { newValue in
                                if newValue && !services.assistantAutomationPolicy.autoSendExperimentEnabled {
                                    showAutoSendConfirmation = true
                                } else if !newValue {
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
            }
        }
    }

    // MARK: - Model

    private var modelSection: some View {
        aiGroup(title: "Model", description: "Which AI model powers the assistant.") {
            @Bindable var ai = services.aiChatService
            aiCard {
                // AI model
                aiRow {
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
                // Local models
                aiRow {
                    Image(systemName: "internaldrive")
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
    }

    // MARK: - Layout Helpers

    private func aiGroup<Content: View>(
        title: String,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MacTheme.settingsSectionHeaderFont())
                    .foregroundStyle(MacTheme.textSecondary)
                if let description {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(MacTheme.textSecondary.opacity(0.7))
                }
            }
            .padding(.leading, 4)
            content()
        }
    }

    private func aiCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private var cardDivider: some View {
        Divider().opacity(0.12).padding(.horizontal, MacTheme.settingsRowHorizontalPadding)
    }

    private func aiRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
        }
        .padding(.horizontal, MacTheme.settingsRowHorizontalPadding)
        .padding(.vertical, MacTheme.settingsRowVerticalPadding)
    }

    private func aiToggle(icon: String, label: String, description: String? = nil, isOn: Binding<Bool>) -> some View {
        aiRow {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MacTheme.mutedText)
                .frame(width: 18)
            if let description {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 12.5))
                        .foregroundStyle(MacTheme.textPrimary)
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(MacTheme.textSecondary)
                }
            } else {
                Text(label)
                    .font(.system(size: 12.5))
                    .foregroundStyle(MacTheme.textPrimary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(MacTheme.switchTint)
        }
    }

    private func sectionSubheader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(MacTheme.textSecondary.opacity(0.7))
            .tracking(0.5)
            .padding(.horizontal, MacTheme.settingsRowHorizontalPadding)
            .padding(.top, MacTheme.settingsSubgroupSpacing)
            .padding(.bottom, 2)
    }

    private func openURL(_ string: String) {
        if let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
    }
}
