import SwiftUI
import SwiftData
import PhotosUI

/// Email compose sheet — supports new email and reply.
struct EmailComposeView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]

    @State private var draft: EmailDraft
    @State private var bodyMentions: [RichInputMentionRef] = []
    @State private var eventMentions: [RichInputMentionRef] = []
    @State private var showSendError = false
    @State private var showPhotoLoadError = false
    /// Controls visibility of CC/BCC fields — toggled by the chevron in the To row
    @State private var showCcBcc = false
    /// Controls the AI draft assistant sheet
    @State private var showAIDraft = false
    /// Selected photo item from the formatting toolbar image picker
    @State private var selectedPhoto: PhotosPickerItem?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case to, cc, bcc, subject, body
    }

    private var emailService: EmailService { services.emailService }
    private var connectionsService: ConnectionsService { services.connectionsService }

    // AI gradient matching the app's sparkles icon
    private var aiGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0, green: 0xAA/255.0, blue: 0xF5/255.0), location: 0.087),
                .init(color: Color(red: 0xEF/255.0, green: 0, blue: 0xC2/255.0), location: 0.269),
                .init(color: Color(red: 1, green: 0, blue: 0x38/255.0), location: 0.580),
                .init(color: Color(red: 0xF9/255.0, green: 0x9F/255.0, blue: 0), location: 0.913),
            ],
            startPoint: UnitPoint(x: 0.25, y: 0),
            endPoint: UnitPoint(x: 0.75, y: 1)
        )
    }

    /// Create a new email compose
    init() {
        _draft = State(initialValue: EmailDraft())
    }

    /// Create a reply compose
    init(replyTo message: EmailMessage, threadId: String, body: String? = nil) {
        let replyDraft = EmailDraft(
            to: [message.from.email],
            subject: message.subject.hasPrefix("Re:") ? message.subject : "Re: \(message.subject)",
            body: body ?? "",
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
                        // From field — shows the active sending account; picker when multiple accounts exist
                        fromRow

                        Divider().foregroundStyle(AppTheme.divider)

                        // To field with CC/BCC disclosure chevron
                        toRow

                        // CC and BCC rows — revealed by the chevron disclosure
                        if showCcBcc {
                            Divider().foregroundStyle(AppTheme.divider)
                            ccRow
                            Divider().foregroundStyle(AppTheme.divider)
                            bccRow
                        }

                        Divider().foregroundStyle(AppTheme.divider)

                        // Subject field
                        subjectRow

                        Divider().foregroundStyle(AppTheme.divider)

                        // Formatting toolbar — sticky row of format actions above the body area
                        formattingToolbar

                        Divider().foregroundStyle(AppTheme.divider)

                        // Body — tappable across the full minHeight area, text anchored to top-left
                        bodyArea
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 16, weight: .medium))
                }
                // AI draft button — opens the AI drafting assistant with current compose context
                ToolbarItem(placement: .principal) {
                    Button {
                        showAIDraft = true
                    } label: {
                        Image(systemName: "lasso.badge.sparkles")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(aiGradient)
                    }
                    .buttonStyle(.plain)
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
            .alert("Could not add image", isPresented: $showPhotoLoadError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The image could not be loaded. Try choosing another photo.")
            }
            .navigationTitle(draft.replyToThreadId != nil ? "Reply" : "New Email")
            .navigationBarTitleDisplayMode(.inline)
            // AI draft assistant — compact sheet that streams a draft into the body
            .sheet(isPresented: $showAIDraft) {
                EmailAIDraftSheet(
                    to: draft.to,
                    subject: draft.subject,
                    currentBody: draft.body,
                    onInsert: { generated, mode in
                        switch mode {
                        case .replace:
                            draft.body = generated
                        case .append:
                            if !draft.body.isEmpty, !draft.body.hasSuffix("\n") {
                                draft.body.append("\n")
                            }
                            draft.body.append(generated)
                        }
                        focusedField = .body
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(AppTheme.backgroundTop)
                .preferredColorScheme(services.appearancePreference.colorScheme)
            }
            .onAppear {
                loadEventMentions()
                // Pre-select default from connection
                if draft.fromConnectionId == nil {
                    draft.fromConnectionId = connectionsService.connections.first?.id
                }
                // Focus the appropriate field on open
                if draft.to.first?.isEmpty ?? true {
                    focusedField = .to
                } else if draft.subject.isEmpty {
                    focusedField = .subject
                } else {
                    focusedField = .body
                }
            }
            .onChange(of: selectedPhoto) { _, newItem in
                guard let newItem else { return }
                Task {
                    do {
                        guard let data = try await newItem.loadTransferable(type: Data.self) else {
                            await MainActor.run {
                                showPhotoLoadError = true
                                selectedPhoto = nil
                            }
                            AppLogger.shared.log("[EmailCompose] PhotosPicker returned no image data")
                            return
                        }
                        guard let image = UIImage(data: data) else {
                            await MainActor.run {
                                showPhotoLoadError = true
                                selectedPhoto = nil
                            }
                            AppLogger.shared.log("[EmailCompose] PhotosPicker image decode failed (nil UIImage)")
                            return
                        }
                        // Insert image placeholder tag into body; the email service currently
                        // sends plain text so this serves as a visual cue only for now.
                        let tag = "\n[image: \(image.size.width.rounded())×\(image.size.height.rounded())]\n"
                        await MainActor.run {
                            draft.body += tag
                            selectedPhoto = nil
                        }
                    } catch {
                        await MainActor.run {
                            showPhotoLoadError = true
                            selectedPhoto = nil
                        }
                        AppLogger.shared.log("[EmailCompose] PhotosPicker loadTransferable failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    // MARK: - Formatting Toolbar

    /// Horizontal row of format buttons — appends markdown syntax to the body.
    /// Positioned between Subject and the body area so it's always accessible.
    private var formattingToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                formatButton(icon: "bold", label: "Bold") {
                    insertFormat("**", closing: "**", placeholder: "bold text")
                }
                formatButton(icon: "italic", label: "Italic") {
                    insertFormat("_", closing: "_", placeholder: "italic text")
                }
                formatDivider()
                formatButton(icon: "textformat.size.larger", label: "H1") {
                    insertLinePrefix("# ")
                }
                formatButton(icon: "textformat.size", label: "H2") {
                    insertLinePrefix("## ")
                }
                formatDivider()
                formatButton(icon: "list.bullet", label: "Bullet") {
                    insertLinePrefix("• ")
                }
                formatButton(icon: "list.number", label: "Numbered") {
                    insertLinePrefix("1. ")
                }
                formatButton(icon: "checklist", label: "Checklist") {
                    insertLinePrefix("☐ ")
                }
                formatDivider()
                formatButton(icon: "quote.opening", label: "Quote") {
                    insertLinePrefix("> ")
                }
                formatButton(icon: "minus", label: "Divider") {
                    insertLinePrefix("---")
                }
                formatDivider()
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "photo")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.mutedText)
                        .frame(width: 36, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add image")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(AppTheme.backgroundTop)
    }

    private func formatButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
                .frame(width: 36, height: 32)
                .background(Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func formatDivider() -> some View {
        Rectangle()
            .fill(AppTheme.divider)
            .frame(width: 1, height: 18)
            .padding(.horizontal, 4)
    }

    // MARK: - Format Insert Helpers

    /// Inserts an inline markdown wrapper (e.g. **bold text**) at the end of the body.
    /// The placeholder sits between the delimiters so the user can select-and-type over it.
    private func insertFormat(_ opening: String, closing: String, placeholder: String) {
        let newline = draft.body.isEmpty || draft.body.hasSuffix("\n") ? "" : "\n"
        draft.body += "\(newline)\(opening)\(placeholder)\(closing)"
        focusedField = .body
    }

    /// Inserts a block prefix (heading, bullet, etc.) at the end of the body on a new line.
    private func insertLinePrefix(_ prefix: String) {
        let newline = draft.body.isEmpty || draft.body.hasSuffix("\n") ? "" : "\n"
        draft.body += "\(newline)\(prefix)"
        focusedField = .body
    }

    // MARK: - Field Rows

    /// From row: shows the current sending account; tap to switch if multiple accounts
    @ViewBuilder
    private var fromRow: some View {
        let connections = connectionsService.connections
        HStack(spacing: 8) {
            Text("From")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
                .frame(width: 60, alignment: .trailing)

            if connections.count > 1 {
                // Multi-account: show a menu picker
                Menu {
                    ForEach(connections) { connection in
                        Button {
                            draft.fromConnectionId = connection.id
                        } label: {
                            HStack {
                                Text(connection.email)
                                if draft.fromConnectionId == connection.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedFromEmail(connections: connections))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.mutedText)
                        Spacer()
                    }
                }
            } else {
                // Single account: read-only display
                Text(selectedFromEmail(connections: connections))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// To row with a disclosure chevron that reveals CC/BCC
    private var toRow: some View {
        HStack(spacing: 8) {
            Text("To")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
                .frame(width: 60, alignment: .trailing)

            // Use prompt: to control placeholder color — avoids the default blue tint
            TextField(
                text: Binding(
                    get: { draft.to.first ?? "" },
                    set: { draft.to = $0.isEmpty ? [] : [$0] }
                ),
                prompt: Text("recipient@example.com").foregroundColor(.secondary)
            ) {
                EmptyView()
            }
            .font(.system(size: 15, weight: .medium))
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .to)

            // Chevron disclosure button for CC/BCC
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCcBcc.toggle()
                }
            } label: {
                Image(systemName: showCcBcc ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var ccRow: some View {
        HStack(spacing: 8) {
            Text("Cc")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
                .frame(width: 60, alignment: .trailing)

            TextField(
                text: Binding(
                    get: { draft.cc.first ?? "" },
                    set: { draft.cc = $0.isEmpty ? [] : [$0] }
                ),
                prompt: Text("cc@example.com").foregroundColor(.secondary)
            ) {
                EmptyView()
            }
            .font(.system(size: 15, weight: .medium))
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .cc)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var bccRow: some View {
        HStack(spacing: 8) {
            Text("Bcc")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
                .frame(width: 60, alignment: .trailing)

            TextField(
                text: Binding(
                    get: { draft.bcc.first ?? "" },
                    set: { draft.bcc = $0.isEmpty ? [] : [$0] }
                ),
                prompt: Text("bcc@example.com").foregroundColor(.secondary)
            ) {
                EmptyView()
            }
            .font(.system(size: 15, weight: .medium))
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .bcc)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var subjectRow: some View {
        HStack(spacing: 8) {
            Text("Subject")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
                .frame(width: 60, alignment: .trailing)

            TextField(
                text: $draft.subject,
                prompt: Text("Subject").foregroundColor(.secondary)
            ) {
                EmptyView()
            }
            .font(.system(size: 15, weight: .medium))
            .focused($focusedField, equals: .subject)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Body area — the full minHeight region is tappable to focus the text input.
    /// Content is anchored top-left via ZStack alignment rather than defaulting to center.
    private var bodyArea: some View {
        ZStack(alignment: .topLeading) {
            // Transparent tap target covers the full minimum area so tapping
            // anywhere below the text still focuses the body field
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 300)
                .contentShape(Rectangle())
                .onTapGesture { focusedField = .body }

            RichComposerInput(
                text: $draft.body,
                mentions: $bodyMentions,
                placeholder: "Write your message",
                surface: .emailCompose,
                mentionOptions: mentionOptions,
                isFocused: focusedField == .body,
                onCommand: handleBodyCommand
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    // MARK: - Helpers

    private func selectedFromEmail(connections: [ConnectionAccount]) -> String {
        if let id = draft.fromConnectionId,
           let match = connections.first(where: { $0.id == id }) {
            return match.email
        }
        return connections.first?.email ?? ""
    }

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
