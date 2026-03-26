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

    private var emailService: EmailService { services.emailService }

    var body: some View {
        ZStack {
            AppTheme.backgroundTop.ignoresSafeArea()

            if isLoading {
                ProgressView()
            } else if let detail, !detail.messages.isEmpty {
                threadContent(detail)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(AppTheme.mutedText)
                    Text("Could not load thread")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.subtleText)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            detail = await emailService.loadThread(id: threadId)
            isLoading = false
            // Mark as read when opened
            Task { await emailService.markAsRead(ids: [threadId]) }
        }
        .sheet(isPresented: $showCompose) {
            if let lastMessage = detail?.messages.last {
                EmailComposeView(
                    replyTo: lastMessage,
                    threadId: threadId
                )
            }
        }
    }

    // MARK: - Thread Content

    private func threadContent(_ detail: EmailThreadDetail) -> some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Text(detail.messages.first?.subject ?? "")
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                Button {
                    Task { await emailService.archiveThreads(ids: [threadId]) }
                    dismiss()
                } label: {
                    Image(systemName: "archivebox")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Button {
                    Task { await emailService.deleteThreads(ids: [threadId]) }
                    dismiss()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.danger)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().foregroundStyle(AppTheme.divider)

            // Messages
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(detail.messages) { message in
                        MessageBubble(message: message)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, 80)
            }

            // Reply bar
            replyBar
        }
    }

    private var replyBar: some View {
        VStack(spacing: 0) {
            Divider().foregroundStyle(AppTheme.divider)
            HStack(spacing: 12) {
                Button {
                    showCompose = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrowshape.turn.up.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Reply")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: EmailMessage

    @State private var isExpanded = true

    private var senderInitials: String {
        let parts = message.from.name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(message.from.name.prefix(2)).uppercased()
    }

    private var avatarColor: Color {
        let colors: [Color] = [
            .blue, .purple, .orange, .pink, .teal, .indigo, .mint, .cyan, .brown, .green
        ]
        let hash = abs(message.from.name.hashValue)
        return colors[hash % colors.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Sender header
            HStack(spacing: 10) {
                Text(senderInitials)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(avatarColor, in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(message.from.name)
                        .font(.system(size: 14, weight: .semibold))
                    Text(message.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppTheme.mutedText)
                }

                Spacer()

                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.mutedText)
                }
                .buttonStyle(.plain)
            }

            // Body — use WKWebView for HTML content
            if isExpanded {
                if !message.body.isEmpty {
                    EmailHTMLView(html: message.body)
                        .frame(minHeight: 100, maxHeight: 600)
                } else if let plain = message.plainText, !plain.isEmpty {
                    Text(plain)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.primary)
                } else {
                    Text("No content")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AppTheme.mutedText)
                        .italic()
                }
            }
        }
        .padding(14)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }
}

// MARK: - HTML WebView

/// Renders HTML email body using WKWebView, sized to content height.
struct EmailHTMLView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.dataDetectorTypes = [.link, .phoneNumber]

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Wrap HTML with basic styling for dark mode support
        let wrapped = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
            body {
                font-family: -apple-system, system-ui, sans-serif;
                font-size: 14px;
                line-height: 1.5;
                color: #e0e0e0;
                background: transparent;
                margin: 0;
                padding: 0;
                word-wrap: break-word;
                overflow-wrap: break-word;
            }
            @media (prefers-color-scheme: light) {
                body { color: #1a1a1a; }
            }
            a { color: #5B9FFF; }
            img { max-width: 100%; height: auto; }
            pre, code { overflow-x: auto; max-width: 100%; }
            blockquote {
                border-left: 2px solid #444;
                margin: 8px 0;
                padding-left: 12px;
                color: #999;
            }
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
            // Open links in Safari, don't navigate within the webview
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                await UIApplication.shared.open(url)
                return .cancel
            }
            return .allow
        }
    }
}
