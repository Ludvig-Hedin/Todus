import SwiftUI

/// Email compose view for new emails and replies.
/// Desktop-optimized: wider fields, keyboard shortcuts.
struct MacEmailComposeView: View {
    @Environment(MacAppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var draft: EmailDraft
    @State private var showSendError = false
    private let navigationTitle: String

    /// New email
    init() {
        _draft = State(initialValue: EmailDraft())
        navigationTitle = "New Email"
    }

    /// Reply to a message
    init(replyTo message: EmailMessage, threadId: String, body: String = "") {
        var d = EmailDraft()
        d.to = [message.from.email]
        d.subject = message.subject.hasPrefix("Re:") ? message.subject : "Re: \(message.subject)"
        d.body = body
        d.replyToThreadId = threadId
        d.replyToMessageId = message.id
        _draft = State(initialValue: d)
        navigationTitle = "Reply"
    }

    /// Pre-filled body
    init(body: String) {
        var d = EmailDraft()
        d.body = body
        _draft = State(initialValue: d)
        navigationTitle = "New Email"
    }

    /// Optionally pre-filled from seed body (empty string = new email)
    init(seedBody: String) {
        if seedBody.isEmpty {
            _draft = State(initialValue: EmailDraft())
        } else {
            var d = EmailDraft()
            d.body = seedBody
            _draft = State(initialValue: d)
        }
        navigationTitle = "New Email"
    }

    private var canSend: Bool {
        let toAddress = draft.to.first ?? ""
        return !toAddress.isEmpty && toAddress.contains("@") && !draft.subject.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
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
                            dismiss()
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
                    TextField("recipient@example.com", text: Binding(
                        get: { draft.to.first ?? "" },
                        set: { draft.to = [$0] }
                    ))
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
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
