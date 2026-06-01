import SwiftUI
import WebKit

// MARK: - Scroll Offset Tracking

private struct ScrollOffsetKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    nonisolated static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - EmailThreadView

/// Full email thread — redesigned with:
///   - Scrim header (transparent → gradient on scroll) with grouped glass action icons
///   - Scroll-aware centered title (body text size)
///   - AI summary (max 3 lines) + contextual action buttons based on AI flags
///   - Flat message rows with collapsible details
///   - Free-floating reply bar with bottom scrim gradient
///   - Custom tab bar hidden via AppServices.hideTabBar
struct EmailThreadView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let threadId: String

    @State private var detail: EmailThreadDetail?
    @State private var isLoading = true
    @State private var showCompose = false
    @State private var composeMode: ComposeMode = .reply
    @State private var isStarred = false
    @State private var assistantThread: AssistantThreadContext? = nil
    @State private var isLoadingAssistant = true
    @State private var assistantDraftSeed: String? = nil
    @State private var showDeleteConfirmation = false
    /// Visible transient toast for assistant action results (success or failure).
    /// Replaces the previous modal alert, which was disruptive and easy to miss.
    @State private var assistantToast: ToastMessage?
    /// Tracks which assistant action is currently in flight so the matching button
    /// can show a spinner and stay disabled. Only one action runs at a time.
    @State private var inFlightAction: ThreadAction?
    /// The action that just succeeded — drives the inline "✓ Created" affordance
    /// inside the button. Auto-clears after `recentCompletionDuration` seconds
    /// so the button reverts to its normal label.
    @State private var recentlyCompletedAction: ThreadAction?
    @State private var isSummarizing = false
    /// Global email dark mode toggle — applies to all messages in the thread.
    /// Moved from per-message state so it can be controlled from the header menu.
    @State private var emailDarkMode = false
    /// Guards top-bar archive + mark-as-unread from double-tap while async op is in flight.
    @State private var isTopBarBusy = false
    /// Guards star toggle from double-tap while mutation is pending.
    @State private var isStarBusy = false

    /// How long the inline "Created" confirmation persists inside an action
    /// button before reverting to its normal label.
    private let recentCompletionDuration: Double = 3

    /// Identifies the assistant action currently being executed. Used to gate
    /// per-button loading state and inline confirmation in `actionButtonsRow`.
    private enum ThreadAction: Equatable {
        case task
        case draft
        case followUp
        case event
    }
    /// Scroll offset drives the scroll-aware header title
    @State private var scrollOffset: CGFloat = 0
    @State private var showLabelEditor = false
    @State private var showReminderOptions = false
    @State private var reminderNotice: String?
    /// True when the most recent reminder action failed — drives the alert
    /// title so a "Turn on notifications" message doesn't appear under a
    /// "Reminder Set" header. Reset alongside `reminderNotice`.
    @State private var reminderNoticeIsFailure: Bool = false
    /// Shown when a destructive thread action fails (delete, etc.).
    /// Surfacing the error keeps the user on the thread view so they can retry.
    @State private var actionErrorMessage: String?
    /// Tracks whether AI summary load attempted but failed (no thread, not loading).
    /// Used to render a "Summary unavailable" error state with retry.
    @State private var assistantLoadFailed = false
    /// Monotonic counter incremented on every top-bar action tap (archive,
    /// markAsUnread, delete, etc.) so the `.sensoryFeedback(.impact)` modifier
    /// on the bar fires a light haptic each time. Using a tick instead of a
    /// boolean avoids the "stuck true" pattern where consecutive taps don't
    /// re-trigger the feedback.
    @State private var topBarActionTick: Int = 0

    private var emailService: EmailService { services.emailService }

    /// Subject shown in collapsed header when user has scrolled past the title row
    private var subjectForHeader: String {
        detail?.messages.first?.subject ?? ""
    }
    private var showTitleInHeader: Bool { scrollOffset > 90 }


    enum ComposeMode { case reply, replyAll, forward }

    /// Compose sheet content — extracted out of `body` so the SwiftUI type
    /// checker doesn't blow up on the combined `.sheet` + switch statement.
    @ViewBuilder
    private var composeSheet: some View {
        if let lastMessage = detail?.messages.last {
            composeSheetView(for: lastMessage)
                .preferredColorScheme(services.appearancePreference.colorScheme)
        }
    }

    @ViewBuilder
    private func composeSheetView(for lastMessage: EmailMessage) -> some View {
        switch composeMode {
        case .reply:
            EmailComposeView(replyTo: lastMessage, threadId: threadId, body: assistantDraftSeed)
        case .replyAll:
            EmailComposeView(
                replyTo: lastMessage,
                threadId: threadId,
                body: assistantDraftSeed,
                replyAll: true,
                ownedAddresses: ownedReplyAddresses()
            )
        case .forward:
            // Forward path — pre-fill subject + body so the user only has to
            // type a recipient. Used by the receipt chip's "Forward" action
            // and any "Forward" button in the reply bar.
            EmailComposeView(
                subject: forwardSubject(for: lastMessage),
                body: lastMessage.plainText ?? ""
            )
        }
    }

    private func forwardSubject(for message: EmailMessage) -> String {
        message.subject.lowercased().hasPrefix("fwd:")
            ? message.subject
            : "Fwd: \(message.subject)"
    }

    /// Lowercased set of email addresses owned by the signed-in user across
    /// all connected accounts. Used to strip the user from a reply-all CC list
    /// so they don't accidentally CC themselves.
    private func ownedReplyAddresses() -> Set<String> {
        var addresses = Set(services.connectionsService.connections.map { $0.email.lowercased() })
        if let me = services.authService.userEmail?.lowercased(), !me.isEmpty {
            addresses.insert(me)
        }
        return addresses
    }

    // AI gradient matching the tab bar sparkles icon
    private var aiGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0x00/255, green: 0xAA/255, blue: 0xF5/255), // #00AAF5
                Color(red: 0xEF/255, green: 0x00/255, blue: 0xC2/255), // #EF00C2
                Color(red: 0xFF/255, green: 0x00/255, blue: 0x38/255), // #FF0038
                Color(red: 0xF9/255, green: 0x9F/255, blue: 0x00/255), // #F99F00
            ],
            startPoint: UnitPoint(x: 0.3, y: 0),
            endPoint: UnitPoint(x: 0.7, y: 1)
        )
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundTop.ignoresSafeArea()

            if isLoading {
                ProgressView("Loading…").controlSize(.small).tint(.secondary)
            } else if let detail, !detail.messages.isEmpty {
                mainContent(detail)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(AppTheme.mutedText)
                    Text("Could not load thread")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.subtleText)
                    Button("Try Again") {
                        isLoading = true
                        Task { await loadThread() }
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 4)
                }
            }
        }
        // UI testing hook — lets XCUITests assert that a notification tap
        // routed to the correct thread by querying `email.thread.<threadId>`.
        .accessibilityIdentifier("email.thread.\(threadId)")
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .background { SwipeBackEnabler() }
        .onAppear {
            // Keep the global AI FAB visible on the thread page so the user always
            // has a way to ask AI about the current message. Pre-seed the chat
            // context here (instead of in `openAssistant()`) so a FAB tap from
            // anywhere in the thread already knows which thread the user is on.
            services.hideTabBar = false
            services.aiChatService.currentPageContext =
                "Email thread: \(detail?.messages.first?.subject ?? "Message")"
            services.aiChatService.currentThreadSubject = detail?.messages.first?.subject
            services.aiChatService.currentThreadId = threadId
        }
        .onDisappear {
            // Clear thread context so the next AI-sheet open from a non-thread
            // tab doesn't leak the previous subject into the context pill.
            services.aiChatService.currentThreadSubject = nil
            services.aiChatService.currentThreadId = nil
        }
        .onChange(of: detail?.messages.first?.subject) { _, newSubject in
            // Subject becomes available after the thread loads — refresh the
            // context pill once we know what to call this thread.
            if let newSubject {
                services.aiChatService.currentPageContext = "Email thread: \(newSubject)"
                services.aiChatService.currentThreadSubject = newSubject
            }
        }
        .task { await loadThread() }
        .sheet(isPresented: $showCompose, onDismiss: {
            // Drop the AI-generated reply seed when the compose sheet closes so
            // the next Reply / Reply-All in this thread doesn't silently
            // reuse a stale assistant draft as the starting body. Symptom
            // before this clear: user runs "Draft reply" → AI generates →
            // user edits and sends → second Reply on the same open thread
            // session shows the previously-sent AI text again.
            assistantDraftSeed = nil
        }) { composeSheet }
        .sheet(isPresented: $showLabelEditor) {
            EditLabelsSheet(
                threadId: threadId,
                appliedLabels: detail?.labels ?? [],
                onChange: { Task { await loadThread() } }
            )
            .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        // Surface assistant action results as a transient toast above the reply
        // bar instead of a modal alert. The reply bar floats roughly 80pt off
        // the bottom — give the toast enough inset to clear it.
        .toast($assistantToast, bottomInset: 96)
        .alert(reminderNoticeIsFailure ? "Couldn't set reminder" : "Reminder Set", isPresented: Binding(
            get: { reminderNotice != nil },
            set: { if !$0 { reminderNotice = nil; reminderNoticeIsFailure = false } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(reminderNotice ?? "") }
        // Surface delete/archive/mark-unread failures inline so the user knows
        // nothing happened — previously the API failure was silently swallowed
        // and the view dismissed straight back to the inbox.
        .alert("Action didn't go through", isPresented: Binding(
            get: { actionErrorMessage != nil },
            set: { if !$0 { actionErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(actionErrorMessage ?? "") }
        .confirmationDialog("Set reminder", isPresented: $showReminderOptions, titleVisibility: .visible) {
            Button("In 1 hour") {
                Task { await scheduleReminder(for: .oneHour) }
            }
            Button("Tonight") {
                Task { await scheduleReminder(for: .tonight) }
            }
            Button("Tomorrow morning") {
                Task { await scheduleReminder(for: .tomorrowMorning) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Main Layout

    private func mainContent(_ detail: EmailThreadDetail) -> some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                topBar(detail)
                scrollContent(detail)
            }

            // Bottom reply bar — free-floating with scrim gradient behind it
            bottomBar
        }
    }

    // MARK: - Top Bar
    // Transparent by default. On scroll past the subject, a scrim gradient fades in
    // and the title appears centered. Action icons grouped in a single glass capsule.

    private func topBar(_ detail: EmailThreadDetail) -> some View {
        ZStack {
            HStack(spacing: 10) {
                // Back button — standalone pill
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(LiquidGlassButtonStyle(cornerRadius: 19))
                .minTouchTarget()
                .accessibilityLabel("Back")

                Spacer()

                // Grouped action icons in a single glass capsule:
                //   archive · mark-as-unread · delete · more (ellipsis menu)
                // The Ask AI button was removed — the global AI FAB stays visible
                // above the reply bar for thread-level questions.
                HStack(spacing: 0) {
                    Button {
                        // Gate dismissal on the actual mutation result rather than
                        // diffing the shared `errorMessage` — that approach is fragile
                        // because unrelated calls can mutate `errorMessage` between
                        // the snapshot and the check.
                        guard !isTopBarBusy else { return }
                        isTopBarBusy = true
                        topBarActionTick &+= 1
                        Task {
                            let success = await emailService.markAsUnread(ids: [threadId])
                            isTopBarBusy = false
                            if success {
                                dismiss()
                            } else {
                                actionErrorMessage = emailService.errorMessage
                                    ?? "Could not mark as unread. Please try again."
                            }
                        }
                    } label: {
                        Image(systemName: "envelope.badge")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 42, height: 38)
                    }
                    .buttonStyle(.plain)
                    .disabled(isTopBarBusy)
                    .accessibilityLabel("Mark as unread")

                    Button {
                        guard !isTopBarBusy else { return }
                        isTopBarBusy = true
                        topBarActionTick &+= 1
                        Task {
                            let success = await emailService.archiveThreads(ids: [threadId])
                            isTopBarBusy = false
                            if success {
                                dismiss()
                            } else {
                                actionErrorMessage = emailService.errorMessage
                                    ?? "Could not archive. Please try again."
                            }
                        }
                    } label: {
                        Image(systemName: "archivebox")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 42, height: 38)
                    }
                    .buttonStyle(.plain)
                    .disabled(isTopBarBusy)
                    .accessibilityLabel("Archive")

                    moreOptionsMenu
                }
                .headerCapsuleGlass()
                // Light haptic on every top-bar action tap so the user feels a
                // confirming tactile cue before the dismiss animation runs.
                .sensoryFeedback(.impact(weight: .light), trigger: topBarActionTick)
            }

            // Scroll-aware title — fades in when subject has scrolled off screen
            if showTitleInHeader {
                Text(subjectForHeader)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: 200)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showTitleInHeader)
        // 16pt matches the subject + message card horizontal padding so the back button
        // aligns vertically with the email body card edge.
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        // Pure gradient fade — no solid fill, content smoothly fades out under the bar
        .background(
            LinearGradient(
                stops: [
                    .init(color: AppTheme.backgroundTop.opacity(0.9), location: 0),
                    .init(color: AppTheme.backgroundTop.opacity(0.6), location: 0.5),
                    .init(color: AppTheme.backgroundTop.opacity(0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.bottom, -20) // Extend gradient below the bar for a smoother fade
            .allowsHitTesting(false)
        )
        .confirmationDialog("Delete this thread?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    // Only dismiss on success — if the API call fails, keep the user on the
                    // thread and surface the error so they can retry instead of silently
                    // dropping back to the inbox.
                    let success = await emailService.deleteThreads(ids: [threadId])
                    if success {
                        dismiss()
                    } else {
                        actionErrorMessage = emailService.errorMessage
                            ?? "Please check your connection and try again."
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Scrollable Content

    private func scrollContent(_ detail: EmailThreadDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Invisible scroll tracker anchored to the top of the scroll content
                GeometryReader { geo in
                    Color.clear
                        .preference(key: ScrollOffsetKey.self,
                                    value: -geo.frame(in: .named("threadScroll")).origin.y)
                }
                .frame(height: 0)

                // Labels chips — only render when there are non-system labels.
                if hasVisibleLabels(detail) {
                    labelsRow(detail)
                        .padding(.top, 12)
                        .padding(.bottom, 2)
                }

                // Subject row — full width, star button to the right
                subjectRow(detail)

                // Smart-action chip for verification / receipt threads.
                // Renders the single most useful thing for that kind:
                //   - Verification → giant "Copy 178 691" button
                //   - Receipt → vendor · amount · date chip
                // For non-conversational threads we show this INSTEAD of the
                // AI summary card. Way more useful than hiding everything.
                if services.assistantAutomationPolicy.assistantThreadActionsVisible,
                   let assistant = assistantThread {
                    if let code = assistant.extractedCode, !code.isEmpty {
                        VerificationCodeAction(code: code) {
                            UIPasteboard.general.string = code.replacingOccurrences(of: " ", with: "")
                            assistantToast = .success("Code copied")
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    } else if let receipt = assistant.extractedReceipt {
                        ReceiptInfoChip(receipt: receipt) {
                            // Forward the receipt — opens the existing
                            // compose sheet in forward mode with the latest
                            // message body pre-populated. Useful for sending
                            // to a bookkeeper or expense tracker.
                            assistantDraftSeed = nil
                            composeMode = .forward
                            showCompose = true
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }
                }

                // AI Summary card — only on conversational threads with real
                // content. The non-conversational kinds (verification, receipt,
                // marketing, notification) render the smart-action chip above
                // instead of this card.
                if services.assistantAutomationPolicy.assistantThreadActionsVisible &&
                   shouldShowSummaryCard {
                    summaryCard
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }

                // Contextual action buttons — only show when at least one action
                // qualifies. The "Ask AI" fallback was removed; the global FAB
                // (always visible at bottom-right) is the entry point for chat.
                if services.assistantAutomationPolicy.assistantThreadActionsVisible &&
                   shouldShowActionButtons {
                    actionButtonsRow
                        .padding(.top, 8)
                }

                // Flat message list
                messagesSection(detail)
                    .padding(.top, 16)

                // Extra bottom padding so content isn't hidden behind the reply bar
                Color.clear.frame(height: 80)
            }
        }
        .coordinateSpace(name: "threadScroll")
        .onPreferenceChange(ScrollOffsetKey.self) { value in
            scrollOffset = value
        }
    }

    // MARK: - Subject Row

    private func subjectRow(_ detail: EmailThreadDetail) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Show an em dash for missing subjects — feels less like an error state
            // than the parenthetical "(no subject)" placeholder.
            Text(threadSubjectDisplay(detail))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = threadSubjectDisplay(detail)
                    } label: {
                        Label("Copy subject", systemImage: "doc.on.doc")
                    }
                }

            Spacer(minLength: 8)

            // Star button to the right of the subject. Optimistically flip the
            // local state, then await the mutation — if the server says no, roll
            // back so the icon doesn't lie about the actual star state.
            Button {
                guard !isStarBusy else { return }
                isStarBusy = true
                let prior = isStarred
                isStarred.toggle()
                Task {
                    let success = await emailService.toggleStar(ids: [threadId])
                    isStarBusy = false
                    if !success {
                        isStarred = prior
                        actionErrorMessage = emailService.errorMessage
                            ?? "Could not update star. Please try again."
                    }
                }
            } label: {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(isStarred ? Color.yellow : AppTheme.mutedText)
            }
            .buttonStyle(.plain)
            .disabled(isStarBusy)
            .padding(.top, 3)
            // Spoken state for VoiceOver — the icon alone doesn't convey "starred"
            // vs "not starred" clearly. The label updates whenever `isStarred`
            // flips, including after a rollback.
            .accessibilityLabel(isStarred ? "Starred" : "Not starred")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 2)
    }

    // MARK: - Assistant gating helpers

    /// Whether at least one contextual action is relevant for this thread.
    /// Mirrors the inline conditions in `actionButtonsRow` so we can hide the
    /// entire row (and its top padding) when nothing applies.
    private var hasAnyAction: Bool {
        guard let a = assistantThread, a.threadKind.isConversational else { return false }
        if !a.suggestedTasks.isEmpty { return true }
        if a.replyNeeded || a.existingDraft ||
           a.preparedActions.contains(where: { $0.type == "draft_reply" }) { return true }
        if a.followUpNeeded { return true }
        if a.meetingRequested && a.suggestedEvent != nil { return true }
        return false
    }

    /// Whether the AI summary card has anything worth rendering. Returns false
    /// for non-conversational threads and for conversational threads where the
    /// AI produced no text — that combination would otherwise just show the
    /// "Not summarized yet" placeholder on every receipt/marketing/notification.
    private var shouldShowSummaryCard: Bool {
        // Always allow loading state through so the user sees a skeleton while
        // we fetch. We can't know the thread kind yet at that point.
        if isLoadingAssistant { return true }
        // Failed loads are silently swallowed — no card, no layout jump.
        // The AI FAB is always accessible for follow-up questions.
        if assistantLoadFailed { return false }
        guard let a = assistantThread else { return false }
        guard a.threadKind.isConversational else { return false }
        // `aiLeadLine` is the new primary content path; `summary` is the
        // legacy/fallback. Either signals "we have something to show".
        let hasContent = !a.aiLeadLine.isEmpty
            || !a.summary.isEmpty
            || !a.changedSinceLastOpen.isEmpty
            || hasAnyAction
        return hasContent
    }

    /// Whether to render the action button row. Hidden when no individual
    /// button qualifies (which is true for every non-conversational thread).
    private var shouldShowActionButtons: Bool {
        if isLoadingAssistant { return false }
        return hasAnyAction
    }

    // MARK: - AI Summary Card

    /// Compact AI summary card. Designed to be glanceable — a single line of
    /// summary text with a small sparkles affordance, and at most one
    /// "since last open" change line. Person details / action item bullets /
    /// low-confidence rationale are intentionally cut: the user opens the
    /// thread to read the messages, the card is a hint not a dossier.
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoadingAssistant {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(aiGradient)
                    Text("Summarizing…")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.mutedText)
                }
            } else if let a = assistantThread {
                // Prefer the smart `aiLeadLine` (meeting time / first question /
                // first action item) — it's tuned to be the *one* thing the
                // user wants to know. Falls back to `summary` for older
                // backends that don't compute the lead line yet.
                let lead = a.aiLeadLine.isEmpty ? a.summary : a.aiLeadLine
                if !lead.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(aiGradient)
                            .padding(.top, 2)
                        Text(lead)
                            .font(.system(size: 14))
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Single "since last open" line — the most useful change-feed
                // signal. We drop the rest because the user is already on the
                // thread and can scroll to see what's new.
                if let change = a.changedSinceLastOpen.first {
                    Text(change)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.mutedText)
                        .lineLimit(2)
                }
            } else {
                // Truly empty conversational thread — offer an explicit
                // summarize CTA so AI feels reachable rather than absent.
                Button {
                    Task { await handleSummarize() }
                } label: {
                    HStack(spacing: 6) {
                        if isSummarizing {
                            ButtonInlineProgressView(tint: AppTheme.mutedText, side: AppTheme.Metrics.compactInlineSpinner)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(aiGradient)
                        }
                        Text(isSummarizing ? "Summarizing…" : "Summarize this thread")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSummarizing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(AppTheme.rowStroke, lineWidth: 1)
        )
    }

    // MARK: - Action Buttons Row
    // Contextual — only shows buttons relevant to this thread based on AI flags.
    // Uses padding-free ScrollView to avoid right-side clipping.

    private var actionButtonsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Contextual buttons based on AI analysis flags. Each button
                // shows an inline spinner when its handler is running and other
                // buttons dim to make it obvious which action is in flight.
                // The "Ask AI" fallback was intentionally removed — the global
                // AI FAB at the bottom-right of the screen is the entry point
                // for chatting about this thread.

                // Extract tasks — only when AI found extractable tasks
                if let a = assistantThread, !a.suggestedTasks.isEmpty {
                    ThreadActionButton(
                        label: "Extract task",
                        icon: "checklist",
                        isPrimary: true,
                        isLoading: inFlightAction == .task,
                        isDisabled: inFlightAction != nil && inFlightAction != .task,
                        confirmedLabel: recentlyCompletedAction == .task ? "Task created" : nil
                    ) {
                        if let suggestion = a.suggestedTasks.first {
                            Task { await handleCreateTask(suggestion) }
                        }
                    }
                }

                // Draft reply — only when AI says reply is needed or draft is eligible
                if let a = assistantThread,
                   a.replyNeeded || a.existingDraft || a.preparedActions.contains(where: { $0.type == "draft_reply" }) {
                    ThreadActionButton(
                        label: a.existingDraft ? "Review draft" : "Draft reply",
                        icon: "pencil.line",
                        isPrimary: a.replyNeeded,
                        isLoading: inFlightAction == .draft,
                        isDisabled: inFlightAction != nil && inFlightAction != .draft
                    ) {
                        Task { await handleDraftReply() }
                    }
                }

                // Book follow-up — only when AI detected follow-up needed
                if let a = assistantThread, a.followUpNeeded {
                    ThreadActionButton(
                        label: "Book follow-up",
                        icon: "calendar.badge.plus",
                        isLoading: inFlightAction == .followUp,
                        isDisabled: inFlightAction != nil && inFlightAction != .followUp,
                        confirmedLabel: recentlyCompletedAction == .followUp ? "Follow-up created" : nil
                    ) {
                        Task {
                            let subject = detail?.messages.first?.subject ?? "Email"
                            await handleCreateFollowUp(subject: subject)
                        }
                    }
                }

                // Create event — only when AI detected a meeting request
                if let a = assistantThread, a.meetingRequested, a.suggestedEvent != nil {
                    ThreadActionButton(
                        label: "Create event",
                        icon: "calendar.badge.plus",
                        isLoading: inFlightAction == .event,
                        isDisabled: inFlightAction != nil && inFlightAction != .event,
                        confirmedLabel: recentlyCompletedAction == .event ? "Event added" : nil
                    ) {
                        Task { await handleCreateEvent() }
                    }
                }
            }
            .padding(.horizontal, 16) // Inner padding so pills aren't clipped
            .padding(.vertical, 2)
        }
    }

    // MARK: - Messages Section

    private func messagesSection(_ detail: EmailThreadDetail) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(detail.messages.enumerated()), id: \.element.id) { index, message in
                // Last message is always expanded; others start collapsed
                MessageRow(
                    message: message,
                    expandByDefault: index == detail.messages.count - 1,
                    emailDarkMode: $emailDarkMode,
                    onReply: {
                        composeMode = .reply
                        showCompose = true
                    },
                    onForward: {
                        composeMode = .forward
                        showCompose = true
                    }
                )

                if index < detail.messages.count - 1 {
                    Divider()
                        .foregroundStyle(AppTheme.divider)
                        .padding(.leading, 16 + 36 + 10)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    // MARK: - Labels Row
    // Shown above the subject. Each label renders as a small chip; trailing
    // "+ Add label" button opens the editor sheet so the user can toggle labels.

    private func labelsRow(_ detail: EmailThreadDetail) -> some View {
        let labels = detail.labels ?? []
        // Filter out system-only labels users don't expect to see as chips.
        let visible = labels.filter { label in
            let n = label.name.uppercased()
            // Hide top-level Gmail system labels — STARRED is shown via the star button
            // on the subject row, INBOX/SENT/UNREAD/IMPORTANT are inherent state.
            return !["STARRED", "\\STARRED", "INBOX", "SENT", "UNREAD",
                     "IMPORTANT", "DRAFT", "TRASH", "SPAM"].contains(n)
        }

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(visible, id: \.id) { label in
                    LabelChip(name: prettyLabelName(label.name))
                }

                // Add-label affordance — also serves as the empty-state CTA.
                Button {
                    showLabelEditor = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text(visible.isEmpty ? "Add label" : "Edit")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(AppTheme.mutedText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(AppTheme.rowStroke, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Bottom Bar
    // Free-floating reply buttons — no solid fill, only a smooth gradient
    // that fades content out behind the buttons.

    private var bottomBar: some View {
        HStack(spacing: 8) {
            ForEach([
                ("arrowshape.turn.up.left", "Reply"),
                ("arrowshape.turn.up.left.2", "Reply All"),
                ("arrowshape.turn.up.right", "Forward")
            ], id: \.1) { icon, label in
                Button {
                    composeMode = label == "Reply" ? .reply : label == "Reply All" ? .replyAll : .forward
                    showCompose = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(label)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                // Fully pill-shaped — radius matches the button half-height so it
                // remains a true Capsule on every device size.
                .buttonStyle(LiquidGlassButtonStyle(cornerRadius: 22))
                // Don't allow Reply/Reply All/Forward before the thread detail
                // has loaded — composeMode would open against an empty thread.
                .disabled(isLoading || detail == nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        // Gradient extends through the home indicator area so there's no
        // visible see-through gap behind the buttons.
        .background(
            LinearGradient(
                stops: [
                    .init(color: AppTheme.backgroundTop.opacity(0), location: 0),
                    .init(color: AppTheme.backgroundTop.opacity(0.6), location: 0.35),
                    .init(color: AppTheme.backgroundTop.opacity(0.9), location: 0.7),
                    .init(color: AppTheme.backgroundTop, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.top, -30) // Smooth fade above the buttons
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        )
    }

    // MARK: - Action Handlers

    private func loadThread() async {
        // Cache hit → paint instantly, skip the skeleton. The async loadThread below still
        // runs and silently refreshes in the background so a stale entry self-heals.
        if let cached = emailService.cachedThreadDetail(id: threadId), detail == nil {
            detail = cached
            isLoading = false
            isStarred = cached.labels?.contains(where: {
                let n = $0.name.uppercased()
                return n == "STARRED" || n == "\\STARRED"
            }) ?? false
        }

        // Run the thread fetch, the assistant context fetch, and markAsRead in parallel.
        // Previously the assistant call only started after the thread had returned, doubling
        // the time-to-summary. With Gmail's API + Cloudflare round-trip both calls together
        // are roughly the same wall-clock as either one in isolation.
        async let threadDetail = emailService.loadThread(id: threadId)
        async let assistant = emailService.loadAssistant(threadId: threadId)
        // Silent markAsRead — opening a thread should never leak a "Could not
        // mark as read" message into the shared `errorMessage` (which the
        // inbox watches). The user didn't initiate this action explicitly.
        async let markRead: Bool = emailService.markAsRead(ids: [threadId], silent: true)

        let resolvedDetail = await threadDetail
        detail = resolvedDetail
        isLoading = false

        isStarred = resolvedDetail?.labels?.contains(where: {
            let n = $0.name.uppercased()
            return n == "STARRED" || n == "\\STARRED"
        }) ?? false

        let resolvedAssistant = await assistant
        applyAssistantContext(resolvedAssistant)
        // Track failure so the summary card can show a "Summary unavailable" state
        // rather than the "Not summarized yet" prompt that's reserved for first-load.
        assistantLoadFailed = resolvedAssistant == nil
        isLoadingAssistant = false
        // Result intentionally discarded — markAsRead is silent in this path so a
        // failure doesn't poison the shared `errorMessage`, and we don't surface
        // it locally because opening a thread isn't an explicit user "mark read".
        _ = await markRead
    }

    private func refreshAssistant() async {
        isLoadingAssistant = true
        let resolved = await emailService.loadAssistant(threadId: threadId)
        applyAssistantContext(resolved)
        assistantLoadFailed = resolved == nil
        isLoadingAssistant = false
    }

    /// Updates assistant state from a freshly loaded context. If the context
    /// is for a verification thread, auto-copies the extracted code to the
    /// clipboard the first time we see this thread in the session — so the
    /// user can switch apps and paste without an extra tap.
    private func applyAssistantContext(_ value: AssistantThreadContext?) {
        assistantThread = value
        autoCopyVerificationCodeIfNeeded(value)
    }

    /// One-shot per session: if the thread is verification + has a code +
    /// we haven't already copied it for this thread id, copy it and toast.
    /// Re-opening the same thread later in the session won't re-copy (the
    /// session set guards against accidental clipboard overwrites).
    private func autoCopyVerificationCodeIfNeeded(_ context: AssistantThreadContext?) {
        guard let context else { return }
        guard context.threadKind == .verification,
              let code = context.extractedCode,
              !code.isEmpty,
              !services.autoCopiedVerificationThreads.contains(context.threadId)
        else { return }
        let raw = code.replacingOccurrences(of: " ", with: "")
        UIPasteboard.general.string = raw
        services.autoCopiedVerificationThreads.insert(context.threadId)
        assistantToast = .success("Code copied: \(code)")
    }

    private func handleCreateTask(_ suggestion: MailAssistantSuggestedTask) async {
        inFlightAction = .task
        defer { inFlightAction = nil }
        let success = await emailService.createAssistantTask(threadId: threadId, suggestion: suggestion)
        if success {
            // Inline button confirmation replaces the toast — the button
            // morphs to "✓ Task created" right where the user tapped, which
            // is much more legible than a global toast at the bottom.
            markRecentlyCompleted(.task)
            await refreshAssistant()
        } else {
            assistantToast = .failure("Could not create the task")
        }
    }

    /// Used by the "Book follow-up" button. Tracked separately so the
    /// follow-up button shows a spinner instead of the (also task-creating)
    /// "Extract task" button.
    private func handleCreateFollowUp(subject: String) async {
        inFlightAction = .followUp
        defer { inFlightAction = nil }
        let success = await emailService.createAssistantTask(
            threadId: threadId,
            suggestion: MailAssistantSuggestedTask(
                title: "Follow up: \(subject)",
                description: nil,
                priority: "medium",
                dueDate: nil
            )
        )
        if success {
            markRecentlyCompleted(.followUp)
            await refreshAssistant()
        } else {
            assistantToast = .failure("Could not create the follow-up")
        }
    }

    private func handleCreateEvent() async {
        inFlightAction = .event
        defer { inFlightAction = nil }
        guard let event = assistantThread?.suggestedEvent else {
            assistantToast = .failure("No event suggestion available")
            return
        }
        let success = await emailService.createAssistantEvent(threadId: threadId, suggestion: event)
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
        guard let result = await emailService.generateAssistantDraft(threadId: threadId) else {
            assistantToast = .failure("Could not generate a draft")
            return
        }
        if result.created {
            assistantDraftSeed = result.preview
            composeMode = .reply
            showCompose = true
            await refreshAssistant()
            // No inline confirmation or toast here — the compose sheet
            // opening IS the confirmation.
        } else {
            assistantToast = .failure(result.reason.isEmpty
                ? "Draft already exists or was skipped"
                : result.reason)
        }
    }

    /// Stamp the "just completed" action and schedule it to clear after
    /// `recentCompletionDuration` seconds, so the inline confirmation
    /// auto-reverts. Cancelling here is a no-op — the simple Task is
    /// fine because if a new action starts before the timer fires, the
    /// new completion will overwrite this one anyway.
    private func markRecentlyCompleted(_ action: ThreadAction) {
        recentlyCompletedAction = action
        let captured = action
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(recentCompletionDuration))
            // Only clear if we're still showing the same action — guards
            // against clobbering a fresher confirmation that landed during
            // the sleep.
            if recentlyCompletedAction == captured {
                recentlyCompletedAction = nil
            }
        }
    }

    private func handleSummarize() async {
        isSummarizing = true
        do {
            applyAssistantContext(try await emailService.loadAssistantThrowing(threadId: threadId))
            // A successful explicit summarize clears any prior load-failure state so the
            // card switches from the error/retry view to the populated summary.
            assistantLoadFailed = false
        } catch {
            AppLogger.shared.log("[EmailThreadView] Summarize failed: \(error)")
            assistantToast = .failure("Could not generate summary")
        }
        isSummarizing = false
    }

    // MARK: - More Options Menu (ellipsis in header capsule)
    //
    // The previous `openAssistant()` helper was removed alongside the in-thread
    // "Ask AI" button. Thread context is now seeded onto `aiChatService` in
    // `.onAppear` / `.onChange(of: subject)` instead, so the global FAB tap
    // already has the subject + thread id when the user opens the chat sheet.

    private var moreOptionsMenu: some View {
        Menu {
            Section {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { emailDarkMode.toggle() }
                } label: {
                    Label(
                        emailDarkMode ? "Render in light mode" : "Render in dark mode",
                        systemImage: emailDarkMode ? "sun.max" : "moon"
                    )
                }
            }

            Section {
                Button {
                    showLabelEditor = true
                } label: { Label("Edit labels", systemImage: "tag") }

                Button {
                    showReminderOptions = true
                } label: { Label("Set reminder", systemImage: "alarm") }
            }

            Section {
                Button {
                    Task {
                        let success = await emailService.markAsSpam(ids: [threadId])
                        if success { dismiss() }
                        else { actionErrorMessage = emailService.errorMessage ?? "Could not report spam. Please try again." }
                    }
                } label: { Label("Report spam", systemImage: "exclamationmark.octagon") }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: { Label("Move to Trash", systemImage: "trash") }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 42, height: 38)
        }
        .accessibilityLabel("More actions")
    }

    // MARK: - Labels helpers

    private func hasVisibleLabels(_ detail: EmailThreadDetail) -> Bool {
        guard let labels = detail.labels else { return false }
        return labels.contains { label in
            !["STARRED", "\\STARRED", "INBOX", "SENT", "UNREAD",
              "IMPORTANT", "DRAFT", "TRASH", "SPAM"].contains(label.name.uppercased())
        }
    }

    private enum ReminderPreset {
        case oneHour
        case tonight
        case tomorrowMorning
    }

    private func scheduleReminder(for preset: ReminderPreset) async {
        guard let message = detail?.messages.last ?? detail?.messages.first else { return }
        let remindAt = reminderDate(for: preset)
        let didSchedule = await services.notificationService.scheduleEmailReminder(
            threadId: threadId,
            from: message.from.name.isEmpty ? message.from.email : message.from.name,
            subject: message.subject,
            remindAt: remindAt
        )
        if didSchedule {
            reminderNoticeIsFailure = false
            reminderNotice = "We'll remind you on \(remindAt.formatted(date: .abbreviated, time: .shortened))."
        } else {
            reminderNoticeIsFailure = true
            reminderNotice = "Turn on notifications for Todus to use email reminders."
        }
    }

    private func reminderDate(for preset: ReminderPreset) -> Date {
        let now = Date()
        let calendar = Calendar.current
        switch preset {
        case .oneHour:
            return now.addingTimeInterval(3600)
        case .tonight:
            let todayAtSeven = calendar.date(
                bySettingHour: 19,
                minute: 0,
                second: 0,
                of: now
            ) ?? now.addingTimeInterval(3600)
            if todayAtSeven > now {
                return todayAtSeven
            }
            return calendar.date(byAdding: .day, value: 1, to: todayAtSeven) ?? now.addingTimeInterval(3600)
        case .tomorrowMorning:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.date(
                bySettingHour: 9,
                minute: 0,
                second: 0,
                of: tomorrow
            ) ?? now.addingTimeInterval(3600)
        }
    }

    /// Convert a Gmail label name into a friendly display string.
    /// `CATEGORY_PROMOTIONS` → `Promotions`; user labels are returned as-is.
    private func prettyLabelName(_ raw: String) -> String {
        if raw.hasPrefix("CATEGORY_") {
            return raw.dropFirst("CATEGORY_".count).capitalized
        }
        return raw
    }

    /// Returns the display subject for the thread, falling back to an em dash
    /// when the first message has no subject (or only whitespace).
    private func threadSubjectDisplay(_ detail: EmailThreadDetail) -> String {
        let raw = detail.messages.first?.subject ?? ""
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "—"
        }
        return raw
    }
}

// MARK: - Label Chip

private struct LabelChip: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppTheme.subtleText)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(AppTheme.surfaceSecondary, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous).stroke(AppTheme.rowStroke, lineWidth: 1)
            )
    }
}

// MARK: - Edit Labels Sheet

/// Lists every user label and toggles the thread's membership via `mail.modifyLabels`.
private struct EditLabelsSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let threadId: String
    let appliedLabels: [EmailThreadDetail.ThreadLabel]
    let onChange: () -> Void

    @State private var availableLabels: [EmailLabel] = []
    @State private var selectedIds: Set<String> = []
    @State private var initialIds: Set<String> = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showLabelSaveError = false
    @State private var labelSaveErrorText = ""

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…").controlSize(.small).tint(.secondary)
                } else if let errorMessage {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(AppTheme.mutedText)
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.subtleText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else if availableLabels.isEmpty {
                    Text("No labels yet. Create one in Gmail to use it here.")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.mutedText)
                        .padding(.horizontal, 32)
                        .multilineTextAlignment(.center)
                } else {
                    List {
                        ForEach(availableLabels) { label in
                            Button {
                                if selectedIds.contains(label.id) {
                                    selectedIds.remove(label.id)
                                } else {
                                    selectedIds.insert(label.id)
                                }
                            } label: {
                                HStack {
                                    Text(label.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedIds.contains(label.id) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Edit labels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ButtonInlineProgressView(tint: .primary, side: AppTheme.Metrics.toolbarInlineSpinner)
                        } else { Text("Save").fontWeight(.semibold) }
                    }
                    .disabled(isSaving || selectedIds == initialIds)
                }
            }
        }
            .task { await load() }
            .alert("Couldn't update labels", isPresented: $showLabelSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(labelSaveErrorText)
            }
    }

    private func load() async {
        // Pre-select the labels already on this thread.
        initialIds = Set(appliedLabels.map(\.id))
        selectedIds = initialIds

        do {
            availableLabels = try await services.emailService.listLabels()
                .filter { $0.type == "user" } // hide Gmail system labels (INBOX, SPAM, …)
                .sorted { $0.name.lowercased() < $1.name.lowercased() }
            isLoading = false
        } catch {
            errorMessage = "Could not load labels."
            isLoading = false
        }
    }

    private func save() async {
        isSaving = true
        let added = Array(selectedIds.subtracting(initialIds))
        let removed = Array(initialIds.subtracting(selectedIds))
        let success = await services.emailService.modifyLabels(
            threadId: threadId,
            add: added,
            remove: removed
        )
        isSaving = false
        if success {
            onChange()
            dismiss()
        } else {
            labelSaveErrorText = "Please try again. Your selections are preserved."
            showLabelSaveError = true
        }
    }
}

// MARK: - Thread Action Button

/// Pill button for the horizontal action strip below the summary card.
private struct ThreadActionButton: View {
    let label: String
    let icon: String
    var isPrimary: Bool = false
    /// When true, the icon is replaced with an inline spinner and the button
    /// becomes non-interactive. The label keeps its width so the button doesn't
    /// reflow while an action is in flight.
    var isLoading: Bool = false
    /// When true (and `isLoading == false`), the button is dimmed and disabled.
    /// Used to grey out other actions while one is in flight.
    var isDisabled: Bool = false
    /// When non-nil, the button morphs into a "✓ <confirmedLabel>" pill that
    /// auto-reverts after a few seconds. Used for one-tap-done confirmation
    /// — far more legible than a toast, and right where the user just tapped.
    var confirmedLabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let confirmedLabel {
                    // Confirmation state: green check + "Created" label.
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.green)
                    Text(confirmedLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                } else if isLoading {
                    ButtonInlineProgressView(
                        tint: isPrimary ? AppTheme.backgroundTop : Color.primary,
                        side: AppTheme.Metrics.compactInlineSpinner
                    )
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isPrimary ? AppTheme.backgroundTop : Color.primary)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundStyle(isPrimary ? AppTheme.backgroundTop : Color.primary)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.card + 2, style: .continuous)
                    .fill(
                        confirmedLabel != nil
                            ? AppTheme.surfacePrimary
                            : (isPrimary ? Color.primary : AppTheme.surfacePrimary)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.card + 2, style: .continuous)
                    .stroke(
                        confirmedLabel != nil
                            ? Color.green.opacity(0.45)
                            : (isPrimary ? Color.clear : AppTheme.rowStroke),
                        lineWidth: 1
                    )
            )
            .opacity(isDisabled && !isLoading && confirmedLabel == nil ? 0.45 : 1)
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: confirmedLabel)
            .animation(.easeOut(duration: 0.18), value: isLoading)
        }
        .buttonStyle(.plain)
        .disabled(isLoading || isDisabled || confirmedLabel != nil)
    }
}

// MARK: - Smart Action Chips
//
// Rendered above the messages on non-conversational threads, in place of the
// AI summary card. Each one focuses on the single most useful affordance for
// that kind of email.

/// Big, monospaced verification code presented as a one-tap copy button.
/// Designed to be the first thing the user's eyes hit on a verification
/// email — no scanning the body for the digits.
private struct VerificationCodeAction: View {
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
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Verification code")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.mutedText)
                        .textCase(.uppercase)
                    Text(code)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                    Text(didCopy ? "Copied" : "Copy")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(AppTheme.backgroundTop)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                        .fill(Color.primary)
                )
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppTheme.surfacePrimary,
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .stroke(AppTheme.rowStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy verification code \(code)")
    }
}

/// Compact "vendor · amount · date" chip for receipt-style emails, with a
/// `Forward` action for sending the receipt to a bookkeeper or expense
/// tracker without leaving the thread.
private struct ReceiptInfoChip: View {
    let receipt: AssistantThreadContext.ExtractedReceipt
    let onForward: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "receipt")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.mutedText)
                .frame(width: 28, height: 28)
                .background(AppTheme.surfaceSecondary, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.vendor)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let amount = receipt.amount, !amount.isEmpty {
                        Text(amount)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.subtleText)
                    }
                    if receipt.amount != nil, formattedDate != nil {
                        Text("·")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.mutedText)
                    }
                    if let date = formattedDate {
                        Text(date)
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.mutedText)
                    }
                }
            }
            Spacer(minLength: 0)
            Button(action: onForward) {
                HStack(spacing: 5) {
                    Image(systemName: "arrowshape.turn.up.right")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Forward")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                        .stroke(AppTheme.rowStroke, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Forward this receipt")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            AppTheme.surfacePrimary,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(AppTheme.rowStroke, lineWidth: 1)
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

// MARK: - Message Row

/// Flat message row — no card boxing.
/// Collapsed: avatar + sender + date + snippet preview.
/// Expanded: sender details + toggleable From/To/Date card + HTML body + attachments.
/// Performance: shows plain text immediately, defers WKWebView loading to avoid UI hang.
private struct MessageRow: View {
    let message: EmailMessage
    let expandByDefault: Bool
    /// Optional per-message reply callback. EmailThreadView wires this to its
    /// shared composeMode/showCompose state so context-menu Reply opens the
    /// existing sheet without needing per-row state plumbing.
    let onReply: (() -> Void)?
    let onForward: (() -> Void)?

    @State private var isExpanded: Bool
    @State private var showDetails = false
    /// Defers WKWebView creation to avoid blocking the main thread on navigation
    @State private var htmlReady = false
    /// Controlled by the parent thread view — toggled via the header ellipsis menu.
    @Binding var emailDarkMode: Bool

    init(
        message: EmailMessage,
        expandByDefault: Bool,
        emailDarkMode: Binding<Bool>,
        onReply: (() -> Void)? = nil,
        onForward: (() -> Void)? = nil
    ) {
        self.message = message
        self.expandByDefault = expandByDefault
        self.onReply = onReply
        self.onForward = onForward
        self._isExpanded = State(initialValue: expandByDefault)
        self._emailDarkMode = emailDarkMode
    }

    private var toNames: String {
        message.to.prefix(2).map(\.name).joined(separator: ", ")
    }

    /// Single shared formatter for the abbreviated fallback path. Building a
    /// `RelativeDateTimeFormatter` on every render would be wasteful — keep it
    /// static and re-use across rows.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    /// Renders the collapsed message header date. Messages newer than 24 hours
    /// use a relative phrase ("12 min ago", "3h ago"); older ones fall back to
    /// the abbreviated "May 12, 2:30 PM" format.
    static func formattedHeaderDate(_ date: Date) -> String {
        let delta = Date().timeIntervalSince(date)
        if delta < 60 * 60 * 24, delta >= 0 {
            return relativeFormatter.localizedString(for: date, relativeTo: Date())
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row (always visible)
            Button {
                withAnimation(.snappy(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    SenderAvatarView(email: message.from.email, name: message.from.name, size: 36)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(message.from.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            // Recent messages (<24h) render as relative time ("2 min ago",
                            // "5h ago") which reads more naturally on a thread you're
                            // actively in than a date stamp. Older messages keep the
                            // abbreviated date format.
                            Text(Self.formattedHeaderDate(message.date))
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.mutedText)
                                // Don't let long sender names truncate the date — its
                                // information value beats the truncation symmetry.
                                .layoutPriority(1)
                                .fixedSize()
                        }

                        if !isExpanded {
                            // Collapsed preview snippet — fall back to subject, then a
                            // placeholder so the row never renders blank.
                            let snippet = (message.plainText.flatMap { $0.isEmpty ? nil : $0 }) ?? (message.subject.isEmpty ? "(no preview)" : message.subject)
                            Text(snippet)
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.mutedText)
                                .lineLimit(1)
                        } else {
                            // "To: names" row — tap to toggle details card.
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) { showDetails.toggle() }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("To: \(toNames.isEmpty ? "Me" : toNames)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppTheme.mutedText)
                                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 10))
                                        .foregroundStyle(AppTheme.mutedText)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    onReply?()
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }
                Button {
                    onForward?()
                } label: {
                    Label("Forward", systemImage: "arrowshape.turn.up.right")
                }

                Divider()

                Button {
                    UIPasteboard.general.string = message.from.email
                } label: {
                    Label("Copy from address", systemImage: "envelope")
                }
                Button {
                    UIPasteboard.general.string = message.subject
                } label: {
                    Label("Copy subject", systemImage: "text.quote")
                }
                if let plain = message.plainText, !plain.isEmpty {
                    Button {
                        UIPasteboard.general.string = plain
                    } label: {
                        Label("Copy message text", systemImage: "doc.on.doc")
                    }
                    Button {
                        // Markdown-style quote with > prefix per line — drops directly
                        // into reply drafts in Notion / Slack / Bear without manual edit.
                        let quoted = plain
                            .split(separator: "\n", omittingEmptySubsequences: false)
                            .map { "> \($0)" }
                            .joined(separator: "\n")
                        UIPasteboard.general.string = quoted
                    } label: {
                        Label("Copy as quote", systemImage: "quote.bubble")
                    }
                }
            }

            // Expanded content
            if isExpanded {
                // From / To / Date details card (toggled by "To:" row)
                if showDetails {
                    detailsCard
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Email body — show plain text immediately, defer HTML to avoid UI hang
                if !message.body.isEmpty {
                    if htmlReady {
                        ExpandingEmailHTMLView(html: message.body, darkMode: emailDarkMode)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                            .contextMenu {
                                Button {
                                    emailDarkMode.toggle()
                                } label: {
                                    Label(
                                        emailDarkMode ? "Render in light mode" : "Render in dark mode",
                                        systemImage: emailDarkMode ? "sun.max" : "moon"
                                    )
                                }
                            }
                    } else if let plain = message.plainText, !plain.isEmpty {
                        // Show plain text while WKWebView initializes in the background
                        Text(plain)
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                            .textSelection(.enabled)
                            .transition(.opacity)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }
                } else if let plain = message.plainText, !plain.isEmpty {
                    Text(plain)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .textSelection(.enabled)
                } else {
                    Text("No content")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.mutedText)
                        .italic()
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }

                // Attachments
                if let attachments = message.attachments, !attachments.isEmpty {
                    attachmentsView(attachments)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                }
            }
        }
        .task(id: isExpanded) {
            // Defer WKWebView creation just enough that the row first renders with plain
            // text, then swaps in the full HTML rendering. A short delay also gives
            // SwiftUI a chance to commit the row's frame before the WebView lays itself out.
            if isExpanded && !htmlReady && !message.body.isEmpty {
                try? await Task.sleep(for: .milliseconds(40))
                withAnimation(.easeIn(duration: 0.15)) { htmlReady = true }
            }
        }
    }

    // MARK: - Details Card

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            detailRow(label: "From", value: message.from.name, secondary: message.from.email)
            Divider().foregroundStyle(AppTheme.divider).padding(.leading, 12)
            if let first = message.to.first {
                detailRow(label: "To", value: first.name, secondary: first.email)
                Divider().foregroundStyle(AppTheme.divider).padding(.leading, 12)
            }
            detailRow(label: "Date", value: message.date.formatted(date: .long, time: .shortened), secondary: nil)
        }
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                .stroke(AppTheme.rowStroke, lineWidth: 1)
        )
    }

    private func detailRow(label: String, value: String, secondary: String?) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.mutedText)
                .frame(width: 36, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let secondary {
                Spacer(minLength: 4)
                Text(secondary)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - Attachments

    private func attachmentsView(_ attachments: [EmailAttachment]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(attachments) { attachment in
                HStack(spacing: 10) {
                    // File type icon
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(attachmentColor(for: attachment.mimeType))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Text(attachmentLabel(for: attachment.mimeType))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.filename)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(formatSize(attachment.size))
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.mutedText)
                    }
                    Spacer()
                }
                .padding(10)
                .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                        .stroke(AppTheme.rowStroke, lineWidth: 1)
                )
            }
        }
    }

    private func attachmentColor(for mimeType: String) -> Color {
        if mimeType.contains("pdf") { return .red }
        if mimeType.contains("image") { return .primary }
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

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}

// MARK: - Expanding HTML View

private struct ExpandingEmailHTMLView: View {
    let html: String
    let darkMode: Bool
    @State private var height: CGFloat = 200

    var body: some View {
        EmailHTMLView(html: html, height: $height, darkMode: darkMode)
            // Clamp the rendered frame as a defense-in-depth — even if measureHeight
            // somehow writes a huge value, the SwiftUI layout stays sane.
            .frame(height: max(min(height, 20_000), 1))
            // Clip rounded corners — the email CSS sets its own background color.
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
            .animation(.easeInOut(duration: 0.2), value: darkMode)
    }
}

// MARK: - HTML WebView

struct EmailHTMLView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat
    let darkMode: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.dataDetectorTypes = [.link, .phoneNumber]
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard
            context.coordinator.lastLoadedHTML != html
                || context.coordinator.lastDarkMode != darkMode
        else { return }
        context.coordinator.lastLoadedHTML = html
        context.coordinator.lastDarkMode = darkMode
        webView.loadHTMLString(wrappedHTML, baseURL: nil)
    }

    /// Each MessageRow created its own WKWebView (and a strong-referenced coordinator).
    /// Without explicit teardown the webview, its delegate, and any outstanding
    /// JavaScript evaluation continue to live on after the host view disappears,
    /// leaking memory in long threads. Stop loading and detach the navigation
    /// delegate so the webview can be deallocated promptly.
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        coordinator.webView = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private var wrappedHTML: String {
        darkMode ? darkWrappedHTML : lightWrappedHTML
    }

    /// Default render. Email HTML is authored for light backgrounds — preserve the
    /// sender's own colors, force the WebView into a light color-scheme, and let
    /// the SwiftUI parent draw a white card around it. Mirrors Gmail/Apple Mail/Notion.
    private var lightWrappedHTML: String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <meta name="color-scheme" content="only light">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src * data: blob:; style-src 'unsafe-inline'; script-src 'none'; font-src *;">
        <style>
            :root { color-scheme: only light; }
            * { box-sizing: border-box; max-width: 100%; }
            html, body { margin: 0; padding: 0; overflow-x: hidden; max-width: 100vw; }
            body {
                font-family: -apple-system, system-ui, sans-serif;
                font-size: 15px; line-height: 1.6;
                color: #1a1a1a; background: #ffffff;
                word-wrap: break-word; overflow-wrap: break-word;
                padding: 14px 16px;
            }
            a { color: #1a73e8; word-break: break-word; }
            img { max-width: 100% !important; height: auto !important; }
            pre, code { overflow-x: auto; max-width: 100%; white-space: pre-wrap; word-break: break-word; }
            blockquote { border-left: 2px solid #ddd; margin: 8px 0; padding-left: 12px; color: #666; }
            /* Transactional emails ship fixed-width tables (often 600px). Force them to
               collapse and scroll horizontally rather than overflowing the card edge. */
            table { max-width: 100% !important; display: block; overflow-x: auto; -webkit-overflow-scrolling: touch; }
            /* Defeat width="..." HTML attributes that bypass max-width CSS rules. */
            *[width], *[height] { max-width: 100% !important; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
    }

    /// Opt-in dark render. Strips email backgrounds, forces a uniform light text
    /// color over the dark app surface, and falls back to a safe link color.
    /// Sender-defined text colors are overridden across the common email tag set.
    private var darkWrappedHTML: String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <meta name="color-scheme" content="only dark">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src * data: blob:; style-src 'unsafe-inline'; script-src 'none'; font-src *;">
        <style>
            :root { color-scheme: only dark; }
            * { box-sizing: border-box; max-width: 100%; }
            html, body { margin: 0; padding: 0; overflow-x: hidden; max-width: 100vw; }
            body {
                font-family: -apple-system, system-ui, sans-serif;
                font-size: 15px; line-height: 1.6;
                color: #e0e0e0; background: transparent;
                word-wrap: break-word; overflow-wrap: break-word;
            }
            * { background-color: transparent !important; background-image: none !important; }
            body, body *:not(a):not(img):not(svg):not(picture):not(video):not(button) {
                color: #e0e0e0 !important;
            }
            a { color: #5B9FFF !important; word-break: break-word; }
            img { max-width: 100% !important; height: auto !important; }
            pre, code { overflow-x: auto; max-width: 100%; white-space: pre-wrap; word-break: break-word; }
            blockquote { border-left: 2px solid #555 !important; margin: 8px 0; padding-left: 12px; color: #aaa !important; }
            table { max-width: 100% !important; display: block; overflow-x: auto; -webkit-overflow-scrolling: touch; }
            *[width], *[height] { max-width: 100% !important; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: EmailHTMLView
        weak var webView: WKWebView?
        var lastLoadedHTML: String?
        var lastDarkMode: Bool?

        init(_ parent: EmailHTMLView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            measureHeight(in: webView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak webView, weak self] in
                guard let webView, let self else { return }
                self.measureHeight(in: webView)
            }
        }

        private func measureHeight(in webView: WKWebView) {
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { [weak self, weak webView] result, error in
                guard let self, webView != nil, error == nil else { return }
                let h: CGFloat
                if let v = result as? CGFloat { h = v }
                else if let v = result as? Double { h = CGFloat(v) }
                else if let v = result as? Int { h = CGFloat(v) }
                else { return }
                // Clamp pathological heights — a 50,000pt scroll view can crash the
                // hosting List on weak devices and provides no real benefit (users
                // can't meaningfully scroll a single message that tall inside a thread).
                let clamped = min(max(h, 0), 20_000)
                guard clamped > 0, clamped.isFinite else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    // Avoid no-op writes that still trigger SwiftUI invalidation.
                    if abs(self.parent.height - clamped) > 0.5 {
                        self.parent.height = clamped
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                await UIApplication.shared.open(url)
                return .cancel
            }
            return .allow
        }
    }
}

// MARK: - Header capsule glass

private extension View {
    /// Liquid Glass capsule on iOS 26; ultraThinMaterial + stroke on earlier OS.
    @ViewBuilder
    func headerCapsuleGlass() -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).stroke(AppTheme.cardBorder.opacity(0.5), lineWidth: 0.5))
        }
    }
}
