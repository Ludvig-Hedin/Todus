import SwiftUI
import SwiftData
import Speech
import AVFoundation

// MARK: - Assistant Display Mode

/// Controls how the AI assistant panel is presented — as a floating window or docked side pane.
enum AssistantDisplayMode: String {
    case floating
    case sidepane
}

// MARK: - Prompt Template

/// A reusable prompt from the prompt library.
private struct PromptTemplate: Identifiable {
    let id = UUID()
    let icon: String
    let category: String
    let text: String
}

// MARK: - MacVoiceController

/// Speech-to-text controller for macOS. Manages AVAudioEngine + SFSpeechRecognizer lifecycle.
/// Recognition callbacks hop to the main actor to mutate state safely.
@MainActor
@Observable
private final class MacVoiceController {
    enum RecordingState: Equatable { case idle, recording, transcribing }
    var recordingState: RecordingState = .idle

    // Audio objects are owned by the main actor; callbacks hop back to update them.
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var latestTranscript = ""
    private let speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer()

    /// Request speech + mic permissions, then begin recording.
    func startRecording(onFinished: @escaping @MainActor @Sendable (String) -> Void) {
        Task {
            // Request speech authorization
            let authStatus = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
                SFSpeechRecognizer.requestAuthorization { status in
                    cont.resume(returning: status)
                }
            }
            guard authStatus == .authorized else { return }

            // Request microphone access (macOS uses AVCaptureDevice, not AVAudioSession)
            let micGranted = await AVCaptureDevice.requestAccess(for: .audio)
            guard micGranted else { return }

            beginAudioSession(onFinished: onFinished)
        }
    }

    /// Stop recording; transcription finalises asynchronously. 3s timeout fallback.
    func stopRecording(onFinished: @escaping @MainActor @Sendable (String) -> Void) {
        recordingState = .transcribing
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        audioEngine = nil
        recognitionRequest = nil

        let captured = latestTranscript
        let capturedTask = recognitionTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.recordingState == .transcribing else { return }
            capturedTask?.cancel()
            self.recognitionTask = nil
            self.latestTranscript = ""
            self.recordingState = .idle
            if !captured.isEmpty { onFinished(captured) }
        }
    }

    private func beginAudioSession(onFinished: @escaping @MainActor @Sendable (String) -> Void) {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            Task { @MainActor [weak self] in
                self?.recognitionRequest?.append(buffer)
            }
        }

        do {
            engine.prepare()
            try engine.start()
        } catch { return }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString ?? ""
            let isFinal = result?.isFinal == true || error != nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !text.isEmpty { self.latestTranscript = text }
                if isFinal {
                    let finalText = self.latestTranscript
                    self.latestTranscript = ""
                    self.recognitionTask = nil
                    self.recordingState = .idle
                    if !finalText.isEmpty { onFinished(finalText) }
                }
            }
        }

        audioEngine = engine
        recognitionRequest = request
        recordingState = .recording
    }
}

// MARK: - MacAssistantPanel

/// Full-featured AI assistant chat panel with iOS feature parity.
/// Two display modes: floating overlay window, or docked side pane.
///
/// Features matching iOS AIChatView:
/// - Context-aware suggestion pools with Show more / Prompt library
/// - Page context chip showing current view (Home / Tasks / Email / Calendar)
/// - Voice input (speech-to-text) via macOS Speech framework
/// - Full input bar with attachment button, config, mic, and send controls
/// - Conversation history, model selection, retry, copy, thumbs feedback
/// - Web search indicators, source chips, reasoning box, mutation chips
struct MacAssistantPanel: View {
    @Environment(MacAppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FolderRecord.createdAt) private var folders: [FolderRecord]
    @Query(filter: #Predicate<TaskRecord> { !$0.completed }) private var allTasks: [TaskRecord]

    @Binding var isPresented: Bool
    @Binding var displayMode: AssistantDisplayMode
    /// Current page/section the user is viewing — drives context chip and suggestion pool
    var currentSelection: MacPrimarySelection = .home

    @State private var inputText = ""
    @State private var showsHistory = false
    @State private var showsPromptLibrary = false
    @State private var folderFilter: String = "all"
    @State private var movingConversation: MacChatConversation?

    // Page context pill — auto-set from currentSelection, user can remove
    @State private var pageContextAttached = true

    // Suggestion expansion
    @State private var suggestionsExpanded = false
    @State private var suggestionSeed = 0

    // File attachments — stored locally (not yet sent to backend, matching iOS behavior)
    @State private var isShowingFilePicker = false
    @State private var pendingAttachments: [URL] = []

    // Floating mode — position and size (self-managed)
    @State private var floatingOffset: CGSize = .zero
    @State private var dragAccumulator: CGSize = .zero
    @State private var floatingSize: CGSize = CGSize(width: 400, height: 560)
    @State private var resizeDragStart: CGSize?

    // Animated thinking text
    @State private var thinkingIndex = 0
    private let thinkingPhrases = ["Thinking", "Reading tasks", "Searching", "Writing"]

    // Rename conversation
    @State private var showsRenameAlert = false
    @State private var renameText = ""
    // Share conversation panel — creates a public shareable link
    @State private var showsSharePanel = false

    private var chatService: MacAIChatService { services.aiChatService }

    private var filteredConversations: [MacChatConversation] {
        chatService.savedConversations.filter { convo in
            let folderMatches: Bool = {
                switch folderFilter {
                case "all":
                    return true
                case "unfiled":
                    return convo.folderID == nil
                default:
                    return convo.folderID?.uuidString == folderFilter
                }
            }()

            guard folderMatches else { return false }
            return true
        }
    }

    private func folderName(for folderID: UUID?) -> String? {
        guard let folderID else { return nil }
        return folders.first(where: { $0.id == folderID })?.name
    }

    private func moveConversation(_ conversation: MacChatConversation, to folderID: UUID?) {
        chatService.moveConversation(conversation, to: folderID)
    }

    private func historyFilterButton(title: String, systemImage: String, filter: String) -> some View {
        let count: Int = {
            switch filter {
            case "all":
                return chatService.savedConversations.count
            case "unfiled":
                return chatService.savedConversations.filter { $0.folderID == nil }.count
            default:
                guard let folderID = UUID(uuidString: filter) else { return 0 }
                return chatService.savedConversations.filter { $0.folderID == folderID }.count
            }
        }()
        return Button {
            folderFilter = filter
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(0.7)
            }
            .foregroundStyle(folderFilter == filter ? MacTheme.accent : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(folderFilter == filter ? MacTheme.accent.opacity(0.12) : MacTheme.surfaceCard, in: Capsule())
            .overlay(Capsule().stroke(folderFilter == filter ? MacTheme.accent.opacity(0.25) : MacTheme.cardBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    /// Dark panel background — matches iOS AppTheme.backgroundTop
    private let panelBackground = Color(light: Color(white: 0.98), dark: Color(white: 0.08))

    /// AI gradient — matches the tab bar sparkles icon exactly (same stops as iOS)
    private var aiGradient: LinearGradient {
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

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider().opacity(0.3)

            if chatService.messages.isEmpty {
                emptyStateView
            } else {
                conversationView
            }

            Divider().opacity(0.3)
            inputSection
        }
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: displayMode == .floating ? 14 : 0, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: displayMode == .floating ? 14 : 0, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: displayMode == .floating ? 1 : 0)
        )
        // Resize handle — bottom-right corner (floating mode only)
        .overlay(alignment: .bottomTrailing) {
            if displayMode == .floating {
                Image(systemName: "line.diagonal")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(-45))
                    .frame(width: 14, height: 14)
                    .padding(6)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if resizeDragStart == nil { resizeDragStart = floatingSize }
                                let start = resizeDragStart ?? floatingSize
                                floatingSize = CGSize(
                                    width: max(320, min(700, start.width + value.translation.width)),
                                    height: max(400, min(900, start.height + value.translation.height))
                                )
                            }
                            .onEnded { _ in resizeDragStart = nil }
                    )
                    .onHover { hovering in
                        if hovering { NSCursor.crosshair.push() } else { NSCursor.pop() }
                    }
            }
        }
        .shadow(
            color: displayMode == .floating ? Color.black.opacity(0.2) : .clear,
            radius: displayMode == .floating ? 24 : 0,
            x: 0, y: displayMode == .floating ? 10 : 0
        )
        // Floating mode: self-managed size and position
        .frame(
            width: displayMode == .floating ? floatingSize.width : nil,
            height: displayMode == .floating ? floatingSize.height : nil
        )
        .offset(displayMode == .floating ? floatingOffset : .zero)
        // Cycle thinking text while streaming
        .task(id: chatService.isStreaming) {
            guard chatService.isStreaming else { return }
            thinkingIndex = 0
            while !Task.isCancelled && chatService.isStreaming {
                try? await Task.sleep(for: .seconds(2))
                thinkingIndex = (thinkingIndex + 1) % thinkingPhrases.count
            }
        }
        .task {
            await services.syncSharedFolders(in: modelContext)
        }
        // Auto-save conversation when panel hides
        .onChange(of: isPresented) { _, visible in
            if !visible { chatService.autosave() }
        }
        // Re-attach context pill when panel re-opens
        .onChange(of: isPresented) { _, visible in
            if visible { pageContextAttached = true }
        }
        // Draft persistence
        .onChange(of: inputText) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: "mac_ai_draft_input")
        }
        .onAppear {
            let draft = UserDefaults.standard.string(forKey: "mac_ai_draft_input") ?? ""
            if inputText.isEmpty { inputText = draft }
        }
        .confirmationDialog(
            "Move Conversation",
            isPresented: Binding(
                get: { movingConversation != nil },
                set: { if !$0 { movingConversation = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Unfiled") {
                if let conversation = movingConversation {
                    moveConversation(conversation, to: nil)
                }
                movingConversation = nil
            }
            ForEach(folders) { folder in
                Button(folder.name) {
                    if let conversation = movingConversation {
                        moveConversation(conversation, to: folder.id)
                    }
                    movingConversation = nil
                }
            }
            Button("Cancel", role: .cancel) {
                movingConversation = nil
            }
        }
        // History popover
        .popover(isPresented: $showsHistory, arrowEdge: .bottom) {
            historyList
                .frame(width: 300, height: 380)
        }
        // Prompt library popover
        .popover(isPresented: $showsPromptLibrary, arrowEdge: .bottom) {
            promptLibraryContent
                .frame(width: 320, height: 420)
        }
        // Share conversation popover — creates a public shareable link
        .popover(isPresented: $showsSharePanel, arrowEdge: .bottom) {
            if let id = chatService.currentConversationID?.uuidString {
                MacShareConversationPanel(
                    conversationId: id,
                    conversationTitle: chatService.chatTitle ?? "AI conversation"
                )
                .environment(services)
            }
        }
        // Close share panel when the conversation ID disappears (e.g. after a new chat)
        .onChange(of: chatService.currentConversationID) { _, newID in
            if newID == nil { showsSharePanel = false }
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
        // File picker
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            pendingAttachments.append(contentsOf: urls)
        }
    }

    // MARK: - Header (matches iOS toolbar: history | title | new chat + ... menu)

    private var panelHeader: some View {
        HStack(spacing: 8) {
            // History button (left, matching iOS placement)
            Button { showsHistory.toggle() } label: {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.7))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Conversation History")

            Spacer(minLength: 4)

            // Title (center)
            Text(chatService.chatTitle ?? "AI Assistant")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(1)
                .frame(maxWidth: 180)

            Spacer(minLength: 4)

            // New chat button
            Button {
                withAnimation(.snappy(duration: 0.2)) { chatService.clearHistory() }
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.7))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("New Conversation")

            // Ellipsis menu — conversation actions (matching iOS menu items)
            Menu {
                // Rename
                Button {
                    renameText = chatService.chatTitle ?? ""
                    showsRenameAlert = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                // Model picker
                Menu("Model") {
                    ForEach(availableModels, id: \.self) { model in
                        Button {
                            chatService.selectedModel = model
                        } label: {
                            HStack {
                                Text(modelDisplayName(model))
                                if chatService.selectedModel == model {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                if !chatService.messages.isEmpty {
                    Divider()

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(chatService.conversationAsMarkdown(), forType: .string)
                    } label: {
                        Label("Copy Conversation", systemImage: "doc.on.doc")
                    }

                    // Share — creates a public shareable link (requires saved conversation)
                    if chatService.currentConversationID != nil {
                        Button { showsSharePanel = true } label: {
                            Label("Share Conversation…", systemImage: "square.and.arrow.up")
                        }
                    }

                    Divider()

                    Button(role: .destructive) {
                        withAnimation(.snappy(duration: 0.2)) { chatService.clearHistory() }
                    } label: {
                        Label("Delete Conversation", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.7))
                    .frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 26)

            // Toggle floating / side pane
            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    displayMode = displayMode == .floating ? .sidepane : .floating
                }
            } label: {
                Image(systemName: displayMode == .floating ? "sidebar.right" : "macwindow")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.5))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(displayMode == .floating ? "Dock to Side" : "Float Window")

            // Close
            Button {
                withAnimation(.snappy(duration: 0.2)) { isPresented = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Close (⌘L)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(panelBackground.opacity(0.95))
        // Draggable header in floating mode
        .gesture(
            displayMode == .floating
                ? DragGesture()
                    .onChanged { value in
                        floatingOffset = CGSize(
                            width: dragAccumulator.width + value.translation.width,
                            height: dragAccumulator.height + value.translation.height
                        )
                    }
                    .onEnded { _ in dragAccumulator = floatingOffset }
                : nil
        )
    }

    // MARK: - Empty State (matches iOS: sparkle icon, heading, suggestions, show more, prompt library)

    private var emptyStateView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    // Animated sparkle icon — matching iOS AnimatedSparkleIcon
                    AnimatedSparkleIcon(size: 18)

                    Text("How can I help you today?")
                        .font(.system(size: 17, weight: .semibold))
                        .tracking(-0.3)
                }
                .padding(.horizontal, 14)

                if let error = chatService.errorMessage, !chatService.isStreaming {
                    Text(error)
                        .font(.system(size: 12.5))
                        .foregroundStyle(MacTheme.mutedText)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 14)
                }

                // Suggestions — 3 default, up to 10 when expanded
                VStack(alignment: .leading, spacing: 0) {
                    let pool = contextualSuggestionsPool
                    let shown = suggestionsExpanded ? pool : Array(pool.prefix(3))

                    ForEach(shown, id: \.text) { suggestion in
                        SuggestionRow(icon: suggestion.icon, text: suggestion.text) {
                            sendSuggestion($0)
                        }
                    }

                    // Show more / controls row
                    if suggestionsExpanded {
                        HStack(spacing: 12) {
                            Button {
                                withAnimation(.snappy(duration: 0.2)) { suggestionsExpanded = false }
                            } label: {
                                Label("Show less", systemImage: "chevron.up")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(MacTheme.mutedText)
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                withAnimation(.snappy(duration: 0.15)) { suggestionSeed += 1 }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(MacTheme.mutedText)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    } else if pool.count > 3 {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { suggestionsExpanded = true }
                        } label: {
                            Text("Show more")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(MacTheme.mutedText)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }

                    // Prompt library link
                    Button { showsPromptLibrary = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "bookmark")
                                .font(.system(size: 11, weight: .medium))
                            Text("Prompt library")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(MacTheme.mutedText)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }
                .padding(.horizontal, 6)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Conversation View

    private var conversationView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(chatService.messages) { message in
                        MacMessageBubble(
                            message: message,
                            allTasks: Array(allTasks),
                            canRetry: chatService.canRetry(assistantMessageID: message.id),
                            onRetry: {
                                chatService.retryMessage(
                                    assistantMessageID: message.id,
                                    allTasks: Array(allTasks),
                                    modelContext: modelContext
                                )
                            }
                        )
                        .id(message.id)
                    }

                    // Thinking indicator when streaming and before first token
                    if chatService.isStreaming,
                       chatService.messages.last?.content.isEmpty == true {
                        thinkingIndicator
                            .id("thinking")
                    }
                }
                .padding(14)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.automatic)
            .onChange(of: chatService.messages.count) {
                if let lastID = chatService.messages.last?.id {
                    withAnimation(.snappy(duration: 0.25)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
            .onChange(of: chatService.messages.last?.content) {
                if let lastID = chatService.messages.last?.id, chatService.isStreaming {
                    withAnimation(.linear(duration: 0.05)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
            .onChange(of: chatService.messages.last?.sources.count) {
                if let lastID = chatService.messages.last?.id {
                    withAnimation(.snappy(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Thinking Indicator

    private var thinkingIndicator: some View {
        HStack(spacing: 6) {
            AnimatedSparkleIcon(size: 12)

            Text(thinkingPhrases[thinkingIndex % thinkingPhrases.count])
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MacTheme.mutedText)
                .id(thinkingIndex)
                .transition(.opacity)
        }
        .padding(.leading, 4)
        .animation(.easeInOut(duration: 0.3), value: thinkingIndex)
    }

    // MARK: - Input Section (matches iOS: context chip, text field, toolbar with +/config/mic/send)

    private var inputSection: some View {
        VStack(spacing: 0) {
            // Context chip row — page context pill + attachment pills (above text field, inside the box)
            if pageContextAttached || !pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        // Page context pill — shows which page the user is on (matching iOS blue pill)
                        if pageContextAttached {
                            HStack(spacing: 5) {
                                Image(systemName: selectionIcon(currentSelection))
                                    .font(.system(size: 11, weight: .semibold))
                                Text(currentSelection.title)
                                    .font(.system(size: 11, weight: .medium))
                                Button {
                                    withAnimation(.snappy(duration: 0.15)) {
                                        pageContextAttached = false
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .buttonStyle(.plain)
                            }
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.blue.opacity(0.12), in: Capsule())
                        }

                        // Pending attachment pills
                        ForEach(pendingAttachments, id: \.absoluteString) { url in
                            HStack(spacing: 4) {
                                Image(systemName: "doc")
                                    .font(.system(size: 9, weight: .semibold))
                                Text(url.lastPathComponent)
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                                Button {
                                    pendingAttachments.removeAll { $0 == url }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .buttonStyle(.plain)
                            }
                            .foregroundStyle(MacTheme.mutedText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(MacTheme.surfaceCard, in: Capsule())
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.top, 8)
                .padding(.bottom, 2)
            }

            // Text field
            TextField("Ask, search or make anything…", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...6)
                .padding(.horizontal, 14)
                .padding(.top, (pageContextAttached || !pendingAttachments.isEmpty) ? 4 : 10)
                .padding(.bottom, 6)
                .onSubmit { sendMessage() }

            // Bottom toolbar: [+ attach] [config] | spacer | [mic] [send/stop]
            HStack(spacing: 4) {
                // Attachment button
                Button { isShowingFilePicker = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("Attach File")

                Spacer()

                // Voice-to-text mic button
                MacVoiceInputButton { transcribed in
                    let current = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    inputText = current.isEmpty ? transcribed : current + " " + transcribed
                }

                // Send or Stop button
                if chatService.isStreaming {
                    Button { chatService.cancelStream() } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Color.secondary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Stop Generating")
                    .transition(.scale.combined(with: .opacity))
                } else {
                    let isEmpty = inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(
                                isEmpty ? Color.secondary.opacity(0.3) : Color.accentColor,
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isEmpty)
                    .help("Send (⏎)")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
            .animation(.snappy(duration: 0.18), value: chatService.isStreaming)
        }
        .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .animation(.snappy(duration: 0.15), value: pendingAttachments.count)
    }

    // MARK: - History List

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("History")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.7))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    historyFilterButton(title: "All", systemImage: "tray", filter: "all")
                    historyFilterButton(title: "Unfiled", systemImage: "folder", filter: "unfiled")
                    ForEach(folders) { folder in
                        historyFilterButton(title: folder.name, systemImage: "folder.fill", filter: folder.id.uuidString)
                    }
                }
                .padding(.horizontal, 14)
            }
            .padding(.bottom, 8)

            Divider().opacity(0.3)

            if filteredConversations.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No saved conversations")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredConversations) { convo in
                            Button {
                                chatService.loadConversation(convo)
                                showsHistory = false
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(convo.title)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        HStack(spacing: 4) {
                                            Text(convo.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            if let folderName = folderName(for: convo.folderID) {
                                                Text("•")
                                                Label(folderName, systemImage: "folder")
                                            }
                                        }
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    // swipeActions removed — they only work inside List, not ScrollView+LazyVStack.
                                    // Move and Delete are exposed via the ellipsis Menu instead.
                                    Menu {
                                        Button("Unfiled") {
                                            moveConversation(convo, to: nil)
                                        }
                                        if !folders.isEmpty {
                                            Divider()
                                        }
                                        ForEach(folders) { folder in
                                            Button(folder.name) {
                                                moveConversation(convo, to: folder.id)
                                            }
                                        }
                                        Divider()
                                        Button(role: .destructive) {
                                            chatService.deleteConversation(convo)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.tertiary)
                                            .frame(width: 22, height: 22)
                                    }
                                    .menuStyle(.borderlessButton)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Prompt Library

    private var promptLibraryContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "bookmark")
                    .font(.system(size: 12, weight: .semibold))
                Text("Prompt Library")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.7))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider().opacity(0.3)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(promptTemplates) { prompt in
                        Button {
                            inputText = prompt.text
                            showsPromptLibrary = false
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: prompt.icon)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(MacTheme.mutedText)
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(prompt.category)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .textCase(.uppercase)
                                    Text(prompt.text)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        pendingAttachments = []
        UserDefaults.standard.removeObject(forKey: "mac_ai_draft_input")
        // Set page context so the AI knows where the user is
        chatService.currentPageContext = pageContextAttached ? currentSelection.title + " view" : nil
        chatService.send(userMessage: text, allTasks: Array(allTasks), modelContext: modelContext)
    }

    private func sendSuggestion(_ text: String) {
        chatService.currentPageContext = pageContextAttached ? currentSelection.title + " view" : nil
        chatService.send(userMessage: text, allTasks: Array(allTasks), modelContext: modelContext)
    }

    // MARK: - Context-Aware Suggestion Pool (matches iOS per-tab logic)

    private var contextualSuggestionsPool: [(icon: String, text: String)] {
        let activeCount = allTasks.count

        let pinned: [(icon: String, text: String)]
        let extended: [(icon: String, text: String)]

        switch currentSelection.category {
        case "email":
            pinned = [
                ("envelope.open",           "Summarize my recent emails"),
                ("arrowshape.turn.up.left", "Draft a reply to my latest email"),
                ("tray.and.arrow.down",     "Help me triage my inbox"),
            ]
            extended = [
                ("doc.text.magnifyingglass",   "What emails need my attention today?"),
                ("envelope.badge.person.crop", "Write a cold outreach email"),
                ("star",                       "Which emails are most important?"),
                ("paperplane",                 "Draft a follow-up to my last sent email"),
                ("flag",                       "Show me emails I've flagged"),
                ("magnifyingglass",            "Search for emails about a specific topic"),
            ]
        case "calendar":
            pinned = [
                ("clock",                "What's on my calendar today?"),
                ("calendar.badge.plus",  "Find free focus time this week"),
                ("person.2",             "Help me schedule a meeting"),
            ]
            extended = [
                ("brain.head.profile",                 "Create deep work blocks tomorrow"),
                ("calendar",                           "Give me a full overview of this week"),
                ("moon.stars",                         "Block time tomorrow for planning"),
                ("calendar.badge.exclamationmark",     "Do I have any scheduling conflicts?"),
                ("clock.badge.checkmark",              "When is my next free 2-hour window?"),
                ("sun.max",                            "Plan my ideal workday schedule"),
            ]
        case "tasks":
            if activeCount == 0 {
                pinned = [
                    ("plus.circle",  "Create my first tasks for today"),
                    ("sparkle",      "Brainstorm ideas for what to work on"),
                    ("list.bullet",  "Help me plan my week"),
                ]
            } else if activeCount <= 20 {
                pinned = [
                    ("arrow.up.circle",    "What should I prioritize today?"),
                    ("list.bullet.indent", "Break down my biggest task"),
                    ("checklist",          "Review my \(activeCount) open tasks"),
                ]
            } else {
                pinned = [
                    ("checkmark.circle",   "Help me clear my task backlog"),
                    ("arrow.up.circle",    "What are my top 3 priorities?"),
                    ("trash",              "Review and remove stale tasks"),
                ]
            }
            extended = [
                ("flag.fill",                "Set priority on all my tasks"),
                ("calendar.badge.checkmark", "Which tasks have deadlines this week?"),
                ("exclamationmark.circle",   "Show me all overdue tasks"),
                ("folder.badge.plus",        "Organize my tasks into folders"),
                ("moon.zzz",                 "Plan tomorrow and wind down my day"),
                ("pencil",                   "Rename or update outdated tasks"),
            ]
        default: // home
            pinned = [
                ("sun.max",                  "Give me a morning briefing"),
                ("sparkle",                  "What should I focus on right now?"),
                ("calendar.badge.checkmark", "Triage my tasks and calendar for today"),
            ]
            extended = [
                ("moon.stars",                    "End-of-day review — what did I accomplish?"),
                ("chart.line.uptrend.xyaxis",     "Weekly retrospective — what went well?"),
                ("flag",                          "What are my top priorities this week?"),
                ("rocket",                        "Help me kick off a new project"),
                ("envelope.open",                 "Any important emails I should handle first?"),
                ("brain.head.profile",            "Block focus time and clear my schedule"),
            ]
        }

        // Shuffle extended pool deterministically with seed
        var rng = SeededRandomNumberGenerator(seed: UInt64(suggestionSeed))
        let shuffled = extended.shuffled(using: &rng)
        return pinned + Array(shuffled.prefix(7))
    }

    // MARK: - Prompt Templates

    private var promptTemplates: [PromptTemplate] {
        [
            PromptTemplate(icon: "pencil", category: "Writing", text: "Help me write a professional email"),
            PromptTemplate(icon: "brain.head.profile", category: "Analysis", text: "Analyze my productivity this week"),
            PromptTemplate(icon: "lightbulb", category: "Ideas", text: "Brainstorm project ideas for…"),
            PromptTemplate(icon: "list.bullet", category: "Planning", text: "Create a detailed plan for…"),
            PromptTemplate(icon: "doc.text", category: "Summary", text: "Summarize the key points of…"),
            PromptTemplate(icon: "person.2", category: "Communication", text: "Draft a message to my team about…"),
            PromptTemplate(icon: "chart.bar", category: "Reports", text: "Generate a weekly status report"),
            PromptTemplate(icon: "calendar.badge.plus", category: "Scheduling", text: "Optimize my calendar for next week"),
            PromptTemplate(icon: "envelope.open", category: "Email", text: "Triage my inbox and flag urgent emails"),
            PromptTemplate(icon: "checkmark.circle", category: "Tasks", text: "Review all overdue tasks and suggest next steps"),
            PromptTemplate(icon: "moon.stars", category: "Reflection", text: "End-of-day wrap-up — what did I accomplish?"),
            PromptTemplate(icon: "flag", category: "Priorities", text: "Help me set priorities for the week ahead"),
        ]
    }

    // MARK: - Helpers

    private func selectionIcon(_ sel: MacPrimarySelection) -> String {
        switch sel {
        case .home: return "house.fill"
        case .tasks: return "checkmark.circle.fill"
        case .email: return "envelope.fill"
        case .calendar: return "calendar"
        case .meetings: return "video.fill"
        }
    }

    // Parity with iOS AIChatConfigSheet.availableModels — keep in sync
    private var availableModels: [String] {
        [
            "openai/gpt-5.4",
            "openai/gpt-5.4-mini",
            "openai/gpt-5.4-chat",
            "openai/gpt-5.4-nano",
            "anthropic/claude-sonnet-4-5",
            "anthropic/claude-haiku-4-5",
            "moonshotai/kimi-k2.5",
            "google/gemini-3.1-pro-preview",
            "google/gemini-3.1-flash-lite-preview",
            "google/gemini-3-flash-preview",
        ]
    }

    private func modelDisplayName(_ model: String) -> String {
        switch model {
        case "openai/gpt-5.4":                       return "GPT-5.4"
        case "openai/gpt-5.4-mini":                  return "GPT-5.4 Mini"
        case "openai/gpt-5.4-chat":                  return "GPT-5.4 Chat"
        case "openai/gpt-5.4-nano":                  return "GPT-5.4 Nano"
        case "anthropic/claude-sonnet-4-5":           return "Claude Sonnet 4.5"
        case "anthropic/claude-haiku-4-5":            return "Claude Haiku 4.5"
        case "moonshotai/kimi-k2.5":                  return "Kimi K2.5"
        case "google/gemini-3.1-pro-preview":         return "Gemini 3.1 Pro"
        case "google/gemini-3.1-flash-lite-preview":  return "Gemini 3.1 Flash Lite"
        case "google/gemini-3-flash-preview":         return "Gemini 3 Flash"
        default: return model
        }
    }
}

// MARK: - MacVoiceInputButton

/// Self-contained mic/stop/spinner control for speech-to-text on macOS.
/// Matches iOS VoiceInputButton: idle → recording → transcribing states.
private struct MacVoiceInputButton: View {
    let onTranscribed: @MainActor @Sendable (String) -> Void

    @State private var controller = MacVoiceController()

    var body: some View {
        Button(action: handleTap) {
            ZStack {
                switch controller.recordingState {
                case .idle:
                    Image(systemName: "mic")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                        .transition(.scale.combined(with: .opacity))
                case .recording:
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.red)
                        .transition(.scale.combined(with: .opacity))
                case .transcribing:
                    ProgressView()
                        .scaleEffect(0.55)
                        .tint(MacTheme.mutedText)
                        .transition(.opacity)
                }
            }
            .frame(width: 26, height: 26)
            .animation(.snappy(duration: 0.18), value: controller.recordingState)
        }
        .buttonStyle(.plain)
        .disabled(controller.recordingState == .transcribing)
        .help(controller.recordingState == .idle ? "Voice Input" : "Stop Recording")
    }

    private func handleTap() {
        switch controller.recordingState {
        case .idle:
            controller.startRecording(onFinished: onTranscribed)
        case .recording:
            controller.stopRecording(onFinished: onTranscribed)
        case .transcribing:
            break
        }
    }
}

// MARK: - AnimatedSparkleIcon

/// Sparkle icon with slowly rotating gradient and subtle ambient glow.
/// Direct port of the iOS AnimatedSparkleIcon.
private struct AnimatedSparkleIcon: View {
    let size: CGFloat

    @State private var rotation: Double = 0

    private var gradientColors: [Color] {
        [
            Color(red: 0, green: 0xAA / 255.0, blue: 0xF5 / 255.0),
            Color(red: 0xEF / 255.0, green: 0, blue: 0xC2 / 255.0),
            Color(red: 1, green: 0, blue: 0x38 / 255.0),
            Color(red: 0xF9 / 255.0, green: 0x9F / 255.0, blue: 0),
        ]
    }

    var body: some View {
        let animatedGradient = AngularGradient(
            colors: gradientColors + [gradientColors[0]],
            center: .center,
            angle: .degrees(rotation)
        )

        Image(systemName: "sparkles")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(animatedGradient)
            .background(
                Image(systemName: "sparkles")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(animatedGradient)
                    .blur(radius: 5)
                    .opacity(0.3)
            )
            .onAppear {
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - Message Bubble

private struct MacMessageBubble: View {
    let message: MacChatMessage
    let allTasks: [TaskRecord]
    let canRetry: Bool
    var onRetry: () -> Void = {}

    @State private var showActions = false
    @State private var didCopy = false
    @State private var thumbsState: ThumbsState? = nil
    @State private var showFullMarkdown = false

    private enum ThumbsState { case up, down }

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            HStack(alignment: .top) {
                if message.role == .user { Spacer(minLength: 50) }
                if message.role == .user { userBubble } else { assistantBubble }
                if message.role == .assistant { Spacer(minLength: 0) }
            }

            // Task mutation chips
            if !message.taskMutations.isEmpty {
                mutationChips
            }

            // Post-stream action row (retry, copy, thumbs)
            if message.role == .assistant && !message.isStreaming && !message.content.isEmpty {
                actionRow
                    .opacity(showActions ? 1 : 0)
                    .animation(.easeIn(duration: 0.3), value: showActions)
                    .onAppear {
                        guard !showActions else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation { showActions = true }
                        }
                    }
            }
        }
    }

    // MARK: User Bubble

    private var userBubble: some View {
        Text(message.content)
            .font(.system(size: 13, weight: .medium))
            .lineSpacing(2)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Assistant Bubble

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Web search indicator
            if message.searchState == .searching {
                searchingIndicator
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Source chips
            if !message.sources.isEmpty {
                sourceChips
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Reasoning box
            if !message.reasoningContent.isEmpty {
                reasoningBox
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Main content
            if !message.content.isEmpty {
                assistantContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: message.isStreaming) { _, isStreaming in
                        if !isStreaming {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation(.easeIn(duration: 0.3)) { showFullMarkdown = true }
                            }
                        }
                    }
                    .onAppear {
                        if !message.isStreaming { showFullMarkdown = true }
                    }
            }
        }
        .animation(.snappy(duration: 0.3), value: message.searchState)
        .animation(.snappy(duration: 0.3), value: message.sources.count)
    }

    // MARK: Assistant Content — Markdown

    @ViewBuilder
    private var assistantContent: some View {
        Group {
            if showFullMarkdown {
                fullMarkdownText(message.content)
                    .transition(.opacity)
            } else {
                inlineMarkdownText(message.content)
                    .transition(.opacity)
            }
        }
        .animation(.easeIn(duration: 0.3), value: showFullMarkdown)
        .font(.system(size: 13))
        .lineSpacing(3)
        .foregroundStyle(.primary.opacity(0.85))
        .textSelection(.enabled)
    }

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

    @ViewBuilder
    private func fullMarkdownText(_ content: String) -> some View {
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

    // MARK: Web Search

    private var searchingIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MacTheme.mutedText)
                .rotationEffect(.degrees(360))
                .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: message.searchState == .searching)

            VStack(alignment: .leading, spacing: 2) {
                Text("Searching the web…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MacTheme.mutedText)
                if !message.searchQueries.isEmpty {
                    Text(message.searchQueries.joined(separator: ", "))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var sourceChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(message.sources.enumerated()), id: \.element.id) { index, source in
                    Button {
                        if let url = URL(string: source.url) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("[\(index + 1)]")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(MacTheme.mutedText)
                            Image(systemName: "globe")
                                .font(.system(size: 9, weight: .medium))
                            Text(source.domain)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.primary.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(MacTheme.surfaceCard, in: Capsule())
                        .overlay(Capsule().stroke(MacTheme.cardBorder, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .help(source.title)
                }
            }
        }
    }

    // MARK: Reasoning Box (matches iOS ReasoningBox)

    private var reasoningBox: some View {
        MacReasoningBox(
            content: message.reasoningContent,
            durationMs: message.reasoningDurationMs,
            isStreaming: message.isStreaming
        )
    }

    // MARK: Mutation Chips

    private var mutationChips: some View {
        HStack(spacing: 4) {
            ForEach(message.taskMutations) { mutation in
                mutationChip(mutation)
            }
        }
        .padding(.leading, 2)
    }

    private func mutationChip(_ m: MacTaskMutation) -> some View {
        HStack(spacing: 4) {
            Image(systemName: mutationIcon(m))
                .font(.system(size: 9, weight: .semibold))
            Text(mutationLabel(m))
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(mutationColor(m))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(mutationColor(m).opacity(0.1), in: Capsule())
        .overlay(Capsule().stroke(mutationColor(m).opacity(0.25), lineWidth: 0.5))
        .transition(.scale.combined(with: .opacity))
    }

    private func mutationIcon(_ m: MacTaskMutation) -> String {
        switch m.action {
        case .create: return "plus.circle.fill"
        case .update: return "pencil.circle.fill"
        case .delete: return "trash.circle.fill"
        }
    }

    private func mutationLabel(_ m: MacTaskMutation) -> String {
        switch m.action {
        case .create: return "Created: \(m.title ?? "task")"
        case .update: return "Updated: \(m.title ?? "task")"
        case .delete: return "Deleted task"
        }
    }

    private func mutationColor(_ m: MacTaskMutation) -> Color {
        switch m.action {
        case .create: return .green
        case .update: return .blue
        case .delete: return .red
        }
    }

    // MARK: Action Row (matches iOS: retry, copy, thumbs up/down)

    private var actionRow: some View {
        HStack(spacing: 2) {
            // Retry
            Button { onRetry() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(canRetry ? 0.5 : 0.2))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canRetry)
            .help("Retry")

            // Copy
            Button {
                guard !didCopy else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
                withAnimation(.snappy(duration: 0.15)) { didCopy = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.snappy(duration: 0.15)) { didCopy = false }
                }
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(didCopy ? .green : .primary.opacity(0.5))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(didCopy ? "Copied!" : "Copy")

            // Thumbs up
            Button {
                withAnimation(.snappy(duration: 0.15)) {
                    thumbsState = thumbsState == .up ? nil : .up
                }
            } label: {
                Image(systemName: thumbsState == .up ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(thumbsState == .up ? Color.blue : MacTheme.mutedText)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Thumbs down
            Button {
                withAnimation(.snappy(duration: 0.15)) {
                    thumbsState = thumbsState == .down ? nil : .down
                }
            } label: {
                Image(systemName: thumbsState == .down ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(thumbsState == .down ? Color.orange : MacTheme.mutedText)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 2)
    }
}

// MARK: - MacReasoningBox (matches iOS ReasoningBox)

/// Collapsible thinking/reasoning box. Auto-expands while streaming, auto-collapses when done.
private struct MacReasoningBox: View {
    let content: String
    let durationMs: Int?
    let isStreaming: Bool

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "brain")
                        .font(.system(size: 11, weight: .medium))

                    if let ms = durationMs {
                        let seconds = max(1, ms / 1000)
                        Text("Thought for \(seconds)s")
                            .font(.system(size: 11, weight: .medium))
                    } else {
                        Text("Thinking…")
                            .font(.system(size: 11, weight: .medium))
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .animation(.snappy(duration: 0.2), value: isExpanded)
                }
                .foregroundStyle(MacTheme.mutedText)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(content)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(MacTheme.surfaceCard.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
        .onChange(of: isStreaming) { _, streaming in
            if !streaming && durationMs != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.snappy(duration: 0.3)) { isExpanded = false }
                }
            }
        }
    }
}

// MARK: - Suggestion Row

private struct SuggestionRow: View {
    let icon: String
    let text: String
    let action: (String) -> Void

    @State private var isHovered = false

    var body: some View {
        Button { action(text) } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MacTheme.mutedText)
                    .frame(width: 16)
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.8))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? MacTheme.surfaceHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }
}

// MARK: - Seeded Random Number Generator

/// Deterministic RNG for shuffling suggestions with a seed (so "Refresh" shows new ones).
private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed &+ 0x9E3779B97F4A7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
