import SwiftUI
import SwiftData
import Speech
import AVFoundation
import AppKit

// MARK: - Assistant Display Mode

/// Controls how the AI assistant panel is presented.
enum AssistantDisplayMode: String {
    case floating   // Overlay within the main window — draggable, resizable
    case sidepane   // Docked to the trailing edge of the main window
    case window     // Detached as a standalone NSWindow
    case full       // Fills the entire main window (replaces nav)
}

// MARK: - Floating Panel Geometry

/// Live geometry for the floating panel — owned by `FloatingPanelShell`, shared with
/// `MacAssistantPanel` for header-drag writes. Uses `@Observable` so only the thin shell
/// re-renders each frame during drag/resize; `MacAssistantPanel` is not re-rendered per frame.
@Observable
final class FloatingPanelGeometry: @unchecked Sendable {
    var liveSize: CGSize
    var liveOffset: CGSize

    init(size: CGSize = CGSize(width: 400, height: 560), offset: CGSize = .zero) {
        liveSize = size
        liveOffset = offset
    }
}

// MARK: - Prompt Template

/// A reusable prompt from the prompt library.
private struct PromptTemplate: Identifiable {
    let id = UUID()
    let icon: String
    let category: String
    let text: String
}

// MARK: - WeakRef

/// Sendable weak-reference box so we can capture a @MainActor object inside a
/// Task.detached / @Sendable closure without Swift 6 data-race errors.
/// Access `value` only from inside Task { @MainActor in }.
private final class MacVoiceWeakRef<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

// MARK: - MacAudioEngineHolder

/// Holds AVAudioEngine + SFSpeechRecognizer in an @unchecked Sendable container.
/// All methods are `nonisolated` so heavy audio operations always run off the
/// main actor regardless of the caller's isolation.
private final class MacAudioEngineHolder: @unchecked Sendable {
    let speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer()
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasInstalledTap = false
    private let lock = NSLock()

    /// Synchronous setup. MUST be called off the main thread — caller is always
    /// inside a Task.detached. AVAudioEngine.prepare()/start() can block for
    /// several seconds while hardware initialises.
    nonisolated func setupAndStartEngine() throws {
        assert(!Thread.isMainThread, "setupAndStartEngine must NOT run on main")

        var engine: AVAudioEngine?
        var request: SFSpeechAudioBufferRecognitionRequest?
        var didInstallTap = false

        do {
            let newEngine = AVAudioEngine()
            let newRequest = SFSpeechAudioBufferRecognitionRequest()
            newRequest.shouldReportPartialResults = true
            engine = newEngine
            request = newRequest

            let inputNode = newEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            guard format.channelCount > 0, format.sampleRate > 0 else {
                throw NSError(
                    domain: "VoiceInput",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Invalid audio format. The microphone may be in use by another app."]
                )
            }

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                newRequest.append(buffer)
            }
            didInstallTap = true

            newEngine.prepare()
            try newEngine.start()

            withLock {
                audioEngine = newEngine
                recognitionRequest = newRequest
                hasInstalledTap = true
            }
        } catch {
            if didInstallTap { engine?.inputNode.removeTap(onBus: 0) }
            if let engine, engine.isRunning { engine.stop() }
            request?.endAudio()
            withLock {
                audioEngine = nil
                recognitionRequest = nil
                recognitionTask = nil
                hasInstalledTap = false
            }
            throw error
        }
    }

    nonisolated func cleanup() {
        var engineToStop: AVAudioEngine?
        var hadTap = false
        withLock {
            recognitionTask?.cancel(); recognitionTask = nil
            recognitionRequest?.endAudio()
            engineToStop = audioEngine; hadTap = hasInstalledTap
            audioEngine = nil; recognitionRequest = nil; hasInstalledTap = false
        }
        Task.detached(priority: .utility) {
            if hadTap { engineToStop?.inputNode.removeTap(onBus: 0) }
            engineToStop?.stop()
        }
    }

    nonisolated func stopCapture() {
        var engineToStop: AVAudioEngine?
        var hadTap = false
        withLock {
            recognitionRequest?.endAudio()
            engineToStop = audioEngine; hadTap = hasInstalledTap
            audioEngine = nil; recognitionRequest = nil; hasInstalledTap = false
        }
        Task.detached(priority: .utility) {
            if hadTap { engineToStop?.inputNode.removeTap(onBus: 0) }
            engineToStop?.stop()
        }
    }

    nonisolated func currentRecognitionRequest() -> SFSpeechAudioBufferRecognitionRequest? {
        withLock { recognitionRequest }
    }

    nonisolated func setRecognitionTask(_ task: SFSpeechRecognitionTask?) {
        withLock { recognitionTask = task }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }; return body()
    }
}

// MARK: - MacVoiceController

/// Speech-to-text controller for macOS. Mirrors iOS VoiceController structure:
/// permission checks + audio engine setup run on Task.detached so the main
/// actor is never blocked. The closure-based SFSpeechRecognizer.requestAuthorization
/// and AVCaptureDevice.requestAccess APIs can stall the calling thread on first
/// use — running them via Task { @MainActor in } would freeze the UI because
/// that still executes on the main actor executor. Only Task.detached truly
/// leaves the main actor.
@MainActor
@Observable
private final class MacVoiceController {
    enum RecordingState: Equatable { case idle, starting, recording, transcribing }
    var recordingState: RecordingState = .idle

    private let holder = MacAudioEngineHolder()
    private var latestTranscript = ""
    private var onFinished: (@MainActor @Sendable (String) -> Void)?
    private var didFinishTranscription = false
    private var startupWatchdog: Task<Void, Never>?

    func startRecording(onFinished: @escaping @MainActor @Sendable (String) -> Void) {
        guard recordingState == .idle else { return }
        latestTranscript = ""
        didFinishTranscription = false
        self.onFinished = onFinished
        recordingState = .starting
        armWatchdog()

        let holder = self.holder
        let ref = MacVoiceWeakRef(self)

        Task.detached(priority: .userInitiated) {
            await MacVoiceController.setupOnBackground(ref: ref, holder: holder)
        }
    }

    func stopRecording(onFinished: @escaping @MainActor @Sendable (String) -> Void) {
        guard recordingState == .recording else { return }
        self.onFinished = onFinished
        recordingState = .transcribing
        holder.stopCapture()

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.recordingState == .transcribing else { return }
            let captured = self.latestTranscript
            self.holder.cleanup()
            self.latestTranscript = ""
            self.recordingState = .idle
            if !captured.isEmpty { self.finishTranscription(captured) }
        }
    }

    /// Tear down any in-flight recording / watchdog. Safe to call from .onDisappear.
    func tearDown() {
        cancelWatchdog()
        if recordingState != .idle {
            holder.cleanup()
            latestTranscript = ""
            recordingState = .idle
            onFinished = nil
            didFinishTranscription = false
        }
    }

    /// Pure background function. `static` so it cannot accidentally capture any
    /// MainActor-isolated state. All MainActor updates go through `ref`.
    private static nonisolated func setupOnBackground(
        ref: MacVoiceWeakRef<MacVoiceController>,
        holder: MacAudioEngineHolder
    ) async {
        // 1. Speech permission — only call the dialog-triggering API when truly
        // undetermined; `authorizationStatus()` is a non-blocking lookup.
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        if speechStatus == .notDetermined {
            let resolved = await withCheckedContinuation {
                (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
                SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
            }
            guard resolved == .authorized else {
                await MainActor.run { ref.value?.fail() }
                return
            }
        } else if speechStatus != .authorized {
            await MainActor.run { ref.value?.fail() }
            return
        }

        // 2. Mic permission (macOS uses AVCaptureDevice, not AVAudioSession)
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else {
                await MainActor.run { ref.value?.fail() }
                return
            }
        } else if micStatus != .authorized {
            await MainActor.run { ref.value?.fail() }
            return
        }

        // 3. Recognizer availability
        guard let recognizer = holder.speechRecognizer, recognizer.isAvailable else {
            await MainActor.run { ref.value?.fail() }
            return
        }

        // 4. Audio engine — synchronous and blocking, run here on the bg task.
        do {
            try holder.setupAndStartEngine()
        } catch {
            await MainActor.run { ref.value?.fail() }
            return
        }

        guard let request = holder.currentRecognitionRequest() else {
            await MainActor.run { ref.value?.fail() }
            return
        }

        // 5. Recognition task — callback fires on bg, hop to main for state.
        let task = recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString ?? ""
            let isFinal = result?.isFinal == true || error != nil
            Task { @MainActor in
                guard let ctrl = ref.value else { return }
                if !text.isEmpty { ctrl.latestTranscript = text }
                if isFinal {
                    let finalText = ctrl.latestTranscript
                    ctrl.latestTranscript = ""
                    ctrl.holder.cleanup()
                    ctrl.recordingState = .idle
                    if !finalText.isEmpty { ctrl.finishTranscription(finalText) }
                }
            }
        }
        holder.setRecognitionTask(task)

        await MainActor.run {
            guard let ctrl = ref.value else { return }
            ctrl.recordingState = .recording
            ctrl.cancelWatchdog()
        }
    }

    fileprivate func fail() {
        holder.cleanup()
        recordingState = .idle
        latestTranscript = ""
        onFinished = nil
        cancelWatchdog()
    }

    private func finishTranscription(_ text: String) {
        guard !didFinishTranscription, !text.isEmpty else { return }
        didFinishTranscription = true
        let cb = onFinished
        onFinished = nil
        cb?(text)
    }

    private func armWatchdog() {
        cancelWatchdog()
        startupWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self else { return }
            if self.recordingState == .starting { self.fail() }
        }
    }

    private func cancelWatchdog() {
        startupWatchdog?.cancel()
        startupWatchdog = nil
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
    /// Shared geometry for floating-mode header drag. Owned by `FloatingPanelShell`; reads are
    /// only in gesture closures so `@Observable` changes don't re-render this view per frame.
    var geo: FloatingPanelGeometry? = nil
    /// Called once on header-drag end so the caller can persist the new offset to disk.
    var onHeaderDragCommit: (() -> Void)? = nil
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

    // Live voice chat sheet
    @State private var isShowingVoiceChat = false

    /// Remembered offset at the start of a header drag — used to compute absolute position.
    @State private var headerDragStart: CGSize?
    @State private var isHeaderTitleHovered = false
    @State private var isHeaderTitleDragging = false

    // Animated thinking text
    @State private var thinkingIndex = 0
    private let thinkingPhrases = ["Thinking", "Reading tasks", "Searching", "Writing"]

    // Chat input dynamic height — driven by text content, reset on send
    @State private var chatInputHeight: CGFloat = 18

    // Rename conversation
    @State private var showsRenameAlert = false
    @State private var renameText = ""
    // Share conversation panel — creates a public shareable link
    @State private var showsSharePanel = false
    @State private var showEmailSettingsFallbackAlert = false

    // Panel content mode — drives which content the panel shows
    // Groups live here (inside the panel), NOT in the sidebar
    enum PanelContent: Equatable {
        case chat
        case groupList
        case groupChat(String)  // groupId
    }
    @State private var panelContent: PanelContent = .chat

    private var chatService: MacAIChatService { services.aiChatService }

    /// Whether EventKit calendar access has been granted.
    private var calendarConnected: Bool {
        services.calendarService.canReadEvents()
    }
    /// Whether email is connected and authenticated.
    private var emailConnected: Bool {
        services.emailService.hasConnection
    }

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
        .macClickablePointer()
    }

    /// Dark panel background — matches iOS AppTheme.backgroundTop via MacTheme.contentBackground
    private let panelBackground = MacTheme.contentBackground

    private var displayModeIcon: String {
        switch displayMode {
        case .floating: return "macwindow"
        case .sidepane: return "sidebar.right"
        case .window:   return "uiwindow.split.2x1"
        case .full:     return "arrow.up.left.and.arrow.down.right"
        }
    }

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

            // Content area switches between chat, group list, and group chat
            switch panelContent {
            case .chat:
                if chatService.messages.isEmpty {
                    emptyStateView
                } else {
                    conversationView
                }
                Divider().opacity(0.3)
                inputSection

            case .groupList:
                ScrollView {
                    MacGroupListSection(
                        onSelect: { groupId in
                            panelContent = .groupChat(groupId)
                        },
                        activeGroupId: nil
                    )
                    .padding(12)
                    .background(MacScrollViewChromeAnchor())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { MacScrollStyle.reapplyToAllWindows() }

            case .groupChat(let groupId):
                MacGroupChatView(groupId: groupId)
            }
        }
        .background(panelBackground)
        // Side pane and full-screen are flush to the window edge — no rounding. Floating and window modes round.
        .clipShape(RoundedRectangle(cornerRadius: (displayMode == .sidepane || displayMode == .full) ? 0 : MacTheme.rowRadius, style: .continuous))
        .overlay(
            // Border only in floating mode; window chrome and other modes provide their own boundary.
            RoundedRectangle(cornerRadius: (displayMode == .sidepane || displayMode == .full) ? 0 : MacTheme.rowRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: displayMode == .floating ? 1 : 0)
        )
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
            do {
                try await services.syncSharedFolders(in: modelContext)
            } catch {
                AppLogger.shared.log("[MacAssistantPanel] Failed to sync shared folders: \(error)")
            }
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
        // Live voice chat — bidirectional Gemini Live session via the backend WS proxy
        .sheet(isPresented: $isShowingVoiceChat) {
            MacVoiceChatPanel(
                chatService: chatService,
                tokenService: services.voiceTokenService,
                services: services
            )
        }
    }

    /// Gradient for the live-voice waveform button — matches the iOS treatment.
    private var voiceButtonGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0x00 / 255.0, green: 0xAA / 255.0, blue: 0xF5 / 255.0),
                Color(red: 0xEF / 255.0, green: 0x00 / 255.0, blue: 0xC2 / 255.0),
                Color(red: 0xFF / 255.0, green: 0x00 / 255.0, blue: 0x38 / 255.0),
                Color(red: 0xF9 / 255.0, green: 0x9F / 255.0, blue: 0x00 / 255.0),
            ],
            startPoint: UnitPoint(x: 0.3, y: 0),
            endPoint: UnitPoint(x: 0.7, y: 1)
        )
    }

    // MARK: - Header (matches iOS toolbar: history | title | new chat + ... menu)

    @ViewBuilder
    private var headerTitleView: some View {
        switch panelContent {
        case .chat:
            Text(chatService.chatTitle ?? "AI Assistant")
        case .groupList:
            Text("Group Chats")
        case .groupChat:
            Text(services.groupChatService.currentGroupDetails?.name ?? "Group")
        }
    }

    private var floatingHeaderMoveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard let geo else { return }
                if !isHeaderTitleDragging {
                    isHeaderTitleDragging = true
                    NSCursor.closedHand.set()
                }
                if headerDragStart == nil { headerDragStart = geo.liveOffset }
                let start = headerDragStart ?? .zero
                // Write directly to geo — FloatingPanelShell re-renders (cheap), not this view.
                geo.liveOffset = CGSize(
                    width: start.width + value.translation.width,
                    height: start.height + value.translation.height
                )
            }
            .onEnded { _ in
                headerDragStart = nil
                isHeaderTitleDragging = false
                syncHeaderTitleMoveCursor()
                onHeaderDragCommit?()
            }
    }

    private func syncHeaderTitleMoveCursor() {
        guard displayMode == .floating else { return }
        if isHeaderTitleHovered {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private var panelHeader: some View {
        HStack(spacing: 8) {
            if panelContent == .chat {
                Button { showsHistory.toggle() } label: {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.7))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .macClickablePointer()
                .help("Conversation History")
                .accessibilityLabel("Conversation History")
            } else {
                Button {
                    withAnimation(MacTheme.Motion.base) { panelContent = .chat }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.7))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .macClickablePointer()
                .help("Back to Chat")
                .accessibilityLabel("Back to Chat")
            }

            if displayMode == .floating {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    headerTitleView
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 32)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHeaderTitleHovered = hovering
                    if !isHeaderTitleDragging { syncHeaderTitleMoveCursor() }
                }
                .gesture(floatingHeaderMoveGesture)
            } else {
                Spacer(minLength: 4)
                headerTitleView
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(1)
                    .frame(maxWidth: 180)
                Spacer(minLength: 4)
            }

            if panelContent == .chat {
                Button {
                    withAnimation(MacTheme.Motion.base) { panelContent = .groupList }
                } label: {
                    Image(systemName: "person.2")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.7))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .macClickablePointer()
                .help("Group Chats")
                .accessibilityLabel("Group Chats")
            }

            if panelContent == .chat {
                Button {
                    withAnimation(MacTheme.Motion.base) { chatService.clearHistory() }
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.7))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .macClickablePointer()
                .help("New Conversation")
                .accessibilityLabel("New Conversation")
            }

            if panelContent == .chat { Menu {
                Button {
                    renameText = chatService.chatTitle ?? ""
                    showsRenameAlert = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
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
                    if chatService.currentConversationID != nil {
                        Button { showsSharePanel = true } label: {
                            Label("Share Conversation…", systemImage: "square.and.arrow.up")
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        withAnimation(MacTheme.Motion.base) { chatService.clearHistory() }
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
            .macClickablePointer()
            .frame(width: 26)
            }

            // Layout picker — Floating / Side panel / Separate window
            Menu {
                Button {
                    withAnimation(MacTheme.Motion.base) { displayMode = .floating }
                } label: {
                    Label("Floating Panel", systemImage: "macwindow")
                }
                .disabled(displayMode == .floating)

                Button {
                    withAnimation(MacTheme.Motion.base) { displayMode = .sidepane }
                } label: {
                    Label("Side Panel", systemImage: "sidebar.right")
                }
                .disabled(displayMode == .sidepane)

                Button {
                    displayMode = .window
                } label: {
                    Label("Separate Window", systemImage: "uiwindow.split.2x1")
                }
                .disabled(displayMode == .window)

                Divider()

                Button {
                    withAnimation(MacTheme.Motion.base) { displayMode = .full }
                } label: {
                    Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .disabled(displayMode == .full)
            } label: {
                Image(systemName: displayModeIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.5))
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .macClickablePointer()
            .frame(width: 26)
            .help("Panel Layout")
            .accessibilityLabel("Panel Layout")

            Button {
                withAnimation(MacTheme.Motion.base) { isPresented = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .macClickablePointer()
            .help("Close (⌘L)")
            .accessibilityLabel("Close assistant panel")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(panelBackground.opacity(0.95))
        .onChange(of: displayMode) { _, newMode in
            if newMode != .floating {
                isHeaderTitleHovered = false
                isHeaderTitleDragging = false
                NSCursor.arrow.set()
            }
        }
    }

    // MARK: - Empty State (matches iOS: sparkle icon, heading, suggestions, show more, prompt library)

    /// Compact connect buttons shown when the active section's service pool is empty.
    private var macConnectServicesPrompt: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connect a service to get started")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MacTheme.mutedText)
            HStack(spacing: 8) {
                if !calendarConnected && ["calendar", "home"].contains(currentSelection.category) {
                    Button {
                        Task { _ = await services.calendarService.requestAccess() }
                    } label: {
                        Label("Connect Calendar", systemImage: "calendar")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.1), in: Capsule())
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .macClickablePointer()
    }
                if !emailConnected && ["email", "home"].contains(currentSelection.category) {
                    Button {
                        openInternetAccountsSettings()
                    } label: {
                        Label("Connect Email", systemImage: "envelope")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.orange.opacity(0.1), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .macClickablePointer()
    }
            }
        }
        .alert("Configure Email in System Settings", isPresented: $showEmailSettingsFallbackAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Open System Settings > Internet Accounts to connect an email account, then return to Todus.")
        }
    }

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
                    // When pool is empty the current section's service isn't connected — show CTA
                    if pool.isEmpty {
                        macConnectServicesPrompt
                            .padding(.horizontal, 12)
                            .padding(.top, 2)
                            .padding(.bottom, 8)
                    }
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
                                withAnimation(MacTheme.Motion.base) { suggestionsExpanded = false }
                            } label: {
                                Label("Show less", systemImage: "chevron.up")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(MacTheme.mutedText)
                            }
                            .buttonStyle(.plain)
                            .macClickablePointer()
                            Spacer()

                            Button {
                                withAnimation(MacTheme.Motion.fast) { suggestionSeed += 1 }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(MacTheme.mutedText)
                            }
                            .buttonStyle(.plain)
                            .macClickablePointer()
    }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    } else if pool.count > 3 {
                        Button {
                            withAnimation(MacTheme.Motion.base) { suggestionsExpanded = true }
                        } label: {
                            Text("Show more")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(MacTheme.mutedText)
                        }
                        .buttonStyle(.plain)
                        .macClickablePointer()
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
                    .macClickablePointer()
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
                            calendarConnected: calendarConnected,
                            emailConnected: emailConnected,
                            onRetry: {
                                chatService.retryMessage(
                                    assistantMessageID: message.id,
                                    allTasks: Array(allTasks),
                                    modelContext: modelContext
                                )
                            },
                            onConnect: { service in
                                if service == "calendar" {
                                    Task { _ = await services.calendarService.requestAccess() }
                                }
                                // email: user needs to go to system settings — no in-app action on macOS
                            },
                            onOpenEmailSettings: openInternetAccountsSettings,
                            onEdit: { edited in editMessage(edited) },
                            onSpecAction: { action, params, completion in
                                handleSpecAction(action, params: params, completion: completion)
                            },
                            onUpgrade: {
                                if let url = URL(string: upgradePricingURL()) {
                                    NSWorkspace.shared.open(url)
                                }
                            },
                            onInsertIntoDoc: {
                                guard currentSelection.category == "docs",
                                      !message.isStreaming,
                                      message.role == .assistant,
                                      chatService.messages.last(where: { $0.role == .assistant })?.id == message.id
                                else { return nil }
                                return { text in services.docsService.pendingDocInsert = text }
                            }()
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
                // Ensures the nested SwiftUI `ScrollView`’s `NSScrollView` + `NSClipView` get
                // overlay style and no track strip (global tree walk often misses this region).
                .background(MacScrollViewChromeAnchor())
            }
            .scrollIndicators(.automatic)
            .onAppear { MacScrollStyle.reapplyToAllWindows() }
            .onChange(of: chatService.messages.count) {
                if let lastID = chatService.messages.last?.id {
                    withAnimation(MacTheme.Motion.base) {
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
                    withAnimation(MacTheme.Motion.base) {
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
        .animation(MacTheme.Motion.slow, value: thinkingIndex)
    }

    // MARK: - Input Section (matches iOS: context chip, text field, toolbar with +/config/mic/send)

    private var inputSection: some View {
        VStack(spacing: 0) {
            // Context chip row — page context pill + attachment pills (above text field, inside the box)
            if pageContextAttached || !pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .center, spacing: 6) {
                        // Page context pill — shows which page the user is on (matching iOS blue pill)
                        if pageContextAttached {
                            HStack(spacing: 5) {
                                Image(systemName: selectionIcon(currentSelection))
                                    .font(.system(size: 11, weight: .semibold))
                                Text(pillTitle)
                                    .font(.system(size: 11, weight: .medium))
                                Button {
                                    withAnimation(MacTheme.Motion.fast) {
                                        pageContextAttached = false
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .buttonStyle(.plain)
                                .macClickablePointer()
    }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.12), in: Capsule())
                        }

                        ForEach(pendingAttachments, id: \.self) { url in
                            MacPendingAttachmentChip(url: url) {
                                removePendingAttachment(url)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                .padding(.bottom, 2)
            }

            // Multiline text input: Return = newline, Cmd+Return = send.
            // Using NSViewRepresentable (NSTextView) instead of SwiftUI's TextField because
            // TextField.onSubmit fires on ALL Return presses with no way to distinguish
            // Shift/Option+Return, preventing users from entering line breaks.
            ZStack(alignment: .topLeading) {
                MacChatTextInput(
                    text: $inputText,
                    contentHeight: $chatInputHeight,
                    onSend: sendMessage,
                    onPastedFileURLs: { urls in
                        pendingAttachments.append(contentsOf: urls)
                    }
                )
                    .frame(height: chatInputHeight)
                    .padding(.horizontal, 14)
                    .padding(.top, (pageContextAttached || !pendingAttachments.isEmpty) ? 4 : 10)
                    .padding(.bottom, 6)

                // Placeholder shown when input is empty
                if inputText.isEmpty {
                    Text("Ask, search or make anything…")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.top, (pageContextAttached || !pendingAttachments.isEmpty) ? 4 : 10)
                        .allowsHitTesting(false)
                }
            }

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
                .macClickablePointer()
                .help("Attach File")
                .accessibilityLabel("Attach File")

                Spacer()

                // Live voice chat — opens a full bidirectional voice session
                Button { isShowingVoiceChat = true } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(voiceButtonGradient)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .macClickablePointer()
                .help("Live Voice Chat")
                .accessibilityLabel("Live Voice Chat")

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
                    .macClickablePointer()
                    .help("Stop Generating")
                    .accessibilityLabel("Stop Generating")
                    .transition(.scale.combined(with: .opacity))
                } else {
                    let textEmpty = inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let isEmpty = textEmpty && pendingAttachments.isEmpty
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
                    .macClickablePointer()
                    .disabled(isEmpty)
                    .help("Send (⌘↵)")
                    .accessibilityLabel("Send message")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
            .animation(MacTheme.Motion.base, value: chatService.isStreaming)
        }
        .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.rowRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.rowRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .animation(MacTheme.Motion.fast, value: pendingAttachments.count)
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
                                    .macClickablePointer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .macClickablePointer()
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
                        .macClickablePointer()
    }
                }
            }
        }
    }

    // MARK: - Actions

    /// Removes a pending chip and deletes files we only keep for upload when they live in the system temp dir (e.g. paste-generated images).
    private func removePendingAttachment(_ url: URL) {
        pendingAttachments.removeAll { $0 == url }
        guard url.isFileURL else { return }
        let tmp = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let path = url.resolvingSymlinksInPath().path
        if path.hasPrefix(tmp.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAttachments = !pendingAttachments.isEmpty
        guard !text.isEmpty || hasAttachments else { return }

        let messageText: String
        if text.isEmpty, hasAttachments {
            let n = pendingAttachments.count
            messageText = n == 1
                ? "View the attached file"
                : "View the \(n) attached files"
        } else {
            messageText = text
        }

        let urls = pendingAttachments
        inputText = ""
        chatInputHeight = 18
        pendingAttachments = []
        UserDefaults.standard.removeObject(forKey: "mac_ai_draft_input")
        // Set page context so the AI knows where the user is
        chatService.currentPageContext = pageContextAttached ? {
            if currentSelection.category == "docs",
               let id = services.docsService.currentOpenDocId,
               let title = services.docsService.allDocs.first(where: { $0.id == id })?.title {
                return "Doc: \(title)"
            }
            return currentSelection.title + " view"
        }() : nil
        chatService.send(
            userMessage: messageText,
            attachmentURLs: urls,
            allTasks: Array(allTasks),
            modelContext: modelContext
        )
    }

    private func sendSuggestion(_ text: String) {
        chatService.currentPageContext = pageContextAttached ? {
            if currentSelection.category == "docs",
               let id = services.docsService.currentOpenDocId,
               let title = services.docsService.allDocs.first(where: { $0.id == id })?.title {
                return "Doc: \(title)"
            }
            return currentSelection.title + " view"
        }() : nil
        chatService.send(userMessage: text, allTasks: Array(allTasks), modelContext: modelContext)
    }

    /// Right-click "Edit" on a user bubble: load its content back into the composer,
    /// drop the edited turn and everything after it, and let the user re-send with
    /// new wording. Attachments aren't restored — the original file URLs aren't kept
    /// on macOS once the message is sent, so the user re-attaches if needed.
    private func editMessage(_ message: MacChatMessage) {
        guard message.role == .user, !chatService.isStreaming else { return }
        inputText = message.content
        pendingAttachments = []
        chatService.truncateBefore(messageID: message.id)
        UserDefaults.standard.set(message.content, forKey: "mac_ai_draft_input")
    }

    // MARK: - Context-Aware Suggestion Pool (matches iOS per-tab logic)

    private var contextualSuggestionsPool: [(icon: String, text: String)] {
        let activeCount = allTasks.count

        let pinned: [(icon: String, text: String)]
        let extended: [(icon: String, text: String)]

        switch currentSelection.category {
        case "email":
            // Only show email suggestions when inbox is connected
            guard emailConnected else { return [] }
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
            // Only show calendar suggestions when EventKit access is granted
            guard calendarConnected else { return [] }
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
        case "docs":
            pinned = [
                ("pencil",            "Continue where I left off"),
                ("wand.and.stars",    "Improve the writing and clarity"),
                ("list.bullet.indent","Add structure with headings and sections"),
            ]
            extended = [
                ("text.alignleft",                    "Write an introduction for this document"),
                ("doc.text.magnifyingglass",           "Summarize this document"),
                ("checkmark.circle",                   "Fix grammar and tone throughout"),
                ("arrow.down.right.and.arrow.up.left", "Make this more concise"),
                ("plus.bubble",                        "Expand the main points with more detail"),
                ("text.badge.checkmark",               "Add a conclusion"),
                ("list.bullet",                        "Convert paragraphs into bullet points"),
            ]
        default: // home
            pinned = [
                ("sun.max",    "Give me a morning briefing"),
                ("sparkle",    "What should I focus on right now?"),
            ] + (calendarConnected
                 ? [("calendar.badge.checkmark", "Triage my tasks and calendar for today")]
                 : [("list.bullet", "Review my task list")])
            var extBase: [(icon: String, text: String)] = [
                ("moon.stars",                    "End-of-day review — what did I accomplish?"),
                ("chart.line.uptrend.xyaxis",     "Weekly retrospective — what went well?"),
                ("flag",                          "What are my top priorities this week?"),
                ("rocket",                        "Help me kick off a new project"),
                ("brain.head.profile",            "Block focus time and clear my schedule"),
            ]
            if emailConnected { extBase.append(("envelope.open", "Any important emails I should handle first?")) }
            extended = extBase
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

    private var pillTitle: String {
        if currentSelection.category == "docs",
           let id = services.docsService.currentOpenDocId,
           let title = services.docsService.allDocs.first(where: { $0.id == id })?.title {
            return title
        }
        return currentSelection.title
    }

    private func selectionIcon(_ sel: MacPrimarySelection) -> String {
        switch sel {
        case .home: return "house.fill"
        case .tasks: return "checkmark.circle.fill"
        case .email: return "envelope.fill"
        case .calendar: return "calendar"
        case .meetings: return "video.fill"
        case .docs: return "doc.text.fill"
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

    private func upgradePricingURL() -> String {
        let backend = services.apiClient.baseURL.absoluteString
        if let host = URL(string: backend)?.host, host.hasPrefix("api.") {
            return "https://\(String(host.dropFirst("api.".count)))/pricing"
        }
        return "https://todus.app/pricing"
    }

    private func openInternetAccountsSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension"
        ), NSWorkspace.shared.open(url) else {
            showEmailSettingsFallbackAlert = true
            return
        }
    }

    /// Handles generative-UI card actions emitted by ChatUISpecView. Side-effecting actions
    /// (clipboard, draft autosave/send, undo) execute locally; navigation falls through.
    /// `completion` is invoked for async actions so the originating card can report success/failure.
    private func handleSpecAction(
        _ action: String,
        params: [String: String],
        completion: MacChatUISpecActionCompletion? = nil,
        undoDepth: Int = 0
    ) {
        let maxUndoDepth = 8
        switch action {
        case "copy_text":
            if let content = params["content"] {
                let pb = NSPasteboard.general
                pb.declareTypes([.string], owner: nil)
                pb.setString(content, forType: .string)
            }
            completion?(true, nil)
        case "update_draft":
            guard let draftId = params["draftId"], let payloadStr = params["payload"],
                  let payload = MacDraftService.decodePayload(payloadStr) else {
                completion?(false, "Invalid draft payload")
                return
            }
            Task { @MainActor in
                do {
                    try await services.draftService.update(draftId: draftId, payload: payload)
                    completion?(true, nil)
                } catch {
                    completion?(false, error.localizedDescription)
                }
            }
        case "send_draft":
            guard let payloadStr = params["payload"],
                  let payload = MacDraftService.decodePayload(payloadStr) else {
                completion?(false, "Invalid send payload")
                return
            }
            let draftId = params["draftId"]
            Task { @MainActor in
                do {
                    try await services.draftService.send(draftId: draftId, payload: payload)
                    completion?(true, nil)
                } catch {
                    completion?(false, error.localizedDescription)
                }
            }
        case "attach_to_draft":
            // Attachment picking belongs to the host composer — left as a no-op for now.
            completion?(true, nil)
        case "undo":
            guard undoDepth < maxUndoDepth else {
                completion?(false, nil)
                return
            }
            guard let undoAction = params["undoAction"], !undoAction.isEmpty, undoAction != "undo" else {
                // Always notify the caller — silently returning leaves the originating UI card
                // (e.g. the action confirmation) waiting indefinitely for a result.
                completion?(false, nil)
                return
            }
            var nestedParams: [String: String] = [:]
            if let nestedRaw = params["undoParams"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !nestedRaw.isEmpty,
               let data = nestedRaw.data(using: .utf8),
               let dict = try? JSONDecoder().decode([String: String].self, from: data) {
                nestedParams = dict
            }
            handleSpecAction(undoAction, params: nestedParams, completion: completion, undoDepth: undoDepth + 1)
        case "navigate_thread", "navigate_task", "navigate_event", "navigate_draft",
             "navigate_document", "navigate_day":
            // No deep navigation surface yet on macOS — log so we know when the AI emits these.
            AppLogger.shared.log("[MacAssistantPanel] navigate action: \(action) \(params)")
            completion?(true, nil)
        case "open_attachment":
            if let url = params["previewUrl"], let parsed = URL(string: url) {
                NSWorkspace.shared.open(parsed)
            }
            completion?(true, nil)
        case "toggle_checklist_item":
            // Local-only toggle; persistence model TBD on macOS as well.
            completion?(true, nil)
        default:
            AppLogger.shared.log("[MacAssistantPanel] unknown spec action: \(action) \(params)")
            completion?(true, nil)
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
                case .starting, .transcribing:
                    ProgressView()
                        .scaleEffect(0.55)
                        .tint(MacTheme.mutedText)
                        .transition(.opacity)
                }
            }
            .frame(width: 26, height: 26)
            .animation(MacTheme.Motion.base, value: controller.recordingState)
        }
        .buttonStyle(.plain)
        .macClickablePointer()
        .disabled(controller.recordingState == .starting || controller.recordingState == .transcribing)
        .help(controller.recordingState == .idle ? "Voice Input" : "Stop Recording")
        .onDisappear { controller.tearDown() }
    }

    private func handleTap() {
        switch controller.recordingState {
        case .idle:
            controller.startRecording(onFinished: onTranscribed)
        case .recording:
            controller.stopRecording(onFinished: onTranscribed)
        case .starting, .transcribing:
            break
        }
    }
}

// MARK: - AnimatedSparkleIcon

/// Sparkle icon with a static gradient. No animation to keep the UI thread free.
private struct AnimatedSparkleIcon: View {
    let size: CGFloat

    private var gradient: LinearGradient {
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
        Image(systemName: "sparkles")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(gradient)
    }
}

// MARK: - Message Bubble

private struct MacMessageBubble: View {
    let message: MacChatMessage
    let allTasks: [TaskRecord]
    let canRetry: Bool
    var calendarConnected: Bool = true
    var emailConnected: Bool = true
    var onRetry: () -> Void = {}
    var onConnect: ((String) -> Void)?
    var onOpenEmailSettings: () -> Void = {}
    /// Right-click / long-press "Edit" on a user message — parent pre-fills the composer
    /// and truncates the conversation so the edited turn re-runs on send.
    var onEdit: ((MacChatMessage) -> Void)?
    /// Generative-UI card action callback (navigate, copy, draft autosave/send, undo, ...).
    var onSpecAction: MacChatUISpecOnAction?
    /// Called when the user taps "Upgrade to Pro" after a credits-exhausted error.
    var onUpgrade: (() -> Void)?
    /// Called when user taps "Insert into doc" — only provided when docs context is active for last AI message.
    var onInsertIntoDoc: ((String) -> Void)?

    @State private var showActions = false
    @State private var didCopy = false
    @State private var thumbsState: ThumbsState? = nil

    private enum ThumbsState { case up, down }

    /// Plain-text payload the context menu copies.
    private var copyableText: String {
        message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canEdit: Bool {
        message.role == .user && !message.isStreaming && onEdit != nil
    }

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            HStack(alignment: .top) {
                if message.role == .user { Spacer(minLength: 50) }
                if message.role == .user {
                    userBubble
                        .contextMenu { bubbleMenu }
                } else {
                    assistantBubble
                        .contextMenu { bubbleMenu }
                }
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

            // "Insert into doc" button — shown when parent is in docs context
            if let onInsert = onInsertIntoDoc,
               message.role == .assistant,
               !message.isStreaming,
               !message.content.isEmpty {
                HStack {
                    Button {
                        onInsert(message.content)
                    } label: {
                        Label("Insert into doc", systemImage: "arrow.down.doc")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MacTheme.mutedText)
                    }
                    .buttonStyle(.borderless)
                    .macClickablePointer()
                    .help("Insert AI response at cursor position in the open document")
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: User Bubble

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if !message.attachmentFileNames.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(Array(message.attachmentFileNames.enumerated()), id: \.offset) { index, name in
                        let url = index < message.attachmentURLs.count ? message.attachmentURLs[index] : nil
                        MacSentAttachmentCell(filename: name, url: url)
                    }
                }
            }
            if !message.content.isEmpty {
                Text(message.content)
                    .font(.system(size: 13, weight: .medium))
                    .lineSpacing(2)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous))
            }
        }
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
            }

            // Generative UI cards (parsed out of the markdown after streaming completes).
            if let spec = message.uiSpec {
                ChatUISpecView(spec: spec) { action, params, completion in
                    onSpecAction?(action, params, completion)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }

            // Connect CTA — when AI mentions a disconnected service
            if !message.isStreaming && !message.content.isEmpty {
                let lc = message.content.lowercased()
                let mentionsCalendarConnectionIssue =
                    lc.contains("calendar not connected") ||
                    lc.contains("not connected to calendar") ||
                    lc.contains("calendar isn't connected") ||
                    lc.contains("calendar is not connected")
                let mentionsEmailConnectionIssue =
                    lc.contains("email not connected") ||
                    lc.contains("not connected to email") ||
                    lc.contains("not connected to inbox") ||
                    lc.contains("inbox not connected") ||
                    lc.contains("email isn't connected") ||
                    lc.contains("email is not connected")

                if !calendarConnected && mentionsCalendarConnectionIssue {
                    macConnectBanner(label: "Connect Calendar", icon: "calendar", color: .primary) {
                        onConnect?("calendar")
                    }
                }
                if !emailConnected && mentionsEmailConnectionIssue {
                    macConnectBanner(label: "Connect Email", icon: "envelope", color: .orange) {
                        onOpenEmailSettings()
                    }
                }

                if let onUpgrade, message.content.hasPrefix("⚠️ You're out of AI credits") {
                    macConnectBanner(label: "Upgrade to Pro", icon: "arrow.up.circle", color: MacTheme.accent) {
                        onUpgrade()
                    }
                }
            }
        }
        .animation(MacTheme.Motion.slow, value: message.searchState)
        .animation(MacTheme.Motion.slow, value: message.sources.count)
    }

    @ViewBuilder
    private func macConnectBanner(label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(label).font(.system(size: 12, weight: .medium))
                Image(systemName: "arrow.right").font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous))
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .macClickablePointer()
        .padding(.top, 2)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    // MARK: Assistant Content — Markdown
    // Always uses full markdown rendering so headings/bullets/code appear immediately
    // during streaming. The typewriter effect comes from tokens being appended.

    @ViewBuilder
    private var assistantContent: some View {
        MarkdownView(content: message.content, fontSize: 13)
            .overlay(alignment: .bottomLeading) {
                if message.isStreaming { MacBlinkingCursor() }
            }
            .foregroundStyle(.primary.opacity(0.85))
            .textSelection(.enabled)
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
                    .macClickablePointer()
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
        case .update: return .primary
        case .delete: return .red
        }
    }

    // MARK: Action Row (matches iOS: retry, copy, thumbs up/down)

    private var actionRow: some View {
        HStack(spacing: 2) {
            if !message.contextSources.isEmpty {
                MacAISourcesButton(sources: message.contextSources)
                    .padding(.trailing, 6)
            }

            // Retry
            Button { onRetry() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(canRetry ? 0.5 : 0.2))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .macClickablePointer()
            .disabled(!canRetry)
            .help("Retry")

            // Copy
            Button {
                guard !didCopy else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
                withAnimation(MacTheme.Motion.fast) { didCopy = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(MacTheme.Motion.fast) { didCopy = false }
                }
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(didCopy ? .green : .primary.opacity(0.5))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .macClickablePointer()
            .help(didCopy ? "Copied!" : "Copy")

            // Thumbs up
            Button {
                withAnimation(MacTheme.Motion.fast) {
                    thumbsState = thumbsState == .up ? nil : .up
                }
            } label: {
                Image(systemName: thumbsState == .up ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(thumbsState == .up ? Color.primary : MacTheme.mutedText)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .macClickablePointer()
            // Thumbs down
            Button {
                withAnimation(MacTheme.Motion.fast) {
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
            .macClickablePointer()
    }
        .padding(.leading, 2)
    }

    // MARK: Right-click / long-press menu — copy + edit (user only)

    @ViewBuilder
    private var bubbleMenu: some View {
        Button {
            guard !copyableText.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copyableText, forType: .string)
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .disabled(copyableText.isEmpty)

        if canEdit {
            Button {
                onEdit?(message)
            } label: {
                Label("Edit message", systemImage: "pencil")
            }
        }
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
                withAnimation(MacTheme.Motion.base) { isExpanded.toggle() }
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
                        .animation(MacTheme.Motion.base, value: isExpanded)
                }
                .foregroundStyle(MacTheme.mutedText)
            }
            .buttonStyle(.plain)
            .macClickablePointer()
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
        .background(MacTheme.surfaceCard.opacity(0.5), in: RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
        .onChange(of: isStreaming) { _, streaming in
            if !streaming && durationMs != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(MacTheme.Motion.slow) { isExpanded = false }
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
                RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous)
                    .fill(isHovered ? MacTheme.surfaceHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .macClickablePointer()
        .onHover { isHovered = $0 }
        .animation(MacTheme.Motion.fast, value: isHovered)
    }
}

// MARK: - MacBlinkingCursor

/// Animated blinking cursor shown at the end of the last AI text chunk during streaming.
private struct MacBlinkingCursor: View {
    @State private var visible = true

    var body: some View {
        Rectangle()
            .frame(width: 2, height: 13)
            .foregroundStyle(.primary.opacity(0.6))
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
            .offset(x: 2, y: 1)
    }
}

// MARK: - MacChatTextInput
// NSTextView-based multiline input: Return = newline, Cmd+Return = send.
// Replaces SwiftUI's TextField which fires onSubmit on ALL Return presses,
// making it impossible for users to enter line breaks.

private struct MacChatTextInput: NSViewRepresentable {
    @Binding var text: String
    @Binding var contentHeight: CGFloat
    let onSend: () -> Void
    var onPastedFileURLs: (([URL]) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, contentHeight: $contentHeight) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = MacChatNSTextView()
        textView.onSend = onSend
        textView.onPasteFileURLs = onPastedFileURLs
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 13)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0

        scrollView.documentView = textView
        MacScrollStyle.applyChrome(to: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        MacScrollStyle.applyChrome(to: scrollView)
        guard let textView = scrollView.documentView as? MacChatNSTextView else { return }
        textView.onSend = onSend
        textView.onPasteFileURLs = onPastedFileURLs
        // Only sync when text changed externally (e.g., cleared after send)
        if textView.string != text {
            textView.string = text
            let h = Self.measuredHeight(of: textView)
            DispatchQueue.main.async { self.contentHeight = h }
        }
    }

    // Counts visual line fragments, adding one extra for the cursor line after a trailing newline.
    // NSLayoutManager's usedRect excludes that empty trailing line, causing the input to stay
    // one line tall when the user presses Return on an otherwise-empty field.
    static func measuredHeight(of textView: NSTextView) -> CGFloat {
        guard let lm = textView.layoutManager,
              let tc = textView.textContainer,
              let font = textView.font else { return 18 }
        lm.ensureLayout(for: tc)
        var lineCount = 0
        var idx = 0
        let total = lm.numberOfGlyphs
        if total == 0 {
            lineCount = 1
        } else {
            while idx < total {
                var range = NSRange()
                lm.lineFragmentRect(forGlyphAt: idx, effectiveRange: &range)
                lineCount += 1
                let next = NSMaxRange(range)
                guard next > idx else { break }
                idx = next
            }
        }
        if textView.string.hasSuffix("\n") { lineCount += 1 }
        let lineHeight = lm.defaultLineHeight(for: font)
        return min(max(ceil(CGFloat(lineCount) * lineHeight), 18), 120)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var contentHeight: CGFloat

        init(text: Binding<String>, contentHeight: Binding<CGFloat>) {
            _text = text
            _contentHeight = contentHeight
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text = tv.string
            contentHeight = MacChatTextInput.measuredHeight(of: tv)
        }
    }
}

private final class MacChatNSTextView: NSTextView {
    var onSend: (() -> Void)?
    var onPasteFileURLs: (([URL]) -> Void)?

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if let files = collectPastedFileURLs(from: pb), !files.isEmpty {
            onPasteFileURLs?(files)
            return
        }
        super.paste(sender)
    }

    /// Images, raw image data, file URLs, and PDFs from the pasteboard.
    private func collectPastedFileURLs(from pb: NSPasteboard) -> [URL]? {
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
            var out: [URL] = []
            for image in images {
                guard
                    let tiff = image.tiffRepresentation,
                    let rep = NSBitmapImageRep(data: tiff),
                    let data = rep.representation(using: .png, properties: [:])
                else { continue }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("paste-image-\(UUID().uuidString).png")
                do {
                    try data.write(to: url)
                    out.append(url)
                } catch { continue }
            }
            if !out.isEmpty { return out }
        }
        if let urlObjs = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            let fileURLs = urlObjs.filter { $0.isFileURL }
            if !fileURLs.isEmpty { return fileURLs }
        }
        for (type, ext) in [(NSPasteboard.PasteboardType.png, "png"), (NSPasteboard.PasteboardType.tiff, "tiff"),
                             (NSPasteboard.PasteboardType.pdf, "pdf")] {
            if let data = pb.data(forType: type) {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("paste-\(UUID().uuidString).\(ext)")
                do {
                    try data.write(to: url)
                    return [url]
                } catch { break }
            }
        }
        return nil
    }

    override func keyDown(with event: NSEvent) {
        // Cmd+Return = send the message
        if event.keyCode == 36 /* kVK_Return */ && event.modifierFlags.contains(.command) {
            onSend?()
            return
        }
        // Plain Return (and all other keys) = natural NSTextView behavior (newline)
        super.keyDown(with: event)
    }
}

// MARK: - Pending attachment chip (preview + format, iOS-style pill)

private enum MacPendingAttachmentFormat {
    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tiff", "tif", "bmp", "ico",
    ]

    static func isImageFile(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    static func formatUppercase(_ url: URL) -> String {
        let ext = url.pathExtension.uppercased()
        return ext.isEmpty ? "FILE" : ext
    }

    /// File name without extension, truncated (format is shown separately).
    static func displayName(_ url: URL) -> String {
        var base = url.deletingPathExtension().lastPathComponent
        if base.isEmpty { base = url.lastPathComponent }
        if base.count > 20 {
            return String(base.prefix(18)) + "…"
        }
        return base
    }
}

// MARK: - Sent Attachment Thumbnail (in message bubble)

/// Shows a 56×56 image preview or doc icon for an attachment that has already been sent.
private struct MacSentAttachmentCell: View {
    let filename: String
    let url: URL?

    @State private var preview: NSImage?

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tiff", "tif", "bmp", "ico",
    ]

    private var isImage: Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        return Self.imageExtensions.contains(ext)
    }

    private var label: String {
        let ext = (filename as NSString).pathExtension.uppercased()
        return isImage ? "Image" : (ext.isEmpty ? "File" : ext)
    }

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            ZStack {
                if isImage, let img = preview {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else if isImage {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(MacTheme.surfaceCard)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 18))
                                .foregroundStyle(MacTheme.mutedText)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(MacTheme.surfaceCard)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "doc.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(MacTheme.mutedText)
                        )
                }
            }
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 62)
        .task(id: url?.path ?? filename) {
            guard isImage, let u = url else { return }
            // Read the file bytes off the main actor so a large attachment doesn't stall the
            // chat UI. `Data` is Sendable (NSImage is not), so we hand bytes back to the main
            // actor and only decode/downsample once we're here.
            let data = await Task.detached(priority: .utility) { () -> Data? in
                let didAccess = u.startAccessingSecurityScopedResource()
                defer { if didAccess { u.stopAccessingSecurityScopedResource() } }
                return try? Data(contentsOf: u)
            }.value
            guard let data, let image = NSImage(data: data) else { return }
            preview = macDownsampledThumbnail(image, maxPixels: 112)
        }
    }
}

// MARK: - Pending Attachment Chip (composer)

private struct MacPendingAttachmentChip: View {
    let url: URL
    let onRemove: () -> Void

    @State private var preview: NSImage?

    private var isImage: Bool { MacPendingAttachmentFormat.isImageFile(url) }

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if isImage, let img = preview {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(MacTheme.surfaceCard)
                        .frame(width: 22, height: 22)
                        .overlay {
                            Image(systemName: "doc")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(MacTheme.mutedText)
                        }
                }
            }

            HStack(spacing: 4) {
                Text(MacPendingAttachmentFormat.displayName(url))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MacTheme.mutedText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(MacPendingAttachmentFormat.formatUppercase(url))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .frame(minWidth: 0, maxWidth: 200, alignment: .leading)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .macClickablePointer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(MacTheme.surfaceCard, in: Capsule())
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
        .task(id: url.path) {
            guard isImage else { return }
            let u = url
            let didAccess = u.startAccessingSecurityScopedResource()
            defer {
                if didAccess { u.stopAccessingSecurityScopedResource() }
            }
            guard let image = NSImage(contentsOf: u) else { return }
            preview = macDownsampledThumbnail(image, maxPixels: 64)
        }
    }
}

/// Decodes a small bitmap for 22pt thumbnails so large photos do not stay fully resident.
private func macDownsampledThumbnail(_ image: NSImage, maxPixels: CGFloat) -> NSImage {
    var proposed = image.size
    guard proposed.width > 0, proposed.height > 0 else { return image }
    let scale = min(maxPixels / max(proposed.width, 1), maxPixels / max(proposed.height, 1), 1)
    proposed = CGSize(width: max(proposed.width * scale, 1), height: max(proposed.height * scale, 1))
    let img = NSImage(size: proposed)
    img.lockFocus()
    image.draw(
        in: NSRect(origin: .zero, size: proposed),
        from: NSRect(origin: .zero, size: image.size),
        operation: .copy,
        fraction: 1
    )
    img.unlockFocus()
    return img
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
