import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation
import Speech

// MARK: - AIChatView

/// Full-screen chat sheet. Streams AI responses with live markdown rendering and typewriter animation.
/// Supports task read/write via tool calls. History and model config accessible from toolbar.
struct AIChatView: View {
    /// The tab the user was on when they opened the AI sheet — pre-fills the context pill.
    var currentTab: AppTab = .home

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    @Query(sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]

    @State private var inputText = ""
    @State private var inputMentions: [RichInputMentionRef] = []
    @State private var eventMentions: [RichInputMentionRef] = []
    @FocusState private var isInputFocused: Bool

    /// Page context pill — name + icon auto-set from currentTab, user can remove it.
    @State private var pageContextAttached = true

    // Sheet presentation states
    @State private var showsHistory = false
    @State private var showsConfig = false
    @State private var showsDataSheet = false
    @State private var showsDeleteConfirm = false
    @State private var showsRenameAlert = false
    @State private var renameText = ""
    @State private var showsPromptLibrary = false

    // Suggestion expansion — "Show more" / "Refresh" / "Back"
    @State private var suggestionsExpanded = false
    @State private var suggestionSeed = 0   // changing this shuffles the extended pool

    // Attachment state — native confirmationDialog triggers individual system pickers
    @State private var isPickingAttachment = false
    @State private var isShowingPhotoPicker = false
    @State private var isShowingCamera = false
    @State private var isShowingFilePicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pendingAttachments: [String] = []

    // Live voice chat
    @State private var showVoiceChat = false

    // Animated thinking text cycles while streaming
    @State private var thinkingIndex = 0
    private let thinkingPhrases = ["Thinking", "Reading tasks", "Searching", "Writing"]

    private var chatService: AIChatService { services.aiChatService }

    /// AI gradient — matches the tab bar sparkles icon exactly
    private var aiGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0, green: 0xAA/255.0, blue: 0xF5/255.0), location: 0.087),
                .init(color: Color(red: 0xEF/255.0, green: 0, blue: 0xC2/255.0), location: 0.269),
                .init(color: Color(red: 1, green: 0, blue: 0x38/255.0), location: 0.580),
                .init(color: Color(red: 0xF9/255.0, green: 0x9F/255.0, blue: 0), location: 0.913),
            ],
            startPoint: UnitPoint(x: 0.25, y: 0),
            endPoint: UnitPoint(x: 0.75, y: 1)
        )
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AppTheme.backgroundTop.ignoresSafeArea()

                // Dismiss attachment picker panel by tapping anywhere in the chat area
                if isPickingAttachment {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.snappy(duration: 0.15)) { isPickingAttachment = false }
                        }
                }

                if chatService.messages.isEmpty {
                    // Show error state when backend is unreachable and no conversation exists
                    if let error = chatService.errorMessage, !chatService.isStreaming {
                        self.aiUnreachableView(error: error)
                            .transition(AnyTransition.opacity)
                    } else {
                        emptyStateView
                            .transition(AnyTransition.opacity)
                    }
                } else {
                    conversationView
                        .transition(AnyTransition.opacity)
                }
            }
            // Top gradient fade — same height as header buttons, fades content below toolbar
            .safeAreaInset(edge: .top) {
                LinearGradient(
                    colors: [AppTheme.backgroundTop.opacity(0.5), AppTheme.backgroundTop.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 12)
                .allowsHitTesting(false)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .sheet(isPresented: $showsHistory) {
            ChatHistoryView()
                .presentationDragIndicator(.visible)
                .presentationBackground(AppTheme.backgroundTop)
        }
        .sheet(isPresented: $showsConfig) {
            AIChatConfigSheet()
                .presentationDragIndicator(.visible)
        }
        // Prompt library — presets + user-saved prompts
        .sheet(isPresented: $showsPromptLibrary) {
            PromptLibrarySheet(onSelect: { prompt in
                inputText = prompt.text
                showsPromptLibrary = false
            })
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(AppTheme.backgroundTop)
        }
        // Conversation data sheet — shows token usage, cost, message stats
        .sheet(isPresented: $showsDataSheet) {
            ConversationDataSheet(stats: conversationStats)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(AppTheme.backgroundTop)
        }
        // Delete confirmation dialog
        .confirmationDialog("Delete this conversation?", isPresented: $showsDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteConversation() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will clear all messages. This action cannot be undone.")
        }
        // Rename alert
        .alert("Rename Conversation", isPresented: $showsRenameAlert) {
            TextField("Title", text: $renameText)
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { chatService.chatTitle = trimmed }
            }
            Button("Cancel", role: .cancel) {}
        }
        // Attachment pickers — triggered by custom panel (not system confirmationDialog)
        .photosPicker(isPresented: $isShowingPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url) {
                    let ext = url.pathExtension.isEmpty ? "dat" : url.pathExtension
                    if let filename = AttachmentService.shared.saveData(data, fileExtension: ext) {
                        pendingAttachments.append(filename)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { image in
                if let image, let filename = AttachmentService.shared.saveImage(image) {
                    pendingAttachments.append(filename)
                }
            }
            .ignoresSafeArea()
        }
        // Live voice chat modal — presented from the waveform button in the input bar
        .fullScreenCover(isPresented: $showVoiceChat) {
            VoiceChatModalView(
                chatService: chatService,
                tokenService: services.voiceTokenService
            )
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data),
                   let filename = AttachmentService.shared.saveImage(uiImage) {
                    pendingAttachments.append(filename)
                }
            }
            selectedPhotoItem = nil
        }
        .animation(.snappy(duration: 0.22), value: chatService.messages.count)
        // Live-save draft input so it survives app kills too
        .onChange(of: inputText) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: "ai_draft_input")
        }
        // Cycle thinking text while streaming
        .task(id: chatService.isStreaming) {
            guard chatService.isStreaming else { return }
            thinkingIndex = 0
            while !Task.isCancelled && chatService.isStreaming {
                try? await Task.sleep(for: .seconds(2))
                thinkingIndex = (thinkingIndex + 1) % thinkingPhrases.count
            }
        }
        // Auto-save conversation when the sheet is dismissed without pressing "New Chat"
        .onDisappear {
            chatService.autosave()
            // Persist draft input across dismissals
            UserDefaults.standard.set(inputText, forKey: "ai_draft_input")
        }
        .onAppear {
            // Restore draft input
            let draft = UserDefaults.standard.string(forKey: "ai_draft_input") ?? ""
            if inputText.isEmpty { inputText = draft }
            // Re-attach context pill when sheet re-opens
            pageContextAttached = true
            loadEventMentions()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // History button — always visible
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showsHistory = true
            } label: {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
        }

        // Chat title (or app name when empty)
        ToolbarItem(placement: .principal) {
            Text(chatService.chatTitle ?? "AI Assistant")
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.2)
                .lineLimit(1)
                .frame(maxWidth: 200)
        }

        // New chat + options menu — trailing
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 16) {
                // New chat button
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        chatService.clearHistory()
                    }
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                // Ellipsis menu — conversation actions
                Menu {
                    // Rename
                    Button {
                        renameText = chatService.chatTitle ?? ""
                        showsRenameAlert = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    // Copy conversation
                    Button {
                        copyConversation()
                    } label: {
                        Label("Copy Conversation", systemImage: "doc.on.doc")
                    }

                    // Duplicate chat
                    Button {
                        duplicateChat()
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }

                    // Share
                    Button {
                        shareConversation()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }

                    // View data
                    Button {
                        showsDataSheet = true
                    } label: {
                        Label("View Data", systemImage: "chart.bar")
                    }

                    Divider()

                    // Delete — destructive
                    Button(role: .destructive) {
                        showsDeleteConfirm = true
                    } label: {
                        Label("Delete Conversation", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    // MARK: - AI Unreachable State

    /// Shown when the backend is unreachable and no conversation exists yet.
    private func aiUnreachableView(error: String) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppTheme.subtleText)

            VStack(spacing: 8) {
                Text("Can't reach the assistant")
                    .font(.system(size: 20, weight: .bold))

                Text("Check your connection and try again.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                // Actually retry the last message instead of just clearing the error
                chatService.retry(allTasks: Array(allTasks), modelContext: modelContext)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Retry")
                        .font(.system(size: 15, weight: .semibold))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    // Sparkles icon — matches tab bar: same size, same gradient, no circle
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(aiGradient)

                    Text("How can I help you today?")
                        .font(.system(size: 20, weight: .semibold))
                        .tracking(-0.3)
                }
                .padding(.horizontal, 16)

                // Suggestions — 3 default, up to 10 when expanded
                VStack(alignment: .leading, spacing: 0) {
                    let pool = contextualSuggestionsPool
                    let shown = suggestionsExpanded ? pool : Array(pool.prefix(3))

                    ForEach(shown, id: \.text) { suggestion in
                        suggestionRow(icon: suggestion.icon, text: suggestion.text)
                    }

                    // Show more / controls row
                    if suggestionsExpanded {
                        HStack(spacing: 16) {
                            // Back / collapse
                            Button {
                                withAnimation(.snappy(duration: 0.2)) { suggestionsExpanded = false }
                            } label: {
                                Label("Show less", systemImage: "chevron.up")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AppTheme.mutedText)
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            // Refresh — shuffle extended suggestions
                            Button {
                                withAnimation(.snappy(duration: 0.15)) { suggestionSeed += 1 }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AppTheme.mutedText)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    } else if pool.count > 3 {
                        // Show more button
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { suggestionsExpanded = true }
                        } label: {
                            Text("Show more")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppTheme.mutedText)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }

                    // Prompt library link
                    Button {
                        showsPromptLibrary = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bookmark")
                                .font(.system(size: 12, weight: .medium))
                            Text("Prompt library")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(AppTheme.mutedText)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }
                .padding(.horizontal, 8)
            }

            Spacer()

            inputSection
                .padding(.horizontal, 8)
                .padding(.bottom, 8)   // gap above keyboard on empty state
        }
    }

    /// Full pool of up to 10 context-aware suggestions. First 3 are shown by default.
    /// `suggestionSeed` drives shuffling of the extended 4–10 slots on Refresh.
    private var contextualSuggestionsPool: [(icon: String, text: String)] {
        let activeCount = allTasks.filter { !$0.completed }.count

        // First 3: always shown (pinned), context-sensitive
        let pinned: [(icon: String, text: String)]
        // Extended pool (slots 4-10): shuffled with seed
        let extended: [(icon: String, text: String)]

        switch currentTab {
        case .email:
            pinned = [
                ("envelope.open",              "Summarize my recent emails"),
                ("arrowshape.turn.up.left",    "Draft a reply to my latest email"),
                ("tray.and.arrow.down",        "Help me triage my inbox"),
            ]
            extended = [
                ("doc.text.magnifyingglass",   "What emails need my attention today?"),
                ("envelope.badge.person.crop", "Write a cold outreach email to a new lead"),
                ("archivebox",                 "Archive everything older than a week"),
                ("star",                       "Which emails are most important right now?"),
                ("paperplane",                 "Draft a follow-up to my last sent email"),
                ("flag",                       "Show me emails I've flagged or starred"),
                ("magnifyingglass",            "Search for emails about a specific topic"),
            ]
        case .calendar:
            pinned = [
                ("clock",                      "What's on my calendar today?"),
                ("calendar.badge.plus",        "Find free focus time this week"),
                ("person.2",                   "Help me schedule a meeting"),
            ]
            extended = [
                ("brain.head.profile",         "Create deep work blocks on my calendar tomorrow"),
                ("calendar",                   "Give me a full overview of this week"),
                ("moon.stars",                 "Block time tomorrow morning for planning"),
                ("calendar.badge.exclamationmark", "Do I have any scheduling conflicts?"),
                ("clock.badge.checkmark",      "When is my next free 2-hour window?"),
                ("person.badge.plus",          "Help me prepare for my next meeting"),
                ("sun.max",                    "Plan my ideal workday schedule"),
            ]
        case .tasks:
            if activeCount == 0 {
                pinned = [
                    ("plus.circle",            "Create my first tasks for today"),
                    ("sparkle",                "Brainstorm ideas for what to work on"),
                    ("list.bullet",            "Help me plan my week"),
                ]
            } else if activeCount <= 20 {
                pinned = [
                    ("arrow.up.circle",        "What should I prioritize today?"),
                    ("list.bullet.indent",     "Break down my biggest task into steps"),
                    ("checklist",              "Review my \(activeCount) open tasks"),
                ]
            } else {
                pinned = [
                    ("checkmark.circle",       "Help me clear my task backlog"),
                    ("arrow.up.circle",        "What are my top 3 priorities?"),
                    ("trash",                  "Review and remove stale tasks"),
                ]
            }
            extended = [
                ("flag.fill",                  "Set priority on all my tasks"),
                ("calendar.badge.checkmark",   "Which tasks have deadlines this week?"),
                ("exclamationmark.circle",     "Show me all overdue tasks"),
                ("folder.badge.plus",          "Organize my tasks into folders"),
                ("moon.zzz",                   "Plan tomorrow and wind down my day"),
                ("chart.bar",                  "How productive have I been this week?"),
                ("pencil",                     "Rename or update outdated tasks"),
            ]
        case .home:
            pinned = [
                ("sun.max",                    "Give me a morning briefing"),
                ("sparkle",                    "What should I focus on right now?"),
                ("calendar.badge.checkmark",   "Triage my tasks and calendar for today"),
            ]
            extended = [
                ("moon.stars",                 "End-of-day review — what did I accomplish?"),
                ("chart.line.uptrend.xyaxis",  "Weekly retrospective — what went well?"),
                ("flag",                       "What are my top priorities this week?"),
                ("rocket",                     "Help me kick off a new project"),
                ("envelope.open",              "Any important emails I should handle first?"),
                ("brain.head.profile",         "Block focus time and clear my schedule"),
                ("person.2",                   "Help me coordinate with my team today"),
            ]
        }

        // Shuffle the extended pool with the current seed so Refresh shows new ones
        let shuffled = extended.shuffled(seed: suggestionSeed)
        return pinned + Array(shuffled.prefix(7)) // total cap of 10
    }

    private func suggestionRow(icon: String, text: String) -> some View {
        Button {
            inputText = text
            sendMessage()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(width: 20)
                Text(text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Conversation View

    private var conversationView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(chatService.messages) { message in
                        MessageBubble(
                            message: message,
                            allTasks: Array(allTasks),
                            onNavigate: { action, params in
                                handleCardNavigation(action, params: params)
                            }
                        )
                            .id(message.id)
                    }

                    // "Thinking…" indicator while streaming and before first token
                    if chatService.isStreaming,
                       chatService.messages.last?.content.isEmpty == true {
                        thinkingIndicator
                            .id("thinking")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively)
            // Pin input section directly above keyboard — 8 pt gap above keyboard for breathing room
            .safeAreaInset(edge: .bottom) {
                inputSection
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 12)   // match side spacing for consistent inset from screen edge
                    .background(AppTheme.backgroundTop.ignoresSafeArea(edges: .bottom))
            }
            .onChange(of: chatService.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: chatService.messages.last?.content) { _, _ in
                if let lastID = chatService.messages.last?.id {
                    withAnimation(.linear(duration: 0.05)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
            // Scroll when web search sources arrive (changes message height)
            .onChange(of: chatService.messages.last?.sources.count) { _, _ in
                if let lastID = chatService.messages.last?.id {
                    withAnimation(.snappy(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Thinking Indicator

    private var thinkingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.75)
                .tint(AppTheme.mutedText)

            Text(thinkingPhrases[thinkingIndex % thinkingPhrases.count])
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
                .id(thinkingIndex)  // force re-render so transition fires
                .transition(.opacity)
        }
        .padding(.leading, 4)
    }

    // MARK: - Input Section
    // Layout mirrors CaptureComposer exactly:
    //   [circle paperclip btn (outside left)] [VStack: text field / divider / [config | spacer | send]]
    // Attachment panel floats above the circle button when active.

    private let chatInputControlSize: CGFloat = 44

    private var inputSection: some View {
        // ZStack anchors the custom attachment panel above the + button
        ZStack(alignment: .bottomLeading) {
            // Main input row — matches CaptureComposer HStack layout exactly
            HStack(alignment: .bottom, spacing: 10) {
                // Circle plus button — toggles custom attachment panel above it
                Button {
                    withAnimation(.snappy(duration: 0.15)) { isPickingAttachment.toggle() }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(AppTheme.mutedText)
                        .frame(width: chatInputControlSize, height: chatInputControlSize)
                }
                .buttonStyle(.plain)
                .background(AppTheme.surfacePrimary, in: Circle())
                .overlay(Circle().stroke(AppTheme.strongBorder, lineWidth: 1))

                // Input box — images now live inside the box itself
                chatInputBox
            }

            // Attachment picker panel — floats above the + button, anchored bottom-leading
            if isPickingAttachment {
                attachmentPickerPanel
                    .padding(.bottom, chatInputControlSize + 8)
                    .transition(.scale(scale: 0.85, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.15), value: isPickingAttachment)
    }

    /// Whether the input box should show its full toolbar (config, mic, send).
    /// Compact mode: only text field + mic, matching the height of the + button.
    private var isInputExpanded: Bool {
        isInputFocused || !chatService.messages.isEmpty || chatService.isStreaming
    }

    private var mentionOptions: [RichInputMentionRef] {
        let taskMentions = allTasks.prefix(12).map { task in
            RichInputMentionRef(
                id: task.id.uuidString,
                kind: .task,
                title: task.title,
                subtitle: task.dueDate.map { "\($0.formatted(date: .abbreviated, time: .shortened))" },
                displayText: task.title,
                accessibilityLabel: "Task \(task.title)"
            )
        }

        let threadMentions = services.emailService.threads.prefix(12).map { thread in
            RichInputMentionRef(
                id: thread.id,
                kind: .thread,
                title: thread.subject,
                subtitle: thread.from.email,
                displayText: thread.subject,
                accessibilityLabel: "Email thread \(thread.subject)"
            )
        }

        let peopleMentions = Dictionary(grouping: services.emailService.threads.map(\.from), by: \.email)
            .compactMap { _, senders in senders.first }
            .prefix(12)
            .map { sender in
                RichInputMentionRef(
                    id: sender.email,
                    kind: .person,
                    title: sender.name,
                    subtitle: sender.email,
                    displayText: sender.name,
                    accessibilityLabel: "Person \(sender.name)"
                )
            }

        return Array(taskMentions) + Array(threadMentions) + Array(peopleMentions) + eventMentions
    }

    private var chatInputBox: some View {
        let isEmpty = inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingAttachments.isEmpty

        // Whether any "above-text" accessories are visible (pill or attachments)
        let hasAccessories = pageContextAttached || !pendingAttachments.isEmpty

        return VStack(spacing: 0) {
            // ── Above-text row: page context pill + attachment thumbnails ──────
            if pageContextAttached || !pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // Page context pill — shows which tab/page the user is on
                        if pageContextAttached {
                            HStack(spacing: 5) {
                                Image(systemName: currentTab.activeIcon)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(currentTab.title)
                                    .font(.system(size: 12, weight: .medium))
                                Button {
                                    withAnimation(.snappy(duration: 0.15)) {
                                        pageContextAttached = false
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .buttonStyle(.plain)
                            }
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.blue.opacity(0.12), in: Capsule())
                        }

                        // Attachment thumbnails
                        ForEach(pendingAttachments, id: \.self) { filename in
                            attachmentThumbnail(filename: filename)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.top, 10)
                .padding(.bottom, 2)
            }

            if isInputExpanded {
                RichComposerInput(
                    text: $inputText,
                    mentions: $inputMentions,
                    placeholder: "Ask, search or make anything…",
                    surface: .aiChat,
                    mentionOptions: mentionOptions,
                    onCommand: { _ in }
                )
                    .padding(.horizontal, 16)
                    .padding(.top, hasAccessories ? 6 : 12)
                    .padding(.bottom, 8)

                // Bottom toolbar: [config | spacer | mic | send/stop]
                HStack(spacing: 4) {
                    Button { showsConfig = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppTheme.mutedText)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
                    .minTouchTarget()

                    Spacer()

                    // Live voice chat button — opens full-screen voice modal
                    Button { showVoiceChat = true } label: {
                        Image(systemName: "waveform")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(voiceButtonGradient)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
                    .minTouchTarget()

                    ChatVoiceInputButton(onTranscription: { transcribed in
                        let current = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                        inputText = current.isEmpty ? transcribed : current + " " + transcribed
                    })

                    if chatService.isStreaming {
                        Button { chatService.cancelStream() } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(AppPrimaryButtonStyle())
                        .clipShape(Circle())
                        .minTouchTarget()
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(AppPrimaryButtonStyle())
                        .clipShape(Circle())
                        .minTouchTarget()
                        .disabled(isEmpty)
                        .opacity(isEmpty ? 0.4 : 1)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            } else {
                HStack(spacing: 8) {
                    RichComposerInput(
                        text: $inputText,
                        mentions: $inputMentions,
                        placeholder: "Ask, search or make anything…",
                        surface: .aiChat,
                        mentionOptions: mentionOptions,
                        onCommand: { _ in }
                    )
                    .padding(.leading, 16)

                    Button { showVoiceChat = true } label: {
                        Image(systemName: "waveform")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(voiceButtonGradient)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())

                    ChatVoiceInputButton(onTranscription: { transcribed in
                        let current = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                        inputText = current.isEmpty ? transcribed : current + " " + transcribed
                    })
                    .padding(.trailing, 6)
                }
                .frame(height: chatInputControlSize)
            }
        }
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: isInputExpanded ? 24 : chatInputControlSize / 2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: isInputExpanded ? 24 : chatInputControlSize / 2, style: .continuous).stroke(AppTheme.strongBorder, lineWidth: 1))
        .animation(.snappy(duration: 0.18), value: chatService.isStreaming)
        .animation(.snappy(duration: 0.2), value: isInputExpanded)
        .animation(.easeOut(duration: 0.12), value: isEmpty)
        .animation(.snappy(duration: 0.15), value: pendingAttachments.count)
    }

    /// Single attachment thumbnail with X button fully contained within image bounds.
    @ViewBuilder
    private func attachmentThumbnail(filename: String) -> some View {
        ZStack(alignment: .topTrailing) {
            if let image = AttachmentService.shared.loadImage(for: filename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.surfaceSecondary)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "doc")
                            .font(.system(size: 18))
                            .foregroundStyle(AppTheme.mutedText)
                    )
            }
            // X button inset within image bounds — no offset so it never clips
            Button {
                pendingAttachments.removeAll { $0 == filename }
                AttachmentService.shared.delete(filename: filename)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .background(Color.black.opacity(0.5), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(4)
        }
    }

    /// Custom attachment picker panel — floats above the + button, anchored bottom-leading.
    /// Replaces native confirmationDialog (system sheet) for better spatial anchoring.
    private var attachmentPickerPanel: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.15)) { isPickingAttachment = false }
                isShowingPhotoPicker = true
            } label: { attachmentMenuRow(icon: "photo.on.rectangle", label: "Photo Library") }
            .buttonStyle(.plain)

            Divider().opacity(0.4)

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    withAnimation(.snappy(duration: 0.15)) { isPickingAttachment = false }
                    isShowingCamera = true
                } label: { attachmentMenuRow(icon: "camera", label: "Take Photo") }
                .buttonStyle(.plain)

                Divider().opacity(0.4)
            }

            Button {
                withAnimation(.snappy(duration: 0.15)) { isPickingAttachment = false }
                isShowingFilePicker = true
            } label: { attachmentMenuRow(icon: "doc.badge.plus", label: "Choose File") }
            .buttonStyle(.plain)
        }
        .frame(width: 210)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.cardBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 4)
    }

    private func attachmentMenuRow(icon: String, label: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 22)
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Voice Button Gradient

    /// Multi-color AI gradient for the live voice button — matches the tab bar sparkles icon.
    private var voiceButtonGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0, green: 0xAA / 255.0, blue: 0xF5 / 255.0), location: 0.087),
                .init(color: Color(red: 0xEF / 255.0, green: 0, blue: 0xC2 / 255.0), location: 0.269),
                .init(color: Color(red: 1, green: 0, blue: 0x38 / 255.0), location: 0.580),
                .init(color: Color(red: 0xF9 / 255.0, green: 0x9F / 255.0, blue: 0), location: 0.913),
            ],
            startPoint: UnitPoint(x: 0.25, y: 0),
            endPoint: UnitPoint(x: 0.75, y: 1)
        )
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        let mentions = inputMentions
        inputMentions = []
        // Clear persisted draft since the message was sent
        UserDefaults.standard.removeObject(forKey: "ai_draft_input")
        // Set the current page context so the AI knows where the user is
        chatService.currentPageContext = pageContextAttached ? currentTab.title + " tab" : nil
        chatService.send(
            userMessage: text,
            mentions: mentions,
            allTasks: Array(allTasks),
            modelContext: modelContext
        )
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastID = chatService.messages.last?.id else { return }
        withAnimation(.snappy(duration: 0.25)) {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }

    // MARK: - Conversation Actions

    /// Build markdown-formatted text of the entire conversation
    private func conversationAsMarkdown() -> String {
        chatService.messages.map { msg in
            let tag = msg.role == .user ? "**User**" : "**Assistant**"
            return "\(tag)\n\(msg.content)"
        }.joined(separator: "\n\n---\n\n")
    }

    private func copyConversation() {
        UIPasteboard.general.string = conversationAsMarkdown()
    }

    private func duplicateChat() {
        // Save current conversation as a new entry then clear to start fresh
        chatService.autosave()
        // Reload the same messages back in — effectively duplicates the conversation
        let currentMessages = chatService.messages
        let currentTitle = chatService.chatTitle
        chatService.clearHistory()
        for msg in currentMessages {
            chatService.messages.append(AIChatMessage(role: msg.role, content: msg.content))
        }
        chatService.chatTitle = (currentTitle ?? "Untitled") + " (copy)"
    }

    private func deleteConversation() {
        withAnimation(.snappy(duration: 0.2)) {
            chatService.clearHistory()
        }
    }

    private func shareConversation() {
        let text = conversationAsMarkdown()
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            // Find the top-most presented controller to avoid presentation conflicts
            var top = root
            while let presented = top.presentedViewController { top = presented }
            av.popoverPresentationController?.sourceView = top.view
            top.present(av, animated: true)
        }
    }

    private func loadEventMentions() {
        Task {
            let start = Date()
            let end = Calendar.current.date(byAdding: .day, value: 14, to: start) ?? start
            let events = await services.calendarService.events(from: start, to: end)
            let mentions = events.prefix(12).map { event in
                RichInputMentionRef(
                    id: event.id,
                    kind: .event,
                    title: event.title,
                    subtitle: event.startDate.formatted(date: .abbreviated, time: .shortened),
                    displayText: event.title,
                    accessibilityLabel: "Event \(event.title)"
                )
            }

            await MainActor.run {
                eventMentions = Array(mentions)
            }
        }
    }

    /// Conversation stats for the "View Data" sheet
    private var conversationStats: [(label: String, value: String)] {
        let msgs = chatService.messages
        let userMsgs = msgs.filter { $0.role == .user }
        let aiMsgs = msgs.filter { $0.role == .assistant }
        let totalChars = msgs.reduce(0) { $0 + $1.content.count }
        let totalWords = msgs.reduce(0) { $0 + $1.content.split(separator: " ").count }
        // Rough token estimate: ~4 chars per token for English text
        let estimatedTokens = totalChars / 4
        // Rough cost estimate: ~$0.15 per 1M input tokens for GPT-4.1-mini via OpenRouter
        let estimatedCost = Double(estimatedTokens) * 0.00000015

        return [
            ("Messages", "\(msgs.count)"),
            ("User messages", "\(userMsgs.count)"),
            ("AI messages", "\(aiMsgs.count)"),
            ("Total words", "\(totalWords)"),
            ("Total characters", "\(totalChars)"),
            ("Est. tokens", "~\(estimatedTokens)"),
            ("Est. cost", String(format: "$%.4f", estimatedCost)),
            ("Model", chatService.selectedModel),
        ]
    }

    // MARK: - Generative UI Card Navigation

    /// Handles navigation actions from generative UI card taps.
    /// Dismisses the AI chat sheet, switches to the correct tab, and sets
    /// pending navigation state so the destination view can pick it up.
    private func handleCardNavigation(_ action: String, params: [String: String]) {
        switch action {
        case "navigate_thread":
            guard let threadId = params["threadId"] else { return }
            services.pendingEmailThreadId = threadId
            services.navigateTo = .email
            dismiss()

        case "navigate_task":
            guard let taskIdStr = params["taskId"],
                  let taskId = UUID(uuidString: taskIdStr) else { return }
            services.pendingTaskId = taskId
            services.navigateTo = .tasks
            dismiss()

        case "navigate_event":
            if let _ = params["eventId"] {
                // Calendar events use EventKit — switch to calendar tab.
                // Deep-link to a specific event is not supported yet by CalendarKit.
                services.navigateTo = .calendar
                dismiss()
            }

        case "navigate_draft":
            // Drafts open the compose sheet with pre-loaded content
            if let _ = params["draftId"] {
                services.navigateTo = .email
                dismiss()
            }

        default:
            print("[GenerativeUI] Unhandled action: \(action) params: \(params)")
        }
    }
}

// MARK: - Content Parsing

/// Splits AI response text into plain-text segments and [task:UUID] reference tokens.
/// The task references will be rendered as interactive MiniTaskCard views.
private enum ContentPart {
    case text(String)
    case taskRef(UUID)
}

private func parseMessageContent(_ content: String) -> [ContentPart] {
    // Match [task:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx]
    guard #available(iOS 16, *) else { return [.text(content)] }
    let pattern = /\[task:([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\]/
    var parts: [ContentPart] = []
    var lastEnd = content.startIndex

    for match in content.matches(of: pattern) {
        let pre = String(content[lastEnd..<match.range.lowerBound])
        if !pre.isEmpty { parts.append(.text(pre)) }
        if let uuid = UUID(uuidString: String(match.1)) {
            parts.append(.taskRef(uuid))
        }
        lastEnd = match.range.upperBound
    }
    let tail = String(content[lastEnd...])
    if !tail.isEmpty { parts.append(.text(tail)) }
    return parts.isEmpty ? [.text(content)] : parts
}

// MARK: - MessageBubble

/// Renders a single chat message. User messages right-aligned, AI messages left full-width.
/// allTasks is passed in so assistant bubbles can render [task:UUID] tokens as cards.
private struct MessageBubble: View {
    let message: AIChatMessage
    let allTasks: [TaskRecord]
    /// Callback for generative UI card actions (e.g. navigate to thread/task/event).
    var onNavigate: ((String, [String: String]) -> Void)?

    @State private var showActions = false
    @State private var didCopy = false
    @State private var thumbsState: ThumbsState? = nil
    /// Switches to full markdown (.full syntax) after streaming ends, with a crossfade.
    /// This avoids the expensive `.full` parse on every streaming token.
    @State private var showFullMarkdown = false

    private enum ThumbsState { case up, down }

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            HStack {
                if message.role == .user { Spacer(minLength: 60) }
                if message.role == .user { userBubble } else { assistantBubble }
                if message.role == .assistant { Spacer(minLength: 0) }
            }

            // Mutation chips
            if !message.taskMutations.isEmpty {
                mutationChips
            }

            // Post-stream action row (copy / thumbs) with fade-in
            if message.role == .assistant && !message.isStreaming && !message.content.isEmpty {
                actionRow
                    .opacity(showActions ? 1 : 0)
                    .animation(.easeIn(duration: 0.3), value: showActions)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation { showActions = true }
                        }
                    }
                    .onChange(of: message.isStreaming) { _, isStreaming in
                        if !isStreaming {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                withAnimation { showActions = true }
                            }
                        }
                    }
            }
        }
    }

    // MARK: User Bubble — no border, just background fill

    private var userBubble: some View {
        Text(message.content)
            .font(.system(size: 16, weight: .medium))
            .tracking(-0.1)
            .lineSpacing(3)
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                AppTheme.surfacePrimary,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            // Intentionally no stroke overlay — cleaner look per design feedback
    }

    // MARK: Assistant Bubble

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Web search status indicator — shown while backend is searching
            if message.searchState == .searching {
                SearchingIndicator(queries: message.searchQueries)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Source chips — shown after search completes, before/alongside the answer
            if !message.sources.isEmpty {
                SourceChipsView(sources: message.sources, onSourceTap: nil)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Collapsible reasoning box — shows the AI's thinking process
            if !message.reasoningContent.isEmpty {
                ReasoningBox(
                    content: message.reasoningContent,
                    durationMs: message.reasoningDurationMs,
                    isStreaming: message.isStreaming
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Main content
            if message.content.isEmpty && message.isStreaming {
                EmptyView() // Thinking indicator shown by parent
            } else {
                assistantContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, showFullMarkdown ? 8 : 0)
                    // When streaming ends, wait 150ms then crossfade to full markdown
                    .onChange(of: message.isStreaming) { _, isStreaming in
                        if !isStreaming {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation(.easeIn(duration: 0.3)) { showFullMarkdown = true }
                            }
                        }
                    }
                    // Pre-loaded (history) messages show full markdown immediately
                    .onAppear {
                        if !message.isStreaming { showFullMarkdown = true }
                    }
            }
        }
        .animation(.snappy(duration: 0.3), value: message.searchState)
        .animation(.snappy(duration: 0.3), value: message.sources.count)
    }

    /// Mixed-content renderer: text runs with live markdown + [task:UUID] cards + generative UI specs.
    @ViewBuilder
    private var assistantContent: some View {
        let parts = parseMessageContent(message.content)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parts.indices, id: \.self) { i in
                contentPartView(parts[i], isLastPart: i == parts.count - 1)
            }
            // Render generative UI spec if present (parsed after streaming completes)
            if let spec = message.uiSpec {
                ChatUISpecView(spec: spec) { action, params in
                    handleSpecAction(action, params: params)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    /// Handles actions from generative UI card taps — forwards to parent via onNavigate callback.
    private func handleSpecAction(_ action: String, params: [String: String]) {
        onNavigate?(action, params)
    }

    @ViewBuilder
    private func contentPartView(_ part: ContentPart, isLastPart: Bool) -> some View {
        switch part {
        case .text(let txt):
            // Streaming phase: fast inline-only markdown (bold, italic, inline code, preserves newlines).
            // Completion phase: crossfade to full markdown (headings, list bullets, code blocks).
            Group {
                if showFullMarkdown {
                    fullMarkdownText(txt)
                        .transition(.opacity)
                } else {
                    inlineMarkdownText(txt)
                        .overlay(alignment: .bottomLeading) {
                            // Blinking cursor only after the very last text chunk
                            if isLastPart && message.isStreaming { BlinkingCursor() }
                        }
                        .transition(.opacity)
                }
            }
            .animation(.easeIn(duration: 0.3), value: showFullMarkdown)
            .font(.system(size: 16, weight: .regular))
            .tracking(-0.1)
            .lineSpacing(4)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)

        case .taskRef(let uuid):
            if let task = allTasks.first(where: { $0.id == uuid }) {
                MiniTaskCard(task: task)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
    }

    /// Inline-only markdown — fast, used during streaming.
    /// Handles bold, italic, inline code and preserves `\n` whitespace.
    @ViewBuilder
    private func inlineMarkdownText(_ content: String) -> some View {
        let attributed = Self.styledInlineMarkdown(content, sources: message.sources, styleCitations: styleCitations)
        if let attributed {
            Text(attributed)
        } else {
            Text(content)
        }
    }

    /// Helper that builds an inline-parsed AttributedString with citation styling applied.
    /// Extracted from @ViewBuilder to avoid Void-in-ViewBuilder compiler errors.
    private static func styledInlineMarkdown(
        _ content: String,
        sources: [WebSource],
        styleCitations: (inout AttributedString) -> Void
    ) -> AttributedString? {
        guard var attributed = try? AttributedString(
            markdown: content,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else { return nil }
        if !sources.isEmpty { styleCitations(&attributed) }
        return attributed
    }

    /// Helper that builds a full-parsed AttributedString with citation styling applied.
    private static func styledFullMarkdown(
        _ content: String,
        sources: [WebSource],
        styleCitations: (inout AttributedString) -> Void
    ) -> AttributedString? {
        guard var attributed = try? AttributedString(
            markdown: content,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        ) else { return nil }
        if !sources.isEmpty { styleCitations(&attributed) }
        return attributed
    }

    /// Full markdown — runs once when streaming ends.
    /// Adds headings, list bullets, code blocks on top of inline syntax.
    /// Preprocesses single `\n` → `\n\n` because CommonMark collapses single newlines
    /// to a space, causing all paragraphs/bullets to run together in one blob.
    @ViewBuilder
    private func fullMarkdownText(_ content: String) -> some View {
        // Normalize: single \n → \n\n so markdown sees paragraph breaks, not spaces.
        let normalized = content.replacingOccurrences(
            of: "(?<!\n)\n(?!\n)",
            with: "\n\n",
            options: .regularExpression
        )
        let attributed = Self.styledFullMarkdown(normalized, sources: message.sources, styleCitations: styleCitations)
        if let attributed {
            Text(attributed)
        } else {
            Text(content)
        }
    }

    /// Post-process an AttributedString to highlight [1], [2] etc. citation markers.
    /// Makes them blue, slightly smaller, and links them to the source URL.
    private func styleCitations(_ attributed: inout AttributedString) {
        // Find [n] patterns in the plain text and style them
        let plainText = String(attributed.characters)
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d{1,2})\]"#) else { return }
        let nsRange = NSRange(plainText.startIndex..., in: plainText)
        let matches = regex.matches(in: plainText, range: nsRange)

        // Process in reverse so indices stay valid
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: plainText),
                  let numberRange = Range(match.range(at: 1), in: plainText),
                  let citationNumber = Int(plainText[numberRange]),
                  citationNumber >= 1, citationNumber <= message.sources.count
            else { continue }

            // Convert String range to AttributedString range
            let attrStart = AttributedString.Index(fullRange.lowerBound, within: attributed)
            let attrEnd = AttributedString.Index(fullRange.upperBound, within: attributed)
            guard let start = attrStart, let end = attrEnd else { continue }

            let source = message.sources[citationNumber - 1]

            // Style: blue, slightly smaller, with link to source URL
            attributed[start..<end].foregroundColor = .accentColor
            attributed[start..<end].font = .system(size: 12, weight: .semibold)
            attributed[start..<end].baselineOffset = 4 // Superscript effect
            if let url = URL(string: source.url) {
                attributed[start..<end].link = url
            }
        }
    }

    // MARK: Mutation Chips

    private var mutationChips: some View {
        FlowLayout(spacing: 6) {
            ForEach(message.taskMutations) { mutation in
                mutationChip(mutation)
            }
        }
        .padding(.leading, 4)
    }

    private func mutationChip(_ mutation: AIChatTaskMutation) -> some View {
        HStack(spacing: 5) {
            Image(systemName: mutationIcon(mutation))
                .font(.system(size: 10, weight: .semibold))
            Text(mutationLabel(mutation))
                .font(.system(size: 11, weight: .semibold))
                .tracking(-0.1)
        }
        .foregroundStyle(mutationColor(mutation))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(mutationColor(mutation).opacity(0.1), in: Capsule())
        .overlay(Capsule().stroke(mutationColor(mutation).opacity(0.25), lineWidth: 1))
        .transition(.scale.combined(with: .opacity))
    }

    private func mutationIcon(_ m: AIChatTaskMutation) -> String {
        switch m.action {
        case .create: return "plus.circle.fill"
        case .update: return "pencil.circle.fill"
        case .delete: return "trash.circle.fill"
        }
    }

    private func mutationLabel(_ m: AIChatTaskMutation) -> String {
        switch m.action {
        case .create: return "Created: \(m.title ?? "task")"
        case .update: return "Updated: \(m.title ?? "task")"
        case .delete: return "Deleted task"
        }
    }

    private func mutationColor(_ m: AIChatTaskMutation) -> Color {
        switch m.action {
        case .create: return .green
        case .update: return .blue
        case .delete: return AppTheme.danger
        }
    }

    // MARK: Action Row — copy shows checkmark briefly; thumbs toggle state

    private var actionRow: some View {
        HStack(spacing: 16) {
            // Copy button: shows checkmark for 1.5s after tap
            Button {
                UIPasteboard.general.string = message.content
                withAnimation(.snappy(duration: 0.15)) { didCopy = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.snappy(duration: 0.15)) { didCopy = false }
                }
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(didCopy ? Color.green : AppTheme.mutedText)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            // Thumbs up — highlights when selected
            Button {
                withAnimation(.snappy(duration: 0.15)) {
                    thumbsState = thumbsState == .up ? nil : .up
                }
            } label: {
                Image(systemName: thumbsState == .up ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(thumbsState == .up ? Color.blue : AppTheme.mutedText)
            }
            .buttonStyle(.plain)

            // Thumbs down — highlights when selected
            Button {
                withAnimation(.snappy(duration: 0.15)) {
                    thumbsState = thumbsState == .down ? nil : .down
                }
            } label: {
                Image(systemName: thumbsState == .down ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(thumbsState == .down ? Color.orange : AppTheme.mutedText)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 4)
    }
}

// MARK: - SearchingIndicator

/// Animated indicator shown while the backend is performing a web search.
/// Displays a spinning globe icon and the search query being executed.
private struct SearchingIndicator: View {
    let queries: [String]
    @State private var isRotating = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
                .rotationEffect(.degrees(isRotating ? 360 : 0))
                .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: isRotating)
                .onAppear { isRotating = true }

            VStack(alignment: .leading, spacing: 2) {
                Text("Searching the web…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.mutedText)

                if let query = queries.first {
                    Text(query)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.subtleText)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - SourceChipsView

/// Horizontally scrollable row of source pills. Tap to expand a detail sheet showing the snippet,
/// or long-press to open the URL directly in Safari.
private struct SourceChipsView: View {
    let sources: [WebSource]
    /// Optional callback when a source chip is tapped (for external handling). Nil = use built-in sheet.
    var onSourceTap: ((WebSource) -> Void)?

    @State private var selectedSource: WebSource?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                    Button {
                        if let handler = onSourceTap {
                            handler(source)
                        } else {
                            selectedSource = source
                        }
                    } label: {
                        HStack(spacing: 6) {
                            // Citation number badge
                            Text("[\(index + 1)]")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(AppTheme.mutedText)

                            // Favicon via Google's S2 service
                            AsyncImage(url: faviconURL(source.url)) { image in
                                image.resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 14, height: 14)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            } placeholder: {
                                Image(systemName: "globe")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppTheme.mutedText)
                            }

                            Text(source.domain)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.surfacePrimary, in: Capsule())
                        .overlay(Capsule().stroke(AppTheme.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    // Long-press opens URL directly in Safari
                    .contextMenu {
                        if let url = URL(string: source.url) {
                            Link("Open in Safari", destination: url)
                            Button {
                                UIPasteboard.general.string = source.url
                            } label: {
                                Label("Copy URL", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedSource) { source in
            SourceDetailSheet(source: source)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private func faviconURL(_ urlString: String) -> URL? {
        guard let host = URL(string: urlString)?.host else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=32")
    }
}

// MARK: - SourceDetailSheet

/// Expanded source card shown when tapping a source chip.
/// Shows the full title, domain, snippet, and an "Open" button.
private struct SourceDetailSheet: View {
    let source: WebSource
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // Header: favicon + domain
                HStack(spacing: 10) {
                    AsyncImage(url: faviconURL(source.url)) { image in
                        image.resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } placeholder: {
                        Image(systemName: "globe")
                            .font(.system(size: 18))
                            .foregroundStyle(AppTheme.mutedText)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.title)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(2)
                        Text(source.domain)
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.mutedText)
                    }
                }

                // Snippet
                if !source.snippet.isEmpty {
                    Text(source.snippet)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }

                // Open in Safari button
                if let url = URL(string: source.url) {
                    Link(destination: url) {
                        HStack {
                            Image(systemName: "safari")
                            Text("Open in Safari")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AppTheme.cardBorder, lineWidth: 1)
                        )
                    }
                }

                Spacer()
            }
            .padding(20)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(AppTheme.mutedText)
                    }
                }
            }
        }
    }

    private func faviconURL(_ urlString: String) -> URL? {
        guard let host = URL(string: urlString)?.host else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=32")
    }
}

// MARK: - ReasoningBox

/// Collapsible thinking/reasoning box that shows the AI's internal reasoning process.
/// Auto-expands while streaming, auto-collapses when done. Tap header to toggle.
private struct ReasoningBox: View {
    let content: String
    let durationMs: Int?
    let isStreaming: Bool

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — tap to toggle expansion
            Button {
                withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    // Animated brain icon — pulses while streaming
                    Image(systemName: "brain")
                        .font(.system(size: 12, weight: .medium))
                        .symbolEffect(.pulse, isActive: isStreaming && durationMs == nil)

                    if let ms = durationMs {
                        let seconds = max(1, ms / 1000)
                        Text("Thought for \(seconds)s")
                            .font(.system(size: 13, weight: .medium))
                    } else {
                        Text("Thinking…")
                            .font(.system(size: 13, weight: .medium))
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .animation(.snappy(duration: 0.2), value: isExpanded)
                }
                .foregroundStyle(AppTheme.mutedText)
            }
            .buttonStyle(.plain)

            // Reasoning content — collapsible
            if isExpanded {
                Text(content)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.subtleText)
                    .lineSpacing(3)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(
            AppTheme.surfacePrimary.opacity(0.5),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 0.5)
        )
        // Auto-collapse when streaming finishes with a slight delay
        .onChange(of: isStreaming) { _, streaming in
            if !streaming && durationMs != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.snappy(duration: 0.3)) { isExpanded = false }
                }
            }
        }
    }
}

// MARK: - MiniTaskCard

/// Compact tappable task card rendered when the AI outputs a [task:UUID] token.
/// Matches the visual language of TaskRowView (border, radius, fonts).
private struct MiniTaskCard: View {
    let task: TaskRecord
    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: {
            HStack(spacing: 12) {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(task.completed ? Color.blue : AppTheme.mutedText)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(-0.1)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if let due = task.dueDate {
                        Text(due, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.mutedText)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
            }
            .padding(12)
            .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            TaskDetailSheet(task: task)
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - ChatVoiceInputButton

private struct ChatVoiceInputButton: View {
    let onTranscription: (String) -> Void

    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var partialText: String = ""

    // Speech / audio
    private let speechRecognizer = SFSpeechRecognizer()
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    var body: some View {
        Group {
            if isTranscribing {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(width: 36, height: 36)
            } else if isRecording {
                Button(action: stopRecording) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                }
                .frame(width: 36, height: 36)
                .background(Color.red, in: Circle())
                .overlay(Circle().stroke(AppTheme.cardBorder, lineWidth: 1))
                .buttonStyle(.plain)
                .minTouchTarget()
            } else {
                Button(action: startRecording) {
                    Image(systemName: "mic")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.mutedText)
                        .frame(width: 30, height: 30)
                }
                .frame(width: 36, height: 36)
                .background(AppTheme.surfacePrimary, in: Circle())
                .overlay(Circle().stroke(AppTheme.cardBorder, lineWidth: 1))
                .buttonStyle(.plain)
                .minTouchTarget()
            }
        }
        .onDisappear { cleanup() }
    }

    // MARK: - Recording Control

    private func startRecording() {
        Task { @MainActor in
            guard await requestPermissions() else { return }
            do {
                try configureAudioSession()
                let request = SFSpeechAudioBufferRecognitionRequest()
                request.shouldReportPartialResults = true
                self.recognitionRequest = request

                let inputNode = audioEngine.inputNode
                let recordingFormat = inputNode.outputFormat(forBus: 0)
                inputNode.removeTap(onBus: 0)
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                    request.append(buffer)
                }

                audioEngine.prepare()
                try audioEngine.start()

                isRecording = true
                partialText = ""

                recognitionTask = speechRecognizer?.recognitionTask(with: request) { result, error in
                    if let result = result {
                        partialText = result.bestTranscription.formattedString
                    }
                    if let error = error {
                        // Stop on error
                        stopRecordingInternal(finalize: true)
                        #if DEBUG
                        print("Speech recognition error: \(error.localizedDescription)")
                        #endif
                    } else if result?.isFinal == true {
                        stopRecordingInternal(finalize: true)
                    }
                }
            } catch {
                cleanup()
                #if DEBUG
                print("Failed to start recording: \(error)")
                #endif
            }
        }
    }

    private func stopRecording() {
        stopRecordingInternal(finalize: true)
    }

    @MainActor
    private func stopRecordingInternal(finalize: Bool) {
        guard isRecording || isTranscribing else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()
        isRecording = false
        if finalize { isTranscribing = true }

        // Defer delivery slightly to allow final result to surface
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let finalText = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !finalText.isEmpty {
                onTranscription(finalText)
            }
            cleanup()
        }
    }

    // MARK: - Permissions & Session

    private func requestPermissions() async -> Bool {
        let speechAuth = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechAuth == .authorized else { return false }

        let micGranted: Bool = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        return micGranted
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    @MainActor
    private func cleanup() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        isRecording = false
        isTranscribing = false
    }
}

// MARK: - BlinkingCursor

private struct BlinkingCursor: View {
    @State private var visible = true

    var body: some View {
        Rectangle()
            .frame(width: 2, height: 16)
            .foregroundStyle(.primary.opacity(0.7))
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: visible)
            .onAppear { visible = false }
            .offset(x: 2)
    }
}

// MARK: - ChatHistoryView

/// Lists all saved conversations. Drag handle at top, "Chats" title top-left,
/// new-chat button top-right, search bar pinned to bottom — matches the reference design.
struct ChatHistoryView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""

    private var chatService: AIChatService { services.aiChatService }

    private var filtered: [AIChatConversation] {
        guard !searchText.isEmpty else { return chatService.savedConversations }
        return chatService.savedConversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom header — "Chats" title left, new-chat button right
            HStack(alignment: .center) {
                Text("Chats")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.5)

                Spacer()

                // New chat button — starts fresh and dismisses this sheet
                Button {
                    chatService.clearHistory()
                    dismiss()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .background(AppTheme.surfacePrimary, in: Circle())
                        .overlay(Circle().stroke(AppTheme.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider().opacity(0.3)

            // Conversation list or empty state
            if chatService.savedConversations.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filtered) { conv in
                        Button {
                            chatService.loadConversation(conv)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conv.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .tracking(-0.2)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(RelativeDateTimeFormatter().localizedString(for: conv.createdAt, relativeTo: Date()))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AppTheme.mutedText)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                chatService.deleteConversation(conv)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        // Search bar pinned to bottom — same as reference screenshot
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.mutedText)
                    .font(.system(size: 15, weight: .medium))
                TextField("Search chats", text: $searchText)
                    .font(.system(size: 15, weight: .medium))
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.mutedText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.cardBorder, lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        // Background matches main chat sheet — set via presentationBackground at call site
        .background(AppTheme.backgroundTop.ignoresSafeArea())
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
            Text("No previous chats")
                .font(.system(size: 18, weight: .semibold))
                .tracking(-0.3)
            Text("Your chat history will appear here.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - AIChatConfigSheet

/// Lets the user control which AI model is active and what the AI can access.
struct AIChatConfigSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    private var chatService: AIChatService { services.aiChatService }

    /// Curated list of frontier models available via OpenRouter.
    /// To add/remove models: edit this list or set PRIMARY_MODEL / FALLBACK_MODELS in TaskAppConfig.plist.
    private let availableModels: [(id: String, name: String, subtitle: String)] = [
        ("openai/gpt-5.4",                  "GPT-5.4",                    "OpenAI · Flagship"),
        ("openai/gpt-5.4-mini",             "GPT-5.4 Mini",               "OpenAI · Fast & cheap"),
        ("openai/gpt-5.4-chat",             "GPT-5.4 Chat",               "OpenAI · Conversational"),
        ("openai/gpt-5.4-nano",             "GPT-5.4 Nano",               "OpenAI · Ultra-fast"),
        ("anthropic/claude-sonnet-4-5",     "Claude Sonnet 4.5",          "Anthropic · Balanced"),
        ("anthropic/claude-haiku-4-5",      "Claude Haiku 4.5",           "Anthropic · Fast"),
        ("moonshotai/kimi-k2.5",            "Kimi K2.5",                  "Moonshot · Strong coding"),
        ("google/gemini-3.1-pro-preview",   "Gemini 3.1 Pro Preview",     "Google · Advanced reasoning"),
        ("google/gemini-3.1-flash-lite-preview", "Gemini 3.1 Flash Lite Preview", "Google · Fast & efficient"),
        ("google/gemini-3-flash-preview",   "Gemini 3 Flash Preview",     "Google · Balanced speed"),
    ]

    var body: some View {
        NavigationStack {
            List {
                // Tasks section
                Section {
                    Toggle("Read tasks", isOn: Bindable(chatService).aiCanReadTasks)
                        .tint(Color.blue)
                    Toggle("Write tasks", isOn: Bindable(chatService).aiCanWriteTasks)
                        .tint(Color.blue)
                } header: {
                    Text("Tasks")
                } footer: {
                    Text("\"Read\" injects your task list into the AI's context. \"Write\" lets the AI create, edit, and delete tasks.")
                }

                // Calendar section
                Section {
                    Toggle("Read calendar", isOn: Bindable(chatService).aiCanReadCalendar)
                        .tint(Color.blue)
                    Toggle("Create events", isOn: Bindable(chatService).aiCanWriteCalendar)
                        .tint(Color.blue)
                } header: {
                    Text("Calendar")
                } footer: {
                    Text("\"Read\" injects today's and this week's events. \"Create\" lets the AI add events to your calendar.")
                }

                // Email section
                Section {
                    Toggle("Read emails", isOn: Bindable(chatService).aiCanReadEmail)
                        .tint(Color.blue)
                    Toggle("Send emails", isOn: Bindable(chatService).aiCanSendEmail)
                        .tint(Color.blue)
                } header: {
                    Text("Email")
                } footer: {
                    Text("\"Read\" shares your recent inbox with the AI. \"Send\" lets the AI compose and send emails on your behalf.")
                }

                // Model picker section
                Section {
                    ForEach(availableModels, id: \.id) { model in
                        Button {
                            chatService.selectedModel = model.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.name)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.primary)
                                    Text(model.subtitle)
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundStyle(AppTheme.mutedText)
                                }
                                Spacer()
                                if chatService.selectedModel == model.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.blue)
                                }
                            }
                            // contentShape ensures the full row area is tappable,
                            // required when using .buttonStyle(.plain) inside a List.
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Model")
                } footer: {
                    Text("Models are routed via OpenRouter. To update the available list, edit the availableModels array in AIChatConfigSheet.swift, or override PRIMARY_MODEL in TaskAppConfig.plist.")
                }
            }
            .navigationTitle("AI Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
    }
}

// MARK: - FlowLayout

/// Simple wrapping HStack layout for mutation chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalHeight = y + rowHeight
        }
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Prompt Library Sheet

/// Browsable library of built-in presets and user-saved prompts.
/// Selecting a prompt pre-fills the chat input field.
private struct PromptLibrarySheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let onSelect: (SavedPrompt) -> Void

    @State private var selectedCategory = "All"
    @State private var showSaveInput = false
    @State private var newPromptTitle = ""
    @State private var newPromptText = ""

    private var chatService: AIChatService { services.aiChatService }

    private var allPrompts: [SavedPrompt] {
        SavedPrompt.presets + chatService.savedPrompts
    }

    private var categories: [String] {
        ["All"] + Array(Set(allPrompts.map(\.category))).sorted()
    }

    private var filteredPrompts: [SavedPrompt] {
        selectedCategory == "All" ? allPrompts : allPrompts.filter { $0.category == selectedCategory }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { cat in
                            Button {
                                withAnimation(.snappy(duration: 0.15)) { selectedCategory = cat }
                            } label: {
                                Text(cat)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(selectedCategory == cat ? .primary : AppTheme.mutedText)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        selectedCategory == cat
                                            ? AppTheme.surfacePrimary
                                            : Color.clear,
                                        in: Capsule()
                                    )
                                    .overlay(Capsule().stroke(AppTheme.cardBorder, lineWidth: selectedCategory == cat ? 1 : 0))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                Divider().opacity(0.4)

                // Prompt list
                List {
                    ForEach(filteredPrompts) { prompt in
                        Button {
                            onSelect(prompt)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: prompt.icon)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(AppTheme.mutedText)
                                    .frame(width: 22)
                                    .padding(.top, 1)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(prompt.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if !prompt.isPreset {
                                            Text("Saved")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(AppTheme.mutedText)
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 2)
                                                .background(AppTheme.surfaceSecondary, in: Capsule())
                                        }
                                    }
                                    Text(prompt.text)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if !prompt.isPreset {
                                Button(role: .destructive) {
                                    chatService.deleteSavedPrompt(prompt)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Prompt Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSaveInput = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
            }
            .alert("Save Prompt", isPresented: $showSaveInput) {
                TextField("Title (e.g. Weekly plan)", text: $newPromptTitle)
                TextField("Prompt text", text: $newPromptText)
                Button("Save") {
                    let title = newPromptTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    let text = newPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty, !text.isEmpty else { return }
                    chatService.addSavedPrompt(SavedPrompt(
                        title: title, text: text,
                        icon: "bookmark.fill", category: "Saved"
                    ))
                    newPromptTitle = ""; newPromptText = ""
                }
                Button("Cancel", role: .cancel) { newPromptTitle = ""; newPromptText = "" }
            } message: {
                Text("Save a custom prompt to reuse it later.")
            }
        }
    }
}

// MARK: - Conversation Data Sheet

/// Shows conversation stats: message counts, token estimates, cost, model info.
private struct ConversationDataSheet: View {
    let stats: [(label: String, value: String)]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(stats, id: \.label) { stat in
                    HStack {
                        Text(stat.label)
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(stat.value)
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Conversation Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
    }
}

// MARK: - Seeded shuffle extension

private extension Array {
    /// Shuffle using a deterministic integer seed so Refresh shows a consistent new order.
    func shuffled(seed: Int) -> [Element] {
        var rng = SeededRNG(seed: seed)
        var arr = self
        for i in stride(from: arr.count - 1, through: 1, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            arr.swapAt(i, j)
        }
        return arr
    }
}

/// Simple LCG random number generator seeded with an integer — deterministic shuffle.
private struct SeededRNG {
    var state: UInt64
    init(seed: Int) { state = UInt64(bitPattern: Int64(seed &* 6364136223846793005 &+ 1)) }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
