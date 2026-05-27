import SwiftUI
import WebKit

/// Email thread detail view — shows all messages in a thread with HTML rendering.
/// Used inline (split-panel) or in a sheet (from search). Pass `onClose` for inline mode.
struct MacEmailThreadView: View {
    @Environment(MacAppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let threadId: String
    /// Called when the user taps the back button in inline (split-panel) mode.
    /// When nil, falls back to the SwiftUI environment dismiss action (sheet mode).
    var onClose: (() -> Void)? = nil

    @State private var detail: GetThreadResponse? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var expandedMessages: Set<String> = []
    /// Per-message WebView content heights, populated after each HTML page finishes loading.
    @State private var webViewHeights: [String: CGFloat] = [:]
    /// Per-message override for dark email render. Default = light card.
    @State private var emailDarkMessages: Set<String> = []
    @State private var showCompose = false
    @State private var composeMode: ThreadComposeMode = .reply

    private enum ThreadComposeMode: Hashable {
        case reply
        case replyAll
        case forward
    }
    @State private var assistantThread: AssistantThreadContext? = nil
    @State private var isLoadingAssistant = true
    @State private var assistantDraftSeed = ""
    /// Per-thread local dismissal of the assistant card. When the user taps
    /// "Not useful" the card collapses for the duration of the session — no
    /// backend feedback yet, but the trust loop closes immediately. The
    /// Settings → Mail Assistant toggle remains the global escape hatch.
    /// (UX assessment S3.)
    @State private var assistantLocallyDismissed: Bool = false
    /// Visible transient toast for assistant action results (success or failure).
    /// Replaces the previous modal alert which was disruptive and easy to miss.
    @State private var assistantToast: MacToastMessage?
    /// Tracks which assistant action is currently in flight so the matching
    /// button can show a spinner / disable, and other buttons grey out. Only
    /// one action runs at a time.
    @State private var inFlightAction: ThreadAction?
    /// The action that just succeeded — drives the inline "✓ Created"
    /// affordance inside the button. Auto-clears after 3s so the button
    /// reverts to its normal label.
    @State private var recentlyCompletedAction: ThreadAction?
    /// Surfaces a confirmation dialog before the destructive Delete action.
    /// Without this, an accidental click on the trash icon (which sits right
    /// next to Archive) permanently deletes the thread with no undo path.
    @State private var showDeleteConfirmation: Bool = false
    /// One-shot per thread: tracks whether the regex-extracted verification
    /// code has been auto-copied to the clipboard. Prevents re-copying when
    /// the user toggles tabs / re-renders while still inside the thread.
    /// Distinct from `services.autoCopiedVerificationThreads`, which guards
    /// the assistant-derived code path. (iOS parity.)
    @State private var copiedCodeOnce: Bool = false
    /// Surfaces the "Remind me about this…" snooze sheet. Wires into
    /// `MacNotificationService.scheduleEmailReminder` once the user picks a preset.
    @State private var showReminderOptions: Bool = false
    /// Presents a small popover with a `DatePicker` for the "Pick a date…" preset
    /// so users can schedule an arbitrary reminder fire time.
    @State private var showReminderDatePicker: Bool = false
    /// Bound to the popover's `DatePicker`. Initialised lazily when the popover opens.
    @State private var pickedReminderDate: Date = Date().addingTimeInterval(3600)
    /// Mac-side fallback verification code extracted from subject / first
    /// message body when the assistant context doesn't carry one. Computed
    /// lazily once the thread loads. Empty string means "no code found".
    @State private var fallbackVerificationCode: String = ""
    /// Mac-side fallback receipt info extracted from subject / body when the
    /// assistant context doesn't carry one. nil means "no signal".
    @State private var fallbackTrackingInfo: TrackingInfo? = nil
    /// Inflight smart-action toolbar action — drives per-icon spinner state.
    @State private var smartActionInFlight: SmartAction? = nil

    /// How long the inline "Created" confirmation persists inside an action
    /// button before reverting to its normal label.
    private let recentCompletionDuration: Double = 3

    enum ThreadAction: Equatable {
        case task
        case draft
        case event
    }

    /// Identifies which smart-action toolbar button is currently running so
    /// we can show a spinner on the matching icon and dim the others. The
    /// toolbar reuses the existing `handleCreateTask`/`handleCreateEvent`/
    /// `handleDraftReply` paths, but those run when the user has clicked the
    /// always-visible toolbar, not the assistant card.
    enum SmartAction: Equatable {
        case createTask
        case createEvent
        case generateReply
    }

    /// Lightweight "we found a tracking / order number" record used by the
    /// regex fallback chip when the assistant context doesn't include a
    /// receipt. `url` may be nil when we recognised the number's shape but
    /// can't form a tracker URL — in that case we hide the action button.
    struct TrackingInfo: Equatable {
        enum Kind: Equatable { case shipment, order }
        let kind: Kind
        let number: String
        let url: URL?
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)

            if isLoading && detail == nil {
                // Centered inside a max-height frame so the transition from
                // spinner → loaded content doesn't shove the surrounding chrome
                // around. Using `controlSize(.small)` + secondary tint matches
                // the iOS thread loader so a brief spinner reads as a hint, not
                // a full-screen wait.
                VStack(spacing: MacTheme.spacing8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.secondary)
                    Text("Loading…")
                        .font(MacTheme.cardSubtitleFont())
                        .foregroundStyle(MacTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, detail == nil {
                VStack(spacing: MacTheme.spacing12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(MacTheme.mutedText)
                    Text(error)
                        .font(MacTheme.cardSubtitleFont())
                        .foregroundStyle(MacTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                    Button {
                        errorMessage = nil
                        isLoading = true
                        Task { await loadThread() }
                    } label: {
                        Text("Try Again")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MacTheme.accent)
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail {
                // Single scrollable area — the outer ScrollView handles all scrolling.
                // Messages use PassthroughWKWebView which forwards scroll events upward
                // so the WebView itself never consumes scroll wheel input.
                ScrollView {
                    VStack(spacing: 0) {
                        // The "Latest message" preview block was removed —
                        // it duplicated the first lines of the most recent
                        // message that was already rendered just below it,
                        // adding only noise to the top of the thread.

                        // Smart-action toolbar — three always-visible icon
                        // buttons (Create task / Create event / Generate
                        // reply) below the header. iOS parity affordance:
                        // gives the user one-tap access to the same
                        // mutations the assistant card surfaces, even when
                        // AI is still loading or has nothing to suggest.
                        smartActionToolbar(detail: detail)
                            .padding(.horizontal, MacTheme.spacing16)
                            .padding(.top, MacTheme.spacing12)
                            .padding(.bottom, MacTheme.spacing4)

                        // Smart-action chip for verification / receipt threads.
                        // Replaces the (otherwise hidden) AI card with the one
                        // affordance that's actually useful on these emails:
                        //   - Verification → giant "Copy 178 691" button
                        //   - Receipt → vendor · amount · date chip
                        if services.assistantAutomationPolicy.assistantThreadActionsVisible,
                           let assistant = assistantThread {
                            if let code = assistant.extractedCode, !code.isEmpty {
                                MacVerificationCodeAction(code: code) {
                                    let pasteboard = NSPasteboard.general
                                    pasteboard.clearContents()
                                    pasteboard.setString(
                                        code.replacingOccurrences(of: " ", with: ""),
                                        forType: .string
                                    )
                                    assistantToast = .success("Code copied")
                                }
                                .padding(.horizontal, MacTheme.spacing16)
                                .padding(.top, MacTheme.spacing16)
                                .padding(.bottom, MacTheme.spacing12)
                            } else if let receipt = assistant.extractedReceipt {
                                MacReceiptInfoChip(receipt: receipt) {
                                    // Forward the receipt — opens the compose
                                    // sheet in forward mode with the existing
                                    // body. Useful for sending to a
                                    // bookkeeper or expense tracker.
                                    composeMode = .forward
                                    showCompose = true
                                }
                                .padding(.horizontal, MacTheme.spacing16)
                                .padding(.top, MacTheme.spacing16)
                                .padding(.bottom, MacTheme.spacing12)
                            } else {
                                // Assistant exists but found neither a code
                                // nor a receipt — fall back to client-side
                                // regex extraction so verification / order
                                // mails still get a chip on older backends
                                // or when extraction silently fails.
                                regexFallbackChips
                            }
                        } else {
                            // No assistant context (e.g. assistant disabled
                            // or still loading) — still try the regex
                            // fallback so verification codes are surfaced
                            // before the AI round-trip completes.
                            regexFallbackChips
                        }

                        // Hide the AI card entirely on low-signal threads
                        // (verification codes, receipts, marketing,
                        // notifications). For conversational threads we keep
                        // the existing card with its loading / empty / populated
                        // states so the user knows AI did look.
                        if services.assistantAutomationPolicy.assistantThreadActionsVisible
                            && shouldShowAssistantCard
                        {
                            MacMailAssistantCard(
                                assistant: assistantThread,
                                isLoading: isLoadingAssistant,
                                isSpam: isThreadInSpam(detail),
                                inFlightAction: inFlightAction,
                                recentlyCompletedAction: recentlyCompletedAction,
                                onRefresh: refreshAssistant,
                                onCreateTask: { suggestion in await handleCreateTask(suggestion) },
                                onCreateEvent: { await handleCreateEvent() },
                                onDraftReply: { await handleDraftReply() },
                                onDismiss: {
                                    withAnimation(MacTheme.Motion.base) {
                                        assistantLocallyDismissed = true
                                    }
                                }
                            )
                            .padding(.horizontal, MacTheme.spacing16)
                            .padding(.top, MacTheme.spacing16)
                            .padding(.bottom, MacTheme.spacing12)
                        }

                        // Messages rendered flat with dividers — no per-message card boxing
                        ForEach(Array(detail.messages.enumerated()), id: \.element.id) { index, message in
                            messageView(message, isLast: index == detail.messages.count - 1)
                            if index < detail.messages.count - 1 {
                                Divider()
                                    .opacity(0.2)
                                    .padding(.leading, 56)
                            }
                        }
                    }
                    .padding(.bottom, MacTheme.spacing32)
                }

                replyBar
            }
        }
        .task { await loadThread() }
        .sheet(isPresented: $showCompose, onDismiss: {
            assistantDraftSeed = ""
            composeMode = .reply
        }) {
            if let lastMessage = detail?.messages.last {
                Group {
                    switch composeMode {
                    case .reply:
                        MacEmailComposeView(replyTo: lastMessage, threadId: threadId, body: assistantDraftSeed)
                    case .replyAll:
                        // Pass the signed-in user's addresses so reply-all doesn't
                        // CC the user themselves. Covers both the active mailbox
                        // and any connected accounts/aliases.
                        MacEmailComposeView(
                            replyAllTo: lastMessage,
                            threadId: threadId,
                            body: assistantDraftSeed,
                            ownedAddresses: ownedAddressesForReplyAll()
                        )
                    case .forward:
                        MacEmailComposeView(forwarding: lastMessage)
                    }
                }
                .frame(minWidth: 520, minHeight: 380)
            }
        }
        // Surface assistant action results as a transient toast at the
        // bottom of the thread instead of a modal alert. The reply bar sits
        // at the very bottom — give the toast enough inset to clear it.
        .macToast($assistantToast, bottomInset: 88)
    }

    /// Whether the AI summary card should render at all. Hides for
    /// non-conversational threads (verification codes, receipts, marketing,
    /// automated notifications). Loading and conversational-with-no-signal
    /// states still show the card so the user can see AI worked.
    private var shouldShowAssistantCard: Bool {
        // User locally dismissed it via "Not useful" — respect that for the
        // rest of the session. Re-opening the thread later resets the state.
        if assistantLocallyDismissed { return false }
        // While the assistant context is still loading we don't yet know the
        // thread kind — render the card with its skeleton so the user gets
        // immediate visual feedback rather than a delayed pop-in.
        if isLoadingAssistant { return true }
        guard let thread = assistantThread else { return false }
        return thread.threadKind.isConversational
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: MacTheme.spacing12) {
            Button {
                if let onClose { onClose() } else { dismiss() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Back to inbox")
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 1) {
                Text(detail?.messages.first?.subject ?? "Thread")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                    .lineLimit(1)
                    .textSelection(.enabled)
                    .contextMenu {
                        if let subject = detail?.messages.first?.subject, !subject.isEmpty {
                            Button {
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setString(subject, forType: .string)
                            } label: {
                                Label("Copy subject", systemImage: "doc.on.doc")
                            }
                            .keyboardShortcut("c", modifiers: [.command, .shift])
                        }
                    }
                // Header sender mirrors the inbox row, which is built from the latest
                // message (`detail.latest ?? messages.last`). Using `messages.first`
                // here showed the original sender on long reply chains, mismatching the
                // row the user just clicked.
                if let from = (detail?.latest ?? detail?.messages.last)?.from {
                    Text(from.name)
                        .font(MacTheme.cardSubtitleFont())
                        .foregroundStyle(MacTheme.textSecondary)
                }
            }

            Spacer()

            HStack(spacing: MacTheme.spacing4) {
                Button {
                    Task { await services.emailService.archiveThreads(ids: [threadId]) }
                    if let onClose { onClose() } else { dismiss() }
                } label: {
                    Image(systemName: "archivebox")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Archive")
                .accessibilityLabel("Archive thread")

                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(red: 0.85, green: 0.3, blue: 0.3))
                }
                .buttonStyle(.plain)
                .help("Delete")
                .accessibilityLabel("Delete thread")
                .confirmationDialog(
                    "Delete this thread?",
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        Task { await services.emailService.deleteThreads(ids: [threadId]) }
                        if let onClose { onClose() } else { dismiss() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The thread will be moved to Trash. Use Archive instead for messages you want to keep.")
                }

                // Overflow menu — currently only carries the "Remind me
                // about this…" entry (iOS parity). We render the menu
                // unconditionally so adding more items later doesn't
                // require touching the header layout again.
                Menu {
                    Button {
                        showReminderOptions = true
                    } label: {
                        Label("Remind me about this…", systemImage: "alarm")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MacTheme.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More")
                .accessibilityLabel("More actions")
                // Custom-date popover for the "Pick a date…" preset. Anchored
                // to the overflow menu so it surfaces near the trigger.
                .popover(isPresented: $showReminderDatePicker, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pick a reminder time")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MacTheme.textPrimary)
                        DatePicker(
                            "",
                            selection: $pickedReminderDate,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        HStack {
                            Spacer()
                            Button("Cancel") { showReminderDatePicker = false }
                                .buttonStyle(.plain)
                                .foregroundStyle(MacTheme.textSecondary)
                            Button("Set reminder") {
                                showReminderDatePicker = false
                                let chosen = pickedReminderDate
                                Task { await scheduleReminder(at: chosen) }
                            }
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                    .padding(14)
                    .frame(width: 280)
                }
            }
        }
        .padding(.horizontal, MacTheme.spacing16)
        .padding(.vertical, MacTheme.spacing8)
        // Snooze presets for the "Remind me about this…" entry. Each preset
        // computes a fire date and hands it to
        // `MacNotificationService.scheduleEmailReminder`, which schedules a
        // local notification carrying `userInfo: ["email_thread_id": threadId]`
        // so tap-routing surfaces the thread on launch (iOS parity).
        .confirmationDialog(
            "Remind me about this thread",
            isPresented: $showReminderOptions,
            titleVisibility: .visible
        ) {
            Button("In 1 hour") { handleReminderSelection(preset: .oneHour) }
            Button("In 4 hours") { handleReminderSelection(preset: .fourHours) }
            Button("Tomorrow morning") { handleReminderSelection(preset: .tomorrowMorning) }
            Button("This evening") { handleReminderSelection(preset: .thisEvening) }
            Button("Pick a date…") { handleReminderSelection(preset: .pickDate) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("We'll send you a local notification at the selected time.")
        }
    }

    // MARK: - Action Handlers

    private func refreshAssistant() async {
        isLoadingAssistant = true
        let resolved = await services.emailService.loadAssistant(threadId: threadId)
        assistantThread = resolved
        autoCopyVerificationCodeIfNeeded(resolved)
        isLoadingAssistant = false
    }

    /// One-shot per session: if the thread is verification + has a code +
    /// we haven't already copied it for this thread id, copy it to the
    /// clipboard and toast. Re-opening the same thread later won't re-copy.
    private func autoCopyVerificationCodeIfNeeded(_ context: AssistantThreadContext?) {
        guard let context else { return }
        guard context.threadKind == .verification,
              let code = context.extractedCode,
              !code.isEmpty,
              !services.autoCopiedVerificationThreads.contains(context.threadId)
        else { return }
        let raw = code.replacingOccurrences(of: " ", with: "")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(raw, forType: .string)
        services.autoCopiedVerificationThreads.insert(context.threadId)
        assistantToast = .success("Code copied: \(code)")
    }

    /// Stamp the "just completed" action and schedule it to clear after
    /// `recentCompletionDuration` seconds, so the inline confirmation
    /// auto-reverts. If a fresher action lands during the sleep, the new
    /// completion will overwrite this one and the cleanup becomes a no-op.
    private func markRecentlyCompleted(_ action: ThreadAction) {
        recentlyCompletedAction = action
        let captured = action
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(recentCompletionDuration))
            if recentlyCompletedAction == captured {
                recentlyCompletedAction = nil
            }
        }
    }

    private func handleCreateTask(_ suggestion: MailAssistantSuggestedTask) async {
        inFlightAction = .task
        defer { inFlightAction = nil }
        let success = await services.emailService.createAssistantTask(threadId: threadId, suggestion: suggestion)
        if success {
            // Inline button confirmation replaces the toast — the button
            // morphs to "✓ Task created" right where the user just clicked.
            markRecentlyCompleted(.task)
            await refreshAssistant()
        } else {
            assistantToast = .failure("Could not create the task")
        }
    }

    private func handleCreateEvent() async {
        inFlightAction = .event
        defer { inFlightAction = nil }
        guard let event = assistantThread?.suggestedEvent else {
            assistantToast = .failure("No event suggestion is ready yet")
            return
        }
        let success = await services.emailService.createAssistantEvent(threadId: threadId, suggestion: event)
        if success {
            markRecentlyCompleted(.event)
            await refreshAssistant()
        } else {
            assistantToast = .failure("Could not create the event")
        }
    }

    private func handleDraftReply() async {
        inFlightAction = .draft
        defer { inFlightAction = nil }
        guard let result = await services.emailService.generateAssistantDraft(threadId: threadId) else {
            assistantToast = .failure("Could not generate a reply draft")
            return
        }
        if result.created {
            assistantDraftSeed = result.preview ?? ""
            showCompose = true
            await refreshAssistant()
            // No inline confirmation or toast — the compose sheet opening
            // IS the confirmation.
        } else {
            let reason = result.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            assistantToast = .failure(reason.isEmpty
                ? "Draft already exists or was skipped"
                : reason)
        }
    }

    // The previous `openAssistant()` helper was removed alongside the in-card
    // "Ask AI" / "Research" buttons. The persistent `AssistantButton` FAB in
    // `MacRootView` is the single entry point for opening the AI panel.

    // MARK: - Message View

    private func messageView(_ message: EmailMessage, isLast: Bool) -> some View {
        let isExpanded = expandedMessages.contains(message.id) || isLast
        let msgId = message.id
        let darkMode = emailDarkMessages.contains(msgId)
        let heightBinding = Binding<CGFloat>(
            get: { webViewHeights[msgId] ?? 300 },
            set: { webViewHeights[msgId] = $0 }
        )

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(MacTheme.Motion.fast) {
                    if expandedMessages.contains(message.id) {
                        expandedMessages.remove(message.id)
                    } else {
                        expandedMessages.insert(message.id)
                    }
                }
            } label: {
                HStack(spacing: MacTheme.spacing8) {
                    MacSenderAvatarView(email: message.from.email, name: message.from.name, size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(message.from.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MacTheme.textPrimary)
                        Text(message.date, format: .dateTime.month().day().hour().minute())
                            .font(MacTheme.metaFont())
                            .foregroundStyle(MacTheme.mutedText)
                    }
                    Spacer()
                    if isExpanded {
                        Button {
                            withAnimation(MacTheme.Motion.fast) {
                                if emailDarkMessages.contains(msgId) {
                                    emailDarkMessages.remove(msgId)
                                } else {
                                    emailDarkMessages.insert(msgId)
                                }
                            }
                        } label: {
                            Image(systemName: darkMode ? "sun.max" : "moon")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(MacTheme.mutedText)
                                .symbolEffect(.bounce, value: darkMode)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(darkMode ? "Switch to light render" : "Switch to dark render")
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                }
                .padding(.horizontal, MacTheme.spacing16)
                .padding(.vertical, MacTheme.spacing12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    composeMode = .reply
                    showCompose = true
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }
                .keyboardShortcut("r", modifiers: .command)

                Button {
                    composeMode = .replyAll
                    showCompose = true
                } label: {
                    Label("Reply all", systemImage: "arrowshape.turn.up.left.2")
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button {
                    composeMode = .forward
                    showCompose = true
                } label: {
                    Label("Forward", systemImage: "arrowshape.turn.up.right")
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Divider()

                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(message.from.email, forType: .string)
                } label: {
                    Label("Copy from address", systemImage: "envelope")
                }
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(message.subject, forType: .string)
                } label: {
                    Label("Copy subject", systemImage: "text.quote")
                }
                if let plain = message.plainText, !plain.isEmpty {
                    Button {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(plain, forType: .string)
                    } label: {
                        Label("Copy message text", systemImage: "doc.on.doc")
                    }
                    Button {
                        // Markdown-style quote — pastes ready-to-send into reply
                        // drafts elsewhere (Slack, Notion, another email client).
                        let quoted = plain
                            .split(separator: "\n", omittingEmptySubsequences: false)
                            .map { "> \($0)" }
                            .joined(separator: "\n")
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(quoted, forType: .string)
                    } label: {
                        Label("Copy as quote", systemImage: "quote.bubble")
                    }
                }
            }

            if isExpanded {
                if !message.body.isEmpty {
                    // PassthroughWKWebView forwards scroll events up so the outer SwiftUI
                    // ScrollView handles all scrolling — no nested scroll problem.
                    EmailHTMLView(html: message.body, height: heightBinding, darkMode: darkMode)
                        .frame(height: webViewHeights[msgId] ?? 300)
                        .background {
                            if !darkMode {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white)
                            }
                        }
                        .overlay {
                            if !darkMode {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .animation(MacTheme.Motion.base, value: darkMode)
                        .padding(.horizontal, MacTheme.spacing16)
                        .contextMenu {
                            Button {
                                if emailDarkMessages.contains(msgId) {
                                    emailDarkMessages.remove(msgId)
                                } else {
                                    emailDarkMessages.insert(msgId)
                                }
                            } label: {
                                Label(
                                    darkMode ? "Render in light mode" : "Render in dark mode",
                                    systemImage: darkMode ? "sun.max" : "moon"
                                )
                            }
                        }
                } else if let plainText = message.plainText, !plainText.isEmpty {
                    Text(plainText)
                        .font(.system(size: 13))
                        .foregroundStyle(MacTheme.textPrimary)
                        .padding(.horizontal, MacTheme.spacing16)
                        .padding(.vertical, MacTheme.spacing8)
                        .textSelection(.enabled)
                } else {
                    Text("No content")
                        .font(.system(size: 13))
                        .foregroundStyle(MacTheme.mutedText)
                        .italic()
                        .padding(MacTheme.spacing16)
                }

                // Attachments were decoded but never shown — a user couldn't tell
                // an email had any. Mirrors the iOS chip list (display only;
                // download needs a backend fetch endpoint).
                if let attachments = message.attachments, !attachments.isEmpty {
                    attachmentsView(attachments)
                        .padding(.horizontal, MacTheme.spacing16)
                        .padding(.top, MacTheme.spacing8)
                }
            }
        }
    }

    // MARK: - Attachments

    @ViewBuilder
    private func attachmentsView(_ attachments: [EmailAttachment]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(attachments) { attachment in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(attachmentColor(for: attachment.mimeType))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Text(attachmentLabel(for: attachment.mimeType))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.filename)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(MacTheme.textPrimary)
                            .lineLimit(1)
                            .help(attachment.filename)
                        let sizeLabel = formatAttachmentSize(attachment.size)
                        if !sizeLabel.isEmpty {
                            Text(sizeLabel)
                                .font(.system(size: 11))
                                .foregroundStyle(MacTheme.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                        .stroke(MacTheme.cardBorder, lineWidth: 1)
                )
            }
        }
    }

    private func attachmentColor(for mimeType: String) -> Color {
        if mimeType.contains("pdf") { return .red }
        if mimeType.contains("image") { return .blue }
        if mimeType.contains("word") || mimeType.contains("document") { return Color(red: 0.18, green: 0.44, blue: 0.78) }
        if mimeType.contains("sheet") || mimeType.contains("excel") { return .green }
        return .gray
    }

    private func attachmentLabel(for mimeType: String) -> String {
        if mimeType.contains("pdf") { return "PDF" }
        if mimeType.contains("image") { return "IMG" }
        if mimeType.contains("word") { return "DOC" }
        if mimeType.contains("sheet") || mimeType.contains("excel") { return "XLS" }
        return "FILE"
    }

    private func formatAttachmentSize(_ bytes: Int) -> String {
        if bytes <= 0 { return "" }
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    // MARK: - Reply Bar

    private var replyBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)
            HStack(spacing: MacTheme.spacing8) {
                ForEach(
                    [
                        ("arrowshape.turn.up.left", "Reply", ThreadComposeMode.reply),
                        ("arrowshape.turn.up.left.2", "Reply all", ThreadComposeMode.replyAll),
                        ("arrowshape.turn.up.right", "Forward", ThreadComposeMode.forward),
                    ],
                    id: \.1
                ) { icon, label, mode in
                    Button {
                        composeMode = mode
                        showCompose = true
                    } label: {
                        HStack(spacing: MacTheme.spacing6) {
                            Image(systemName: icon)
                                .font(.system(size: 12, weight: .medium))
                            Text(label)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(MacTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MacTheme.spacing8)
                        .background(MacTheme.accent.opacity(0.08), in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(MacTheme.spacing12)
        }
    }

    // MARK: - Data Loading

    private func loadThread() async {
        // Cache hit → paint instantly, skip the spinner. The async loadThread
        // below still runs and silently refreshes in the background so a stale
        // entry self-heals. Same pattern as the iOS thread view.
        if let cached = services.emailService.cachedThreadDetail(id: threadId), detail == nil {
            detail = cached
            isLoading = false
            errorMessage = nil
            recomputeFallbackChips(from: cached)
        } else if detail == nil {
            isLoading = true
            errorMessage = nil
        }
        isLoadingAssistant = true

        async let threadDetail = services.emailService.loadThread(id: threadId)
        async let assistant = services.emailService.loadAssistant(threadId: threadId)

        // Show the email body as soon as the thread arrives, even if the assistant
        // call is still pending. Previously we waited for both, doubling the perceived
        // load time when the assistant call was the slower of the two.
        let resolved = await threadDetail
        if let resolved {
            detail = resolved
            errorMessage = nil
        } else if detail == nil {
            // Prefer the friendlier message the service already computed
            // (translates auth / 404 / timeout / offline into copy a user can
            // act on) instead of the generic "Could not load thread." fallback.
            errorMessage = services.emailService.errorMessage ?? "Could not load thread."
        }
        isLoading = false

        // Compute client-side fallbacks (verification code / tracking) as
        // soon as the body arrives so they can render before the assistant
        // round-trip completes. The assistant-derived chips, when they
        // arrive, take precedence — see `regexFallbackChips`.
        if let d = detail {
            recomputeFallbackChips(from: d)
        }

        let resolvedAssistant = await assistant
        assistantThread = resolvedAssistant
        autoCopyVerificationCodeIfNeeded(resolvedAssistant)
        isLoadingAssistant = false

        Task { await services.emailService.markAsRead(ids: [threadId]) }
    }

    /// Run the regex-based verification + tracking extractors over the
    /// thread subject and first message body. Auto-copies the verification
    /// code to the pasteboard once per thread (driven by `copiedCodeOnce`).
    private func recomputeFallbackChips(from detail: GetThreadResponse) {
        let subject = detail.messages.first?.subject ?? ""
        let firstMessage = detail.messages.first
        // Prefer plain text — body is HTML and would force the regex to walk
        // through markup. When the backend didn't ship plainText, strip the
        // HTML tags coarsely so we at least operate on something resembling
        // prose.
        let bodyText: String = {
            if let plain = firstMessage?.plainText, !plain.isEmpty { return plain }
            let html = firstMessage?.body ?? ""
            // Very loose tag strip — good enough for keyword + digit hits.
            return html.replacingOccurrences(
                of: "<[^>]+>",
                with: " ",
                options: .regularExpression
            )
        }()

        // Verification code — only set when the assistant didn't already
        // surface one (the assistant path renders a richer chip).
        if assistantThread?.extractedCode?.isEmpty ?? true {
            let code = Self.extractVerificationCode(subject: subject, body: bodyText) ?? ""
            fallbackVerificationCode = code
            if !code.isEmpty && !copiedCodeOnce {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(
                    code.replacingOccurrences(of: " ", with: ""),
                    forType: .string
                )
                copiedCodeOnce = true
                assistantToast = .success("Code copied: \(code)")
            }
        } else {
            fallbackVerificationCode = ""
        }

        // Tracking / order — only set when the assistant didn't surface a
        // receipt. A receipt chip already covers the "vendor · amount · date"
        // case; this fills in shipment + bare order numbers.
        if assistantThread?.extractedReceipt == nil {
            fallbackTrackingInfo = Self.extractTrackingInfo(subject: subject, body: bodyText)
        } else {
            fallbackTrackingInfo = nil
        }
    }

    // The "Latest message" preview was removed — it duplicated content the
    // user could already see in the message list directly below it. Helpers
    // that were exclusive to that preview block (`previewText`) were removed
    // along with it.

    /// Returns true when the thread is classified as spam/junk by the mail provider.
    /// Used to suppress AI assistant suggestions on those threads — historically the
    /// assistant printed "IMPORTANT TO RESPOND TO" on spam, eroding user trust.
    /// (UX assessment QW1.)
    private func isThreadInSpam(_ detail: GetThreadResponse) -> Bool {
        guard let labels = detail.labels else { return false }
        return labels.contains(where: { label in
            let value = (label.id + "|" + label.name).uppercased()
            return value.contains("SPAM") || value.contains("JUNK")
        })
    }

    // MARK: - Regex Fallback Chips

    /// Renders the verification-code or tracking-info chip computed by the
    /// client-side regex extractor. Used when the assistant context didn't
    /// surface one (older backends, partial signals, or assistant still
    /// loading). The visual treatment mirrors the assistant-derived chips
    /// so the user can't tell the two paths apart.
    @ViewBuilder
    private var regexFallbackChips: some View {
        if !fallbackVerificationCode.isEmpty {
            MacVerificationCodeAction(code: fallbackVerificationCode) {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(
                    fallbackVerificationCode.replacingOccurrences(of: " ", with: ""),
                    forType: .string
                )
                assistantToast = .success("Code copied")
            }
            .padding(.horizontal, MacTheme.spacing16)
            .padding(.top, MacTheme.spacing16)
            .padding(.bottom, MacTheme.spacing12)
        } else if let tracking = fallbackTrackingInfo {
            MacTrackingInfoChip(info: tracking)
                .padding(.horizontal, MacTheme.spacing16)
                .padding(.top, MacTheme.spacing16)
                .padding(.bottom, MacTheme.spacing12)
        }
    }

    // MARK: - Smart-Action Toolbar
    //
    // Three always-visible icon buttons (Create task / Create event /
    // Generate reply) rendered below the header. iOS parity affordance —
    // the assistant card already exposes the same actions when AI flags
    // them, but the toolbar gives the user a one-click entry point even
    // before the assistant round-trip finishes. Each handler pipes into
    // the existing assistant mutation paths.
    private func smartActionToolbar(detail: GetThreadResponse) -> some View {
        HStack(spacing: MacTheme.spacing8) {
            MacSmartActionIcon(
                systemImage: "checklist",
                label: "Create task",
                tooltip: "Create a task from this thread",
                isRunning: smartActionInFlight == .createTask,
                isDimmed: smartActionInFlight != nil && smartActionInFlight != .createTask
            ) {
                Task { await runSmartCreateTask(detail: detail) }
            }

            MacSmartActionIcon(
                systemImage: "calendar.badge.plus",
                label: "Create event",
                tooltip: assistantThread?.suggestedEvent?.startAt != nil
                    ? "Add the suggested meeting to your calendar"
                    : "AI hasn't detected an event in this thread yet",
                isRunning: smartActionInFlight == .createEvent,
                isDimmed: smartActionInFlight != nil && smartActionInFlight != .createEvent,
                isDisabled: !canCreateEventNow
            ) {
                Task { await runSmartCreateEvent() }
            }

            MacSmartActionIcon(
                systemImage: "sparkles",
                label: "Generate reply",
                tooltip: "Draft a reply with AI",
                isRunning: smartActionInFlight == .generateReply,
                isDimmed: smartActionInFlight != nil && smartActionInFlight != .generateReply
            ) {
                Task { await runSmartGenerateReply() }
            }

            Spacer(minLength: 0)
        }
    }

    /// We can only create a calendar event when the assistant has supplied
    /// a suggestion with start + end times — the backend mutation requires
    /// both. The icon stays visible but disables itself otherwise so the
    /// toolbar shape never jumps.
    private var canCreateEventNow: Bool {
        guard let event = assistantThread?.suggestedEvent else { return false }
        return event.startAt != nil && event.endAt != nil
    }

    private func runSmartCreateTask(detail: GetThreadResponse) async {
        smartActionInFlight = .createTask
        defer { smartActionInFlight = nil }
        // Prefer the assistant's first suggested task — it carries the
        // richer description / due date. Otherwise synthesise one from the
        // thread subject so the toolbar still works on cold threads.
        let suggestion: MailAssistantSuggestedTask = assistantThread?.suggestedTasks.first
            ?? MailAssistantSuggestedTask(
                title: detail.messages.first?.subject ?? "Email follow-up",
                description: nil,
                priority: "medium",
                dueDate: nil
            )
        let success = await services.emailService.createAssistantTask(
            threadId: threadId,
            suggestion: suggestion
        )
        if success {
            markRecentlyCompleted(.task)
            assistantToast = .success("Task created")
            await refreshAssistant()
        } else {
            assistantToast = .failure("Could not create the task")
        }
    }

    private func runSmartCreateEvent() async {
        smartActionInFlight = .createEvent
        defer { smartActionInFlight = nil }
        guard let event = assistantThread?.suggestedEvent,
              event.startAt != nil, event.endAt != nil else {
            assistantToast = .failure("No event suggestion is ready yet — give AI a moment.")
            return
        }
        let success = await services.emailService.createAssistantEvent(
            threadId: threadId,
            suggestion: event
        )
        if success {
            markRecentlyCompleted(.event)
            assistantToast = .success("Event added")
            await refreshAssistant()
        } else {
            assistantToast = .failure("Could not create the event")
        }
    }

    private func runSmartGenerateReply() async {
        smartActionInFlight = .generateReply
        defer { smartActionInFlight = nil }
        guard let result = await services.emailService.generateAssistantDraft(threadId: threadId) else {
            assistantToast = .failure("Could not generate a reply draft")
            return
        }
        if result.created {
            assistantDraftSeed = result.preview ?? ""
            composeMode = .reply
            showCompose = true
            await refreshAssistant()
        } else {
            let reason = result.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            assistantToast = .failure(reason.isEmpty
                ? "Draft already exists or was skipped"
                : reason)
        }
    }

    // MARK: - Reminder Action
    //
    // Schedules a local notification via `MacNotificationService.scheduleEmailReminder`.
    // The notification carries `userInfo: ["email_thread_id": threadId]` so the
    // tap-routing in `TodusMacApp` opens this thread when the user clicks the alert.

    enum ReminderPreset: Equatable {
        case oneHour
        case fourHours
        case tomorrowMorning
        case thisEvening
        case pickDate
    }

    private func handleReminderSelection(preset: ReminderPreset) {
        // "Pick a date…" defers to the custom DatePicker popover instead of
        // scheduling immediately — the popover's "Set reminder" button is
        // what eventually calls `scheduleReminder(at:)`.
        if preset == .pickDate {
            pickedReminderDate = reminderDate(for: .oneHour)
            showReminderDatePicker = true
            return
        }
        let remindAt = reminderDate(for: preset)
        Task { await scheduleReminder(at: remindAt) }
    }

    /// Hands the chosen fire date to `MacNotificationService` and surfaces a
    /// success / failure toast. Shared by the preset path and the custom
    /// date-picker popover.
    private func scheduleReminder(at chosenDate: Date) async {
        let scheduled = await services.notificationService.scheduleEmailReminder(
            threadId: threadId,
            subject: detail?.messages.first?.subject ?? "Email reminder",
            at: chosenDate
        )
        let formatted = formatReminderTime(chosenDate)
        assistantToast = scheduled
            ? .success("Reminder set for \(formatted)")
            : .failure("Couldn't set reminder — check Notification permissions")
    }

    /// Formats a reminder fire date for toast display. Uses a
    /// `RelativeDateTimeFormatter` when the date is within the next 24 hours
    /// (e.g. "tomorrow at 9:00 AM", "in 4 hours") and falls back to an
    /// abbreviated date + shortened time for anything further out.
    private func formatReminderTime(_ date: Date) -> String {
        let now = Date()
        let interval = date.timeIntervalSince(now)
        if interval > 0 && interval < 24 * 3600 {
            let calendar = Calendar.current
            if calendar.isDateInTomorrow(date) {
                let timeFormatter = DateFormatter()
                timeFormatter.timeStyle = .short
                return "tomorrow at \(timeFormatter.string(from: date))"
            }
            let relative = RelativeDateTimeFormatter()
            relative.unitsStyle = .full
            return relative.localizedString(for: date, relativeTo: now)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func reminderDate(for preset: ReminderPreset) -> Date {
        let now = Date()
        let calendar = Calendar.current
        switch preset {
        case .oneHour:
            return now.addingTimeInterval(3600)
        case .fourHours:
            return now.addingTimeInterval(4 * 3600)
        case .tomorrowMorning:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? now.addingTimeInterval(3600)
        case .thisEvening:
            let tonight = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: now) ?? now.addingTimeInterval(3600)
            if tonight > now { return tonight }
            return calendar.date(byAdding: .day, value: 1, to: tonight) ?? now.addingTimeInterval(3600)
        case .pickDate:
            // Without an inline date picker on this surface we just fall
            // back to "tomorrow morning" so the toast still feels useful.
            // A proper picker will land alongside the real scheduling API.
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? now.addingTimeInterval(3600)
        }
    }

    // MARK: - Regex Extractors
    //
    // Conservative client-side detectors that fire only when there's strong
    // textual evidence. Each one returns nil when nothing matches so the
    // chip stays hidden — false positives on a thread view are far more
    // damaging than missed detections.

    /// Pulls a 4–8 digit verification code out of the subject / body when
    /// it sits near a keyword like "code", "verification", "OTP",
    /// "passcode", or the Swedish "kod". Returns nil otherwise. The first
    /// hit wins — verification mails almost always lead with the code.
    static func extractVerificationCode(subject: String, body: String) -> String? {
        let keywordPattern = #"(?i)(verification|verify|verifiering|verifier|one[- ]?time|otp|passcode|pass code|security code|code|kod|sicherheitscode|c[oó]digo)"#
        let combined = subject + "\n" + body
        guard let keywordRegex = try? NSRegularExpression(pattern: keywordPattern) else {
            return nil
        }
        let nsRange = NSRange(combined.startIndex..., in: combined)
        let keywordHit = keywordRegex.firstMatch(in: combined, range: nsRange)
        guard keywordHit != nil else { return nil }

        // Allow optional thin/regular spaces inside the code (e.g. "178 691").
        // The leading/trailing boundary keeps us from picking up the year out
        // of "Copyright 2026" or 6-digit phone fragments inside addresses.
        let digitPattern = #"(?<![\d\w])(\d{3,4}[\s-]?\d{3,4}|\d{4,8})(?![\d\w])"#
        guard let digitRegex = try? NSRegularExpression(pattern: digitPattern) else {
            return nil
        }
        let matches = digitRegex.matches(in: combined, range: nsRange)
        for match in matches {
            guard let r = Range(match.range, in: combined) else { continue }
            let raw = String(combined[r])
            // Strip every kind of whitespace + hyphens for length validation
            // but keep the originally-spaced form for display.
            let stripped = raw.filter { $0.isNumber }
            guard (4...8).contains(stripped.count) else { continue }
            // Reject leading-zero "phone-number-ish" runs and very common
            // false positives like year numbers (1900–2099).
            if let asInt = Int(stripped), (1900...2099).contains(asInt) { continue }
            return raw
        }
        return nil
    }

    /// Detects a shipment tracking number or an order/confirmation number
    /// in the subject/body. Shipment carriers (UPS / FedEx / USPS) get a
    /// "Track shipment" URL; bare order numbers labeled "Order #" /
    /// "Confirmation" surface a chip without a URL so we don't deep-link
    /// somewhere arbitrary.
    static func extractTrackingInfo(subject: String, body: String) -> TrackingInfo? {
        let combined = subject + "\n" + body

        // UPS — 1Z + 16 alphanumerics
        if let match = firstMatch(pattern: #"(?<![A-Z0-9])(1Z[A-Z0-9]{16})(?![A-Z0-9])"#, in: combined) {
            let url = URL(string: "https://www.ups.com/track?tracknum=\(match)")
            return TrackingInfo(kind: .shipment, number: match, url: url)
        }
        // FedEx — 12 or 15 digit runs (loose; FedEx has many formats).
        // Require the carrier name nearby so we don't grab transaction ids.
        let mentionsFedEx = combined.range(of: "fedex", options: .caseInsensitive) != nil
        if mentionsFedEx,
           let match = firstMatch(pattern: #"(?<![\d])(\d{12}|\d{15})(?![\d])"#, in: combined) {
            let url = URL(string: "https://www.fedex.com/fedextrack/?trknbr=\(match)")
            return TrackingInfo(kind: .shipment, number: match, url: url)
        }
        // USPS — 20+ digit runs are typical; require the carrier name nearby
        // to keep us from grabbing transaction ids.
        let mentionsUSPS = combined.range(of: "usps", options: .caseInsensitive) != nil
            || combined.range(of: "postal service", options: .caseInsensitive) != nil
        if mentionsUSPS,
           let match = firstMatch(pattern: #"(?<![\d])(\d{20,22})(?![\d])"#, in: combined) {
            let url = URL(string: "https://tools.usps.com/go/TrackConfirmAction?tLabels=\(match)")
            return TrackingInfo(kind: .shipment, number: match, url: url)
        }
        // Generic "Order #ABC-1234" / "Confirmation: 1234"
        let orderPattern = #"(?i)(?:order|confirmation|booking|reservation|reference)[^\n]{0,6}(?:#|number|no\.?|:)?\s*([A-Z0-9][A-Z0-9\-]{4,18})"#
        if let captured = firstCapture(pattern: orderPattern, in: combined) {
            return TrackingInfo(kind: .order, number: captured, url: nil)
        }
        return nil
    }

    /// Returns the first full match (not capture) of `pattern` against
    /// `text`, or nil when nothing matches.
    private static func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, range: nsRange),
              let r = Range(m.range, in: text) else { return nil }
        return String(text[r])
    }

    /// Returns the first capture group (#1) of the first match of
    /// `pattern` against `text`, or nil. Used for patterns like
    /// "Order #(\d+)" where we want the bare number.
    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, range: nsRange),
              m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    /// Builds the set of "this is me" addresses used to filter the user out of
    /// reply-all Cc lists. Covers the primary signed-in account plus every
    /// connected mailbox the user has authorized — multi-account users who
    /// reply-all to a thread where one of their other accounts is on Cc no
    /// longer end up CC'ing themselves.
    /// (Relocated here from MacMailAssistantCard — it uses `services` and is
    /// called from this view, but was placed in a struct with no `services`.)
    private func ownedAddressesForReplyAll() -> Set<String> {
        var owned = Set<String>()
        if let primary = services.authService.userEmail?.lowercased(), !primary.isEmpty {
            owned.insert(primary)
        }
        for connection in services.connectionsService.connections {
            let lowered = connection.email.lowercased()
            if !lowered.isEmpty { owned.insert(lowered) }
        }
        return owned
    }

}

// MARK: - Assistant Card

/// Redesigned assistant card — leads with actionable suggestions and a clear summary.
/// Hides technical internals (raw confidence %, risk level) in favor of plain-language context.
private struct MacMailAssistantCard: View {
    /// nil while loading — card shows a loading state
    let assistant: AssistantThreadContext?
    let isLoading: Bool
    /// When the thread is classified as spam/junk by the provider, the card
    /// hides the recommendation label and disables suggestion buttons. The AI
    /// still computed a verdict, but acting on spam was the single biggest
    /// trust-eroding bug. (UX assessment QW1.)
    let isSpam: Bool
    /// Currently in-flight assistant action — drives per-button loading and
    /// dimming. `nil` means no action is running.
    let inFlightAction: MacEmailThreadView.ThreadAction?
    /// Action that just completed — drives the inline "✓ Created" affordance
    /// inside the matching button. Auto-clears after a few seconds.
    let recentlyCompletedAction: MacEmailThreadView.ThreadAction?
    let onRefresh: () async -> Void
    let onCreateTask: (MailAssistantSuggestedTask) async -> Void
    let onCreateEvent: () async -> Void
    let onDraftReply: () async -> Void
    /// Local dismissal handler — when the user signals "this isn't useful"
    /// we collapse the card for the rest of the session. The trust loop
    /// closes immediately, even before a backend feedback channel exists.
    /// (UX assessment S3.)
    let onDismiss: () -> Void
    @State private var shimmerPhase = false

    /// True when an action is in flight and it isn't `kind`. We use this to
    /// disable other buttons while one is busy so the user can't fire two
    /// mutations at once and get conflicting toasts.
    private func isOtherActionRunning(than kind: MacEmailThreadView.ThreadAction?) -> Bool {
        guard let inFlightAction else { return false }
        return inFlightAction != kind
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.accent)
                    Text("AI Analysis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MacTheme.textSecondary)
                }
                Spacer()
                // Quick "this isn't useful" — collapses the card for the
                // session. Different from refresh: refresh assumes the AI
                // can do better; dismiss assumes the AI shouldn't have shown
                // up at all on this thread.
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MacTheme.mutedText)
                }
                .buttonStyle(.plain)
                .help("Not useful — hide for this thread")

                Button {
                    Task { await onRefresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                }
                .buttonStyle(.plain)
                .help("Re-analyze this thread")
            }

            if isLoading {
                // Loading skeleton
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(MacTheme.surfaceHover.opacity(shimmerPhase ? 0.55 : 1))
                        .frame(height: 12)
                        .frame(maxWidth: .infinity)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(MacTheme.surfaceHover.opacity(shimmerPhase ? 0.55 : 1))
                        .frame(height: 12)
                        .frame(maxWidth: 200)
                }
                .onAppear { shimmerPhase = true }
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: shimmerPhase)
            } else if isSpam {
                spamContent
            } else if let assistant {
                assistantContent(assistant)
            } else {
                // Honest empty state — nothing actionable here. Previously the card
                // said "Analysis not available", which read like a broken feature.
                // (UX assessment QW9.)
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                    Text("Nothing to act on here — looks like an FYI.")
                        .font(MacTheme.cardSubtitleFont())
                        .foregroundStyle(MacTheme.mutedText)
                }
            }
        }
        .padding(MacTheme.spacing12)
        .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(MacTheme.cardBorder.opacity(0.7), lineWidth: 0.6)
        )
    }

    /// Spam-gate content. Shown instead of recommendations whenever the thread
    /// is classified as spam/junk — the assistant won't goad the user into
    /// "responding to important spam".
    @ViewBuilder
    private var spamContent: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.85, green: 0.45, blue: 0.20))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("This looks like spam")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Text("AI suggestions are disabled for this thread. Move it back to your inbox if it was misclassified.")
                    .font(MacTheme.cardSubtitleFont())
                    .foregroundStyle(MacTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func assistantContent(_ assistant: AssistantThreadContext) -> some View {
        // We deliberately collapsed five sections (recommendation label,
        // contextual suggestions, summary, action items, person, change feed)
        // into one focused block: a single "what to do" line + optional
        // change-feed footnote + the action button. The user is reading the
        // thread itself for the rest of the context — anything more here is
        // noise.

        // Prefer the backend-computed `aiLeadLine` (meeting time / first
        // question / first action item). Falls back to client-side
        // contextual suggestions, then to summary, for older backends.
        let suggestions = contextualSuggestions(assistant)
        let leadLine: String? = !assistant.aiLeadLine.isEmpty
            ? assistant.aiLeadLine
            : (suggestions.first ?? (assistant.summary.isEmpty ? nil : assistant.summary))

        if let leadLine {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacTheme.accent)
                    .padding(.top, 2)
                Text(leadLine)
                    .font(.system(size: 13))
                    .foregroundStyle(MacTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        // Single change-feed line — the most useful update since last open.
        // We drop the rest because the user is already on the thread and can
        // scroll to see what's new.
        if let change = assistant.changedSinceLastOpen.first {
            Text(change)
                .font(MacTheme.cardSubtitleFont())
                .foregroundStyle(MacTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        // SECTION 5: Action buttons.
        //
        // One primary CTA chosen from the highest-confidence signal, with the
        // rest folded behind a "More" menu. "Ask AI" / "Research" entries were
        // removed — the persistent `AssistantButton` FAB in `MacRootView` is
        // the single entry point for opening the AI panel. The button row
        // hides entirely when no action qualifies (i.e. `primaryAction` would
        // have been the old "Ask AI" fallback).
        if let primary = primaryAction(for: assistant) {
            HStack(spacing: MacTheme.spacing6) {
                let confirmed = recentlyConfirmedLabel(for: primary.kind)
                Button {
                    primary.run()
                } label: {
                    HStack(spacing: 6) {
                        if isPrimaryRunning(primary.kind) {
                            ProgressView().controlSize(.mini)
                        } else if let confirmed {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.green)
                            Text(confirmed)
                        } else {
                            Text(primary.label)
                        }
                    }
                }
                .buttonStyle(MacAssistantActionButtonStyle(isPrimary: confirmed == nil))
                .disabled(inFlightAction != nil || confirmed != nil)
                .opacity(isOtherActionRunning(than: actionFor(primary.kind)) ? 0.55 : 1)
                .animation(MacTheme.Motion.fast, value: confirmed)
                .help(primary.help)

                // Only render the "More" menu when at least one secondary
                // option is available — otherwise it's an empty menu that
                // looks broken.
                if hasSecondaryActions(assistant: assistant, primaryKind: primary.kind) {
                    Menu("More") {
                        let hasTask = !assistant.suggestedTasks.isEmpty
                        if primary.kind != .extractTask, hasTask {
                            Button("Extract task") {
                                if let firstTask = assistant.suggestedTasks.first {
                                    Task { await onCreateTask(firstTask) }
                                }
                            }
                            .disabled(inFlightAction != nil)
                        }

                        let hasEvent = assistant.suggestedEvent?.startAt != nil && assistant.suggestedEvent?.endAt != nil
                        if primary.kind != .createEvent, hasEvent {
                            Button("Create event") {
                                Task { await onCreateEvent() }
                            }
                            .disabled(inFlightAction != nil)
                        }

                        let canDraft = assistant.replyNeeded
                            || assistant.existingDraft
                            || assistant.preparedActions.contains(where: { $0.type == "draft_reply" })
                        if primary.kind != .draftReply, canDraft {
                            Button(assistant.existingDraft ? "Review draft" : "Draft reply") {
                                Task { await onDraftReply() }
                            }
                            .disabled(inFlightAction != nil)
                        }
                    }
                    .menuStyle(.button)
                    .buttonStyle(MacAssistantActionButtonStyle())
                    .disabled(inFlightAction != nil)
                    .opacity(inFlightAction != nil ? 0.55 : 1)
                }
            }
            .font(.system(size: 11, weight: .semibold))
        }
    }

    /// Whether the primary CTA matches the in-flight action — drives the
    /// inline spinner inside the primary button.
    private func isPrimaryRunning(_ kind: PrimaryAction.Kind) -> Bool {
        guard let inFlightAction else { return false }
        return actionFor(kind) == inFlightAction
    }

    /// Inline confirmation label for the primary action when its corresponding
    /// `ThreadAction` recently completed. Returns nil when nothing recently
    /// completed or the kind doesn't match.
    private func recentlyConfirmedLabel(for kind: PrimaryAction.Kind) -> String? {
        guard let recently = recentlyCompletedAction,
              actionFor(kind) == recently
        else { return nil }
        switch kind {
        case .extractTask: return "Task created"
        case .createEvent: return "Event added"
        case .draftReply: return nil // draft path opens compose sheet, no inline confirm
        }
    }

    private func actionFor(_ kind: PrimaryAction.Kind) -> MacEmailThreadView.ThreadAction? {
        switch kind {
        case .extractTask: return .task
        case .createEvent: return .event
        case .draftReply: return .draft
        }
    }

    private func hasSecondaryActions(
        assistant: AssistantThreadContext,
        primaryKind: PrimaryAction.Kind
    ) -> Bool {
        let hasTask = !assistant.suggestedTasks.isEmpty && primaryKind != .extractTask
        let hasEvent =
            assistant.suggestedEvent?.startAt != nil
            && assistant.suggestedEvent?.endAt != nil
            && primaryKind != .createEvent
        let canDraft =
            (assistant.replyNeeded
                || assistant.existingDraft
                || assistant.preparedActions.contains(where: { $0.type == "draft_reply" }))
            && primaryKind != .draftReply
        return hasTask || hasEvent || canDraft
    }

    /// Picks the single highest-confidence CTA for the email. Returns `nil`
    /// when no actionable signal applies — the previous "Ask AI" fallback was
    /// removed (the global FAB covers that), so we'd rather hide the action
    /// row entirely than show a button that doesn't help.
    fileprivate struct PrimaryAction {
        enum Kind { case extractTask, createEvent, draftReply }
        let kind: Kind
        let label: String
        let help: String
        let run: () -> Void
    }

    fileprivate func primaryAction(for a: AssistantThreadContext) -> PrimaryAction? {
        // Order matters: meetings are time-sensitive, so they win when both
        // a task and a meeting are detected. Replies come next, then tasks.
        if let event = a.suggestedEvent, event.startAt != nil, event.endAt != nil {
            return PrimaryAction(
                kind: .createEvent,
                label: "Create event",
                help: "Add \"\(event.title.isEmpty ? "this meeting" : event.title)\" to your calendar",
                run: { Task { await onCreateEvent() } }
            )
        }

        if a.replyNeeded || a.existingDraft || a.preparedActions.contains(where: { $0.type == "draft_reply" }) {
            return PrimaryAction(
                kind: .draftReply,
                label: a.existingDraft ? "Review draft" : "Draft reply",
                help: a.existingDraft ? "Review the AI-drafted reply" : "Generate a reply draft with AI",
                run: { Task { await onDraftReply() } }
            )
        }

        if let firstTask = a.suggestedTasks.first {
            return PrimaryAction(
                kind: .extractTask,
                label: "Extract task",
                help: "Create a task: \(firstTask.title)",
                run: { Task { await onCreateTask(firstTask) } }
            )
        }

        return nil
    }

    /// Generates plain-language, actionable suggestions based on the assistant flags.
    /// This is what the user actually cares about — not raw confidence numbers.
    private func contextualSuggestions(_ a: AssistantThreadContext) -> [String] {
        var suggestions: [String] = []

        if a.meetingRequested {
            if let event = a.suggestedEvent {
                suggestions.append("This looks like a meeting request\(event.title.isEmpty ? "" : " for \"\(event.title)\"")\(event.startAt != nil ? " — create a calendar event to confirm." : ".")")
            } else {
                suggestions.append("This email contains a meeting request. Review and add it to your calendar.")
            }
        }

        if a.replyNeeded {
            if a.preparedActions.contains(where: { $0.type == "draft_reply" }) {
                suggestions.append("A reply is expected — tap \"Draft reply\" to have AI write one for you.")
            } else {
                suggestions.append("This email may need a reply from you.")
            }
        }

        if a.followUpNeeded && !a.replyNeeded {
            suggestions.append("This conversation may need a follow-up soon.")
        }

        if !a.suggestedTasks.isEmpty && !a.replyNeeded && !a.meetingRequested {
            let taskTitle = a.suggestedTasks.first?.title ?? "a task"
            suggestions.append("There's a to-do here — tap \"Extract task\" to add \"\(taskTitle)\" to your tasks.")
        }

        return suggestions
    }

}

private struct MacAssistantPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(MacTheme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(MacTheme.surfaceHover.opacity(0.9), in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(MacTheme.cardBorder.opacity(0.8), lineWidth: 0.6))
    }
}

private struct MacAssistantActionButtonStyle: ButtonStyle {
    var isPrimary: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isPrimary ? MacTheme.contentBackground : MacTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .interactiveHitTarget(expansion: 6)
            .pointerStyle(.link)
            .background(
                RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous)
                    .fill(
                        isPrimary
                            ? MacTheme.textPrimary.opacity(configuration.isPressed ? 0.8 : 0.92)
                            : MacTheme.surfaceHover.opacity(configuration.isPressed ? 0.95 : 0.75)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous)
                    .stroke(isPrimary ? Color.clear : MacTheme.cardBorder.opacity(0.8), lineWidth: 0.6)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

// MARK: - HTML Email View

/// Renders HTML email content using WKWebView.
/// Uses PassthroughWKWebView which forwards scroll wheel events to its parent so that
/// the containing SwiftUI ScrollView handles all scrolling — no nested-scroll problem.
/// Reports content height via `height` binding so the parent can size the frame correctly.
struct EmailHTMLView: NSViewRepresentable {
    let html: String
    @Binding var height: CGFloat
    let darkMode: Bool

    func makeNSView(context: Context) -> PassthroughWKWebView {
        let webView = PassthroughWKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        // Transparent background so the SwiftUI theme shows through
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: PassthroughWKWebView, context: Context) {
        // Only reload when HTML content or dark-mode flag actually changes — prevents
        // infinite loop: height state update → updateNSView → reload → new height → repeat.
        guard
            context.coordinator.lastHTML != html
                || context.coordinator.lastDarkMode != darkMode
        else { return }
        context.coordinator.lastHTML = html
        context.coordinator.lastDarkMode = darkMode
        context.coordinator.onHeightUpdate = { newHeight in
            guard newHeight > 0 else { return }
            DispatchQueue.main.async {
                self.height = newHeight
            }
        }

        // Strict CSP blocks inline scripts, event handlers, and arbitrary network requests.
        // Mirrors iOS EmailThreadView CSP. Required to neutralize sender-controlled HTML.
        let wrapped = darkMode ? darkWrappedHTML : lightWrappedHTML
        webView.loadHTMLString(wrapped, baseURL: nil)
    }

    /// Default: render email in light color-scheme so sender's own colors render
    /// correctly. SwiftUI parent draws a white card around the WebView.
    private var lightWrappedHTML: String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="only light">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src * data: blob:; font-src * data:; media-src * data: blob:; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none';">
        <style>
          :root { color-scheme: only light; }
          * { box-sizing: border-box; }
          * { -webkit-user-select: text !important; user-select: text !important; }
          html, body { margin: 0; padding: 0; overflow-x: hidden; overflow-y: hidden; }
          body {
            font-family: -apple-system, system-ui, sans-serif;
            font-size: 13px; line-height: 1.5;
            color: #1a1a1a; background: #ffffff;
            word-wrap: break-word; overflow-wrap: break-word;
            cursor: text;
            padding: 12px 14px;
          }
          a { color: #1a73e8; }
          img { max-width: 100% !important; height: auto !important; }
          pre, code { overflow-x: auto; max-width: 100%; white-space: pre-wrap; font-size: 12px; }
          blockquote { border-left: 2px solid #ddd; margin: 8px 0; padding-left: 12px; color: #666; }
          table { max-width: 100%; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
    }

    /// Opt-in dark render. Strips backgrounds, forces a uniform light text color,
    /// keeps link/blockquote contrast.
    private var darkWrappedHTML: String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="only dark">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src * data: blob:; font-src * data:; media-src * data: blob:; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none';">
        <style>
          :root { color-scheme: only dark; }
          * { box-sizing: border-box; }
          * { -webkit-user-select: text !important; user-select: text !important; }
          html, body { margin: 0; padding: 0; overflow-x: hidden; overflow-y: hidden; }
          body {
            font-family: -apple-system, system-ui, sans-serif;
            font-size: 13px; line-height: 1.5;
            color: #e0e0e0; background: transparent;
            word-wrap: break-word; overflow-wrap: break-word;
            cursor: text;
          }
          * { background-color: transparent !important; background-image: none !important; }
          body, body *:not(a):not(img):not(svg):not(picture):not(video):not(button) {
            color: #e0e0e0 !important;
          }
          a { color: #5B9FFF !important; }
          img { max-width: 100% !important; height: auto !important; }
          pre, code { overflow-x: auto; max-width: 100%; white-space: pre-wrap; font-size: 12px; }
          blockquote { border-left: 2px solid #555 !important; margin: 8px 0; padding-left: 12px; color: #aaa !important; }
          table { max-width: 100%; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?
        var lastDarkMode: Bool?
        var onHeightUpdate: ((CGFloat) -> Void)?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { result, _ in
                if let h = result as? CGFloat { self.onHeightUpdate?(h) }
                else if let h = result as? Int { self.onHeightUpdate?(CGFloat(h)) }
                else if let h = result as? Double { self.onHeightUpdate?(CGFloat(h)) }
                else if let n = result as? NSNumber { self.onHeightUpdate?(CGFloat(truncating: n)) }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                return .cancel
            }
            return .allow
        }
    }
}

// MARK: - Smart Action Chips
//
// Rendered above the messages on non-conversational threads, in place of the
// AI Analysis card. Each one focuses on the single most useful affordance for
// that kind of email.

/// Big, monospaced verification code presented as a one-tap copy button.
/// Designed to be the first thing the user's eyes hit on a verification
/// email so they don't have to scan the body for the digits.
private struct MacVerificationCodeAction: View {
    let code: String
    let onCopy: () -> Void

    @State private var didCopy = false

    var body: some View {
        Button {
            onCopy()
            didCopy = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                didCopy = false
            }
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("VERIFICATION CODE")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.7)
                        .foregroundStyle(MacTheme.mutedText)
                    Text(code)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(MacTheme.textPrimary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                    Text(didCopy ? "Copied" : "Copy")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(MacTheme.contentBackground)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous)
                        .fill(MacTheme.textPrimary.opacity(0.92))
                )
            }
            .padding(MacTheme.spacing12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                MacTheme.surfaceCard,
                in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help("Copy verification code")
        .accessibilityLabel("Copy verification code \(code)")
    }
}

/// Compact "vendor · amount · date" chip for receipt-style emails, with a
/// `Forward` button for sending the receipt to a bookkeeper or expense
/// tracker without leaving the thread.
private struct MacReceiptInfoChip: View {
    let receipt: AssistantThreadContext.ExtractedReceipt
    let onForward: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "receipt")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MacTheme.mutedText)
                .frame(width: 26, height: 26)
                .background(MacTheme.surfaceHover, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(receipt.vendor)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let amount = receipt.amount, !amount.isEmpty {
                        Text(amount)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                    if receipt.amount != nil, formattedDate != nil {
                        Text("·")
                            .font(.system(size: 12))
                            .foregroundStyle(MacTheme.mutedText)
                    }
                    if let date = formattedDate {
                        Text(date)
                            .font(.system(size: 12))
                            .foregroundStyle(MacTheme.mutedText)
                    }
                }
            }
            Spacer(minLength: 0)
            Button(action: onForward) {
                HStack(spacing: 5) {
                    Image(systemName: "arrowshape.turn.up.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Forward")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .buttonStyle(MacAssistantActionButtonStyle())
            .pointerStyle(.link)
            .help("Forward this receipt")
        }
        .padding(.horizontal, MacTheme.spacing12)
        .padding(.vertical, 9)
        .background(
            MacTheme.surfaceCard,
            in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.6)
        )
    }

    private var formattedDate: String? {
        guard
            let raw = receipt.receivedAt,
            let date = ISO8601DateFormatter().date(from: raw)
        else { return nil }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}

// MARK: - Smart Action Toolbar Icon

/// Compact icon button used by the smart-action toolbar (Create task /
/// Create event / Generate reply). Mirrors `MacAssistantActionButtonStyle`
/// visually so the toolbar feels native to the rest of the assistant
/// surfaces. Shows a spinner when `isRunning`, dims when `isDimmed`, and
/// gates touch when `isDisabled`.
private struct MacSmartActionIcon: View {
    let systemImage: String
    let label: String
    let tooltip: String
    let isRunning: Bool
    let isDimmed: Bool
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isRunning {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(MacTheme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous)
                    .fill(MacTheme.surfaceHover.opacity(0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder.opacity(0.8), lineWidth: 0.6)
            )
            .opacity(isDisabled ? 0.45 : (isDimmed ? 0.55 : 1.0))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .disabled(isDisabled || isRunning)
        .help(tooltip)
        .accessibilityLabel(label)
    }
}

// MARK: - Tracking / Order Chip

/// Receipt-style chip rendered for client-side tracking / order matches.
/// Shows the detected number and — for shipment carriers we recognise —
/// a "Track shipment" button that opens the carrier's tracking page.
/// Order-only matches surface a "View order" affordance only when we have
/// a URL; without one we just display the number so the user can copy it
/// rather than be pushed to a guess URL.
private struct MacTrackingInfoChip: View {
    let info: MacEmailThreadView.TrackingInfo

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MacTheme.mutedText)
                .frame(width: 26, height: 26)
                .background(MacTheme.surfaceHover, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(headerLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                    .lineLimit(1)
                Text(info.number)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(MacTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            if let url = info.url {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10, weight: .semibold))
                        Text(actionLabel)
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .buttonStyle(MacAssistantActionButtonStyle())
                .pointerStyle(.link)
                .help(actionLabel)
            } else {
                // Copy fallback — without a URL the best we can do is hand
                // the number to the clipboard so the user can paste it into
                // the merchant's tracker themselves.
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(info.number, forType: .string)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Copy")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .buttonStyle(MacAssistantActionButtonStyle())
                .pointerStyle(.link)
                .help("Copy \(info.number)")
            }
        }
        .padding(.horizontal, MacTheme.spacing12)
        .padding(.vertical, 9)
        .background(
            MacTheme.surfaceCard,
            in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.6)
        )
    }

    private var iconName: String {
        switch info.kind {
        case .shipment: return "shippingbox"
        case .order:    return "bag"
        }
    }

    private var headerLabel: String {
        switch info.kind {
        case .shipment: return "Shipment tracking"
        case .order:    return "Order reference"
        }
    }

    private var actionLabel: String {
        switch info.kind {
        case .shipment: return "Track shipment"
        case .order:    return "View order"
        }
    }
}

// MARK: - Passthrough WKWebView

/// WKWebView subclass that forwards scroll wheel events to its next responder instead of
/// consuming them internally. This lets the containing SwiftUI ScrollView handle all
/// scrolling so there's no nested-scroll issue when viewing emails.
class PassthroughWKWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        // Pass the event up the responder chain to the parent SwiftUI ScrollView
        nextResponder?.scrollWheel(with: event)
    }
}
