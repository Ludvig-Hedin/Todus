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
    @State private var assistantNotice: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)

            if isLoading {
                Spacer()
                ProgressView().controlSize(.regular)
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: MacTheme.spacing8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(MacTheme.mutedText)
                    Text(error)
                        .font(MacTheme.cardSubtitleFont())
                        .foregroundStyle(MacTheme.textSecondary)
                }
                Spacer()
            } else if let detail {
                // Single scrollable area — the outer ScrollView handles all scrolling.
                // Messages use PassthroughWKWebView which forwards scroll events upward
                // so the WebView itself never consumes scroll wheel input.
                ScrollView {
                    VStack(spacing: 0) {
                        messagePreview(detail)
                            .padding(.horizontal, MacTheme.spacing16)
                            .padding(.top, MacTheme.spacing16)
                            .padding(.bottom, MacTheme.spacing12)

                        if services.assistantAutomationPolicy.assistantThreadActionsVisible {
                            MacMailAssistantCard(
                                assistant: assistantThread,
                                isLoading: isLoadingAssistant,
                                onRefresh: refreshAssistant,
                                onCreateTask: { suggestion in await handleCreateTask(suggestion) },
                                onCreateEvent: { await handleCreateEvent() },
                                onDraftReply: { await handleDraftReply() },
                                onAskAssistant: openAssistant,
                                onResearch: openAssistant
                            )
                            .padding(.horizontal, MacTheme.spacing16)
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
                        MacEmailComposeView(replyAllTo: lastMessage, threadId: threadId, body: assistantDraftSeed)
                    case .forward:
                        MacEmailComposeView(forwarding: lastMessage)
                    }
                }
                .frame(minWidth: 520, minHeight: 380)
            }
        }
        .alert("Mail Assistant", isPresented: Binding(
            get: { assistantNotice != nil },
            set: { if !$0 { assistantNotice = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(assistantNotice ?? "")
        }
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

            VStack(alignment: .leading, spacing: 1) {
                Text(detail?.messages.first?.subject ?? "Thread")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                    .lineLimit(1)
                if let from = detail?.messages.first?.from {
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

                Button {
                    Task { await services.emailService.deleteThreads(ids: [threadId]) }
                    if let onClose { onClose() } else { dismiss() }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(red: 0.85, green: 0.3, blue: 0.3))
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
        }
        .padding(.horizontal, MacTheme.spacing16)
        .padding(.vertical, MacTheme.spacing12)
    }

    // MARK: - Action Handlers

    private func refreshAssistant() async {
        isLoadingAssistant = true
        assistantThread = await services.emailService.loadAssistant(threadId: threadId)
        isLoadingAssistant = false
    }

    private func handleCreateTask(_ suggestion: MailAssistantSuggestedTask) async {
        let success = await services.emailService.createAssistantTask(threadId: threadId, suggestion: suggestion)
        assistantNotice = success ? "Task created from this email thread." : "Could not create the task."
        if success { await refreshAssistant() }
    }

    private func handleCreateEvent() async {
        guard let event = assistantThread?.suggestedEvent else {
            assistantNotice = "No event suggestion is ready for this thread yet."
            return
        }
        let success = await services.emailService.createAssistantEvent(threadId: threadId, suggestion: event)
        assistantNotice = success ? "Calendar event created from this thread." : "Could not create the event."
        if success { await refreshAssistant() }
    }

    private func handleDraftReply() async {
        guard let result = await services.emailService.generateAssistantDraft(threadId: threadId) else {
            assistantNotice = "Could not generate a reply draft."
            return
        }
        if result.created {
            assistantDraftSeed = result.preview ?? ""
            showCompose = true
            await refreshAssistant()
        } else {
            assistantNotice =
                result.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Draft already exists or was skipped."
                : result.reason
        }
    }

    private func openAssistant() {
        services.aiChatService.currentPageContext = "Email thread: \(detail?.messages.first?.subject ?? "Message")"
        services.showsAssistantPanel = true
    }

    // MARK: - Message View

    private func messageView(_ message: EmailMessage, isLast: Bool) -> some View {
        let isExpanded = expandedMessages.contains(message.id) || isLast
        let msgId = message.id
        let heightBinding = Binding<CGFloat>(
            get: { webViewHeights[msgId] ?? 300 },
            set: { webViewHeights[msgId] = $0 }
        )

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
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
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                }
                .padding(.horizontal, MacTheme.spacing16)
                .padding(.vertical, MacTheme.spacing12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                if !message.body.isEmpty {
                    // PassthroughWKWebView forwards scroll events up so the outer SwiftUI
                    // ScrollView handles all scrolling — no nested scroll problem.
                    EmailHTMLView(html: message.body, height: heightBinding)
                        .frame(height: webViewHeights[msgId] ?? 300)
                        .padding(.horizontal, MacTheme.spacing16)
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
            }
        }
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
        isLoading = true
        isLoadingAssistant = true

        async let threadDetail = services.emailService.loadThread(id: threadId)
        async let assistant = services.emailService.loadAssistant(threadId: threadId)

        // Show the email body as soon as the thread arrives, even if the assistant
        // call is still pending. Previously we waited for both, doubling the perceived
        // load time when the assistant call was the slower of the two.
        detail = await threadDetail
        if detail == nil { errorMessage = "Could not load thread." }
        isLoading = false

        assistantThread = await assistant
        isLoadingAssistant = false

        Task { await services.emailService.markAsRead(ids: [threadId]) }
    }

    private func messagePreview(_ detail: GetThreadResponse) -> some View {
        let latest = detail.messages.last

        return VStack(alignment: .leading, spacing: MacTheme.spacing8) {
            HStack(spacing: MacTheme.spacing6) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacTheme.accent)
                Text("Latest message")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Spacer()
                if let latest {
                    Text(latest.date, format: .dateTime.month().day().hour().minute())
                        .font(MacTheme.metaFont())
                        .foregroundStyle(MacTheme.mutedText)
                }
            }

            Text(previewText(for: latest))
                .font(.system(size: 13))
                .foregroundStyle(MacTheme.textSecondary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MacTheme.spacing12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func previewText(for message: EmailMessage?) -> String {
        guard let message else { return "Open the thread to read the full conversation." }
        let raw = (message.plainText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? message.plainText
            : message.subject) ?? "Open the thread to read the full conversation."
        return raw.replacingOccurrences(of: "\n", with: " ")
    }
}

// MARK: - Assistant Card

/// Redesigned assistant card — leads with actionable suggestions and a clear summary.
/// Hides technical internals (raw confidence %, risk level) in favor of plain-language context.
private struct MacMailAssistantCard: View {
    /// nil while loading — card shows a loading state
    let assistant: AssistantThreadContext?
    let isLoading: Bool
    let onRefresh: () async -> Void
    let onCreateTask: (MailAssistantSuggestedTask) async -> Void
    let onCreateEvent: () async -> Void
    let onDraftReply: () async -> Void
    let onAskAssistant: () -> Void
    let onResearch: () -> Void
    @State private var shimmerPhase = false

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
            } else if let assistant {
                assistantContent(assistant)
            } else {
                // Analysis unavailable
                Text("Analysis not available for this email.")
                    .font(MacTheme.cardSubtitleFont())
                    .foregroundStyle(MacTheme.mutedText)
            }
        }
        .padding(MacTheme.spacing12)
        .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(MacTheme.cardBorder.opacity(0.7), lineWidth: 0.6)
        )
    }

    @ViewBuilder
    private func assistantContent(_ assistant: AssistantThreadContext) -> some View {
        // SECTION 1: What does this email need?
        let suggestions = contextualSuggestions(assistant)
        Text(assistant.recommendation.label.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(MacTheme.mutedText)
            .tracking(0.7)

        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(suggestions, id: \.self) { suggestion in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MacTheme.accent)
                            .padding(.top, 2)
                        Text(suggestion)
                            .font(.system(size: 13))
                            .foregroundStyle(MacTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }

        // SECTION 2: Summary (if different from the suggestions and non-empty)
        if !assistant.summary.isEmpty && !suggestionsContainSummary(assistant) {
            Text(assistant.summary)
                .font(.system(size: 13))
                .foregroundStyle(suggestions.isEmpty ? MacTheme.textPrimary : MacTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        // SECTION 3: Action items as bullets
        if !assistant.actionItems.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("Action items")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(MacTheme.mutedText)
                    .textCase(.uppercase)
                    .padding(.bottom, 1)
                ForEach(assistant.actionItems, id: \.self) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(MacTheme.textSecondary)
                            .frame(width: 4, height: 4)
                            .padding(.top, 5)
                        Text(item)
                            .font(.system(size: 12))
                            .foregroundStyle(MacTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }

        // SECTION 4: AI uncertainty note — only shown when confidence is very low
        // "High risk" means the AI isn't confident enough to take automated actions — irrelevant to display to the user.
        // We only surface a note when confidence < 40% so users know to be skeptical.
        if assistant.confidence < 0.4 && !assistant.reason.isEmpty {
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(MacTheme.mutedText)
                    .padding(.top, 1)
                Text(assistant.reason)
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if let person = assistant.people.first {
            VStack(alignment: .leading, spacing: 3) {
                Text(person.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Text(person.relationshipSummary)
                    .font(MacTheme.cardSubtitleFont())
                    .foregroundStyle(MacTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if !assistant.changedSinceLastOpen.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(assistant.changedSinceLastOpen.prefix(2), id: \.self) { item in
                    Text(item)
                        .font(MacTheme.cardSubtitleFont())
                        .foregroundStyle(MacTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        Divider().opacity(0.3)

        // SECTION 5: Action buttons with descriptive tooltips explaining disabled states
        HStack(spacing: MacTheme.spacing6) {
            let hasTask = !assistant.suggestedTasks.isEmpty
            Button("Extract task") {
                if let firstTask = assistant.suggestedTasks.first {
                    Task { await onCreateTask(firstTask) }
                }
            }
            .buttonStyle(MacAssistantActionButtonStyle(isPrimary: hasTask))
            .disabled(!hasTask)
            .help(hasTask
                ? "Create a task from this email: \(assistant.suggestedTasks.first?.title ?? "")"
                : "No specific tasks were identified in this email")

            let hasEvent = assistant.suggestedEvent?.startAt != nil && assistant.suggestedEvent?.endAt != nil
            Button("Create event") {
                Task { await onCreateEvent() }
            }
            .buttonStyle(MacAssistantActionButtonStyle())
            .disabled(!hasEvent)
            .help(hasEvent
                ? "Add \"\(assistant.suggestedEvent?.title ?? "meeting")\" to your calendar"
                : "No meeting details found in this email")

            let canDraft = assistant.replyNeeded || assistant.existingDraft || assistant.preparedActions.contains(where: { $0.type == "draft_reply" })
            Button(assistant.existingDraft ? "Review draft" : "Draft reply") {
                Task { await onDraftReply() }
            }
            .buttonStyle(MacAssistantActionButtonStyle())
            .disabled(!canDraft)
            .help(canDraft
                ? (assistant.existingDraft ? "Review the AI-drafted reply" : "Generate a reply draft with AI")
                : "A reply doesn't appear to be needed for this email")

            Button("Ask AI", action: onAskAssistant)
                .buttonStyle(MacAssistantActionButtonStyle())
                .help("Open the AI assistant to ask questions about this email")

            Button("Research", action: onResearch)
                .buttonStyle(MacAssistantActionButtonStyle())
                .help("Research topics related to this email with AI")
        }
        .font(.system(size: 11, weight: .semibold))
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

    /// Returns true if the suggestion prose already covers the summary content (avoids duplication).
    private func suggestionsContainSummary(_ a: AssistantThreadContext) -> Bool {
        // If suggestions are non-empty and the summary is just a short restatement, skip it.
        // Heuristic: if summary is under 80 chars it's likely covered by the suggestions.
        let suggestions = contextualSuggestions(a)
        return !suggestions.isEmpty && a.summary.count < 80
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

    func makeNSView(context: Context) -> PassthroughWKWebView {
        let webView = PassthroughWKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        // Transparent background so the SwiftUI theme shows through
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: PassthroughWKWebView, context: Context) {
        // Only reload when HTML content actually changes — prevents infinite loop:
        // height state update → updateNSView → reload → new height → repeat
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        context.coordinator.onHeightUpdate = { newHeight in
            guard newHeight > 0 else { return }
            DispatchQueue.main.async {
                self.height = newHeight
            }
        }

        let wrapped = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          * { box-sizing: border-box; }
          html, body { margin: 0; padding: 0; overflow-x: hidden; overflow-y: hidden; }
          body {
            font-family: -apple-system, system-ui, sans-serif;
            font-size: 13px; line-height: 1.5;
            color: #d0d0d0; background: transparent;
            word-wrap: break-word; overflow-wrap: break-word;
          }
          @media (prefers-color-scheme: light) { body { color: #1a1a1a; } }
          a { color: #5B9FFF; }
          img { max-width: 100% !important; height: auto !important; }
          pre, code { overflow-x: auto; max-width: 100%; white-space: pre-wrap; font-size: 12px; }
          blockquote { border-left: 2px solid #555; margin: 8px 0; padding-left: 12px; color: #888; }
          table { max-width: 100%; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
        webView.loadHTMLString(wrapped, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?
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
