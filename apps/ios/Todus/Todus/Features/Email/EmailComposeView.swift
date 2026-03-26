import SwiftUI

/// Email compose sheet — supports new email and reply.
struct EmailComposeView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var draft: EmailDraft
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case to, subject, body
    }

    private var emailService: EmailService { services.emailService }

    /// Create a new email compose
    init() {
        _draft = State(initialValue: EmailDraft())
    }

    /// Create a reply compose
    init(replyTo message: EmailMessage, threadId: String) {
        let replyDraft = EmailDraft(
            to: [message.from.email],
            subject: message.subject.hasPrefix("Re:") ? message.subject : "Re: \(message.subject)",
            replyToThreadId: threadId,
            replyToMessageId: message.id
        )
        _draft = State(initialValue: replyDraft)
    }

    /// Create compose with pre-filled body (from CreateSheet "Email" type)
    init(body: String) {
        var d = EmailDraft()
        d.body = body
        _draft = State(initialValue: d)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundTop.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // To field
                        fieldRow(label: "To") {
                            TextField("recipient@example.com", text: Binding(
                                get: { draft.to.first ?? "" },
                                set: { draft.to = [$0] }
                            ))
                            .font(.system(size: 15, weight: .medium))
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .to)
                        }

                        Divider().foregroundStyle(AppTheme.divider)

                        // Subject field
                        fieldRow(label: "Subject") {
                            TextField("Subject", text: $draft.subject)
                                .font(.system(size: 15, weight: .medium))
                                .focused($focusedField, equals: .subject)
                        }

                        Divider().foregroundStyle(AppTheme.divider)

                        // Body
                        TextEditor(text: $draft.body)
                            .font(.system(size: 15, weight: .regular))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 300)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .focused($focusedField, equals: .body)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 16, weight: .medium))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            let success = await emailService.sendEmail(draft)
                            if success { dismiss() }
                        }
                    } label: {
                        if emailService.isSending {
                            ProgressView()
                                .tint(.primary)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .disabled(!canSend || emailService.isSending)
                }
            }
            .navigationTitle(draft.replyToThreadId != nil ? "Reply" : "New Email")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Focus the appropriate field
                if draft.to.first?.isEmpty ?? true {
                    focusedField = .to
                } else if draft.subject.isEmpty {
                    focusedField = .subject
                } else {
                    focusedField = .body
                }
            }
        }
    }

    // MARK: - Helpers

    private var canSend: Bool {
        let toAddress = draft.to.first ?? ""
        return !toAddress.isEmpty && toAddress.contains("@") && !draft.subject.isEmpty
    }

    private func fieldRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
                .frame(width: 60, alignment: .trailing)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
