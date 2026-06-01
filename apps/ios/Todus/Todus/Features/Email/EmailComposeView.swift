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
    /// Attachment filenames carried over from CreateSheet. Surfaced in the
    /// compose UI as chips. The send pipeline does not yet upload binary
    /// attachments, but keeping them visible avoids silent data loss and lets
    /// the user reference them in the body.
    @State private var seededAttachmentNames: [String] = []
    @State private var pendingAttachmentRemovals: Set<String> = []
    @State private var showSendError = false
    /// Monotonic counter incremented on successful sends so the form's
    /// `.sensoryFeedback(.success, trigger:)` fires a haptic before dismissal.
    @State private var sendSuccessTick: Int = 0
    /// Controls visibility of CC/BCC fields — toggled by the chevron in the To row
    @State private var showCcBcc = false
    /// Controls the AI draft assistant sheet
    @State private var showAIDraft = false
    /// Debounce task for draft autosave — re-armed on every field change.
    @State private var autosaveTask: Task<Void, Never>?
    /// Stable identifier for this compose draft. Replies key off the thread/message,
    /// new emails get a fresh UUID so several windows of the same composition don't collide.
    @State private var draftStorageKey: String
    @FocusState private var focusedField: Field?
    @Environment(\.scenePhase) private var scenePhase

    /// UserDefaults key prefix for autosaved drafts. Key suffix is the draft ID
    /// (replyToThreadId for replies, a fresh UUID for new emails).
    private static let autosaveKeyPrefix = "email_compose_autosave_v1."

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

    /// Create a reply compose
    /// - Parameters:
    ///   - replyAll: When true, prefills CC with the original message's `to + cc`,
    ///     excluding the sender (already in To) and any addresses owned by the
    ///     current user (`ownedAddresses`). Pass an empty set to skip self-filtering.
    init(
        replyTo message: EmailMessage,
        threadId: String,
        body: String? = nil,
        replyAll: Bool = false,
        ownedAddresses: Set<String> = []
    ) {
        var ccAddresses: [String] = []
        if replyAll {
            let normalizedOwned = Set(ownedAddresses.map { $0.lowercased() })
            let senderLower = message.from.email.lowercased()
            var seen = Set<String>([senderLower])
            seen.formUnion(normalizedOwned)
            for addr in message.to + (message.cc ?? []) {
                let lower = addr.email.lowercased()
                if seen.contains(lower) { continue }
                seen.insert(lower)
                ccAddresses.append(addr.email)
            }
        }
        let replyDraft = EmailDraft(
            to: [message.from.email],
            cc: ccAddresses,
            subject: message.subject.hasPrefix("Re:") ? message.subject : "Re: \(message.subject)",
            body: body ?? "",
            replyToThreadId: threadId,
            replyToMessageId: message.id
        )
        _draft = State(initialValue: replyDraft)
        // Reply-all expands the CC row by default so the user sees who'll be looped in.
        _showCcBcc = State(initialValue: !ccAddresses.isEmpty)
        // Reply drafts are keyed by thread only — reply and reply-all share the same
        // slot. The previous split (`reply.<id>` vs `replyAll.<id>`) orphaned drafts:
        // a user who started a reply, switched to reply-all, and re-opened the thread
        // would never see their original body again. Sharing the key means the most
        // recent autosave wins regardless of which entry-point was used.
        _draftStorageKey = State(initialValue: "compose.\(threadId)")
    }

    /// Create compose with pre-filled to, cc, bcc, subject, body, attachments, and/or sender (from CreateSheet)
    init(to: String? = nil, cc: String? = nil, bcc: String? = nil, subject: String? = nil, body: String? = nil, seededAttachments: [String] = [], fromConnectionId: String? = nil) {
        var d = EmailDraft()
        if let to, !to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            d.to = [to.trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        if let cc, !cc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            d.cc = [cc.trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        if let bcc, !bcc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            d.bcc = [bcc.trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        if let subject { d.subject = subject }
        if let body { d.body = body }
        // Pre-select the sender chosen in CreateSheet's From picker.
        if let fromConnectionId { d.fromConnectionId = fromConnectionId }
        _draft = State(initialValue: d)
        _seededAttachmentNames = State(initialValue: seededAttachments)
        // The autosaved "new email" slot must NOT be reused when the caller
        // pre-filled any field (e.g. "Email john@x.com" from a contact card).
        // Otherwise an abandoned subject/body from an earlier compose for a
        // completely different recipient resurfaces and the user can send the
        // wrong message without noticing.
        let calledWithSeed =
            to != nil || cc != nil || bcc != nil || subject != nil || body != nil
            || !seededAttachments.isEmpty || fromConnectionId != nil
        _draftStorageKey = State(
            initialValue: calledWithSeed ? "new.\(UUID().uuidString)" : Self.newComposeStorageKey
        )
    }

    /// Shared key for "new email" drafts so a single unsent draft is restored on reopen.
    /// (Only one new-compose draft is preserved at a time; replies use their own thread key.)
    private static let newComposeStorageKey = "new"

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                AppTheme.sheetBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // From field — shows the active sending account; picker when multiple accounts exist.
                        // Wrapped with the offline notice so we don't bust the ViewBuilder child limit.
                        Group {
                            // Inline offline notice — the system-level offline banner is hidden
                            // behind sheets, so without this the user sees no signal that Send is disabled.
                            if !services.networkMonitor.isConnected {
                                offlineNotice
                            }
                            // Hide the From row entirely when there's a single connected
                            // account. With one inbox the row is pure noise: the user has
                            // no choice to make and the address is implicit. The divider
                            // below also collapses so the form starts with the To row.
                            if connectionsService.connections.count > 1 {
                                fromRow
                                Divider().foregroundStyle(AppTheme.divider)
                            }
                        }

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

                        // Seeded attachments from CreateSheet — chip row so files
                        // captured in the universal create modal stay visible.
                        if !seededAttachmentNames.isEmpty {
                            attachmentChipsRow
                            Divider().foregroundStyle(AppTheme.divider)
                        }

                        // Body — tappable across the full minHeight area, text anchored to top-left
                        bodyArea
                    }
                }

                // Floating AI assistant — bottom-right, glass capsule, matches the
                // global AI FAB style elsewhere in the app. Was previously a tiny
                // gradient sparkle in the nav bar title slot, which was easy to miss
                // and easy to misread as a logo.
                aiFAB
                    .padding(.trailing, 18)
                    .padding(.bottom, 24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 16, weight: .medium))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            // Resolve the picked From connection to its email address
                            // so the backend routes the send through the correct
                            // mailbox (default behaviour when no picker selection).
                            let fromEmail = draft.fromConnectionId.flatMap { id in
                                connectionsService.connections.first { $0.id == id }?.email
                            }
                            let success = await emailService.sendEmail(draft, fromEmail: fromEmail)
                            if success {
                                deletePendingAttachments()
                                // Clear the autosaved draft once it's safely on the wire
                                clearAutosavedDraft()
                                // Bump a counter so the .sensoryFeedback modifier below
                                // fires its success haptic before we dismiss the sheet.
                                sendSuccessTick &+= 1
                                dismiss()
                            } else {
                                showSendError = true
                            }
                        }
                    } label: {
                        if emailService.isSending {
                            // Show "Sending…" alongside the spinner so the user has an
                            // unambiguous text cue instead of just a tiny spinner that
                            // can read as "stuck on Send tap".
                            HStack(spacing: 6) {
                                ButtonInlineProgressView(tint: .primary, side: AppTheme.Metrics.toolbarInlineSpinner)
                                Text("Sending…")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    // Disable Send while offline — the global offline banner is hidden
                    // behind this sheet, so we have to surface the state inline too.
                    .disabled(!canSend || emailService.isSending || !services.networkMonitor.isConnected)
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
            // AI assistant — opens the full AI chat sheet on top of the composer, with
            // the email context pre-seeded into the input. The user asks naturally
            // ("make it shorter", "rewrite friendlier", "draft a reply to this") and
            // copies/long-presses the AI's response back into the body. Replaces the
            // previous one-shot AIDraftSheet which routed through a broken endpoint.
            .sheet(isPresented: $showAIDraft) {
                AIChatView(
                    currentTab: .email,
                    initialPrompt: aiChatSeedPrompt
                )
                .appSheetBackground()
                .preferredColorScheme(services.appearancePreference.colorScheme)
            }
            .onAppear {
                loadEventMentions()
                // Restore any in-progress autosaved draft. Only overwrites empty fields so
                // we don't clobber explicitly-passed initializer values.
                restoreAutosavedDraft()
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
            // Autosave on every meaningful field change. Debounced 1s so rapid typing
            // doesn't thrash UserDefaults.
            .onChange(of: draft.to) { scheduleAutosave() }
            .onChange(of: draft.cc) { scheduleAutosave() }
            .onChange(of: draft.bcc) { scheduleAutosave() }
            .onChange(of: draft.subject) { scheduleAutosave() }
            .onChange(of: draft.body) { scheduleAutosave() }
            // Flush the pending debounce immediately when the app moves off-screen.
            // The 1s `Task.sleep` in scheduleAutosave is cancelled when the scene
            // suspends, so a typed-but-not-yet-saved draft would otherwise be lost
            // if the user backgrounds within 1s of typing.
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background || newPhase == .inactive {
                    autosaveTask?.cancel()
                    persistAutosaveSnapshot()
                }
            }
            .onDisappear {
                // Same safety net — if the sheet dismisses (programmatically or via
                // gesture) before the 1s debounce fires, commit the current snapshot
                // so the draft restores on the next compose open.
                autosaveTask?.cancel()
                persistAutosaveSnapshot()
            }
            // Tactile confirmation when a send succeeds. `sendSuccessTick` is
            // bumped right before dismissal so the haptic fires reliably even
            // though the sheet is about to tear down.
            .sensoryFeedback(.success, trigger: sendSuccessTick)
        }
    }

    // MARK: - AI FAB

    /// Floating AI button anchored to bottom-right. Same glass treatment and gradient
    /// sparkles as the global AI FAB in MainTabView so it reads as the same affordance.
    private var aiFAB: some View {
        Button {
            showAIDraft = true
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(aiGradient)
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .buttonStyle(FABButtonStyle())
        .fabGlass()
        .accessibilityLabel("Ask AI about this draft")
        // Block the AI draft action while a send is in flight so it can't be
        // tapped mid-send (the draft is about to leave the screen).
        .disabled(emailService.isSending)
    }

    /// Builds a context-aware prompt the AI chat starts pre-filled with. Reply drafts
    /// get a "draft a reply to <recipient> about <subject>" seed; brand-new emails get
    /// a "draft an email to <recipient> about <subject>" seed. The user can edit before
    /// sending — the field is just a starting point, not auto-submitted.
    private var aiChatSeedPrompt: String {
        let recipient = draft.to.first.flatMap { $0.isEmpty ? nil : $0 } ?? "the recipient"
        let subject = draft.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let subjectPhrase = subject.isEmpty ? "" : " about \"\(subject)\""
        let bodyTrim = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let isReply = draft.replyToThreadId != nil

        var lines: [String] = []
        if isReply {
            lines.append("Help me draft a reply to \(recipient)\(subjectPhrase).")
        } else {
            lines.append("Help me draft an email to \(recipient)\(subjectPhrase).")
        }
        if !bodyTrim.isEmpty {
            lines.append("")
            lines.append("Current draft:")
            lines.append(bodyTrim)
        }
        lines.append("")
        lines.append("Return just the email body — no preamble.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Formatting Toolbar

    /// Horizontal row of format buttons — appends markdown syntax to the body.
    /// Positioned between Subject and the body area so it's always accessible.
    /// Buttons are disabled when the body field is not focused — they only act on body
    /// content, so showing them as enabled while another field is focused is misleading.
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(AppTheme.sheetBackground)
        .disabled(focusedField != .body)
        .opacity(focusedField == .body ? 1.0 : 0.4)
    }

    /// Inline note shown above the From row when the device has no connection.
    /// Mirrors the global offline banner that's hidden behind this sheet.
    private var offlineNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 12, weight: .semibold))
            Text("You're offline — message will not send.")
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(AppTheme.subtleText)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.surfaceSecondary)
    }

    private func formatButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                // Was `AppTheme.mutedText` (= .secondary × 0.65 opacity), which was
                // nearly invisible against the light sheet background. `.secondary`
                // gives ~60% contrast — readable in both light and dark.
                .foregroundStyle(.secondary)
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

            // Use prompt: to control placeholder color — avoids the default blue tint.
            // Recipient string is tokenized on every change so users can paste
            // `a@b.com, c@d.com; e@f.com` and get three separate recipients on send.
            // TODO(bug-hunt): tokenizing in the Binding `set` on every keystroke eats the
            // separator while typing — `"a@b.com,"` tokenizes to `["a@b.com"]`, then `get`
            // re-joins to `"a@b.com"`, so the comma/semicolon vanishes and a 2nd recipient
            // can't be typed (paste still works). Fix: bind to a raw @State string per field
            // and tokenize on .onSubmit / before send, not on every change. Same for cc/bcc.
            TextField(
                text: Binding(
                    get: { draft.to.joined(separator: ", ") },
                    set: { draft.to = Self.tokenizeRecipients($0) }
                ),
                prompt: Text("Add recipients").foregroundColor(.secondary)
            ) {
                EmptyView()
            }
            .font(.system(size: 15, weight: .medium))
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .to)
            .submitLabel(.next)
            // Advance to CC if it's expanded, otherwise jump straight to subject.
            .onSubmit { focusedField = showCcBcc ? .cc : .subject }

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
            .accessibilityLabel(showCcBcc ? "Hide CC and BCC" : "Show CC and BCC")
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
                    get: { draft.cc.joined(separator: ", ") },
                    set: { draft.cc = Self.tokenizeRecipients($0) }
                ),
                // Plain placeholder text — an email-shaped placeholder ("cc@example.com")
                // gets auto-styled blue by iOS data detectors, making the empty field
                // look like it's prefilled with a tappable link in light mode.
                prompt: Text("Add Cc recipients").foregroundColor(.secondary)
            ) {
                EmptyView()
            }
            .font(.system(size: 15, weight: .medium))
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .cc)
            .submitLabel(.next)
            .onSubmit { focusedField = .bcc }
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
                    get: { draft.bcc.joined(separator: ", ") },
                    set: { draft.bcc = Self.tokenizeRecipients($0) }
                ),
                prompt: Text("Add Bcc recipients").foregroundColor(.secondary)
            ) {
                EmptyView()
            }
            .font(.system(size: 15, weight: .medium))
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .bcc)
            .submitLabel(.next)
            .onSubmit { focusedField = .subject }
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

    /// Horizontal scroll of seeded attachment chips. Tapping the X removes
    /// the chip from the draft immediately, but defers file deletion until send succeeds.
    private var attachmentChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(seededAttachmentNames, id: \.self) { filename in
                    HStack(spacing: 6) {
                        Image(systemName: AttachmentService.shared.isImageFile(filename) ? "photo" : "doc")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.mutedText)
                        Text(filename)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 160)
                        Button {
                            seededAttachmentNames.removeAll { $0 == filename }
                            pendingAttachmentRemovals.insert(filename)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.mutedText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove attachment \(filename)")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.surfaceSecondary, in: Capsule())
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
    }

    /// Body area — the full minHeight region is tappable to focus the text input.
    /// Content is anchored top-left via ZStack alignment rather than defaulting to center.
    ///
    /// `minHeight` is sized to the *visible* screen height (minus the form rows above
    /// and the keyboard) so the user can tap anywhere in the empty space below their
    /// last line of text to focus the body. Previously capped at 300pt, which meant
    /// tapping the lower half of the visible body area silently did nothing because
    /// it landed outside the tap target.
    private var bodyArea: some View {
        ZStack(alignment: .topLeading) {
            // Transparent tap target — fills the remaining visible space so the user
            // can tap anywhere in the body region to focus the input.
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 700)
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

    /// Splits a recipient field's raw string into individual addresses. Accepts the
    /// formats users actually type / paste:
    ///   • `a@b.com, c@d.com, e@f.com`     (commas)
    ///   • `a@b.com; c@d.com; e@f.com`     (semicolons — common from desktop clients)
    ///   • `a@b.com c@d.com`               (whitespace-separated)
    ///   • `"Jane Doe" <jane@x.com>`       (display-name angle form — stripped to email)
    /// Empty tokens are dropped, surrounding whitespace trimmed. The result is
    /// duplicate-free preserving first-seen order, so `a@b.com, a@b.com` becomes
    /// a single recipient.
    static func tokenizeRecipients(_ raw: String) -> [String] {
        guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let separators = CharacterSet(charactersIn: ",;\n\t")
        var seen = Set<String>()
        var result: [String] = []
        for piece in raw.components(separatedBy: separators) {
            // Pull email out of "Name <addr@x>" display-name form.
            var token = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            if let lt = token.firstIndex(of: "<"), let gt = token.firstIndex(of: ">"), lt < gt {
                token = String(token[token.index(after: lt)..<gt])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !token.isEmpty else { continue }
            let key = token.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(token)
        }
        return result
    }


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
        let toRecipients = draft.to
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let allRecipients = (draft.to + draft.cc + draft.bcc)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        // Empty subject is intentionally allowed — it's valid per RFC 5322 and
        // is common in practice ("(no subject)" replies, quick acknowledgements).
        // Send remains gated on having at least one recipient and on every
        // typed recipient being a syntactically-valid address.
        return !toRecipients.isEmpty
            && allRecipients.allSatisfy { isValidEmail($0) }
    }

    /// Stricter email validation — requires a non-empty local part, an `@`, a non-empty
    /// domain part, and at least one `.` in the domain. Replaces the previous "contains @"
    /// check which accepted obvious junk like `@`, `a@`, or `b@b`.
    private func isValidEmail(_ candidate: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Draft Autosave

    /// Schedules a debounced autosave. Cancels any in-flight autosave task so we
    /// only commit once typing settles down (1s).
    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: .milliseconds(1000))
            guard !Task.isCancelled else { return }
            persistAutosaveSnapshot()
        }
    }

    /// Serialises the current draft to UserDefaults under the draft key.
    /// Stored as a small dictionary of strings so we don't depend on Codable
    /// conformance from the shared EmailDraft model.
    private func persistAutosaveSnapshot() {
        // Don't persist a fully empty draft — there's nothing to recover.
        let isEmpty = draft.to.allSatisfy(\.isEmpty)
            && draft.cc.allSatisfy(\.isEmpty)
            && draft.bcc.allSatisfy(\.isEmpty)
            && draft.subject.isEmpty
            && draft.body.isEmpty
        if isEmpty {
            clearAutosavedDraft()
            return
        }
        let payload: [String: Any] = [
            "to": draft.to,
            "cc": draft.cc,
            "bcc": draft.bcc,
            "subject": draft.subject,
            "body": draft.body,
            "savedAt": Date().timeIntervalSince1970,
        ]
        UserDefaults.standard.set(payload, forKey: autosaveKey)
    }

    /// Reads any previously autosaved draft and merges it into `draft`. Initializer-
    /// supplied values take precedence (we only fill empty fields) so passing an
    /// explicit subject/body via `init(to:subject:body:)` still wins.
    private func restoreAutosavedDraft() {
        migrateLegacyAutosaveIfNeeded()
        guard let payload = UserDefaults.standard.dictionary(forKey: autosaveKey) else { return }
        if draft.to.isEmpty || (draft.to.first ?? "").isEmpty,
           let saved = payload["to"] as? [String], !saved.isEmpty {
            draft.to = saved
        }
        if draft.cc.isEmpty, let saved = payload["cc"] as? [String], !saved.isEmpty {
            draft.cc = saved
        }
        if draft.bcc.isEmpty, let saved = payload["bcc"] as? [String], !saved.isEmpty {
            draft.bcc = saved
        }
        if draft.subject.isEmpty, let saved = payload["subject"] as? String, !saved.isEmpty {
            draft.subject = saved
        }
        if draft.body.isEmpty, let saved = payload["body"] as? String, !saved.isEmpty {
            draft.body = saved
        }
    }

    /// Removes the autosaved draft for this compose context. Called after a successful
    /// send and when the draft becomes fully empty.
    private func clearAutosavedDraft() {
        UserDefaults.standard.removeObject(forKey: autosaveKey)
    }

    /// One-shot migration from the old per-mode autosave keys (`reply.<threadId>`,
    /// `replyAll.<threadId>`) to the unified `compose.<threadId>` slot. Runs only when
    /// the current storage key is thread-scoped AND no payload exists at the new key
    /// AND a legacy payload is present. The most recent legacy payload wins (replyAll
    /// preferred when both exist because it tends to carry more state). Legacy keys
    /// are deleted after copy so the migration is idempotent.
    private func migrateLegacyAutosaveIfNeeded() {
        let storageKey = draftStorageKey
        guard storageKey.hasPrefix("compose.") else { return }
        let threadId = String(storageKey.dropFirst("compose.".count))
        guard !threadId.isEmpty else { return }
        let defaults = UserDefaults.standard
        if defaults.dictionary(forKey: autosaveKey) != nil { return }
        let prefix = Self.autosaveKeyPrefix
        let replyAllKey = "\(prefix)replyAll.\(threadId)"
        let replyKey = "\(prefix)reply.\(threadId)"
        let payload = defaults.dictionary(forKey: replyAllKey) ?? defaults.dictionary(forKey: replyKey)
        if let payload {
            defaults.set(payload, forKey: autosaveKey)
            AppLogger.shared.log("Migrated email autosave from reply/replyAll to compose key for thread \(threadId)")
        }
        // Always remove legacy keys so they don't leak into UserDefaults forever.
        defaults.removeObject(forKey: replyAllKey)
        defaults.removeObject(forKey: replyKey)
    }

    private func deletePendingAttachments() {
        for filename in pendingAttachmentRemovals {
            AttachmentService.shared.delete(filename: filename)
        }
        pendingAttachmentRemovals.removeAll()
    }

    /// Per-user-scoped autosave key. Drafts written under one signed-in account
    /// must never be visible to a different account on the same device, so the
    /// signed-in email is folded into the key. Falls back to a stable "_anon_"
    /// bucket before sign-in resolves so a draft typed during the loading flash
    /// isn't lost outright.
    private var autosaveKey: String {
        let userBucket: String
        if let email = services.authService.userEmail?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !email.isEmpty {
            userBucket = email
        } else {
            userBucket = "_anon_"
        }
        return "\(Self.autosaveKeyPrefix)\(userBucket)|\(draftStorageKey)"
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
