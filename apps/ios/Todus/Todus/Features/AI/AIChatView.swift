import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation
import Speech

// MARK: - AIChatView

/// Full-screen chat sheet. Streams AI responses with live markdown rendering and typewriter animation.
/// Supports task read/write via tool calls. History and model config accessible from toolbar.
struct AIChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Query(sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]

    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    // Sheet presentation states
    @State private var showsHistory = false
    @State private var showsConfig = false

    // Attachment state — native confirmationDialog triggers individual system pickers
    @State private var isPickingAttachment = false
    @State private var isShowingPhotoPicker = false
    @State private var isShowingCamera = false
    @State private var isShowingFilePicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pendingAttachments: [String] = []

    // Animated thinking text cycles while streaming
    @State private var thinkingIndex = 0
    private let thinkingPhrases = ["Thinking", "Reading tasks", "Searching", "Writing"]

    private var chatService: AIChatService { services.aiChatService }

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
                    emptyStateView
                        .transition(.opacity)
                } else {
                    conversationView
                        .transition(.opacity)
                }
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

        // New chat button — always visible
        ToolbarItem(placement: .topBarTrailing) {
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
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.surfacePrimary)
                            .frame(width: 64, height: 64)
                            .overlay(Circle().stroke(AppTheme.cardBorder, lineWidth: 1))
                        Image(systemName: "sparkles")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.primary)
                    }

                    Text("How can I help you today?")
                        .font(.system(size: 26, weight: .semibold))
                        .tracking(-0.5)
                }
                .padding(.horizontal, 24)

                // Dynamic suggestions based on task count — shows relevant prompts
                // so users always see something immediately useful
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(contextualSuggestions, id: \.text) { suggestion in
                        suggestionRow(icon: suggestion.icon, text: suggestion.text)
                    }
                }
                .padding(.horizontal, 16)
            }

            Spacer()

            inputSection
                .padding(.horizontal, 12)
                .padding(.bottom, 16)   // gap above keyboard on empty state
        }
    }

    /// Returns 3 context-aware suggestions based on how many active tasks the user has.
    /// Goal: always show something immediately useful, not generic placeholders.
    private var contextualSuggestions: [(icon: String, text: String)] {
        let activeCount = allTasks.filter { !$0.completed }.count

        if activeCount == 0 {
            // No tasks yet — guide the user to get started
            return [
                (icon: "plus.circle",   text: "Create my first tasks for today"),
                (icon: "sparkle",       text: "Brainstorm ideas for what to work on"),
                (icon: "list.bullet",   text: "Help me plan my week")
            ]
        } else if activeCount < 6 {
            // Few tasks — encourage building momentum
            return [
                (icon: "plus.circle",   text: "Add more tasks to get my list going"),
                (icon: "sparkle",       text: "Brainstorm what I should be working on"),
                (icon: "checklist",     text: "Review and plan my \(activeCount) tasks")
            ]
        } else if activeCount <= 20 {
            // Healthy backlog — help prioritize and move forward
            return [
                (icon: "arrow.up.circle", text: "What should I prioritize today?"),
                (icon: "sparkle",         text: "Brainstorm and plan"),
                (icon: "pencil",          text: "Create a batch of tasks")
            ]
        } else {
            // Overloaded — help clear the backlog
            return [
                (icon: "checkmark.circle", text: "Help me clear my task backlog"),
                (icon: "arrow.up.circle",  text: "What are my top 3 priorities?"),
                (icon: "trash",            text: "Review and remove stale tasks")
            ]
        }
    }

    private func suggestionRow(icon: String, text: String) -> some View {
        Button {
            inputText = text
            sendMessage()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(width: 24)
                Text(text)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Conversation View

    private var conversationView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(chatService.messages) { message in
                        MessageBubble(message: message, allTasks: Array(allTasks))
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
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 8)   // gap between input and keyboard
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

    private var chatInputBox: some View {
        let isEmpty = inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingAttachments.isEmpty

        return VStack(spacing: 0) {
            // Pending attachment thumbnails live inside the input box, above the text field.
            // This prevents cropping that occurred when they were in the outer VStack.
            if !pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingAttachments, id: \.self) { filename in
                            attachmentThumbnail(filename: filename)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.top, 10)
                .padding(.bottom, 2)
            }

            // Text field — same font/padding as CaptureComposer, no Divider below
            TextField("Ask, search or make anything…", text: $inputText, axis: .vertical)
                .font(.system(size: 16, weight: .medium))
                .lineLimit(1...5)
                .focused($isInputFocused)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, pendingAttachments.isEmpty ? 12 : 6)
                .padding(.bottom, 8)

            // Bottom toolbar: [config | spacer | send/stop] — no Divider, matches CaptureComposer
            HStack(spacing: 4) {
                // AI config button
                Button { showsConfig = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.mutedText)
                }
                .buttonStyle(.plain)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())

                Spacer()

                // Voice transcription — muted mic idle, red stop when recording, spinner when transcribing
                ChatVoiceInputButton(onTranscription: { transcribed in
                    let current = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    inputText = current.isEmpty ? transcribed : current + " " + transcribed
                })

                // Send / Stop — uses AppPrimaryButtonStyle (blue) to match CaptureComposer send button
                if chatService.isStreaming {
                    Button { chatService.cancelStream() } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .clipShape(Circle())
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
                    .disabled(isEmpty)
                    .opacity(isEmpty ? 0.4 : 1)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppTheme.strongBorder, lineWidth: 1))
        .animation(.snappy(duration: 0.18), value: chatService.isStreaming)
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

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        chatService.send(userMessage: text, allTasks: Array(allTasks), modelContext: modelContext)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastID = chatService.messages.last?.id else { return }
        withAnimation(.snappy(duration: 0.25)) {
            proxy.scrollTo(lastID, anchor: .bottom)
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
        VStack(alignment: .leading, spacing: 0) {
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
    }

    /// Mixed-content renderer: text runs with live markdown + [task:UUID] cards.
    @ViewBuilder
    private var assistantContent: some View {
        let parts = parseMessageContent(message.content)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parts.indices, id: \.self) { i in
                contentPartView(parts[i], isLastPart: i == parts.count - 1)
            }
        }
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
        if let attributed = try? AttributedString(
            markdown: content,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
        } else {
            Text(content)
        }
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
        if let attributed = try? AttributedString(
            markdown: normalized,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        ) {
            Text(attributed)
        } else {
            Text(content)
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
                // AI Access section
                Section {
                    Toggle("Read tasks", isOn: Bindable(chatService).aiCanReadTasks)
                        .tint(Color.blue)
                    Toggle("Write tasks", isOn: Bindable(chatService).aiCanWriteTasks)
                        .tint(Color.blue)
                } header: {
                    Text("AI Access")
                } footer: {
                    Text("\"Read tasks\" injects your task list into the AI's context. \"Write tasks\" allows the AI to create, edit, and delete tasks.")
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

