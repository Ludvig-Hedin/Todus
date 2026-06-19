import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation

/// EventKit id for presenting `EKEventDetailSheet` from generative UI card taps.
private struct EventDetailSheetID: Identifiable {
    let id: String
}

// MARK: - AIChatView

/// Full-screen chat sheet. Streams AI responses with live markdown rendering and typewriter animation.
/// Supports task read/write via tool calls. History and model config accessible from toolbar.
struct AIChatView: View {
    /// The tab the user was on when they opened the AI sheet — pre-fills the context pill.
    var currentTab: AppTab = .home
    /// Optional pre-filled prompt. Set when AIChatView is opened from a focused context
    /// (e.g. the email composer's AI button) so the input starts with a task-specific
    /// question instead of an empty field. Cleared by the persisted-draft restore in
    /// `onAppear` if a more recent saved draft exists.
    var initialPrompt: String? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppServices.self) private var services
    @Query(sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]

    @State private var inputText = ""
    @State private var inputMentions: [RichInputMentionRef] = []
    @State private var eventMentions: [RichInputMentionRef] = []
    /// Tracks whether the text input UITextView has focus — driven by PasteHandlingTextInput callbacks
    /// (not @FocusState, which doesn't work with UIViewRepresentable-wrapped UITextViews)
    @State private var isInputFocused: Bool = false

    /// Page context pill — name + icon auto-set from currentTab, user can remove it.
    @State private var pageContextAttached = true

    // Sheet presentation states
    @State private var showsHistory = false
    @State private var showsConfig = false
    /// Whether the text input was focused when the config sheet was opened, so we can restore it on dismiss.
    @State private var wasInputFocusedBeforeConfig = false
    @State private var showsDataSheet = false
    @State private var showsDeleteConfirm = false
    @State private var showsRenameAlert = false
    @State private var renameText = ""
    @State private var showsPromptLibrary = false
    // Surfaced when a generative-UI card tap maps to an action this build doesn't handle.
    @State private var unhandledCardActionMessage: String? = nil
    /// System calendar event detail (from generative `CalendarEventCard` taps).
    @State private var eventDetailSheetID: EventDetailSheetID? = nil

    // Suggestion expansion — "Show more" / "Refresh" / "Back"
    @State private var suggestionsExpanded = false
    @State private var suggestionSeed = 0   // changing this shuffles the extended pool

    // Attachment state — `+` button opens the rich AIAttachmentSheet, which
    // then triggers individual system pickers via the callbacks below.
    @State private var isShowingAttachmentSheet = false
    @State private var isShowingPhotoPicker = false
    @State private var isShowingCamera = false
    @State private var isShowingFilePicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pendingAttachments: [String] = []

    // Live voice chat
    @State private var showVoiceChat = false

    // Full-screen compose overlay — expands input into a dedicated sheet for long prompts
    @State private var showsFullScreenInput = false
    // True when the text input has grown to its maxHeight cap (120pt); shows expand button
    @State private var inputAtMaxHeight = false

    // Animated thinking text cycles while streaming
    @State private var thinkingIndex = 0
    private let thinkingPhrases = ["Thinking", "Reading tasks", "Searching", "Writing"]

    // Auto-scroll behavior: only follow the bottom while the user is already there.
    // Set to false when the user manually scrolls back so token streams don't yank
    // them away from what they're reading.
    @State private var userScrolledUp: Bool = false

    // Edit-message undo support — captures messages that were truncated when the
    // user long-pressed "Edit" on an earlier turn, so they can restore them via
    // the Edit chip × button before sending the new draft.
    @State private var lastTruncatedHistory: [AIChatMessage] = []
    /// True while the composer holds the text of a message being edited (cleared on send or cancel).
    @State private var isEditingMessage: Bool = false
    /// ID of the message being edited — truncation is deferred until the user presses Send,
    /// so the full conversation remains visible while they refine the edit.
    @State private var editingMessageID: UUID?

    private var chatService: AIChatService { services.aiChatService }

    /// Whether EventKit calendar access has been granted to this app.
    private var calendarConnected: Bool {
        services.calendarService.canReadEvents()
    }
    /// Whether an email inbox is loaded (proxy for email being connected and accessible).
    private var emailConnected: Bool {
        chatService.aiCanReadEmail && !services.emailService.threads.isEmpty
    }

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
                AppTheme.sheetBackground.ignoresSafeArea()

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
                    colors: [AppTheme.sheetBackground.opacity(0.5), AppTheme.sheetBackground.opacity(0)],
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
                .appSheetBackground()
                .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        .sheet(isPresented: $showsConfig, onDismiss: {
            if wasInputFocusedBeforeConfig {
                wasInputFocusedBeforeConfig = false
                // Re-focus the input after the sheet dismissal animation completes.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    isInputFocused = true
                }
            }
        }) {
            AIChatConfigSheet()
                .presentationDragIndicator(.visible)
                .appSheetBackground()
                .preferredColorScheme(services.appearancePreference.colorScheme)
                .onAppear {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
        }
        // Prompt library — presets + user-saved prompts
        .sheet(isPresented: $showsPromptLibrary) {
            PromptLibrarySheet(onSelect: { prompt in
                inputText = prompt.text
                showsPromptLibrary = false
            })
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .appSheetBackground()
            .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        // Conversation data sheet — shows token usage, cost, message stats
        .sheet(isPresented: $showsDataSheet) {
            ConversationDataSheet(stats: conversationStats)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .appSheetBackground()
                .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        .sheet(item: $eventDetailSheetID) { item in
            EKEventDetailSheet(eventId: item.id)
                .presentationDragIndicator(.visible)
                .appSheetBackground()
        }
        // Delete confirmation dialog
        .confirmationDialog("Delete this conversation?", isPresented: $showsDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteConversation() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will clear all messages. This action cannot be undone.")
        }
        // Tool-call delete confirmation — suspends the AI's delete_task call until
        // the user approves it (Bug #4). The service awaits this dialog's resolution
        // via a CheckedContinuation, so cancelling actually aborts the tool call
        // rather than letting the deletion silently proceed.
        .confirmationDialog(
            "Delete this task?",
            isPresented: Binding(
                get: { chatService.pendingDeleteConfirmation != nil },
                set: { newVal in
                    // If SwiftUI auto-dismisses without a button (e.g. backgrounded),
                    // treat it as cancel so we never hang the tool call.
                    if !newVal, let pending = chatService.pendingDeleteConfirmation {
                        chatService.confirmPendingDelete(pending, confirm: false)
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: chatService.pendingDeleteConfirmation
        ) { pending in
            Button("Delete", role: .destructive) {
                chatService.confirmPendingDelete(pending, confirm: true)
            }
            Button("Cancel", role: .cancel) {
                chatService.confirmPendingDelete(pending, confirm: false)
            }
        } message: { pending in
            Text("The AI wants to delete \"\(pending.title ?? "this task")\". This action cannot be undone.")
        }
        // Generic mutation confirmation — send email, create/update/delete calendar event.
        // Without this binding, the service's `awaitMutationConfirmation` would suspend
        // forever and the assistant bubble would stay in `isStreaming` indefinitely (C3).
        .confirmationDialog(
            mutationDialogTitle,
            isPresented: Binding(
                get: { chatService.pendingMutationConfirmation != nil },
                set: { newVal in
                    if !newVal, let pending = chatService.pendingMutationConfirmation {
                        chatService.confirmPendingMutation(pending, confirm: false)
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: chatService.pendingMutationConfirmation
        ) { pending in
            Button(mutationConfirmLabel(for: pending),
                   role: pending.kind == .deleteCalendarEvent ? .destructive : nil) {
                chatService.confirmPendingMutation(pending, confirm: true)
            }
            Button("Cancel", role: .cancel) {
                chatService.confirmPendingMutation(pending, confirm: false)
            }
        } message: { pending in
            // Compose a one-or-two-line message — subtitle holds the structured
            // recipients/subject/event detail; body is the email body (truncated).
            let lines = [pending.subtitle, pending.body?.trimmingCharacters(in: .whitespacesAndNewlines)]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            let preview = lines.joined(separator: "\n\n")
            Text(preview.isEmpty ? pending.title : preview)
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
        // Unhandled generative-UI card action — surface so the user knows the tap did register
        .alert(
            "This action isn't supported yet",
            isPresented: Binding(
                get: { unhandledCardActionMessage != nil },
                set: { if !$0 { unhandledCardActionMessage = nil } }
            ),
            presenting: unhandledCardActionMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        // Rich attachment sheet — opens from the `+` button in the input bar.
        // Presents as a translucent material sheet so the system can render
        // liquid glass on iOS 26+ while older OSes get a thin-material fallback.
        .sheet(isPresented: $isShowingAttachmentSheet) {
            AIAttachmentSheet(
                chatService: chatService,
                onOpenCamera: { isShowingCamera = true },
                onOpenPhotoLibrary: { isShowingPhotoPicker = true },
                onOpenFilePicker: { isShowingFilePicker = true },
                onAttachImage: { uiImage in
                    if let filename = AttachmentService.shared.saveImage(uiImage) {
                        pendingAttachments.append(filename)
                    }
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(.thinMaterial)
            .presentationCornerRadius(28)
            .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        // Attachment pickers — triggered from the AIAttachmentSheet callbacks.
        .photosPicker(isPresented: $isShowingPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                Task {
                    if let filename = await AttachmentService.shared.importFile(at: url) {
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
            .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        // Live voice chat modal — presented from the waveform button in the input bar
        .fullScreenCover(isPresented: $showVoiceChat) {
            VoiceChatModalView(
                chatService: chatService,
                tokenService: services.voiceTokenService
            )
            .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        // Full-screen compose — lets users write long prompts comfortably
        .sheet(isPresented: $showsFullScreenInput) {
            FullScreenComposeView(inputText: $inputText, onSend: {
                showsFullScreenInput = false
                // Brief delay so the sheet dismiss animation plays before sending
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { sendMessage() }
            })
            .presentationDragIndicator(.visible)
            .appSheetBackground()
            .preferredColorScheme(services.appearancePreference.colorScheme)
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
            // Cancel any in-flight SSE stream so URLSession doesn't keep draining
            // tokens (and burning API credits) against a sheet that's no longer
            // visible. `cancelStream` calls `finaliseStream` so already-accumulated
            // tokens persist and the conversation autosaves below preserves them.
            if chatService.isStreaming {
                chatService.cancelStream()
            }
            chatService.autosave()
            // Persist draft input across dismissals
            UserDefaults.standard.set(inputText, forKey: "ai_draft_input")
        }
        // Persist the in-progress conversation when the app is backgrounded or about
        // to become inactive — onDisappear alone doesn't fire on force-quit, so we'd
        // otherwise lose any unsaved turns the user just streamed.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                chatService.autosave()
                UserDefaults.standard.set(inputText, forKey: "ai_draft_input")
            }
        }
        // Persist after every assistant turn completes so anything streamed survives
        // a force-quit during the same session.
        .onChange(of: chatService.isStreaming) { _, isStreaming in
            if !isStreaming { chatService.autosave() }
        }
        .onAppear {
            // Restore draft input — but the caller-supplied `initialPrompt` wins when
            // the field is empty (avoids the autosaved generic draft overwriting a
            // task-specific prompt seeded by the email composer's AI button).
            if inputText.isEmpty {
                if let initialPrompt, !initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    inputText = initialPrompt
                } else {
                    inputText = UserDefaults.standard.string(forKey: "ai_draft_input") ?? ""
                }
            }
            // Re-attach context pill when sheet re-opens
            pageContextAttached = true
            loadEventMentions()
        }
    }

    // MARK: - Mutation Confirmation Helpers

    /// Title surfaced for whichever generic mutation is awaiting confirmation. We
    /// only need the active pending mutation (if any) — when there's nothing pending
    /// SwiftUI hides the dialog regardless of the title.
    private var mutationDialogTitle: String {
        guard let kind = chatService.pendingMutationConfirmation?.kind else { return "Confirm action" }
        switch kind {
        case .sendEmail:            return "Send this email?"
        case .createCalendarEvent:  return "Create this event?"
        case .updateCalendarEvent:  return "Update this event?"
        case .deleteCalendarEvent:  return "Delete this event?"
        }
    }

    /// Action button label per mutation kind — matches the verb the user expects
    /// (Send / Create / Update / Delete) instead of a generic "Confirm".
    private func mutationConfirmLabel(for pending: AIChatService.PendingMutationConfirmation) -> String {
        switch pending.kind {
        case .sendEmail:            return "Send"
        case .createCalendarEvent:  return "Create"
        case .updateCalendarEvent:  return "Update"
        case .deleteCalendarEvent:  return "Delete"
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

        // Chat title (or app name when empty) — fills available space, truncates with ellipsis
        ToolbarItem(placement: .principal) {
            Text(chatService.chatTitle ?? "AI Assistant")
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.2)
                .lineLimit(1)
                .truncationMode(.tail)
        }

        // New chat button — separate item so it doesn't share a pill with the menu
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

        // Options menu — conversation actions
        ToolbarItem(placement: .topBarTrailing) {
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

                Text(error)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("Check your connection and sign-in state, then try again.")
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
                .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
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
        // Suggestions content fills the space above the keyboard-pinned input section.
        // safeAreaInset keeps the input's bottom glued just above the keyboard (same
        // as conversationView) — prevents the input from growing down into the keyboard
        // when the user types multiple lines.
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    // Sparkles icon — animated gradient with subtle glow
                    AnimatedSparkleIcon(size: 20)

                    HStack(spacing: 8) {
                        Text("How can I help you today?")
                            .font(.system(size: 20, weight: .semibold))
                            .tracking(-0.3)
                        Spacer(minLength: 0)
                        // Always-visible shuffle button — taps reshuffle the
                        // suggestion pool whether expanded or collapsed (P6).
                        Button {
                            withAnimation(.snappy(duration: 0.15)) {
                                suggestionSeed += 1
                            }
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            Image(systemName: "shuffle")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppTheme.mutedText)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Shuffle suggestions")
                    }


                }
                .padding(.horizontal, 16)

                // Suggestions — 3 default, up to 10 when expanded
                VStack(alignment: .leading, spacing: 0) {
                    let pool = contextualSuggestionsPool
                    // If pool is empty, the current tab's service is not connected —
                    // show connect buttons instead of suggestions.
                    if pool.isEmpty {
                        connectServicesPrompt
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                            .padding(.bottom, 8)
                    }
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
        }
        // Pin the input section's bottom edge just above the keyboard — identical to
        // conversationView. safeAreaInset updates as the keyboard shows/hides and as
        // the input box grows, so multiline text never pushes the input below the keyboard.
        .safeAreaInset(edge: .bottom) {
            inputSection
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background {
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [AppTheme.sheetBackground.opacity(0), AppTheme.sheetBackground.opacity(0.94)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 48)
                        AppTheme.sheetBackground.opacity(0.97)
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
        }
    }

    /// Non-empty trimmed thread subject, or `nil` when the assistant is not
    /// grounded on a real email thread (matches icon + title + suggestions).
    private var trimmedThreadSubject: String? {
        if let s = chatService.currentThreadSubject?.trimmingCharacters(in: .whitespaces),
           !s.isEmpty {
            return s
        }
        return nil
    }

    /// Icon for the context pill — switches to an envelope when an email
    /// thread is in scope, otherwise mirrors the active tab.
    private var contextPillIcon: String {
        trimmedThreadSubject == nil ? currentTab.activeIcon : "envelope.fill"
    }

    /// Title for the context pill — when in an email thread, prefers the
    /// truncated subject so it's clear which message the AI is grounded on.
    private var contextPillTitle: String {
        if let subject = trimmedThreadSubject {
            return subject
        }
        return currentTab.title
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
            // Only show email suggestions when email is actually connected
            guard emailConnected else { return [] }
            // When the user opened the assistant from inside a thread we know a
            // single thread is in scope, so the prompts shift from inbox-wide
            // triage to thread-specific actions.
            if trimmedThreadSubject != nil {
                pinned = [
                    ("doc.text",                "Summarize this email"),
                    ("arrowshape.turn.up.left", "Draft a reply"),
                    ("checklist",               "Extract tasks from this email"),
                ]
                extended = [
                    ("calendar.badge.plus",     "Suggest a meeting time based on this thread"),
                    ("text.viewfinder",         "Pull out the key dates and decisions"),
                    ("person.2",                "Who's on this thread and what do they want?"),
                    ("questionmark.bubble",     "Help me answer the questions raised here"),
                    ("flag",                    "Is this thread urgent? What should I prioritize?"),
                    ("text.bubble",             "Give me three reply options with different tones"),
                    ("arrow.uturn.right",       "Suggest a polite way to decline"),
                ]
                break
            }
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
            // Only show calendar suggestions when calendar permission is granted
            guard calendarConnected else { return [] }
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
        case .meetings:
            pinned = [
                ("video",                      "Summarize my upcoming meetings"),
                ("doc.text.magnifyingglass",   "What meetings already have recaps or action items?"),
                ("calendar.badge.plus",        "Which meetings should I sync from calendar?"),
            ]
            extended = [
                ("person.2",                   "Which meetings need a note taker scheduled?"),
                ("checkmark.circle",           "Turn meeting action items into tasks"),
                ("clock.arrow.trianglehead.counterclockwise.rotate.90", "What did I miss in recent meetings?"),
                ("sparkles",                   "Generate a recap for my latest meeting"),
                ("questionmark.bubble",        "Help me prepare questions for the next meeting"),
                ("link",                       "Find meetings with Google Meet links"),
                ("waveform.path.ecg",          "Show me meetings that still need follow-up"),
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
        case .home, .docs, .create, .ai:
            // Always show the universal morning/focus prompts; add service-specific ones conditionally
            pinned = [
                ("sun.max",                    "Give me a morning briefing"),
                ("sparkle",                    "What should I focus on right now?"),
            ] + (calendarConnected ? [("calendar.badge.checkmark", "Triage my tasks and calendar for today")] : [("list.bullet", "Review my task list")])
            var extBase: [(icon: String, text: String)] = [
                ("moon.stars",                 "End-of-day review — what did I accomplish?"),
                ("chart.line.uptrend.xyaxis",  "Weekly retrospective — what went well?"),
                ("flag",                       "What are my top priorities this week?"),
                ("rocket",                     "Help me kick off a new project"),
                ("brain.head.profile",         "Block focus time and clear my schedule"),
                ("person.2",                   "Help me coordinate with my team today"),
            ]
            if emailConnected { extBase.append(("envelope.open", "Any important emails I should handle first?")) }
            extended = extBase
        }

        // Shuffle the extended pool with the current seed so Refresh shows new ones
        let shuffled = extended.shuffled(seed: suggestionSeed)
        return pinned + Array(shuffled.prefix(7)) // total cap of 10
    }

    /// Compact pills row shown above the suggestions in the empty state.
    /// Surfaces the active model + which integrations the AI has access to
    /// (Gmail / Calendar) so users know what to expect before sending. (P9)
    private var statusPillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                statusPill(icon: "cpu", label: shortModelLabel(chatService.selectedModel))
                statusPill(
                    icon: "envelope.fill",
                    label: emailConnected ? "Gmail on" : "Gmail off",
                    dim: !emailConnected
                )
                statusPill(
                    icon: "calendar",
                    label: calendarConnected ? "Calendar on" : "Calendar off",
                    dim: !calendarConnected
                )
            }
        }
    }

    private func statusPill(icon: String, label: String, dim: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(dim ? AppTheme.subtleText : AppTheme.mutedText)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppTheme.surfacePrimary, in: Capsule())
        .overlay(Capsule().stroke(AppTheme.cardBorder, lineWidth: 0.5))
    }

    /// Trim provider prefix + variant suffix from a model id so the pill stays
    /// short — e.g. "openai/gpt-5.4-mini" → "GPT-5.4 Mini".
    private func shortModelLabel(_ raw: String) -> String {
        let trailing = raw.split(separator: "/").last.map(String.init) ?? raw
        // Capitalize first letter; replace hyphens with spaces so it reads as a title.
        return trailing
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { word -> String in
                guard let first = word.first else { return String(word) }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    /// Compact connect-service buttons shown when the active tab's service pool is empty.
    private var connectServicesPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connect a service to get started")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
            HStack(spacing: 8) {
                if !calendarConnected && (currentTab == .calendar || currentTab == .home) {
                    Button {
                        Task { _ = await services.calendarService.requestAccess() }
                    } label: {
                        Label("Connect Calendar", systemImage: "calendar")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.1), in: Capsule())
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
                if !emailConnected && (currentTab == .email || currentTab == .home) {
                    Button {
                        services.navigateTo = .email
                        dismiss()
                    } label: {
                        Label("Connect Email", systemImage: "envelope")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.1), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
                            canRetry: chatService.canRetry(assistantMessageID: message.id),
                            calendarConnected: calendarConnected,
                            emailConnected: emailConnected,
                            onRetry: {
                                chatService.retry(
                                    assistantMessageID: message.id,
                                    allTasks: Array(allTasks),
                                    modelContext: modelContext
                                )
                            },
                            onNavigate: { action, params in
                                handleCardNavigation(action, params: params)
                            },
                            onCardError: { unhandledCardActionMessage = $0 },
                            onConnect: { service in
                                if service == "calendar" {
                                    Task { _ = await services.calendarService.requestAccess() }
                                } else if service == "email" {
                                    services.navigateTo = .email
                                    dismiss()
                                }
                            },
                            onEdit: { edited in editMessage(edited) }
                        )
                            .id(message.id)
                    }

                    // "Thinking…" indicator while streaming and before any visible
                    // assistant content has arrived. The indicator stays through
                    // long search / reasoning phases (which can run 5–10s with no
                    // visible content) and only disappears once a real token lands.
                    if chatService.isStreaming,
                       let last = chatService.messages.last,
                       last.role == .assistant,
                       last.content.isEmpty {
                        thinkingIndicator
                            .id("thinking")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 120)
                // Tap anywhere on the message list to dismiss the keyboard —
                // `simultaneousGesture` lets child button taps still fire normally.
                .simultaneousGesture(
                    TapGesture().onEnded {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
                )
            }
            .scrollDismissesKeyboard(.interactively)
            // Pin input section directly above keyboard — 8 pt gap above keyboard for breathing room
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
                    streamFailureBanner
                    inputSection
                }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    // Gradient fade — taller fade so content above the input is still partially
                    // visible; solid background only covers the input box itself, not a huge area.
                    .background {
                        VStack(spacing: 0) {
                            LinearGradient(
                                colors: [AppTheme.sheetBackground.opacity(0), AppTheme.sheetBackground.opacity(0.94)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 48)
                            AppTheme.sheetBackground.opacity(0.97)
                        }
                        .ignoresSafeArea(edges: .bottom)
                    }
            }
            // Dismiss the keyboard with interactive scroll; do not add a `simultaneousGesture`
            // on the whole `ScrollView` (it also hit-tests the `safeAreaInset` input bar).
            .onChange(of: chatService.messages.count) { _, _ in
                // New message appended — always honour the scroll-to-anchor so the user
                // sees their just-sent message at the top. Reset the user-scrolled-up
                // flag because the user is now interacting again.
                userScrolledUp = false
                scrollToLatestUserMessageTop(proxy: proxy)
            }
            // While the assistant streams, only follow the bottom if the user hasn't
            // manually scrolled away. Detecting "near bottom" without a scroll-offset
            // probe is tricky in pure SwiftUI; gating on a manual interaction flag set
            // by the scroll-dismisses-keyboard / drag gesture (below) is a pragmatic
            // approximation. Avoid scrolling on every token. (Bug #5)
            .onChange(of: chatService.messages.last?.content) { oldContent, newContent in
                let wasEmpty = oldContent?.isEmpty ?? true
                let nowHasContent = !(newContent?.isEmpty ?? true)
                // Only re-anchor when the message *first* gets content — that's the
                // moment the bubble height jumps and the user message would otherwise
                // disappear off-screen. After that, leave the scroll alone.
                guard wasEmpty && nowHasContent, !userScrolledUp else { return }
                if let anchor = chatService.messages.last(where: { $0.role == .user })?.id {
                    withAnimation(.linear(duration: 0.1)) {
                        proxy.scrollTo(anchor, anchor: .top)
                    }
                }
            }
            // Scroll when web search sources arrive (changes message height) — but only
            // if the user is still following the stream.
            .onChange(of: chatService.messages.last?.sources.count) { _, _ in
                guard !userScrolledUp else { return }
                scrollToLatestUserMessageTop(proxy: proxy, animation: .snappy(duration: 0.2))
            }
            // Mutation chips appear async after tool calls finish — they grow the
            // bubble vertically and would otherwise push the user message off-screen.
            // Re-anchor so the user keeps their reading position. (P5)
            .onChange(of: chatService.messages.last?.taskMutations.count) { _, _ in
                guard !userScrolledUp else { return }
                scrollToLatestUserMessageTop(proxy: proxy, animation: .snappy(duration: 0.2))
            }
            // A drag gesture on the scroll content means the user is reading earlier
            // turns — flip the flag so streaming tokens don't pull them back. Reset
            // when a new message is appended (handled above).
            .simultaneousGesture(
                DragGesture(minimumDistance: 8).onChanged { _ in
                    if !userScrolledUp { userScrolledUp = true }
                }
            )
        }
    }

    // MARK: - Stream Failure / Rate Limit Banner

    /// Inline banner shown above the composer when an SSE stream drops (network) or
    /// the backend returns 429. Tapping it triggers a one-shot retry — we never auto
    /// reconnect because mid-stream the model may already have produced partial output.
    @ViewBuilder
    private var streamFailureBanner: some View {
        if let rateMsg = chatService.rateLimitedMessage {
            bannerRow(
                icon: "clock.badge.exclamationmark",
                text: rateMsg,
                color: .orange,
                isTappable: chatService.streamFailed && !chatService.isStreaming,
                action: {
                    chatService.retryAfterStreamFailure(
                        allTasks: Array(allTasks),
                        modelContext: modelContext
                    )
                }
            )
        } else if chatService.streamFailed && !chatService.isStreaming {
            bannerRow(
                icon: "wifi.exclamationmark",
                text: "Connection lost — tap to retry",
                color: .orange,
                isTappable: true,
                action: {
                    chatService.retryAfterStreamFailure(
                        allTasks: Array(allTasks),
                        modelContext: modelContext
                    )
                }
            )
        }
    }

    private func bannerRow(
        icon: String,
        text: String,
        color: Color,
        isTappable: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: { if isTappable { action() } }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if isTappable {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                    .stroke(color.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isTappable)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Thinking Indicator

    /// Copy that reflects what's actually happening on the current turn instead
    /// of cycling blind. Web search → "Searching…", reasoning streaming →
    /// "Thinking…", otherwise fall back to the slow cycle below. (P7)
    private var thinkingCopy: String {
        guard let last = chatService.messages.last, last.role == .assistant else {
            return thinkingPhrases[thinkingIndex % thinkingPhrases.count]
        }
        if last.searchState == .searching {
            if let q = last.searchQueries.first, !q.isEmpty {
                return "Searching for \"\(q)\""
            }
            return "Searching the web…"
        }
        if !last.reasoningContent.isEmpty {
            return "Thinking…"
        }
        return thinkingPhrases[thinkingIndex % thinkingPhrases.count]
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 8) {
            AnimatedSparkleIcon(size: 14)

            Text(thinkingCopy)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
                .id(thinkingCopy)  // force re-render so transition fires
                .transition(.opacity)
        }
        .padding(.leading, 4)
    }

    // MARK: - Input Section
    // Layout: [circle + btn] [chatInputBox: config | text | expand | voice | mic | send]
    // Attachment panel floats above the + button when active (via HStack-level overlay).

    private let chatInputControlSize: CGFloat = 44

    private var inputSection: some View {
        // Main input row — attachment options now live in the AIAttachmentSheet
        // presented from the `+` button (see `.sheet(isPresented:)` further down).
        HStack(alignment: .bottom, spacing: 10) {
            Button {
                isShowingAttachmentSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(width: chatInputControlSize, height: chatInputControlSize)
            }
            .buttonStyle(.plain)
            .background(AppTheme.surfacePrimary, in: Circle())
            .overlay(Circle().stroke(AppTheme.strongBorder, lineWidth: 1))

            chatInputBox
        }
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

        // Cap at 50 threads before dictionary grouping to prevent O(n) main-thread hang
        // when the user taps the input field and this computed property re-evaluates.
        let peopleMentions = Dictionary(grouping: services.emailService.threads.prefix(50).map(\.from), by: \.email)
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
        let isEmpty =
            inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            pendingAttachments.isEmpty

        // Whether any "above-text" accessories are visible (edit chip, pill, or attachments)
        let hasAccessories = isEditingMessage || pageContextAttached || !pendingAttachments.isEmpty

        // Two-row layout: full-width text on top, button row on the bottom.
        // This avoids squeezing the text field between buttons, and prevents
        // the GeometryReader layout cycle that caused the 9s freeze (toggling
        // inputAtMaxHeight no longer changes the text field's available width).
        return VStack(spacing: 0) {
            // ── Above-text row: page context pill + attachment thumbnails ──────
            if hasAccessories {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // Edit chip — shown while the composer holds a message being edited
                        if isEditingMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Editing")
                                    .font(.system(size: 13, weight: .semibold))
                                Button {
                                    withAnimation(.snappy(duration: 0.15)) {
                                        cancelEdit()
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .buttonStyle(.plain)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.accentColor, in: Capsule())
                            .transition(.scale.combined(with: .opacity))
                        }

                        // Page context pill — when the user opened the assistant
                        // from inside an email thread we show the truncated subject
                        // (much more useful than the generic "Email" tab label).
                        if pageContextAttached {
                            HStack(spacing: 6) {
                                Image(systemName: contextPillIcon)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(contextPillTitle)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: 220)
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
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.primary.opacity(0.12), in: Capsule())
                        }

                        // Attachment thumbnails
                        ForEach(pendingAttachments, id: \.self) { filename in
                            attachmentThumbnail(filename: filename)
                        }
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 12)
                }
                .padding(.top, 10)
                .padding(.bottom, 0)
            }

            // ── Full-width text input ──────────────────────────────────────────
            RichComposerInput(
                text: $inputText,
                mentions: $inputMentions,
                placeholder: "Ask, search or make anything…",
                surface: .aiChat,
                mentionOptions: mentionOptions,
                isFocused: isInputFocused,
                maxHeight: 120,
                onPasteImage: { image in
                    if let filename = AttachmentService.shared.saveImage(image) {
                        pendingAttachments.append(filename)
                    }
                },
                onPasteFileData: { data, ext in
                    if let filename = AttachmentService.shared.saveData(data, fileExtension: ext) {
                        pendingAttachments.append(filename)
                    }
                },
                onCommand: { _ in },
                onFocusChange: { focused in isInputFocused = focused }
            )
            .frame(maxHeight: 120)
            // Track height to show/hide expand button — safe here because the
            // buttons row is separate, so toggling inputAtMaxHeight cannot alter
            // the text field width and cause a layout feedback loop.
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.size.height) { _, h in
                            let atMax = h >= 118
                            if atMax != inputAtMaxHeight { inputAtMaxHeight = atMax }
                        }
                }
            )
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)

            // ── Button row: [config]  spacer  [expand] [voice] [mic] [send] ──
            HStack(spacing: 8) {
                // Config button — opens model / settings sheet
                Button {
                    wasInputFocusedBeforeConfig = isInputFocused
                    showsConfig = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.mutedText)
                }
                .buttonStyle(.plain)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .accessibilityLabel("Chat settings")

                Spacer()

                // Full-screen expand — only when text has reached max input height and there's content
                if inputAtMaxHeight && !isEmpty {
                    Button { showsFullScreenInput.toggle() } label: {
                        Image(systemName: showsFullScreenInput
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.mutedText)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
                    .transition(.scale.combined(with: .opacity))
                }

                // Live voice chat button — opens full-screen voice modal
                Button { showVoiceChat = true } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(voiceButtonGradient)
                }
                .buttonStyle(.plain)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .accessibilityLabel("Start voice chat")

                // Transcribe mic button
                VoiceInputButton(onTranscribed: { transcribed in
                    let current = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    inputText = current.isEmpty ? transcribed : current + " " + transcribed
                })

                // Stop button while streaming, otherwise the Send button — but the
                // Send button always renders so it doesn't pop in/out as the user
                // types the first character (P1). Disabled state is conveyed via
                // opacity instead of removal.
                if chatService.isStreaming {
                    Button { chatService.cancelStream() } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.accentColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ai.chat.stopButton")
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.accentColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isEmpty)
                    .opacity(isEmpty ? 0.4 : 1)
                    .accessibilityIdentifier("ai.chat.sendButton")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.composer, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.composer, style: .continuous).stroke(AppTheme.strongBorder, lineWidth: 1))
        .animation(.snappy(duration: 0.18), value: chatService.isStreaming)
        .animation(.easeOut(duration: 0.12), value: isEmpty)
        .animation(.snappy(duration: 0.15), value: pendingAttachments.count)
        .animation(.snappy(duration: 0.15), value: inputAtMaxHeight)
        // Use simultaneous tap so the UITextView still receives the same tap (a plain
        // `onTapGesture` on the container can win the gesture arena and feel like the
        // field blurs or ignores the first touch).
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.composer, style: .continuous))
        .simultaneousGesture(
            TapGesture().onEnded { isInputFocused = true }
        )
    }

    /// Attachment thumbnail — adapts to context:
    /// - When a page context pill is present: shows as a pill with small preview + filename + X (cohesive row)
    /// - When standalone: shows as a square thumbnail with X overlay
    @ViewBuilder
    private func attachmentThumbnail(filename: String) -> some View {
        let isImage = AttachmentService.shared.isImageFile(filename)
        let displayName = filename.components(separatedBy: "_").dropFirst().joined(separator: "_")
            .replacingOccurrences(of: ".\(filename.components(separatedBy: ".").last ?? "")", with: "")
        let ext = filename.components(separatedBy: ".").last?.uppercased() ?? "FILE"
        let shortName = displayName.isEmpty ? ext : (displayName.count > 12 ? String(displayName.prefix(12)) + "…" : displayName)

        if pageContextAttached {
            // Pill style — matches the page context pill look
            HStack(spacing: 6) {
                if isImage {
                    AttachmentThumbnailView(filename: filename, size: 22) {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.chip, style: .continuous)
                            .fill(AppTheme.surfaceSecondary)
                    }
                } else {
                    Image(systemName: "doc")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(shortName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Button {
                    pendingAttachments.removeAll { $0 == filename }
                    AttachmentService.shared.delete(filename: filename)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(AppTheme.mutedText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppTheme.surfaceSecondary, in: Capsule())
        } else {
            // Square thumbnail style — standalone without context pill
            ZStack(alignment: .topTrailing) {
                if isImage {
                    AttachmentThumbnailView(filename: filename, size: 56) {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                            .fill(AppTheme.surfaceSecondary)
                    }
                } else {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                        .fill(AppTheme.surfaceSecondary)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "doc")
                                .font(.system(size: 18))
                                .foregroundStyle(AppTheme.mutedText)
                        )
                }
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
        let hasAttachments = !pendingAttachments.isEmpty

        // Allow sending if there's text OR attachments (file-only send supported)
        guard !text.isEmpty || hasAttachments else { return }

        // When user sends attachments with no text, auto-prompt to view the attachment
        let messageText: String
        if text.isEmpty && hasAttachments {
            let count = pendingAttachments.count
            messageText = count == 1
                ? "View the attached file"
                : "View the \(count) attached files"
        } else {
            messageText = text
        }

        let filesToSend = pendingAttachments
        inputText = ""
        let mentions = inputMentions
        inputMentions = []
        pendingAttachments = []

        // Capture context chip label/icon BEFORE clearing state so we can attach
        // them to the outgoing AIChatMessage as a visible pill above the bubble.
        let sentContextLabel: String? = pageContextAttached ? contextPillTitle : nil
        let sentContextIcon: String? = pageContextAttached ? contextPillIcon : nil

        // Deferred edit truncation — we kept the conversation intact while the user
        // was editing; now that they're actually sending we truncate at the edited
        // message ID before inserting the replacement.
        if let editID = editingMessageID {
            chatService.truncateBefore(messageID: editID)
            editingMessageID = nil
        }
        isEditingMessage = false
        lastTruncatedHistory = []
        // Clear persisted draft since the message was sent
        UserDefaults.standard.removeObject(forKey: "ai_draft_input")
        // Set the current page context so the AI knows where the user is.
        // If an email thread is in scope, prefer the subject — the model gets a
        // much stronger hint than a generic "Email tab" label.
        if pageContextAttached {
            if let subject = chatService.currentThreadSubject?.trimmingCharacters(in: .whitespaces),
               !subject.isEmpty {
                chatService.currentPageContext = "Email thread: \(subject)"
            } else {
                chatService.currentPageContext = currentTab.title + " tab"
            }
        } else {
            chatService.currentPageContext = nil
        }
        chatService.send(
            userMessage: messageText,
            mentions: mentions,
            attachmentFileNames: filesToSend,
            allTasks: Array(allTasks),
            modelContext: modelContext,
            contextLabel: sentContextLabel,
            contextIcon: sentContextIcon
        )
    }

    /// Long-press "Edit" on a user bubble: load its content + mentions + attachments back
    /// into the composer and focus the input. The conversation stays fully visible so the
    /// user can read the AI's reply while refining their message. Truncation is deferred
    /// until the user actually presses Send — at that point we cut from `editingMessageID`
    /// and re-run the turn with the updated wording.
    private func editMessage(_ message: AIChatMessage) {
        guard message.role == .user, !chatService.isStreaming else { return }
        inputText = message.content
        inputMentions = message.mentions
        pendingAttachments = message.attachmentFileNames
        isEditingMessage = true
        // Remember WHICH message is being edited so sendMessage() can truncate at the
        // right point. We no longer truncate here — the conversation stays intact.
        editingMessageID = message.id
        isInputFocused = true
        UserDefaults.standard.set(message.content, forKey: "ai_draft_input")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Cancel an in-progress edit — restore input to blank and clear edit state.
    /// No history restoration needed because we never truncated the conversation.
    private func cancelEdit() {
        isEditingMessage = false
        editingMessageID = nil
        lastTruncatedHistory = []
        inputText = ""
        inputMentions = []
        pendingAttachments = []
        UserDefaults.standard.removeObject(forKey: "ai_draft_input")
    }

    /// Keeps the most recent user message near the top of the scroll view so long assistant replies
    /// stay below it instead of pinning to the end of the thread.
    private func scrollToLatestUserMessageTop(proxy: ScrollViewProxy, animation: Animation? = .snappy(duration: 0.25)) {
        if let anchor = chatService.messages.last(where: { $0.role == .user })?.id {
            withAnimation(animation) {
                proxy.scrollTo(anchor, anchor: .top)
            }
        } else if let lastID = chatService.messages.last?.id {
            withAnimation(animation) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }

    // MARK: - Conversation Actions

    /// Build markdown-formatted text of the entire conversation.
    ///
    /// `redactPII` strips obvious PII (email addresses) before returning so the output
    /// is safer to share externally. The user's own clipboard copy keeps the raw
    /// markdown — we only redact when sharing via UIActivityViewController.
    /// NOTE: this only redacts email addresses. Attachment payloads (image bytes,
    /// document files) are NOT included in the export today; if/when they're added,
    /// the share path must also strip them — see `shareConversation()`.
    private func conversationAsMarkdown(redactPII: Bool = false) -> String {
        let raw = chatService.messages.map { msg in
            let tag = msg.role == .user ? "**User**" : "**Assistant**"
            return "\(tag)\n\(msg.content)"
        }.joined(separator: "\n\n---\n\n")
        return redactPII ? Self.redactEmailAddresses(in: raw) : raw
    }

    /// Replace email addresses with `***@***` so a shared transcript doesn't leak
    /// the user's contacts to whoever they hand it to.
    private static func redactEmailAddresses(in text: String) -> String {
        let pattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "***@***")
    }

    private func copyConversation() {
        // Local clipboard copy for the user — keep raw, no redaction.
        UIPasteboard.general.string = conversationAsMarkdown(redactPII: false)
    }

    private func duplicateChat() {
        chatService.duplicateCurrentConversation()
    }

    private func deleteConversation() {
        withAnimation(.snappy(duration: 0.2)) {
            chatService.clearHistory()
        }
    }

    private func shareConversation() {
        // Going out to UIActivityViewController — redact email addresses so they
        // don't end up in someone else's hands. Attachments aren't in the markdown
        // today, but if they're added later this is the choke point that needs to
        // also strip them.
        let text = conversationAsMarkdown(redactPII: true)
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        // Prefer the foreground-active scene; `connectedScenes.first` is unordered
        // and can present on a background window on iPad / multi-window.
        let activeScene = (UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.first) as? UIWindowScene
        if let scene = activeScene,
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
            if let eid = params["eventId"] {
                eventDetailSheetID = EventDetailSheetID(id: eid)
            }

        case "navigate_draft":
            // Drafts open the compose sheet with pre-loaded content
            if let _ = params["draftId"] {
                services.navigateTo = .email
                dismiss()
            }

        default:
            // Unhandled action — bail silently instead of popping a "not supported"
            // alert that interrupts the conversation. We still log it for debugging
            // and trigger a soft haptic so the user knows the tap registered. A
            // follow-up should detect unsupported actions at render time and dim
            // the card so it looks non-interactive.
            print("[GenerativeUI] Unhandled action: \(action) params: \(params)")
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}

// MARK: - Content Parsing

/// Splits AI response into markdown segments, `[task:UUID]`, and `[event:EVENTKIT_ID]` tokens.
/// Task and event tokens render as native cards (see `MiniTaskCard`, `MiniEventCard`).
private enum ContentPart {
    case text(String)
    case taskRef(UUID)
    case eventRef(String)
}

/// Strips an in-progress `\`\`\`ui-spec` fenced block from streaming content
/// so raw JSON never flashes through MarkdownView before parsing is complete.
private func stripStreamingUISpec(_ raw: String) -> String {
    guard let range = raw.range(of: "```ui-spec", options: .backwards) else { return raw }
    return String(raw[raw.startIndex..<range.lowerBound])
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func parseMessageContent(_ content: String) -> [ContentPart] {
    guard #available(iOS 16, *) else { return [.text(content)] }

    // Fast path: typical assistant replies contain no card refs at all. A literal
    // substring check is orders of magnitude cheaper than running two regex
    // sweeps over the whole buffer and avoids most of the per-flush cost during
    // streaming. (Swift `Regex<...>` is not Sendable, so caching the patterns at
    // file scope under strict concurrency would require `nonisolated(unsafe)`;
    // we instead keep them function-local — they're only constructed on the
    // rare path where the message actually contains refs.)
    if !content.contains("[task:") && !content.contains("[event:") {
        return [.text(content)]
    }

    let taskPattern = /\[task:([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\]/
    let eventPattern = /\[event:([^\]]+)\]/

    struct MergedRef {
        let range: Range<String.Index>
        let part: ContentPart
    }
    var merged: [MergedRef] = []
    for m in content.matches(of: taskPattern) {
        if let uuid = UUID(uuidString: String(m.1)) {
            merged.append(MergedRef(range: m.range, part: .taskRef(uuid)))
        }
    }
    for m in content.matches(of: eventPattern) {
        let eid = String(m.1).trimmingCharacters(in: .whitespacesAndNewlines)
        if !eid.isEmpty { merged.append(MergedRef(range: m.range, part: .eventRef(eid))) }
    }
    merged.sort { $0.range.lowerBound < $1.range.lowerBound }

    var parts: [ContentPart] = []
    var lastEnd = content.startIndex
    for ref in merged {
        guard ref.range.lowerBound >= lastEnd else { continue }
        let pre = String(content[lastEnd..<ref.range.lowerBound])
        if !pre.isEmpty { parts.append(.text(pre)) }
        parts.append(ref.part)
        lastEnd = ref.range.upperBound
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
    let canRetry: Bool
    /// Whether calendar permission is granted — used to show connect CTA.
    var calendarConnected: Bool = true
    /// Whether email is loaded — used to show connect CTA.
    var emailConnected: Bool = true
    var onRetry: () -> Void = {}
    /// Callback for generative UI card actions (e.g. navigate to thread/task/event).
    var onNavigate: ((String, [String: String]) -> Void)?
    /// Draft/send failures from generative UI — parent surfaces `unhandledCardActionMessage` alert.
    var onCardError: ((String) -> Void)?
    /// Callback when user taps a connect-service button in the message — "calendar" or "email".
    var onConnect: ((String) -> Void)?
    /// Long-press "Edit" on a user message — parent pre-fills the composer
    /// and truncates the conversation so the edited turn re-runs on send.
    var onEdit: ((AIChatMessage) -> Void)?

    @Environment(AppServices.self) private var services
    @State private var showActions = false
    @State private var didCopy = false
    @State private var previewAttachment: PreviewAttachment?
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @State private var isSpeaking = false

    private struct PreviewAttachment: Identifiable {
        let filename: String
        var id: String { filename }
    }

    /// Plain-text payload the long-press menu copies. Trimmed so trailing
    /// whitespace from streaming doesn't land on the pasteboard.
    private var copyableText: String {
        message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canEdit: Bool {
        message.role == .user && !message.isStreaming && onEdit != nil
    }

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            HStack {
                if message.role == .user { Spacer(minLength: 60) }
                if message.role == .user {
                    userBubble
                        .contextMenu { bubbleMenu }
                } else {
                    assistantBubble
                        .contextMenu { bubbleMenu }
                }
                if message.role == .assistant { Spacer(minLength: 0) }
            }

            // Mutation chips
            if !message.taskMutations.isEmpty {
                mutationChips
            }

            // Post-stream action row (copy / thumbs) with fade-in
            if message.role == .assistant && !message.isStreaming &&
                (!message.content.isEmpty || message.uiSpec != nil) {
                actionRow
                    .opacity(showActions ? 1 : 0)
                    .animation(.easeIn(duration: 0.3), value: showActions)
                    .onAppear {
                        guard !showActions else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation { showActions = true }
                        }
                    }
                    .onChange(of: message.isStreaming) { _, isStreaming in
                        if !isStreaming, !showActions {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                withAnimation { showActions = true }
                            }
                        }
                    }
            }
        }
        .fullScreenCover(item: $previewAttachment) { item in
            AttachmentPreviewSheet(filename: item.filename) {
                previewAttachment = nil
            }
        }
    }

    // MARK: User Bubble — no border, just background fill

    @ViewBuilder
    private func userAttachmentCell(filename: String, index: Int, total: Int) -> some View {
        let isImage = AttachmentService.shared.isImageFile(filename)
        let label = AttachmentService.shared.friendlyAttachmentLabel(
            filename: filename,
            index: index,
            total: total
        )
        Button {
            previewAttachment = PreviewAttachment(filename: filename)
        } label: {
            VStack(alignment: .center, spacing: 4) {
                if isImage {
                    AttachmentThumbnailView(filename: filename, size: 64) {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                            .fill(AppTheme.surfaceSecondary)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 18))
                                    .foregroundStyle(AppTheme.mutedText)
                            )
                    }
                } else {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                        .fill(AppTheme.surfaceSecondary)
                        .frame(width: 64, height: 64)
                        .overlay(
                            Image(systemName: "doc.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(AppTheme.mutedText)
                        )
                }
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 72)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Attachment: \(label). Double tap to view full screen")
    }

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Context chip — shows which email/page was attached when the message was sent
            if let label = message.contextLabel {
                HStack(spacing: 5) {
                    Image(systemName: message.contextIcon ?? "doc.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.07), in: Capsule())
                .frame(maxWidth: 260, alignment: .trailing)
            }
            if !message.attachmentFileNames.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(message.attachmentFileNames.enumerated()), id: \.offset) { index, name in
                        userAttachmentCell(
                            filename: name,
                            index: index,
                            total: message.attachmentFileNames.count
                        )
                    }
                }
            }
            if !message.content.isEmpty {
                Text(message.content)
                    .font(.system(size: 16, weight: .medium))
                    .tracking(-0.1)
                    .lineSpacing(3)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        AppTheme.chatUserBubbleFill,
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.card + 2, style: .continuous)
                    )
                    // Cap the user bubble on wide screens (iPad / landscape) so a long
                    // pasted prompt doesn't stretch edge-to-edge. (P11)
                    .frame(maxWidth: 560, alignment: .trailing)
            }
        }
    }

    // MARK: Assistant Bubble

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Web search status indicator — shown while backend is searching
            if message.searchState == .searching {
                SearchingIndicator(queries: message.searchQueries)
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

            // Main content. When the bubble is mid-stream with no content yet we
            // render a 2-line shimmer instead of a blank gap — gives the user a
            // sense the response is forming even while the thinking indicator
            // animates above. (P3)
            if message.content.isEmpty && message.isStreaming {
                AssistantShimmerPlaceholder()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
            } else {
                assistantContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
            }

            // Connect CTA — shown when AI mentions a service that isn't connected.
            // Detection: service not connected AND response text mentions the service name.
            if !message.isStreaming && !message.content.isEmpty {
                let lc = message.content.lowercased()
                if !calendarConnected && (lc.contains("calendar") || lc.contains("not connected")) {
                    connectBanner(service: "calendar", icon: "calendar", color: .primary)
                }
                if !emailConnected && (lc.contains("email") || lc.contains("inbox") || lc.contains("not connected")) {
                    connectBanner(service: "email", icon: "envelope", color: .orange)
                }
            }
        }
        .animation(.snappy(duration: 0.3), value: message.searchState)
        .animation(.snappy(duration: 0.3), value: message.sources.count)
    }

    @ViewBuilder
    private func connectBanner(service: String, icon: String, color: Color) -> some View {
        Button {
            onConnect?(service)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text("Connect \(service.capitalized)")
                    .font(.system(size: 13, weight: .medium))
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous))
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    /// Mixed-content renderer: text runs with live markdown + [task:UUID] cards + generative UI specs.
    @ViewBuilder
    private var assistantContent: some View {
        let rawContent = message.isStreaming ? stripStreamingUISpec(message.content) : message.content
        let parts = parseMessageContent(rawContent)
        let eventCount = parts.reduce(0) { n, p in
            if case .eventRef = p { return n + 1 }
            return n
        }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                contentPartView(
                    part,
                    isLastPart: i == parts.count - 1,
                    eventCompact: eventCount > 1
                )
            }
            // Render generative UI spec if present (parsed after streaming completes)
            if let spec = message.uiSpec {
                ChatUISpecView(spec: spec) { action, params, completion in
                    handleSpecAction(action, params: params, completion: completion)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    /// Handles actions from generative UI card taps. Side-effecting actions (autosave, send,
    /// clipboard, undo) are executed locally; navigation actions are forwarded to the parent.
    private func handleSpecAction(
        _ action: String,
        params: [String: String],
        completion: ChatUISpecActionCompletion? = nil,
        undoDepth: Int = 0
    ) {
        let maxUndoDepth = 8
        switch action {
        case "copy_text":
            if let content = params["content"] {
                UIPasteboard.general.string = content
            }
            completion?(true, nil)
        case "update_draft":
            guard let draftId = params["draftId"], let payloadStr = params["payload"],
                  let payload = DraftService.decodePayload(payloadStr) else {
                completion?(false, "Invalid draft payload")
                return
            }
            Task { @MainActor in
                do {
                    try await services.draftService.update(draftId: draftId, payload: payload)
                    completion?(true, nil)
                } catch {
                    let msg = error.localizedDescription
                    onCardError?("Draft could not be saved: \(msg)")
                    completion?(false, msg)
                }
            }
        case "send_draft":
            guard let payloadStr = params["payload"],
                  let payload = DraftService.decodePayload(payloadStr) else {
                completion?(false, "Invalid send payload")
                return
            }
            let draftId = params["draftId"]
            Task { @MainActor in
                do {
                    try await services.draftService.send(draftId: draftId, payload: payload)
                    completion?(true, nil)
                } catch {
                    let msg = error.localizedDescription
                    onCardError?("Message could not be sent: \(msg)")
                    completion?(false, msg)
                }
            }
        case "attach_to_draft":
            // Attachment picking belongs to the host composer; surface the intent for now.
            onNavigate?(action, params)
            completion?(true, nil)
        case "undo":
            guard undoDepth < maxUndoDepth else {
                completion?(false, nil)
                return
            }
            guard let undoAction = params["undoAction"], !undoAction.isEmpty, undoAction != "undo" else {
                completion?(false, nil)
                return
            }
            var nestedParams: [String: String] = [:]
            if let nestedRaw = params["undoParams"] {
                let trimmed = nestedRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    guard let data = nestedRaw.data(using: .utf8),
                          let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
                        completion?(false, nil)
                        return
                    }
                    nestedParams = dict
                }
            }
            handleSpecAction(undoAction, params: nestedParams, completion: completion, undoDepth: undoDepth + 1)
        case "open_attachment":
            // Open the preview URL in Safari if provided. Real attachment download lives in the
            // email thread surface; chat-side preview is "good enough" for v1.
            if let url = params["previewUrl"], let parsed = URL(string: url) {
                UIApplication.shared.open(parsed)
            }
            completion?(true, nil)
        case "toggle_checklist_item":
            // Local-only toggle today; persistence model TBD.
            completion?(true, nil)
        case "navigate_document":
            onNavigate?(action, params)
            completion?(true, nil)
        case "navigate_day":
            onNavigate?(action, params)
            completion?(true, nil)
        default:
            onNavigate?(action, params)
            completion?(true, nil)
        }
    }

    @ViewBuilder
    private func contentPartView(_ part: ContentPart, isLastPart: Bool, eventCompact: Bool) -> some View {
        switch part {
        case .text(let txt):
            MarkdownView(content: txt)
                .overlay(alignment: .bottomLeading) {
                    if isLastPart && message.isStreaming { BlinkingCursor() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // VoiceOver: mark this run as updating live so each flush doesn't
                // re-announce the full content from the top. We expose the final
                // content via `accessibilityValue` so the last announcement after
                // stream-completion still reads the answer end-to-end. (P12)
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityValue(message.isStreaming ? "" : txt)

        case .taskRef(let uuid):
            if let task = allTasks.first(where: { $0.id == uuid }) {
                MiniTaskCard(task: task)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

        case .eventRef(let eventId):
            MiniEventCard(eventId: eventId, compact: eventCompact)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
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
        // Failures get a distinctive icon so the user spots them immediately.
        if !m.success { return "exclamationmark.triangle.fill" }
        switch m.action {
        case .create: return "plus.circle.fill"
        case .update: return "pencil.circle.fill"
        case .delete: return "trash.circle.fill"
        }
    }

    private func mutationLabel(_ m: AIChatTaskMutation) -> String {
        // Surface the error so failed tool calls aren't silently dropped (Bug #3).
        if !m.success {
            let actionVerb: String
            switch m.action {
            case .create: actionVerb = "Couldn't create"
            case .update: actionVerb = "Couldn't update"
            case .delete: actionVerb = "Couldn't delete"
            }
            let titleSuffix = m.title.map { " \"\($0)\"" } ?? ""
            let errorSuffix = m.errorMessage.map { ": \($0)" } ?? ""
            return "\(actionVerb)\(titleSuffix)\(errorSuffix)"
        }
        switch m.action {
        case .create: return "Created: \(m.title ?? "task")"
        case .update: return "Updated: \(m.title ?? "task")"
        // Bug #9: include the task title when the AI deletes one.
        case .delete: return "Deleted: \(m.title ?? "task")"
        }
    }

    private func mutationColor(_ m: AIChatTaskMutation) -> Color {
        if !m.success { return AppTheme.danger }
        switch m.action {
        case .create: return .green
        case .update: return .primary
        case .delete: return AppTheme.danger
        }
    }

    // MARK: Action Row — copy shows checkmark briefly; thumbs toggle state

    private var actionRow: some View {
        let copyableText = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let canCopy = !copyableText.isEmpty

        return HStack(spacing: 4) {
            if !message.sources.isEmpty {
                AISourcesButton(sources: message.sources) { source in
                    handleSourceSelection(source)
                }
                .padding(.trailing, 4)
            }

            Button {
                onRetry()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canRetry)
            .opacity(canRetry ? 1 : 0.45)

            // Copy button: shows checkmark for 1.5s after tap, ignores re-taps while showing
            Button {
                guard !didCopy else { return }
                UIPasteboard.general.string = copyableText
                withAnimation(.snappy(duration: 0.15)) { didCopy = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.snappy(duration: 0.15)) { didCopy = false }
                }
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(didCopy ? .green : AppTheme.mutedText)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(!canCopy)

            // TODO(P4): Wire thumbs up/down to a chat-feedback endpoint. The
            // existing `assistant.recordFeedback` tRPC route is for the morning
            // assistant surface — not for AI chat messages — and shipping local
            // no-op toggles fools users into thinking their rating was recorded.
            // Removed for now; restore once a chat-message feedback endpoint is
            // available on the backend.
        }
        .padding(.leading, 4)
    }

    /// Forward a Sources sheet selection to the parent's navigation handler.
    /// Web sources open inline in the sheet; everything else (thread, event,
    /// task, email) navigates via the existing `handleCardNavigation` action
    /// map — same action names + param keys as the generative-UI cards so we
    /// get task → Tasks tab, thread/email → Email tab, event → event detail.
    private func handleSourceSelection(_ source: AISource) {
        guard let entityId = source.entityId else { return }
        switch source.kind {
        case .thread, .email:
            onNavigate?("navigate_thread", ["threadId": entityId])
        case .calendarEvent, .meeting:
            onNavigate?("navigate_event", ["eventId": entityId])
        case .task:
            onNavigate?("navigate_task", ["taskId": entityId])
        default:
            return
        }
    }

    // MARK: Long-press menu — copy + edit (user only)

    @ViewBuilder
    private var bubbleMenu: some View {
        Button {
            guard !copyableText.isEmpty else { return }
            UIPasteboard.general.string = copyableText
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .disabled(copyableText.isEmpty)

        Button {
            guard !copyableText.isEmpty else { return }
            // Markdown-style block quote — pastes into reply drafts (Slack /
            // Notion / Bear / email) as a quoted reference instead of plain
            // text. One line per source line so quote nesting reads naturally.
            let quoted = copyableText
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "> \($0)" }
                .joined(separator: "\n")
            UIPasteboard.general.string = quoted
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } label: {
            Label("Copy as quote", systemImage: "quote.bubble")
        }
        .disabled(copyableText.isEmpty)

        if canEdit {
            Button {
                onEdit?(message)
            } label: {
                Label("Edit message", systemImage: "pencil")
            }
        }

        // Share — UIActivityViewController bridge so long replies can be sent
        // out via Messages, Mail, Notes, etc. without round-tripping through
        // the clipboard. (P8)
        Button {
            guard !copyableText.isEmpty else { return }
            presentShareSheet(for: copyableText)
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .disabled(copyableText.isEmpty)

        // Speak — pipes the content through AVSpeechSynthesizer so the user
        // can listen to longer replies hands-free. Tapping again stops. (P8)
        Button {
            guard !copyableText.isEmpty else { return }
            if speechSynthesizer.isSpeaking {
                speechSynthesizer.stopSpeaking(at: .immediate)
                isSpeaking = false
            } else {
                let utterance = AVSpeechUtterance(string: copyableText)
                utterance.rate = AVSpeechUtteranceDefaultSpeechRate
                speechSynthesizer.speak(utterance)
                isSpeaking = true
            }
        } label: {
            Label(isSpeaking ? "Stop" : "Speak", systemImage: isSpeaking ? "stop.circle" : "speaker.wave.2")
        }
        .disabled(copyableText.isEmpty)
    }

    /// Bridges to UIActivityViewController for the long-press "Share" item.
    /// Walks the presented view chain to avoid the "view not in window hierarchy"
    /// log when the chat sheet itself is the top-most controller.
    private func presentShareSheet(for text: String) {
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        // Prefer the foreground-active scene; `connectedScenes.first` is unordered
        // and can present on a background window on iPad / multi-window.
        let activeScene = (UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.first) as? UIWindowScene
        if let scene = activeScene,
           let root = scene.windows.first?.rootViewController {
            var top = root
            while let presented = top.presentedViewController { top = presented }
            activity.popoverPresentationController?.sourceView = top.view
            top.present(activity, animated: true)
        }
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

// MARK: - ReasoningBox

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
                    .textSelection(.enabled)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(
            AppTheme.surfacePrimary.opacity(0.5),
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
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
                    .foregroundStyle(task.completed ? Color.primary : AppTheme.mutedText)

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
            .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous).stroke(AppTheme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            TaskDetailSheet(task: task)
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - MiniEventCard

/// Compact tappable event card for `[event:EVENTKIT_ID]` in assistant text (mirrors `MiniTaskCard`).
private struct MiniEventCard: View {
    let eventId: String
    var compact: Bool

    @Environment(AppServices.self) private var services
    @State private var title: String = "Event"
    @State private var subtitle: String = ""
    @State private var barColor: Color = .primary
    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: {
            HStack(alignment: .top, spacing: compact ? 8 : 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(barColor)
                    .frame(width: 3, height: compact ? 30 : 40)

                VStack(alignment: .leading, spacing: compact ? 1 : 2) {
                    Text(title)
                        .font(.system(size: compact ? 13 : 14, weight: .semibold))
                        .tracking(-0.1)
                        .foregroundStyle(.primary)
                        .lineLimit(compact ? 1 : 2)
                        .multilineTextAlignment(.leading)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: compact ? 10 : 11, weight: .medium))
                            .foregroundStyle(AppTheme.mutedText)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
            }
            .padding(compact ? 8 : 12)
            .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .task(id: eventId) { await loadEvent() }
        .sheet(isPresented: $showDetail) {
            EKEventDetailSheet(eventId: eventId)
                .presentationDragIndicator(.visible)
        }
    }

    private func loadEvent() async {
        let ev = await services.calendarService.chatDisplayEvent(for: eventId)
        await MainActor.run {
            guard let ev else {
                title = "Calendar event"
                subtitle = "Details may be unavailable"
                return
            }
            let t = ev.title.trimmingCharacters(in: .whitespacesAndNewlines)
            title = t.isEmpty ? "Event" : t
            if ev.isAllDay {
                subtitle = "All day · \(ev.startDate.formatted(date: .abbreviated, time: .omitted))"
            } else {
                let startS = ev.startDate.formatted(date: .abbreviated, time: .shortened)
                let endS = ev.endDate.formatted(date: .omitted, time: .shortened)
                subtitle = "\(startS) – \(endS)"
            }
            barColor = Color(
                red: ev.calendarColorRed,
                green: ev.calendarColorGreen,
                blue: ev.calendarColorBlue
            )
        }
    }
}

// MARK: - AssistantShimmerPlaceholder

/// Two-line rounded shimmer rendered inside an empty streaming assistant bubble.
/// Replaces the previous blank gap so users see the response is forming even
/// before the first token lands. (P3)
private struct AssistantShimmerPlaceholder: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            shimmerBar(width: .infinity, height: 10)
            shimmerBar(width: 220, height: 10)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    @ViewBuilder
    private func shimmerBar(width: CGFloat, height: CGFloat) -> some View {
        let base = RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(AppTheme.surfacePrimary)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(AppTheme.cardBorder.opacity(0.4), lineWidth: 0.5)
            )
            .opacity(0.4 + (phase * 0.5))
        if width == .infinity {
            base.frame(maxWidth: .infinity).frame(height: height)
        } else {
            base.frame(width: width, height: height)
        }
    }
}

// MARK: - BlinkingCursor

private struct BlinkingCursor: View {
    @State private var visible = false

    var body: some View {
        Rectangle()
            .frame(width: 2, height: 16)
            .foregroundStyle(.primary.opacity(0.7))
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible = true
                }
            }
            .offset(x: 2)
    }
}

// MARK: - ChatHistoryView

/// Lists all saved conversations. Drag handle at top, "Chats" title top-left,
/// new-chat button top-right, search bar pinned to bottom — matches the reference design.
struct ChatHistoryView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FolderRecord.createdAt) private var folders: [FolderRecord]

    enum ChatSortOrder { case newestFirst, oldestFirst, alphabetical }

    @State private var searchText = ""
    @State private var folderFilter: String = "all"
    @State private var sortOrder: ChatSortOrder = .newestFirst
    @State private var movingConversation: AIChatConversation?

    private var chatService: AIChatService { services.aiChatService }
    /// Shared formatter — creating one per row per render is wasteful
    private let relativeDateFormatter = RelativeDateTimeFormatter()

    private var filtered: [AIChatConversation] {
        let base = chatService.savedConversations.filter { convo in
            let matchesFolder: Bool = {
                switch folderFilter {
                case "all":
                    return true
                default:
                    return convo.folderID?.uuidString == folderFilter
                }
            }()
            guard matchesFolder else { return false }
            guard !searchText.isEmpty else { return true }
            return convo.title.localizedCaseInsensitiveContains(searchText)
        }
        switch sortOrder {
        case .newestFirst:  return base.sorted { $0.createdAt > $1.createdAt }
        case .oldestFirst:  return base.sorted { $0.createdAt < $1.createdAt }
        case .alphabetical: return base.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        }
    }

    private var folderFilterButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                folderFilterButton(title: "All", systemImage: "tray", filter: "all", count: chatService.savedConversations.count)
                ForEach(folders) { folder in
                    folderFilterButton(
                        title: folder.name,
                        systemImage: "folder.fill",
                        filter: folder.id.uuidString,
                        count: chatService.savedConversations.filter { $0.folderID == folder.id }.count
                    )
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func folderFilterButton(title: String, systemImage: String, filter: String, count: Int) -> some View {
        Button {
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
            .foregroundStyle(folderFilter == filter ? AppTheme.accentBlue : AppTheme.mutedText)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(folderFilter == filter ? AppTheme.accentBlue.opacity(0.12) : AppTheme.surfacePrimary, in: Capsule())
            .overlay(Capsule().stroke(folderFilter == filter ? AppTheme.accentBlue.opacity(0.22) : AppTheme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func folderName(for folderID: UUID?) -> String? {
        guard let folderID else { return nil }
        return folders.first(where: { $0.id == folderID })?.name
    }

    private func moveConversation(_ conversation: AIChatConversation, to folderID: UUID?) {
        chatService.moveConversation(conversation, to: folderID)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom header — "Chats" title left, new-chat button right
            HStack(alignment: .center) {
                Text("Chats")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.5)

                Spacer()

                // Sort / filter dropdown
                Menu {
                    Section("Sort") {
                        Button {
                            sortOrder = .newestFirst
                        } label: {
                            Label("Newest first", systemImage: sortOrder == .newestFirst ? "checkmark" : "")
                        }
                        Button {
                            sortOrder = .oldestFirst
                        } label: {
                            Label("Oldest first", systemImage: sortOrder == .oldestFirst ? "checkmark" : "")
                        }
                        Button {
                            sortOrder = .alphabetical
                        } label: {
                            Label("Alphabetical", systemImage: sortOrder == .alphabetical ? "checkmark" : "")
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .background(AppTheme.surfacePrimary, in: Circle())
                        .overlay(Circle().stroke(AppTheme.cardBorder, lineWidth: 1))
                }
                .menuStyle(.automatic)

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

            folderFilterButtons
                .padding(.bottom, 8)

            Divider().opacity(0.3)

            // Conversation list or empty state
            if filtered.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filtered) { conv in
                        Button {
                            chatService.loadConversation(conv)
                            dismiss()
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(conv.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .tracking(-0.2)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    HStack(spacing: 6) {
                                        Text(relativeDateFormatter.localizedString(for: conv.createdAt, relativeTo: Date()))
                                        if let folderName = folderName(for: conv.folderID) {
                                            Text("•")
                                            Label(folderName, systemImage: "folder")
                                        }
                                    }
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AppTheme.mutedText)
                                }
                                Spacer()
                                Menu {
                                    Button("Unfiled") {
                                        moveConversation(conv, to: nil)
                                    }
                                    if !folders.isEmpty {
                                        Divider()
                                    }
                                    ForEach(folders) { folder in
                                        Button(folder.name) {
                                            moveConversation(conv, to: folder.id)
                                        }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(AppTheme.mutedText)
                                        .frame(width: 24, height: 24)
                                }
                                // .menuStyle(.borderlessButton) removed — macOS-only API
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                movingConversation = conv
                            } label: {
                                Label("Move", systemImage: "folder")
                            }
                            .tint(AppTheme.accentBlue)
                        }
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
            .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous).stroke(AppTheme.cardBorder, lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .task {
            await services.captureService.syncSharedFolders(in: modelContext)
        }
        // Background matches main chat sheet — set via presentationBackground at call site
        .background(AppTheme.sheetBackground.ignoresSafeArea())
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
                        .tint(AppTheme.switchTint)
                    Toggle("Write tasks", isOn: Bindable(chatService).aiCanWriteTasks)
                        .tint(AppTheme.switchTint)
                } header: {
                    Text("Tasks")
                } footer: {
                    Text("\"Read\" injects your task list into the AI's context. \"Write\" lets the AI create, edit, and delete tasks.")
                }

                // Calendar section
                Section {
                    Toggle("Read calendar", isOn: Bindable(chatService).aiCanReadCalendar)
                        .tint(AppTheme.switchTint)
                    Toggle("Create events", isOn: Bindable(chatService).aiCanWriteCalendar)
                        .tint(AppTheme.switchTint)
                } header: {
                    Text("Calendar")
                } footer: {
                    Text("\"Read\" injects today's and this week's events. \"Create\" lets the AI add events to your calendar.")
                }

                // Email section
                Section {
                    Toggle("Read emails", isOn: Bindable(chatService).aiCanReadEmail)
                        .tint(AppTheme.switchTint)
                    Toggle("Send emails", isOn: Bindable(chatService).aiCanSendEmail)
                        .tint(AppTheme.switchTint)
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
                                        .foregroundStyle(.primary)
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
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.sheetBackground.ignoresSafeArea())
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
                .scrollContentBackground(.hidden)
            }
            .background(AppTheme.sheetBackground.ignoresSafeArea())
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
            .scrollContentBackground(.hidden)
            .background(AppTheme.sheetBackground.ignoresSafeArea())
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

// MARK: - FullScreenComposeView

/// Full-screen text editor for composing long prompts.
/// Presented as a sheet from the expand button in the chat input box.
private struct FullScreenComposeView: View {
    @Binding var inputText: String
    let onSend: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                TextEditor(text: $inputText)
                    .font(.system(size: 16))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.sheetBackground)
                    .focused($isFocused)

                // Send button floating over the editor — only shows when there's text
                if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .clipShape(Circle())
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .background(AppTheme.sheetBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .font(.system(size: 15))
                }
                ToolbarItem(placement: .principal) {
                    Text("Compose")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
        .task {
            // Delay focus until the sheet's presentation animation finishes (~300ms).
            // Setting isFocused = true during the animation triggers competing keyboard
            // animations and causes a visible 5-second hang on sheet open.
            try? await Task.sleep(for: .milliseconds(350))
            isFocused = true
        }
        .animation(.snappy(duration: 0.15), value: inputText.isEmpty)
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
