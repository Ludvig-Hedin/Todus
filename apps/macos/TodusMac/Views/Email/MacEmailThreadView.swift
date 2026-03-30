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
        .sheet(isPresented: $showCompose) {
            if let lastMessage = detail?.messages.last {
                MacEmailComposeView(replyTo: lastMessage, threadId: threadId)
                    .frame(minWidth: 520, minHeight: 380)
            }
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
                    .background(MacTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius))
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
        detail = await services.emailService.loadThread(id: threadId)
        if detail == nil {
            errorMessage = "Could not load thread."
        }
        isLoading = false

        // Mark as read
        Task { await services.emailService.markAsRead(ids: [threadId]) }
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
