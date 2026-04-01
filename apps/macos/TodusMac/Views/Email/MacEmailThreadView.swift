import SwiftUI
import WebKit

/// Email thread detail view — shows all messages in a thread with HTML rendering.
/// Desktop-optimized: wider layout, collapsible messages, reply bar.
struct MacEmailThreadView: View {
    @Environment(MacAppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let threadId: String

    @State private var detail: GetThreadResponse? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var expandedMessages: Set<String> = []
    @State private var showCompose = false
    @State private var assistantThread: MailAssistantThread? = nil
    @State private var assistantDraftSeed = ""
    @State private var assistantNotice: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider().opacity(0.3)

            if isLoading {
                Spacer()
                ProgressView()
                    .controlSize(.regular)
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
                // Messages
                ScrollView {
                    LazyVStack(spacing: MacTheme.spacing8) {
                        if let assistant = assistantThread, services.assistantAutomationPolicy.assistantThreadActionsVisible {
                            MacMailAssistantCard(
                                assistant: assistant,
                                onSummarize: refreshAssistant,
                                onCreateTask: { suggestion in
                                    await handleCreateTask(suggestion)
                                },
                                onCreateEvent: {
                                    await handleCreateEvent()
                                },
                                onDraftReply: {
                                    await handleDraftReply()
                                },
                                onAskAssistant: openAssistant,
                                onResearch: openAssistant
                            )
                        }

                        ForEach(Array(detail.messages.enumerated()), id: \.element.id) { index, message in
                            messageView(message, isLast: index == detail.messages.count - 1)
                        }
                    }
                    .padding(MacTheme.spacing16)
                }

                // Reply bar
                replyBar
            }
        }
        .task {
            await loadThread()
        }
        .sheet(isPresented: $showCompose, onDismiss: { assistantDraftSeed = "" }) {
            if let lastMessage = detail?.messages.last {
                MacEmailComposeView(replyTo: lastMessage, threadId: threadId, body: assistantDraftSeed)
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
                dismiss()
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

            // Actions
            HStack(spacing: MacTheme.spacing4) {
                Button {
                    Task { await services.emailService.archiveThreads(ids: [threadId]) }
                    dismiss()
                } label: {
                    Image(systemName: "archivebox")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Archive")

                Button {
                    Task { await services.emailService.deleteThreads(ids: [threadId]) }
                    dismiss()
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

    private func refreshAssistant() async {
        assistantThread = await services.emailService.loadAssistant(threadId: threadId)
    }

    private func handleCreateTask(_ suggestion: MailAssistantSuggestedTask) async {
        let success = await services.emailService.createAssistantTask(threadId: threadId, suggestion: suggestion)
        assistantNotice = success ? "Task created from this email thread." : "Could not create the task."
        if success {
            await refreshAssistant()
        }
    }

    private func handleCreateEvent() async {
        guard let event = assistantThread?.suggestedEvent else {
            assistantNotice = "No event suggestion is ready for this thread yet."
            return
        }

        let success = await services.emailService.createAssistantEvent(threadId: threadId, suggestion: event)
        assistantNotice = success ? "Calendar event created from this thread." : "Could not create the event."
        if success {
            await refreshAssistant()
        }
    }

    private func handleDraftReply() async {
        guard let result = await services.emailService.generateAssistantDraft(threadId: threadId) else {
            assistantNotice = "Could not generate a reply draft."
            return
        }

        if result.created {
            // Draft was just created — seed the compose sheet and open it
            assistantDraftSeed = result.preview ?? ""
            showCompose = true
            await refreshAssistant()
        } else {
            // Draft already exists or was skipped — surface the reason as a notice
            assistantNotice = result.reason
        }
    }

    private func openAssistant() {
        services.aiChatService.currentPageContext = "Email thread: \(detail?.messages.first?.subject ?? "Message")"
        services.showsAssistantPanel = true
    }

    // MARK: - Message View

    private func messageView(_ message: EmailMessage, isLast: Bool) -> some View {
        let isExpanded = expandedMessages.contains(message.id) || isLast

        return VStack(alignment: .leading, spacing: 0) {
            // Sender header (clickable to expand/collapse)
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
                    senderInitial(message.from)

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
                .padding(.horizontal, MacTheme.spacing12)
                .padding(.vertical, MacTheme.spacing8)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().opacity(0.15).padding(.horizontal, MacTheme.spacing12)

                // Message body
                if !message.body.isEmpty {
                    EmailHTMLView(html: message.body)
                        .frame(minHeight: 100)
                        .padding(.horizontal, MacTheme.spacing12)
                        .padding(.vertical, MacTheme.spacing8)
                } else if let plainText = message.plainText, !plainText.isEmpty {
                    Text(plainText)
                        .font(.system(size: 13))
                        .foregroundStyle(MacTheme.textPrimary)
                        .padding(.horizontal, MacTheme.spacing12)
                        .padding(.vertical, MacTheme.spacing8)
                        .textSelection(.enabled)
                } else {
                    Text("No content")
                        .font(.system(size: 13))
                        .foregroundStyle(MacTheme.mutedText)
                        .italic()
                        .padding(MacTheme.spacing12)
                }

                HStack(spacing: MacTheme.spacing8) {
                    Button("Task") {
                        Task {
                            await handleCreateTask(
                                MailAssistantSuggestedTask(
                                    title: message.subject.isEmpty ? "Email follow-up" : "Follow up: \(message.subject)",
                                    description: message.plainText,
                                    priority: "medium",
                                    dueDate: nil
                                )
                            )
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Event") {
                        Task { await handleCreateEvent() }
                    }
                    .buttonStyle(.bordered)

                    Button("Ask AI", action: openAssistant)
                        .buttonStyle(.bordered)

                    Button("Research", action: openAssistant)
                        .buttonStyle(.bordered)
                }
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, MacTheme.spacing12)
                .padding(.bottom, MacTheme.spacing12)
            }
        }
        .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func senderInitial(_ sender: EmailSender) -> some View {
        let initial = sender.name.first.map { String($0).uppercased() } ?? "?"
        let colorIndex = abs(sender.email.hashValue) % 8
        let colors: [Color] = [.blue, .purple, .orange, .pink, .teal, .indigo, .mint, .cyan]

        return ZStack {
            Circle().fill(colors[colorIndex].opacity(0.15))
            Text(initial)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(colors[colorIndex])
        }
        .frame(width: 26, height: 26)
    }

    // MARK: - Reply Bar

    private var replyBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)
            HStack {
                Spacer()
                Button {
                    showCompose = true
                } label: {
                    HStack(spacing: MacTheme.spacing6) {
                        Image(systemName: "arrowshape.turn.up.left")
                            .font(.system(size: 12, weight: .medium))
                        Text("Reply")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(MacTheme.accent)
                    .padding(.horizontal, MacTheme.spacing16)
                    .padding(.vertical, MacTheme.spacing8)
                    .background(MacTheme.accent.opacity(0.08), in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(MacTheme.spacing12)
        }
    }

    // MARK: - Data Loading

    private func loadThread() async {
        isLoading = true
        async let threadDetail = services.emailService.loadThread(id: threadId)
        async let assistant = services.emailService.loadAssistant(threadId: threadId)
        detail = await threadDetail
        assistantThread = await assistant
        if detail == nil {
            errorMessage = "Could not load thread."
        }
        isLoading = false

        // Mark as read
        Task { await services.emailService.markAsRead(ids: [threadId]) }
    }
}

private struct MacMailAssistantCard: View {
    let assistant: MailAssistantThread
    let onSummarize: () async -> Void
    let onCreateTask: (MailAssistantSuggestedTask) async -> Void
    let onCreateEvent: () async -> Void
    let onDraftReply: () async -> Void
    let onAskAssistant: () -> Void
    let onResearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mail Assistant")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.purple)
                        .textCase(.uppercase)
                    HStack(spacing: 8) {
                        MacAssistantPill(text: "\(Int(assistant.confidence * 100))% confidence")
                        MacAssistantPill(text: "\(assistant.riskLevel.rawValue.capitalized) risk")
                        if assistant.autoSendCandidate {
                            MacAssistantPill(text: "Low-risk auto-send")
                        }
                    }
                }
                Spacer()
                Button("Summarize") {
                    Task { await onSummarize() }
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                if assistant.replyNeeded { MacAssistantPill(text: "Needs reply") }
                if assistant.meetingRequested { MacAssistantPill(text: "Meeting request") }
                if !assistant.actionItems.isEmpty { MacAssistantPill(text: "Action items") }
                if assistant.followUpNeeded { MacAssistantPill(text: "Follow-up") }
            }

            Text(assistant.summary)
                .font(.system(size: 13))
                .foregroundStyle(MacTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(assistant.reason)
                .font(MacTheme.cardSubtitleFont())
                .foregroundStyle(MacTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Extract task") {
                    if let firstTask = assistant.suggestedTasks.first {
                        Task { await onCreateTask(firstTask) }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(assistant.suggestedTasks.isEmpty)

                Button("Create event") {
                    Task { await onCreateEvent() }
                }
                .buttonStyle(.bordered)
                .disabled(assistant.suggestedEvent?.startAt == nil || assistant.suggestedEvent?.endAt == nil)

                Button(assistant.existingDraft ? "Open draft" : "Draft reply") {
                    Task { await onDraftReply() }
                }
                .buttonStyle(.bordered)
                .disabled(!assistant.draftEligible && !assistant.existingDraft)

                Button("Ask AI", action: onAskAssistant)
                    .buttonStyle(.bordered)
                Button("Research", action: onResearch)
                    .buttonStyle(.bordered)
            }
            .font(.system(size: 11, weight: .semibold))
        }
        .padding(MacTheme.spacing12)
        .background(Color.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
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
            .background(Color.white.opacity(0.65), in: Capsule(style: .continuous))
    }
}

// MARK: - HTML Email View (NSViewRepresentable)

/// Renders HTML email content using WKWebView on macOS.
struct EmailHTMLView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let wrapped = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          * { box-sizing: border-box; }
          html, body { margin: 0; padding: 0; overflow-x: hidden; }
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
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                return .cancel
            }
            return .allow
        }
    }
}
