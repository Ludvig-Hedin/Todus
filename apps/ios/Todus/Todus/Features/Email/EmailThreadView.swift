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
    /// Time of the last successful assistant context load (API does not return `generatedAt` per thread).
    @State private var assistantContextLoadedAt: Date?
    @State private var isLoadingAssistant = true
    /// Separate from `isLoadingAssistant` so retrying from the failure UI keeps the error
    /// state visible with an inline spinner rather than swapping back to the skeleton loader.
    @State private var isRetryingAssistant = false
    @State private var assistantDraftSeed: String? = nil
    @State private var showDeleteConfirmation = false
    @State private var assistantNotice: String?
    @State private var isSummarizing = false
    /// Scroll offset drives the scroll-aware header title
    @State private var scrollOffset: CGFloat = 0
    @State private var showLabelEditor = false
    @State private var showReminderOptions = false
    @State private var reminderNotice: String?
    /// Shown when a destructive thread action fails (delete, etc.).
    /// Surfacing the error keeps the user on the thread view so they can retry.
    @State private var actionErrorMessage: String?
    /// Tracks whether AI summary load attempted but failed (no thread, not loading).
    /// Used to render a "Summary unavailable" error state with retry.
    @State private var assistantLoadFailed = false

    private var emailService: EmailService { services.emailService }

    /// Subject shown in collapsed header when user has scrolled past the title row
    private var subjectForHeader: String {
        detail?.messages.first?.subject ?? ""
    }
    private var showTitleInHeader: Bool { scrollOffset > 90 }

    /// Footer line under the summary card — uses load time because `AssistantThreadContext` has no server timestamp.
    private var assistantAttributionLine: String {
        guard assistantThread != nil else { return "Ai" }
        if let loaded = assistantContextLoadedAt {
            return "Ai · \(loaded.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Ai"
    }

    enum ComposeMode { case reply, replyAll, forward }

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
                ProgressView().tint(.secondary)
            } else if let detail, !detail.messages.isEmpty {
                mainContent(detail)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(AppTheme.mutedText)
                    Text("Could not load thread")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.subtleText)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .background { SwipeBackEnabler() }
        .onAppear { services.hideTabBar = true }
        .onDisappear {
            services.hideTabBar = false
            // Clear thread context so the next AI-sheet open from a non-thread
            // tab doesn't leak the previous subject into the context pill.
            services.aiChatService.currentThreadSubject = nil
            services.aiChatService.currentThreadId = nil
        }
        .task { await loadThread() }
        .sheet(isPresented: $showCompose) {
            if let lastMessage = detail?.messages.last {
                EmailComposeView(replyTo: lastMessage, threadId: threadId, body: assistantDraftSeed)
                    .preferredColorScheme(services.appearancePreference.colorScheme)
            }
        }
        .sheet(isPresented: $showLabelEditor) {
            EditLabelsSheet(
                threadId: threadId,
                appliedLabels: detail?.labels ?? [],
                onChange: { Task { await loadThread() } }
            )
            .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        .alert("Mail Assistant", isPresented: Binding(
            get: { assistantNotice != nil },
            set: { if !$0 { assistantNotice = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(assistantNotice ?? "") }
        .alert("Reminder Set", isPresented: Binding(
            get: { reminderNotice != nil },
            set: { if !$0 { reminderNotice = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(reminderNotice ?? "") }
        // Surface delete/move-to-trash failures inline so the user knows nothing
        // happened — previously the API failure was silently swallowed and the view dismissed.
        .alert("Couldn't move to Trash", isPresented: Binding(
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

                Spacer()

                // Grouped action icons in a single glass capsule:
                //   archive · mark-as-unread · delete · more (ellipsis menu)
                // The Ask AI button was removed — the global AI FAB stays visible
                // above the reply bar for thread-level questions.
                HStack(spacing: 0) {
                    Button {
                        Task { await emailService.markAsUnread(ids: [threadId]); dismiss() }
                    } label: {
                        Image(systemName: "envelope.badge")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 42, height: 38)
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await emailService.archiveThreads(ids: [threadId]); dismiss() }
                    } label: {
                        Image(systemName: "archivebox")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 42, height: 38)
                    }
                    .buttonStyle(.plain)

                    Button { showDeleteConfirmation = true } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppTheme.danger)
                            .frame(width: 42, height: 38)
                    }
                    .buttonStyle(.plain)

                    moreOptionsMenu
                }
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).stroke(AppTheme.cardBorder.opacity(0.5), lineWidth: 0.5))
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
        .padding(.horizontal, 12)
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

                // AI Summary card
                if services.assistantAutomationPolicy.assistantThreadActionsVisible {
                    summaryCard
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }

                // Contextual action buttons — only show buttons relevant to this thread
                if services.assistantAutomationPolicy.assistantThreadActionsVisible &&
                   (assistantThread != nil || isLoadingAssistant) {
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
        HStack(alignment: .top, spacing: 12) {
            // Show an em dash for missing subjects — feels less like an error state
            // than the parenthetical "(no subject)" placeholder.
            Text(threadSubjectDisplay(detail))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            // Star button to the right of the subject
            Button {
                isStarred.toggle()
                Task { await emailService.toggleStar(ids: [threadId]) }
            } label: {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(isStarred ? Color.yellow : AppTheme.mutedText)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    // MARK: - AI Summary Card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)

            if isLoadingAssistant && !assistantLoadFailed {
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).fill(AppTheme.surfaceSecondary).frame(height: 13).frame(maxWidth: .infinity)
                    RoundedRectangle(cornerRadius: 4).fill(AppTheme.surfaceSecondary).frame(height: 13).frame(maxWidth: 220)
                }
            } else if let a = assistantThread {
                Text(a.recommendation.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
                    .textCase(.uppercase)

                // Summary text — capped at 3 lines to keep it concise
                if !a.summary.isEmpty {
                    Text(a.summary)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.subtleText)
                        .lineLimit(3)
                }

                // Action items as compact bullets (max 3)
                if !a.actionItems.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(a.actionItems.prefix(3), id: \.self) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Text("·")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(AppTheme.mutedText)
                                Text(item)
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppTheme.subtleText)
                                    .lineLimit(2)
                            }
                        }
                    }
                }

                // Low-confidence note — only when really uncertain
                if a.confidence < 0.4, !a.reason.isEmpty {
                    Text(a.reason)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.mutedText)
                        .lineLimit(2)
                }

                if let person = a.people.first {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(person.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(person.relationshipSummary)
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.mutedText)
                            .lineLimit(2)
                    }
                }

                if !a.changedSinceLastOpen.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(a.changedSinceLastOpen.prefix(2), id: \.self) { item in
                            Text(item)
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.mutedText)
                                .lineLimit(2)
                        }
                    }
                }
            } else if assistantLoadFailed {
                // Summary load attempted and failed — show an explicit error state with a
                // small retry tap target so the user can recover without leaving the thread.
                Text("Summary unavailable")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.mutedText)

                Button {
                    Task {
                        isRetryingAssistant = true
                        defer { isRetryingAssistant = false }
                        await refreshAssistant()
                    }
                } label: {
                    HStack(spacing: 5) {
                        if isRetryingAssistant {
                            ButtonInlineProgressView(tint: AppTheme.mutedText, side: AppTheme.Metrics.compactInlineSpinner)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppTheme.mutedText)
                        }
                        Text(isRetryingAssistant ? "Retrying…" : "Retry")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                            .stroke(AppTheme.rowStroke, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRetryingAssistant)
            } else {
                // No summary yet — show prompt and summarize button
                Text("Not summarized yet")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.mutedText)

                Button {
                    Task { await handleSummarize() }
                } label: {
                    HStack(spacing: 5) {
                        if isSummarizing {
                            ButtonInlineProgressView(tint: AppTheme.mutedText, side: AppTheme.Metrics.compactInlineSpinner)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(aiGradient)
                        }
                        Text(isSummarizing ? "Summarizing…" : "Summarize")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                            .stroke(AppTheme.rowStroke, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSummarizing)
            }

            // AI attribution line
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tint)
                Text(assistantAttributionLine)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.mutedText)
            }
        }
        .padding(14)
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
                // Contextual buttons based on AI analysis flags:

                // Extract tasks — only when AI found extractable tasks
                if let a = assistantThread, !a.suggestedTasks.isEmpty {
                    ThreadActionButton(
                        label: "Extract task",
                        icon: "checklist",
                        isPrimary: true
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
                        isPrimary: a.replyNeeded
                    ) {
                        Task { await handleDraftReply() }
                    }
                }

                // Book follow-up — only when AI detected follow-up needed
                if let a = assistantThread, a.followUpNeeded {
                    ThreadActionButton(label: "Book follow-up", icon: "calendar.badge.plus") {
                        Task {
                            let subject = detail?.messages.first?.subject ?? "Email"
                            await handleCreateTask(MailAssistantSuggestedTask(
                                title: "Follow up: \(subject)",
                                description: nil,
                                priority: "medium",
                                dueDate: nil
                            ))
                        }
                    }
                }

                // Create event — only when AI detected a meeting request
                if let a = assistantThread, a.meetingRequested, a.suggestedEvent != nil {
                    ThreadActionButton(label: "Create event", icon: "calendar.badge.plus") {
                        Task { await handleCreateEvent() }
                    }
                }

                // Ask AI — always available as a fallback action
                ThreadActionButton(label: "Ask AI", icon: "sparkles") {
                    openAssistant()
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
                MessageRow(message: message, expandByDefault: index == detail.messages.count - 1)

                if index < detail.messages.count - 1 {
                    Divider()
                        .foregroundStyle(AppTheme.divider)
                        .padding(.leading, 16 + 36 + 10)
                }
            }
        }
        // Card background so the conversation reads as a single grouped surface in
        // both light and dark mode. Light: white card on muted gray app bg. Dark:
        // subtle lift over the near-black background.
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(AppTheme.rowStroke, lineWidth: 1)
        )
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
        }
    }

    // MARK: - Bottom Bar
    // Free-floating reply buttons — no solid fill, only a smooth gradient
    // that fades content out behind the buttons.

    private var bottomBar: some View {
        HStack(spacing: 8) {
            ForEach([
                ("arrowshape.turn.up.left", "Reply"),
                ("arrowshape.turn.up.left.2", "Reply all"),
                ("arrowshape.turn.up.right", "Forward")
            ], id: \.1) { icon, label in
                Button {
                    composeMode = label == "Reply" ? .reply : label == "Reply all" ? .replyAll : .forward
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
        // Run the thread fetch, the assistant context fetch, and markAsRead in parallel.
        // Previously the assistant call only started after the thread had returned, doubling
        // the time-to-summary. With Gmail's API + Cloudflare round-trip both calls together
        // are roughly the same wall-clock as either one in isolation.
        async let threadDetail = emailService.loadThread(id: threadId)
        async let assistant = emailService.loadAssistant(threadId: threadId)
        async let markRead: Void = emailService.markAsRead(ids: [threadId])

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
        await markRead
    }

    private func refreshAssistant() async {
        isLoadingAssistant = true
        let resolved = await emailService.loadAssistant(threadId: threadId)
        applyAssistantContext(resolved)
        assistantLoadFailed = resolved == nil
        isLoadingAssistant = false
    }

    /// Updates assistant state and stamps load time whenever a non-nil context is received.
    private func applyAssistantContext(_ value: AssistantThreadContext?) {
        assistantThread = value
        if value != nil {
            assistantContextLoadedAt = Date()
        }
    }

    private func handleCreateTask(_ suggestion: MailAssistantSuggestedTask) async {
        let success = await emailService.createAssistantTask(threadId: threadId, suggestion: suggestion)
        assistantNotice = success ? "Task created." : "Could not create the task."
        if success { await refreshAssistant() }
    }

    private func handleCreateEvent() async {
        guard let event = assistantThread?.suggestedEvent else {
            assistantNotice = "No event suggestion available."
            return
        }
        let success = await emailService.createAssistantEvent(threadId: threadId, suggestion: event)
        assistantNotice = success ? "Calendar event created." : "Could not create the event."
        if success { await refreshAssistant() }
    }

    private func handleDraftReply() async {
        guard let result = await emailService.generateAssistantDraft(threadId: threadId) else {
            assistantNotice = "Could not generate a draft."
            return
        }
        if result.created {
            assistantDraftSeed = result.preview
            composeMode = .reply
            showCompose = true
            await refreshAssistant()
        } else {
            assistantNotice = result.reason.isEmpty ? "Draft already exists or was skipped." : result.reason
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
            assistantNotice = "Could not generate summary: \(error.localizedDescription)"
        }
        isSummarizing = false
    }

    private func openAssistant() {
        services.currentTab = .email
        let subject = detail?.messages.first?.subject ?? "Message"
        services.aiChatService.currentPageContext = "Email thread: \(subject)"
        services.aiChatService.currentThreadSubject = subject
        services.aiChatService.currentThreadId = threadId
        services.showsAIChat = true
    }

    // MARK: - More Options Menu (ellipsis in header capsule)

    private var moreOptionsMenu: some View {
        Menu {
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
                        await emailService.markAsSpam(ids: [threadId])
                        dismiss()
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
            reminderNotice = "We'll remind you on \(remindAt.formatted(date: .abbreviated, time: .shortened))."
        } else {
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
                    ProgressView().tint(.secondary)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isPrimary ? AppTheme.backgroundTop : Color.primary)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.card + 2, style: .continuous)
                    .fill(isPrimary ? Color.primary : AppTheme.surfacePrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.card + 2, style: .continuous)
                    .stroke(isPrimary ? Color.clear : AppTheme.rowStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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

    @State private var isExpanded: Bool
    @State private var showDetails = false
    /// Defers WKWebView creation to avoid blocking the main thread on navigation
    @State private var htmlReady = false

    init(message: EmailMessage, expandByDefault: Bool) {
        self.message = message
        self.expandByDefault = expandByDefault
        self._isExpanded = State(initialValue: expandByDefault)
    }

    private var toNames: String {
        message.to.prefix(2).map(\.name).joined(separator: ", ")
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

                            Text(message.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.mutedText)
                        }

                        if !isExpanded {
                            // Collapsed preview snippet
                            Text(message.plainText ?? message.subject)
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.mutedText)
                                .lineLimit(1)
                        } else {
                            // "To: names" row — tap to toggle details card
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
                        ExpandingEmailHTMLView(html: message.body)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
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
    @State private var height: CGFloat = 200

    var body: some View {
        EmailHTMLView(html: html, height: $height)
            // Clamp the rendered frame as a defense-in-depth — even if measureHeight
            // somehow writes a huge value, the SwiftUI layout stays sane.
            .frame(height: max(min(height, 20_000), 1))
    }
}

// MARK: - HTML WebView

struct EmailHTMLView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat

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
        guard context.coordinator.lastLoadedHTML != html else { return }
        context.coordinator.lastLoadedHTML = html
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
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src * data: blob:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; font-src *;">
        <style>
            * { box-sizing: border-box; }
            html, body { margin: 0; padding: 0; overflow-x: hidden; }
            body {
                font-family: -apple-system, system-ui, sans-serif;
                font-size: 15px; line-height: 1.6;
                color: #e0e0e0; background: transparent;
                word-wrap: break-word; overflow-wrap: break-word;
            }
            /* Dark mode: strip all background colors, force readable text */
            @media (prefers-color-scheme: dark) {
                * { background-color: transparent !important; }
                body, div, span, p, td, th, li, dd, dt, h1, h2, h3, h4, h5, h6,
                label, strong, em, b, i, u, small, big, sub, sup, center, font {
                    color: #e0e0e0 !important;
                }
                a { color: #5B9FFF !important; }
                blockquote { color: #aaa !important; border-left-color: #555 !important; }
            }
            @media (prefers-color-scheme: light) { body { color: #1a1a1a; } }
            a { color: #5B9FFF; }
            img { max-width: 100% !important; height: auto !important; }
            pre, code { overflow-x: auto; max-width: 100%; white-space: pre-wrap; }
            blockquote { border-left: 2px solid #555; margin: 8px 0; padding-left: 12px; color: #888; }
            table { max-width: 100%; display: block; overflow-x: auto; }
        </style>
        </head>
        <body>\(html)
        <script>
        // Strip bgcolor HTML attributes that CSS can't override
        document.querySelectorAll('[bgcolor]').forEach(function(el) { el.removeAttribute('bgcolor'); });
        </script>
        </html>
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: EmailHTMLView
        weak var webView: WKWebView?
        var lastLoadedHTML: String?

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
