import SwiftUI

/// Email compose view for new emails and replies.
/// Desktop-optimized: wider fields, keyboard shortcuts.
struct MacEmailComposeView: View {
    @Environment(MacAppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var draft: EmailDraft
    @State private var showSendError = false
    private let navigationTitle: String
    /// Optional close handler — supplied when the view is rendered as an inline
    /// side panel so it can collapse the panel instead of dismissing a sheet.
    private let onCloseHandler: (() -> Void)?

    private func close() {
        if let onCloseHandler {
            onCloseHandler()
        } else {
            dismiss()
        }
    }

    /// New email
    init(onClose: (() -> Void)? = nil) {
        _draft = State(initialValue: EmailDraft())
        navigationTitle = "New Email"
        onCloseHandler = onClose
    }

    /// Reply to a message
    init(replyTo message: EmailMessage, threadId: String, body: String = "", onClose: (() -> Void)? = nil) {
        var d = EmailDraft()
        d.to = [message.from.email]
        d.subject = message.subject.hasPrefix("Re:") ? message.subject : "Re: \(message.subject)"
        d.body = body
        d.replyToThreadId = threadId
        d.replyToMessageId = message.id
        _draft = State(initialValue: d)
        navigationTitle = "Reply"
        onCloseHandler = onClose
    }

    /// Reply all — To includes sender + original To; Cc holds other parties from Cc.
    init(replyAllTo message: EmailMessage, threadId: String, body: String = "", onClose: (() -> Void)? = nil) {
        var d = EmailDraft()
        var toEmails: [String] = []
        func pushTo(_ raw: String) {
            let e = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !e.isEmpty else { return }
            if toEmails.contains(where: { $0.caseInsensitiveCompare(e) == .orderedSame }) { return }
            toEmails.append(e)
        }
        pushTo(message.from.email)
        for r in message.to { pushTo(r.email) }
        d.to = toEmails
        var ccList: [String] = []
        if let extras = message.cc {
            for r in extras {
                let x = r.email.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !x.isEmpty else { continue }
                if toEmails.contains(where: { $0.caseInsensitiveCompare(x) == .orderedSame }) { continue }
                if ccList.contains(where: { $0.caseInsensitiveCompare(x) == .orderedSame }) { continue }
                ccList.append(x)
            }
        }
        d.cc = ccList
        if !body.isEmpty { d.body = body }
        d.subject = message.subject.hasPrefix("Re:") ? message.subject : "Re: \(message.subject)"
        d.replyToThreadId = threadId
        d.replyToMessageId = message.id
        _draft = State(initialValue: d)
        navigationTitle = "Reply All"
        onCloseHandler = onClose
    }

    /// Forward — new subject/body; marks draft as forward for the mail API.
    init(forwarding message: EmailMessage, onClose: (() -> Void)? = nil) {
        var d = EmailDraft()
        d.subject = message.subject.hasPrefix("Fwd:") ? message.subject : "Fwd: \(message.subject)"
        let plain = message.plainText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let snippet = plain.isEmpty ? Self.plainTextFromHTML(message.body) : plain
        d.body =
            "\n\n---------- Forwarded message ----------\nFrom: \(message.from.name) <\(message.from.email)>\nSubject: \(message.subject)\n\n\(snippet)\n"
        d.isForward = true
        _draft = State(initialValue: d)
        navigationTitle = "Forward"
        onCloseHandler = onClose
    }

    private static func plainTextFromHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Pre-filled body
    init(body: String, onClose: (() -> Void)? = nil) {
        var d = EmailDraft()
        d.body = body
        _draft = State(initialValue: d)
        navigationTitle = "New Email"
        onCloseHandler = onClose
    }

    /// Optionally pre-filled from seed body (empty string = new email)
    init(seedBody: String, onClose: (() -> Void)? = nil) {
        var d = EmailDraft()
        if !seedBody.isEmpty { d.body = seedBody }
        _draft = State(initialValue: d)
        navigationTitle = "New Email"
        onCloseHandler = onClose
    }

    /// Pre-filled from a mailto: URL — recipient, subject, and body are all optional.
    init(to: String, subject: String, body: String, onClose: (() -> Void)? = nil) {
        var d = EmailDraft()
        if !to.isEmpty { d.to = [to] }
        if !subject.isEmpty { d.subject = subject }
        if !body.isEmpty { d.body = body }
        _draft = State(initialValue: d)
        navigationTitle = "New Email"
        onCloseHandler = onClose
    }

    private var canSend: Bool {
        let toList = draft.to.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !toList.isEmpty, toList.allSatisfy({ $0.contains("@") }), !draft.subject.isEmpty else {
            return false
        }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { close() }
                    .font(.system(size: 13))
                    .keyboardShortcut(.cancelAction)
                    .macClickablePointer()

                Spacer()

                Text(navigationTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)

                Spacer()

                Button {
                    Task {
                        let success = await services.emailService.sendEmail(draft)
                        if success {
                            close()
                        } else {
                            showSendError = true
                        }
                    }
                } label: {
                    if services.emailService.isSending {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        HStack(spacing: MacTheme.spacing4) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Send")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                }
                .disabled(!canSend || services.emailService.isSending)
                .macClickablePointer()
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(MacTheme.spacing16)

            Divider().opacity(0.3)

            // Fields
            VStack(spacing: 0) {
                fieldRow(label: "To") {
                    TextField("name@email.com", text: Binding(
                        get: { draft.to.joined(separator: ", ") },
                        set: { raw in
                            draft.to = raw
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                        }
                    ))
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                }

                if !draft.cc.isEmpty || navigationTitle == "Reply All" {
                    Divider().opacity(0.15).padding(.horizontal, MacTheme.spacing16)
                    fieldRow(label: "Cc") {
                        TextField("name@email.com", text: Binding(
                            get: { draft.cc.joined(separator: ", ") },
                            set: { raw in
                                draft.cc = raw
                                    .split(separator: ",")
                                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                    .filter { !$0.isEmpty }
                            }
                        ))
                        .font(.system(size: 13))
                        .textFieldStyle(.plain)
                    }
                }

                Divider().opacity(0.15).padding(.horizontal, MacTheme.spacing16)

                fieldRow(label: "Subject") {
                    TextField("Subject", text: $draft.subject)
                        .font(.system(size: 13))
                        .textFieldStyle(.plain)
                }

                Divider().opacity(0.15).padding(.horizontal, MacTheme.spacing16)

                // Body
                TextEditor(text: $draft.body)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(MacTheme.spacing16)
                    .frame(maxHeight: .infinity)
            }
        }
        .alert("Failed to send", isPresented: $showSendError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(services.emailService.errorMessage ?? "Please check your connection and try again.")
        }
    }

    private func fieldRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: MacTheme.spacing8) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MacTheme.mutedText)
                .frame(width: 50, alignment: .trailing)
            content()
        }
        .padding(.horizontal, MacTheme.spacing16)
        .padding(.vertical, MacTheme.spacing8)
    }
}
