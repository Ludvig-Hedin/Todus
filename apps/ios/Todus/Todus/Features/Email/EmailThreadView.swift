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
    /// Populated from `brain.generateSummary` — nil if the thread hasn't been vectorized yet.
    @State private var aiSummary: String? = nil
    /// Guards against accidental delete — trash is the only destructive action in the header.
    @State private var showDeleteConfirmation = false

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
            async let summary = fetchAISummary(threadId: threadId)
            aiSummary = await summary
            await markReadTask
        }
        .sheet(isPresented: $showCompose) {
            if let lastMessage = detail?.messages.last {
                EmailComposeView(replyTo: lastMessage, threadId: threadId)
            }
        }
    }

    // MARK: - AI Summary

    private func fetchAISummary(threadId: String) async -> String? {
        struct Input: Encodable { let threadId: String }
        struct ResponseData: Decodable { let short: String? }
        struct Response: Decodable { let data: ResponseData? }
        let response: Response? = try? await services.apiClient.trpcQuery(
            "brain.generateSummary", input: Input(threadId: threadId)
        )
        let text = response?.data?.short
        return (text?.isEmpty == false) ? text : nil
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
                // AI summary — only shown when the brain has indexed this thread
                if let summary = aiSummary {
                    AISummaryCard(summary: summary)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                }

                ForEach(Array(detail.messages.enumerated()), id: \.element.id) { index, message in
                    MessageBubble(message: message)
                        .padding(.horizontal, 16)
                        .padding(.top, index == 0 && aiSummary == nil ? 16 : 8)
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

// MARK: - AI Summary Card

private struct AISummaryCard: View {
    let summary: String
    // Expanded by default — the summary is a key feature and only shown when data exists,
    // so hiding it behind a tap would mean most users never see it.
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.purple)
                    Text("AI Summary")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.mutedText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(summary)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .background(Color.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: EmailMessage
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
