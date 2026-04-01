import SwiftUI
import WebKit

/// Displays a full email thread — list of messages with HTML body rendering.
struct EmailThreadView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let threadId: String

    @State private var detail: EmailThreadDetail?
    @State private var isLoading = true
    @State private var showCompose = false
    /// Tracks star state — initialised from thread labels after load.
    @State private var isStarred = false
    /// Tracks read/unread state — starts false (thread is marked read on open).
    @State private var isUnread = false
    /// Shared thread-level assistant model for summaries, task extraction, and draft suggestions.
    @State private var assistantThread: MailAssistantThread? = nil
    @State private var assistantDraftSeed: String? = nil
    /// Guards against accidental delete — trash is the only destructive action in the header.
    @State private var showDeleteConfirmation = false
    @State private var assistantNotice: String?

    private var emailService: EmailService { services.emailService }

    var body: some View {
        ZStack {
            AppTheme.backgroundTop.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(.secondary)
            } else if let detail, !detail.messages.isEmpty {
                threadContent(detail)
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
        .background { SwipeBackEnabler() }
        .task {
            detail = await emailService.loadThread(id: threadId)
            isLoading = false

            // Derive star state from thread labels
            isStarred = detail?.labels?.contains(where: {
                let n = $0.name.uppercased()
                return n == "STARRED" || n == "\\STARRED"
            }) ?? false

            async let markReadTask: Void = emailService.markAsRead(ids: [threadId])
            async let assistant = emailService.loadAssistant(threadId: threadId)
            assistantThread = await assistant
            await markReadTask
        }
        .sheet(isPresented: $showCompose) {
            if let lastMessage = detail?.messages.last {
                EmailComposeView(replyTo: lastMessage, threadId: threadId, body: assistantDraftSeed)
                    .preferredColorScheme(services.appearancePreference.colorScheme)
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

    private func refreshAssistant() async {
        assistantThread = await emailService.loadAssistant(threadId: threadId)
    }

    private func handleCreateTask(_ suggestion: MailAssistantSuggestedTask) async {
        let success = await emailService.createAssistantTask(threadId: threadId, suggestion: suggestion)
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

        let success = await emailService.createAssistantEvent(threadId: threadId, suggestion: event)
        assistantNotice = success ? "Calendar event created from this thread." : "Could not create the event."
        if success {
            await refreshAssistant()
        }
    }

    private func handleDraftReply() async {
        guard let result = await emailService.generateAssistantDraft(threadId: threadId) else {
            assistantNotice = "Could not generate a reply draft."
            return
        }

        if result.created {
            // Draft was just created — seed compose and open it
            assistantDraftSeed = result.preview
            showCompose = true
            await refreshAssistant()
        } else {
            // Draft already exists or was skipped — surface the reason
            assistantNotice = result.reason
        }
    }

    private func openAssistant() {
        services.currentTab = .email
        services.aiChatService.currentPageContext = "Email thread: \(detail?.messages.first?.subject ?? "Message")"
        services.showsAIChat = true
    }

    // MARK: - Thread Content

    private func threadContent(_ detail: EmailThreadDetail) -> some View {
        VStack(spacing: 0) {
            threadHeader(detail)
            scrollBody(detail)
            replyBar
        }
    }

    // MARK: - Header

    private func threadHeader(_ detail: EmailThreadDetail) -> some View {
        HStack(spacing: 10) {
            // Back
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(LiquidGlassButtonStyle(cornerRadius: 10))
            .minTouchTarget()

            // Subject
            VStack(alignment: .leading, spacing: 1) {
                Text(detail.messages.first?.subject ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.2)
                    .lineLimit(1)
                if let from = detail.messages.first?.from.name {
                    Text(from)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppTheme.mutedText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // Action buttons — star, mark-unread, archive, trash
            HStack(spacing: 6) {
                // Star
                Button {
                    isStarred.toggle()
                    Task { await emailService.toggleStar(ids: [threadId]) }
                } label: {
                    Image(systemName: isStarred ? "star.fill" : "star")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isStarred ? Color.yellow : Color.primary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(LiquidGlassButtonStyle(cornerRadius: 10))
                .minTouchTarget()

                // Mark as unread
                Button {
                    isUnread = true
                    Task {
                        await emailService.markAsUnread(ids: [threadId])
                        dismiss()
                    }
                } label: {
                    Image(systemName: "envelope.badge")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(LiquidGlassButtonStyle(cornerRadius: 10))
                .minTouchTarget()

                // Visual divider between non-destructive and destructive action groups
                Divider()
                    .frame(height: 20)

                // Archive
                Button {
                    Task { await emailService.archiveThreads(ids: [threadId]) }
                    dismiss()
                } label: {
                    Image(systemName: "archivebox")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(LiquidGlassButtonStyle(cornerRadius: 10))
                .minTouchTarget()

                // Trash — shows confirmation to prevent accidental deletion on touch
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.danger)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(LiquidGlassButtonStyle(cornerRadius: 10))
                .minTouchTarget()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider().foregroundStyle(AppTheme.divider)
        }
        .confirmationDialog("Delete this thread?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await emailService.deleteThreads(ids: [threadId]) }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Scroll Body

    private func scrollBody(_ detail: EmailThreadDetail) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let assistant = assistantThread, services.assistantAutomationPolicy.assistantThreadActionsVisible {
                    MailAssistantCard(
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
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                }

                ForEach(Array(detail.messages.enumerated()), id: \.element.id) { index, message in
                    MessageBubble(
                        message: message,
                        onCreateTask: {
                            await handleCreateTask(
                                MailAssistantSuggestedTask(
                                    title: message.subject.isEmpty ? "Email follow-up" : "Follow up: \(message.subject)",
                                    description: message.plainText,
                                    priority: "medium",
                                    dueDate: nil
                                )
                            )
                        },
                        onCreateEvent: {
                            await handleCreateEvent()
                        },
                        onAskAssistant: openAssistant,
                        onResearch: openAssistant
                    )
                        .padding(.horizontal, 16)
                        .padding(.top, index == 0 && assistantThread == nil ? 16 : 8)
                        .padding(.bottom, index == detail.messages.count - 1 ? 16 : 0)
                }
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Reply Bar

    private var replyBar: some View {
        VStack(spacing: 0) {
            Divider().foregroundStyle(AppTheme.divider)
            HStack(spacing: 10) {
                Button {
                    showCompose = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrowshape.turn.up.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Reply")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .buttonStyle(LiquidGlassButtonStyle(cornerRadius: 12))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }
}

// MARK: - Mail Assistant Card

private struct MailAssistantCard: View {
    let assistant: MailAssistantThread
    let onSummarize: () async -> Void
    let onCreateTask: (MailAssistantSuggestedTask) async -> Void
    let onCreateEvent: () async -> Void
    let onDraftReply: () async -> Void
    let onAskAssistant: () -> Void
    let onResearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mail Assistant")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.purple)
                        .textCase(.uppercase)
                    HStack(spacing: 8) {
                        AssistantPill(text: "\(Int(assistant.confidence * 100))% confidence")
                        AssistantPill(text: "\(assistant.riskLevel.rawValue.capitalized) risk")
                        if assistant.autoSendCandidate {
                            AssistantPill(text: "Low-risk auto-send")
                        }
                    }
                }
                Spacer()
                Button("Summarize") {
                    Task { await onSummarize() }
                }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                if assistant.replyNeeded { AssistantPill(text: "Needs reply") }
                if assistant.meetingRequested { AssistantPill(text: "Meeting request") }
                if !assistant.actionItems.isEmpty { AssistantPill(text: "Action items found") }
                if assistant.followUpNeeded { AssistantPill(text: "Follow-up suggested") }
            }

            Text(assistant.summary)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(assistant.reason)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button("Extract tasks") {
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

                    Button("Ask assistant", action: onAskAssistant)
                        .buttonStyle(.bordered)
                    Button("Research", action: onResearch)
                        .buttonStyle(.bordered)
                }
            }

            if !assistant.actionItems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Detected actions")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(assistant.actionItems, id: \.self) { item in
                        Text("• \(item)")
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct AssistantPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.systemBackground).opacity(0.7), in: Capsule(style: .continuous))
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: EmailMessage
    let onCreateTask: () async -> Void
    let onCreateEvent: () async -> Void
    let onAskAssistant: () -> Void
    let onResearch: () -> Void
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sender row
            Button {
                withAnimation(.snappy(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    SenderAvatarView(email: message.from.email, name: message.from.name, size: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.from.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(message.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.mutedText)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.mutedText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            // Body
            if isExpanded {
                Divider()
                    .foregroundStyle(AppTheme.divider)
                    .padding(.horizontal, 14)

                if !message.body.isEmpty {
                    ExpandingEmailHTMLView(html: message.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                } else if let plain = message.plainText, !plain.isEmpty {
                    Text(plain)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                } else {
                    Text("No content")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.mutedText)
                        .italic()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }

                HStack(spacing: 8) {
                    Button("Task") {
                        Task { await onCreateTask() }
                    }
                    .buttonStyle(.bordered)

                    Button("Event") {
                        Task { await onCreateEvent() }
                    }
                    .buttonStyle(.bordered)

                    Button("Ask AI", action: onAskAssistant)
                        .buttonStyle(.bordered)

                    Button("Research", action: onResearch)
                        .buttonStyle(.bordered)
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.rowStroke, lineWidth: 1)
        )
    }
}

// MARK: - Expanding HTML View

private struct ExpandingEmailHTMLView: View {
    let html: String
    @State private var height: CGFloat = 200

    var body: some View {
        EmailHTMLView(html: html, height: $height)
            .frame(height: height)
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

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private var wrappedHTML: String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src * data: blob:; style-src 'unsafe-inline'; font-src *;">
        <style>
            * { box-sizing: border-box; }
            html, body { margin: 0; padding: 0; overflow-x: hidden; }
            body {
                font-family: -apple-system, system-ui, sans-serif;
                font-size: 15px; line-height: 1.55;
                color: #e0e0e0; background: transparent;
                word-wrap: break-word; overflow-wrap: break-word;
            }
            @media (prefers-color-scheme: light) { body { color: #1a1a1a; } }
            a { color: #5B9FFF; }
            img { max-width: 100% !important; height: auto !important; }
            pre, code { overflow-x: auto; max-width: 100%; white-space: pre-wrap; }
            blockquote { border-left: 2px solid #555; margin: 8px 0; padding-left: 12px; color: #888; }
            table { max-width: 100%; display: block; overflow-x: auto; }
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

        init(_ parent: EmailHTMLView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            measureHeight(in: webView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak webView, weak self] in
                guard let webView, let self else { return }
                self.measureHeight(in: webView)
            }
        }

        private func measureHeight(in webView: WKWebView) {
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { [weak self] result, _ in
                guard let self else { return }
                let h: CGFloat
                if let v = result as? CGFloat { h = v }
                else if let v = result as? Double { h = CGFloat(v) }
                else if let v = result as? Int { h = CGFloat(v) }
                else { return }
                guard h > 0 else { return }
                DispatchQueue.main.async { self.parent.height = h }
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
