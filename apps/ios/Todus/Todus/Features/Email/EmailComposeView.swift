import SwiftUI
import SwiftData

/// Email compose sheet — supports new email and reply.
struct EmailComposeView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]

    @State private var draft: EmailDraft
    @State private var bodyMentions: [RichInputMentionRef] = []
    @State private var eventMentions: [RichInputMentionRef] = []
    @State private var showSendError = false
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
                        RichComposerInput(
                            text: $draft.body,
                            mentions: $bodyMentions,
                            placeholder: "Write your message",
                            surface: .emailCompose,
                            mentionOptions: mentionOptions,
                            isFocused: focusedField == .body,
                            onCommand: handleBodyCommand
                        )
                            .frame(minHeight: 300)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
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
                            if success {
                                dismiss()
                            } else {
                                showSendError = true
                            }
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
            // Alert shown when email send fails — gives the user feedback instead of silently failing
            .alert("Failed to send", isPresented: $showSendError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(emailService.errorMessage ?? "Please check your connection and try again.")
            }
            .navigationTitle(draft.replyToThreadId != nil ? "Reply" : "New Email")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadEventMentions()
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

    private var mentionOptions: [RichInputMentionRef] {
        let taskMentions = allTasks.prefix(10).map { task in
            RichInputMentionRef(
                id: task.id.uuidString,
                kind: .task,
                title: task.title,
                subtitle: task.dueDate.map { "\($0.formatted(date: .abbreviated, time: .shortened))" },
                displayText: task.title,
                accessibilityLabel: "Task \(task.title)"
            )
        }

        let threadMentions = services.emailService.threads.prefix(10).map { thread in
            RichInputMentionRef(
                id: thread.id,
                kind: .thread,
                title: thread.subject,
                subtitle: thread.from.email,
                displayText: thread.subject,
                accessibilityLabel: "Email thread \(thread.subject)"
            )
        }

        let peopleMentions = Dictionary(grouping: services.emailService.threads.map(\.from), by: \.email)
            .compactMap { _, senders in senders.first }
            .sorted {
                let lhsName = $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let rhsName = $1.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let lhsPrimaryKey = lhsName.isEmpty ? $0.email.lowercased() : lhsName.lowercased()
                let rhsPrimaryKey = rhsName.isEmpty ? $1.email.lowercased() : rhsName.lowercased()

                if lhsPrimaryKey == rhsPrimaryKey {
                    return $0.email.lowercased() < $1.email.lowercased()
                }

                return lhsPrimaryKey < rhsPrimaryKey
            }
            .prefix(10)
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

    private func handleBodyCommand(_ action: RichInputCommandAction) {
        guard case .signature = action, let signature = services.activeSignature else { return }
        if !draft.body.contains(signature.body) {
            if !draft.body.isEmpty, !draft.body.hasSuffix("\n") {
                draft.body.append("\n")
            }
            draft.body.append(signature.body)
        }
    }

    private func loadEventMentions() {
        Task {
            let start = Date()
            let end = Calendar.current.date(byAdding: .day, value: 30, to: start) ?? start
            let events = await services.calendarService.events(from: start, to: end)
            let mentions = events.prefix(10).map { event in
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
}
