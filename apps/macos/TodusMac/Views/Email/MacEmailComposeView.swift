import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Email compose view for new emails and replies.
/// Desktop-optimized: wider fields, keyboard shortcuts.
struct MacEmailComposeView: View {
    @Environment(MacAppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var draft: EmailDraft
    @State private var showSendError = false
    /// Local flag for the attachment-bearing send path. `EmailService.isSending`
    /// only flips when `sendEmail` is called; the `MacDraftService.send` path used
    /// for attachments bypasses it, leaving the Send button enabled mid-send.
    /// A fast double-click → two real `mail.send` round-trips → two delivered
    /// emails. This flag closes that window.
    @State private var isSendingAttachments = false
    @State private var showCcBcc = false
    @State private var autosaveTask: Task<Void, Never>?
    @State private var draftStorageKey: String
    // Raw text state for recipient fields. Lets the user type freely (including
    // trailing comma+space while composing the next address) without the binding
    // setter eating tokens. Tokenized into draft.to/cc/bcc on focus loss & send.
    @State private var toRaw: String = ""
    @State private var ccRaw: String = ""
    @State private var bccRaw: String = ""
    /// User-picked attachments. Files (`NSOpenPanel`) and images are normalized into
    /// the same struct so the chip row + send payload have one shape to deal with.
    @State private var attachments: [ComposeAttachment] = []
    /// True once the signature has been appended for the current draft so opening
    /// the same composition twice (e.g. via autosave restore) doesn't double up.
    @State private var didApplySignature = false
    /// Bridge to the body NSTextView so the formatting toolbar can insert markdown
    /// at the caret/selection instead of appending to the end of the message.
    @State private var editorController = MacMarkdownEditorController()
    /// Tracks whether the recipient validation message should be visible.
    /// Only true after the user attempts to send with bad input — we don't want
    /// to nag with a red chip the moment compose opens.
    @State private var showRecipientValidationError = false
    /// Flips to true once the user has explicitly emptied the Cc field in this
    /// session. Persisted into the autosave payload so a subsequent restore
    /// doesn't resurrect phantom recipients the user already deleted.
    @State private var hasUserClearedCc = false
    /// Same intent as `hasUserClearedCc`, but for the Bcc field.
    @State private var hasUserClearedBcc = false
    /// Stable per-compose-session idempotency key. Reused as the `draftId` on
    /// every attachment-bearing send so a crash-then-relaunch can't double-post
    /// the same message — the backend dedupes by draftId. Generated once per
    /// view instance via `UUID().uuidString` so each new compose gets a fresh
    /// key, and a single compose session always uses the same one.
    @State private var composeIdempotencyKey: String = UUID().uuidString
    /// Set to true when `restoreAutosavedDraft()` actually restored non-empty
    /// content. Drives the dismissible "Restored from your last draft" banner
    /// at the top of the compose. Auto-clears on the first user edit so the
    /// banner doesn't linger after the user has clearly engaged with the draft.
    @State private var didRestoreFromAutosave = false
    @FocusState private var focusedField: Field?

    /// In-memory attachment record. Owns its raw bytes so the compose flow can
    /// preview the chip, build a base64 payload at send time, and let the user
    /// remove items without touching disk.
    private struct ComposeAttachment: Identifiable, Equatable {
        let id = UUID()
        let filename: String
        let mimeType: String
        let data: Data

        static func == (lhs: ComposeAttachment, rhs: ComposeAttachment) -> Bool {
            lhs.id == rhs.id
        }
    }

    private let navigationTitle: String
    private let onCloseHandler: (() -> Void)?

    private static let autosaveKeyPrefix = "mac_email_compose_autosave_v1."
    private static let newComposeStorageKey = "new"

    private enum Field: Hashable {
        case to, cc, bcc, subject, body
    }

    private func close() {
        if let onCloseHandler {
            onCloseHandler()
        } else {
            dismiss()
        }
    }

    // MARK: - Initialisers

    /// New email
    init(onClose: (() -> Void)? = nil) {
        _draft = State(initialValue: EmailDraft())
        navigationTitle = "New Email"
        onCloseHandler = onClose
        _draftStorageKey = State(initialValue: Self.newComposeStorageKey)
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
        _draftStorageKey = State(initialValue: "reply.\(threadId).single")
    }

    /// Reply all — To includes sender + original To; Cc holds other parties from Cc.
    /// `ownedAddresses` is the signed-in user's own addresses (across connected
    /// accounts + aliases). Any address in that set is filtered out of To and Cc
    /// so the user doesn't reply-all to themselves on every send.
    init(
        replyAllTo message: EmailMessage,
        threadId: String,
        body: String = "",
        ownedAddresses: Set<String> = [],
        onClose: (() -> Void)? = nil
    ) {
        var d = EmailDraft()
        let owned = Set(ownedAddresses.map { $0.lowercased() })
        var toEmails: [String] = []
        func pushTo(_ raw: String) {
            let e = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !e.isEmpty else { return }
            if owned.contains(e.lowercased()) { return }
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
                if owned.contains(x.lowercased()) { continue }
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
        _draftStorageKey = State(initialValue: "reply.\(threadId).all")
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
        _draftStorageKey = State(initialValue: "forward.\(message.id)")
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
        _draftStorageKey = State(initialValue: Self.newComposeStorageKey)
    }

    /// Optionally pre-filled from seed body (empty string = new email)
    init(seedBody: String, onClose: (() -> Void)? = nil) {
        var d = EmailDraft()
        if !seedBody.isEmpty { d.body = seedBody }
        _draft = State(initialValue: d)
        navigationTitle = "New Email"
        onCloseHandler = onClose
        _draftStorageKey = State(initialValue: Self.newComposeStorageKey)
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
        _draftStorageKey = State(initialValue: Self.newComposeStorageKey)
    }

    // MARK: - Validation

    /// Recipients pulled live from the raw text fields so the Send button reflects
    /// what the user has typed even before the field loses focus. Without this,
    /// Send stays disabled until the user tabs out of the To field — every other
    /// mail client validates as-you-type.
    private var liveTo: [String] {
        let tokenized = Self.tokenizeRecipients(toRaw)
        return tokenized.isEmpty ? draft.to : tokenized
    }
    private var liveCc: [String] {
        let tokenized = Self.tokenizeRecipients(ccRaw)
        return tokenized.isEmpty ? draft.cc : tokenized
    }
    private var liveBcc: [String] {
        let tokenized = Self.tokenizeRecipients(bccRaw)
        return tokenized.isEmpty ? draft.bcc : tokenized
    }

    private var canSend: Bool {
        let toRecipients = liveTo
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let allRecipients = (liveTo + liveCc + liveBcc)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        // Subject is intentionally allowed to be empty — matches the iOS reference
        // and is valid per RFC 5322. Send is only gated on having at least one To
        // recipient and every typed recipient being a valid address.
        return !toRecipients.isEmpty
            && allRecipients.allSatisfy { isValidEmail($0) }
    }

    /// Returns the first invalid recipient string, if any. Drives the inline
    /// error chip below the To row.
    private var firstInvalidRecipient: String? {
        let all = (liveTo + liveCc + liveBcc)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return all.first { !isValidEmail($0) }
    }

    private func isValidEmail(_ candidate: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Body

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
                    // Tokenize raw recipient text before sending so anything still in
                    // the field but not yet committed (e.g. user hit Cmd+Return without
                    // tabbing out) makes it into the draft.
                    draft.to = Self.tokenizeRecipients(toRaw)
                    draft.cc = Self.tokenizeRecipients(ccRaw)
                    draft.bcc = Self.tokenizeRecipients(bccRaw)
                    // Surface validation issues inline before we kick the network — the
                    // Send button is disabled, but Cmd+Return could still fire if the
                    // user pressed it after the disabled state was evaluated against
                    // older raw text.
                    guard canSend else {
                        showRecipientValidationError = true
                        return
                    }
                    showRecipientValidationError = false
                    Task { await performSend() }
                } label: {
                    if services.emailService.isSending || isSendingAttachments {
                        HStack(spacing: MacTheme.spacing4) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Sending…")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    } else {
                        HStack(spacing: MacTheme.spacing4) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Send")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                }
                .disabled(!canSend || services.emailService.isSending || isSendingAttachments || !services.networkMonitor.isConnected)
                .macClickablePointer()
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(MacTheme.spacing16)

            Divider().opacity(0.3)

            ScrollView {
                VStack(spacing: 0) {
                    // Restored-draft banner — only shows when `restoreAutosavedDraft`
                    // actually pulled non-empty content back from UserDefaults so
                    // brand-new composes don't flash a banner about nothing.
                    if didRestoreFromAutosave {
                        restoredFromAutosaveBanner
                    }

                    // Offline notice — mirrors the global offline banner, which is hidden behind sheets
                    if !services.networkMonitor.isConnected {
                        offlineNotice
                    }

                    // From row
                    fromRow
                    Divider().opacity(0.15).padding(.horizontal, MacTheme.spacing16)

                    // To with CC/BCC disclosure
                    toRow
                    if showCcBcc {
                        Divider().opacity(0.15).padding(.horizontal, MacTheme.spacing16)
                        ccRow
                        Divider().opacity(0.15).padding(.horizontal, MacTheme.spacing16)
                        bccRow
                    }

                    // Inline validation chip — shows the first invalid recipient when
                    // the user has typed an address that fails the regex. Only visible
                    // after Send was attempted so we don't shout at a half-typed field.
                    if showRecipientValidationError, let bad = firstInvalidRecipient {
                        validationChip(message: "Not a valid email address: \(bad)")
                    }

                    Divider().opacity(0.15).padding(.horizontal, MacTheme.spacing16)

                    subjectRow

                    Divider().opacity(0.15).padding(.horizontal, MacTheme.spacing16)

                    formattingToolbar

                    // Attachment chip row — only renders when there's at least one
                    // attached file so empty composes stay visually clean.
                    if !attachments.isEmpty {
                        Divider().opacity(0.15).padding(.horizontal, MacTheme.spacing16)
                        attachmentChipsRow
                    }

                    Divider().opacity(0.15).padding(.horizontal, MacTheme.spacing16)

                    // Body — NSTextView wrapper with live markdown rendering
                    MacMarkdownBodyEditor(
                        text: $draft.body,
                        placeholder: "Write your message",
                        isFocused: focusedField == .body,
                        font: .systemFont(ofSize: 13),
                        onFocusChange: { focused in
                            if focused { focusedField = .body }
                            else if focusedField == .body { focusedField = nil }
                        },
                        controller: editorController
                    )
                    .frame(maxWidth: .infinity, minHeight: 260, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            restoreAutosavedDraft()
            // Seed raw recipient state from any pre-populated draft (reply, forward, mailto:).
            toRaw = draft.to.joined(separator: ", ")
            ccRaw = draft.cc.joined(separator: ", ")
            bccRaw = draft.bcc.joined(separator: ", ")
            if draft.fromConnectionId == nil {
                draft.fromConnectionId = services.connectionsService.connections.first?.id
            }
            // Append the per-account signature once on first appearance. The guard
            // and substring check together prevent double-appending when the view
            // re-opens with the same draft (autosave restore, sheet re-show).
            appendSignatureIfNeeded()
            if navigationTitle == "Reply All" || !draft.cc.isEmpty {
                showCcBcc = true
            }
            if draft.to.first?.isEmpty ?? true {
                focusedField = .to
            } else if draft.subject.isEmpty {
                focusedField = .subject
            } else {
                focusedField = .body
            }
        }
        // Cancel any pending ~1s autosave when the compose view goes away so a
        // debounced snapshot can't fire and re-persist a draft after it was
        // cleared/sent (the Task isn't tied to the view's lifecycle otherwise).
        .onDisappear {
            autosaveTask?.cancel()
            autosaveTask = nil
        }
        // If the user picks a different From account the signature should refresh —
        // strip the old one (if still present) and append the new one so multi-account
        // users don't ship the wrong sign-off.
        .onChange(of: draft.fromConnectionId) { oldValue, newValue in
            // Strip the previous account's signature block (if it's still
            // present untouched) before appending the new account's sign-off,
            // so switching From accounts doesn't stack two signatures.
            if let oldId = oldValue,
               oldId != newValue,
               let oldBlock = MacSignatureStore.shared.formattedSignatureBlock(for: oldId),
               let range = draft.body.range(of: oldBlock) {
                draft.body.removeSubrange(range)
            }
            didApplySignature = false
            appendSignatureIfNeeded()
        }
        // Re-tokenize live so the inline validation chip clears as soon as the
        // user corrects a bad email — without this the chip lingers until focus
        // leaves the field.
        .onChange(of: toRaw) { _, _ in
            if showRecipientValidationError, firstInvalidRecipient == nil { showRecipientValidationError = false }
        }
        .onChange(of: ccRaw) { oldValue, newValue in
            if showRecipientValidationError, firstInvalidRecipient == nil { showRecipientValidationError = false }
            // User wiped a previously non-empty Cc field — remember the intent so
            // restore doesn't bring the addresses back the next time compose opens.
            let oldTrim = oldValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let newTrim = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !oldTrim.isEmpty && newTrim.isEmpty {
                hasUserClearedCc = true
                // Persist the flag immediately so a quick close doesn't lose it.
                persistAutosaveSnapshot()
            } else if !newTrim.isEmpty {
                // Re-typing into the field cancels the "cleared" intent so a later
                // restore can legitimately surface this content again if needed.
                hasUserClearedCc = false
            }
        }
        .onChange(of: bccRaw) { oldValue, newValue in
            if showRecipientValidationError, firstInvalidRecipient == nil { showRecipientValidationError = false }
            let oldTrim = oldValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let newTrim = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !oldTrim.isEmpty && newTrim.isEmpty {
                hasUserClearedBcc = true
                persistAutosaveSnapshot()
            } else if !newTrim.isEmpty {
                hasUserClearedBcc = false
            }
        }
        .onChange(of: draft.to) { scheduleAutosave(); dismissRestoreBannerOnEdit() }
        .onChange(of: draft.cc) { scheduleAutosave(); dismissRestoreBannerOnEdit() }
        .onChange(of: draft.bcc) { scheduleAutosave(); dismissRestoreBannerOnEdit() }
        .onChange(of: draft.subject) { scheduleAutosave(); dismissRestoreBannerOnEdit() }
        .onChange(of: draft.body) { scheduleAutosave(); dismissRestoreBannerOnEdit() }
        .alert("Failed to send", isPresented: $showSendError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(services.emailService.errorMessage ?? "Please check your connection and try again.")
        }
    }

    // MARK: - Field Rows

    /// Send entry point — extracted so SwiftUI's type-checker can finish in a
    /// reasonable time (inlining all of this into the Button action caused
    /// "the compiler is unable to type-check this expression" failures).
    private func performSend() async {
        // Resolve the picked From account to an email — `mail.send` routes by
        // `fromEmail`, not by connection id.
        draft.fromEmail = selectedFromEmail(connections: services.connectionsService.connections)
        let success: Bool
        if attachments.isEmpty {
            // Legacy path: `EmailService.sendEmail` already refreshes inbox
            // cache and isSending state internally.
            success = await services.emailService.sendEmail(draft)
        } else {
            // Attachment path: route through MacDraftService so `mail.send`
            // is called exactly once with the attachment payload inline.
            // `isSendingAttachments` covers the entire round-trip so the Send
            // button stays disabled — double-clicking the Send button (or
            // hitting ⌘↩ twice) used to fire two `mail.send` calls in a row.
            isSendingAttachments = true
            success = await sendViaDraftServiceWithAttachments()
            if success {
                if let threadId = draft.replyToThreadId {
                    _ = await services.emailService.loadThread(id: threadId)
                }
                await services.emailService.loadThreads(folder: "inbox", refresh: true)
            }
            isSendingAttachments = false
        }
        if success {
            clearAutosavedDraft()
            close()
        } else {
            showSendError = true
        }
    }

    /// Subtle banner shown when `restoreAutosavedDraft` actually pulled
    /// non-empty content back from UserDefaults. Auto-dismisses on first
    /// edit (see `dismissRestoreBannerOnEdit`) and offers a "Start fresh"
    /// escape hatch for users who don't want the stale draft.
    private var restoredFromAutosaveBanner: some View {
        HStack(spacing: MacTheme.spacing8) {
            Image(systemName: "tray.and.arrow.up")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MacTheme.accent)
            Text("Restored from your last draft.")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(MacTheme.textPrimary)
            Spacer(minLength: 0)
            Button("Start fresh") {
                draft.to = []
                draft.cc = []
                draft.bcc = []
                draft.subject = ""
                draft.body = ""
                attachments.removeAll()
                hasUserClearedCc = true
                hasUserClearedBcc = true
                didRestoreFromAutosave = false
                // Body was just emptied — re-arm the signature so "Start fresh"
                // still ships the per-account sign-off instead of a blank body.
                didApplySignature = false
                appendSignatureIfNeeded()
                persistAutosaveSnapshot()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(MacTheme.accent)
        }
        .padding(.horizontal, MacTheme.spacing16)
        .padding(.vertical, MacTheme.spacing8)
        .background(MacTheme.surfaceCard)
    }

    /// Called from every editable field's onChange. First user edit dismisses
    /// the "Restored from your last draft" banner because they're now actively
    /// shaping the draft rather than passively reviewing the restored content.
    private func dismissRestoreBannerOnEdit() {
        if didRestoreFromAutosave {
            didRestoreFromAutosave = false
        }
    }

    private var offlineNotice: some View {
        HStack(spacing: MacTheme.spacing8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 11, weight: .semibold))
            Text("You're offline — message will not send.")
                .font(.system(size: 12, weight: .medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(MacTheme.mutedText)
        .padding(.horizontal, MacTheme.spacing16)
        .padding(.vertical, MacTheme.spacing8)
        .background(MacTheme.surfaceCard)
    }

    @ViewBuilder
    private var fromRow: some View {
        let connections = services.connectionsService.connections
        HStack(spacing: MacTheme.spacing8) {
            Text("From")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MacTheme.mutedText)
                .frame(width: 50, alignment: .trailing)

            if connections.count > 1 {
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
                    HStack(spacing: MacTheme.spacing4) {
                        Text(selectedFromEmail(connections: connections))
                            .font(.system(size: 13))
                            .foregroundStyle(MacTheme.textPrimary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(MacTheme.mutedText)
                        Spacer()
                    }
                }
                .macClickablePointer()
            } else {
                Text(selectedFromEmail(connections: connections))
                    .font(.system(size: 13))
                    .foregroundStyle(MacTheme.textPrimary)
                Spacer()
            }
        }
        .padding(.horizontal, MacTheme.spacing16)
        .padding(.vertical, MacTheme.spacing8)
    }

    private var toRow: some View {
        HStack(spacing: MacTheme.spacing8) {
            Text("To")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MacTheme.mutedText)
                .frame(width: 50, alignment: .trailing)

            TextField("name@email.com", text: $toRaw)
            .font(.system(size: 13))
            .textFieldStyle(.plain)
            .focused($focusedField, equals: .to)
            .onChange(of: focusedField) { _, newValue in
                if newValue != .to { draft.to = Self.tokenizeRecipients(toRaw) }
            }
            .onSubmit { draft.to = Self.tokenizeRecipients(toRaw) }

            Button {
                withAnimation(MacTheme.Motion.fast) {
                    showCcBcc.toggle()
                }
            } label: {
                Image(systemName: showCcBcc ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MacTheme.mutedText)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .macClickablePointer()
        }
        .padding(.horizontal, MacTheme.spacing16)
        .padding(.vertical, MacTheme.spacing8)
    }

    private var ccRow: some View {
        fieldRow(label: "Cc") {
            TextField("name@email.com", text: $ccRaw)
                .focused($focusedField, equals: .cc)
                .onChange(of: focusedField) { _, newValue in
                    if newValue != .cc { draft.cc = Self.tokenizeRecipients(ccRaw) }
                }
                .onSubmit { draft.cc = Self.tokenizeRecipients(ccRaw) }
        }
    }

    private var bccRow: some View {
        fieldRow(label: "Bcc") {
            TextField("name@email.com", text: $bccRaw)
                .focused($focusedField, equals: .bcc)
                .onChange(of: focusedField) { _, newValue in
                    if newValue != .bcc { draft.bcc = Self.tokenizeRecipients(bccRaw) }
                }
                .onSubmit { draft.bcc = Self.tokenizeRecipients(bccRaw) }
        }
    }

    /// Parse recipient text into a list of trimmed, non-empty addresses.
    /// Used at focus-loss and pre-send so users can type "alice@x.com, " without
    /// the binding setter dropping the trailing comma+space mid-edit.
    private static func tokenizeRecipients(_ raw: String) -> [String] {
        // Split on commas, semicolons, AND whitespace/newlines so pasting
        // "a@x.com b@y.com" or "a@x.com; b@y.com" yields separate addresses
        // instead of one invalid mega-token that blocks send. Email addresses
        // never contain internal whitespace, so this is safe.
        let separators = CharacterSet(charactersIn: ",;").union(.whitespacesAndNewlines)
        return raw
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var subjectRow: some View {
        fieldRow(label: "Subject") {
            TextField("Subject", text: $draft.subject)
                .focused($focusedField, equals: .subject)
        }
    }

    private func fieldRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: MacTheme.spacing8) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MacTheme.mutedText)
                .frame(width: 50, alignment: .trailing)
            content()
                .font(.system(size: 13))
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, MacTheme.spacing16)
        .padding(.vertical, MacTheme.spacing8)
    }

    // MARK: - Formatting Toolbar

    private var formattingToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                formatButton(icon: "bold", label: "Bold") {
                    insertFormat("**", closing: "**", placeholder: "bold text")
                }
                .keyboardShortcut("b", modifiers: .command)
                formatButton(icon: "italic", label: "Italic") {
                    insertFormat("_", closing: "_", placeholder: "italic text")
                }
                .keyboardShortcut("i", modifiers: .command)
                // Underline uses an HTML span because CommonMark has no native
                // underline token — mail clients render the inline tag fine and
                // the iOS reference can adopt the same approach later.
                formatButton(icon: "underline", label: "Underline") {
                    insertFormat("<u>", closing: "</u>", placeholder: "underlined text")
                }
                .keyboardShortcut("u", modifiers: .command)
                toolbarDivider()
                formatButton(icon: "textformat.size.larger", label: "H1") {
                    insertLinePrefix("# ")
                }
                formatButton(icon: "textformat.size", label: "H2") {
                    insertLinePrefix("## ")
                }
                toolbarDivider()
                formatButton(icon: "list.bullet", label: "Bullet list") {
                    insertLinePrefix("• ")
                }
                formatButton(icon: "list.number", label: "Numbered list") {
                    insertLinePrefix("1. ")
                }
                formatButton(icon: "checklist", label: "Checklist") {
                    insertLinePrefix("☐ ")
                }
                toolbarDivider()
                formatButton(icon: "quote.opening", label: "Quote") {
                    insertLinePrefix("> ")
                }
                formatButton(icon: "minus", label: "Divider") {
                    insertLinePrefix("---")
                }
                toolbarDivider()
                // Attachment picker — file + image variants share the same NSOpenPanel
                // flow, but split into two buttons so the placement feels like the
                // iOS create-sheet that has both options.
                attachmentButton(icon: "paperclip", label: "Attach file") {
                    pickFiles(images: false)
                }
                attachmentButton(icon: "photo", label: "Attach photo") {
                    pickFiles(images: true)
                }
            }
            .padding(.horizontal, MacTheme.spacing12)
            .padding(.vertical, MacTheme.spacing6)
        }
        // Attachment buttons must stay enabled even when the body isn't focused —
        // a user dragging to attach a file shouldn't have to click into the body first.
        // The formatting buttons still no-op when body is not focused via their
        // own opacity treatment below.
        .opacity(focusedField == .body ? 1.0 : 0.55)
    }

    private func formatButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MacTheme.mutedText)
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .macClickablePointer()
        .accessibilityLabel(label)
    }

    private func toolbarDivider() -> some View {
        Rectangle()
            .fill(MacTheme.mutedText.opacity(0.3))
            .frame(width: 1, height: 14)
            .padding(.horizontal, MacTheme.spacing4)
    }

    private func insertFormat(_ opening: String, closing: String, placeholder: String) {
        focusedField = .body
        if editorController.isReady {
            // Wrap the selection / insert at the caret so formatting lands where
            // the user is typing instead of at the end of the message.
            editorController.wrapSelection(opening: opening, closing: closing, placeholder: placeholder)
        } else {
            let newline = draft.body.isEmpty || draft.body.hasSuffix("\n") ? "" : "\n"
            draft.body += "\(newline)\(opening)\(placeholder)\(closing)"
        }
    }

    private func insertLinePrefix(_ prefix: String) {
        focusedField = .body
        if editorController.isReady {
            editorController.insertLinePrefix(prefix)
        } else {
            let newline = draft.body.isEmpty || draft.body.hasSuffix("\n") ? "" : "\n"
            draft.body += "\(newline)\(prefix)"
        }
    }

    // MARK: - Attachment Picker

    /// Distinct treatment for the attachment buttons — they stay enabled even
    /// when the body isn't focused (unlike the markdown formatters), so they
    /// shouldn't fade with the rest of the toolbar.
    private func attachmentButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MacTheme.textPrimary)
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .macClickablePointer()
        .accessibilityLabel(label)
    }

    /// Opens `NSOpenPanel` and ingests the selected files into the local
    /// `attachments` array. `images=true` restricts the type filter to
    /// common image formats so the "photo" affordance behaves intuitively.
    private func pickFiles(images: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = images ? "Choose photos" : "Choose files to attach"
        if images {
            // UTType.image covers PNG, JPEG, HEIC, GIF, WebP, etc. without us
            // having to enumerate each format ourselves.
            panel.allowedContentTypes = [.image]
        }
        if panel.runModal() == .OK {
            for url in panel.urls {
                ingestFile(url: url)
            }
        }
    }

    /// Loads a file's bytes into a `ComposeAttachment` and appends it to the chip
    /// row. Failures are silent (logged) so a single broken file doesn't blow up
    /// the rest of the picker session.
    private func ingestFile(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let mime = mimeType(for: url)
            attachments.append(
                ComposeAttachment(filename: url.lastPathComponent, mimeType: mime, data: data)
            )
        } catch {
            AppLogger.shared.log("[MacEmailCompose] ingestFile failed for \(url.lastPathComponent): \(error)")
        }
    }

    /// Best-effort MIME lookup. Falls back to `application/octet-stream` for
    /// unknown types so the attachment still gets through to the backend.
    private func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType {
            return type
        }
        return "application/octet-stream"
    }

    // MARK: - Attachment Row

    private var attachmentChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MacTheme.spacing8) {
                ForEach(attachments) { attachment in
                    attachmentChip(attachment)
                }
            }
            .padding(.horizontal, MacTheme.spacing16)
            .padding(.vertical, MacTheme.spacing8)
        }
    }

    private func attachmentChip(_ attachment: ComposeAttachment) -> some View {
        HStack(spacing: 6) {
            Image(systemName: attachment.mimeType.hasPrefix("image/") ? "photo" : "doc")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MacTheme.mutedText)
            Text(attachment.filename)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MacTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 200)
            Button {
                attachments.removeAll { $0.id == attachment.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(MacTheme.mutedText)
            }
            .buttonStyle(.plain)
            .macClickablePointer()
            .accessibilityLabel("Remove attachment \(attachment.filename)")
        }
        .padding(.horizontal, MacTheme.spacing12)
        .padding(.vertical, MacTheme.spacing6)
        .background(MacTheme.surfaceCard, in: Capsule())
    }

    // MARK: - Validation Chip

    private func validationChip(message: String) -> some View {
        HStack(spacing: MacTheme.spacing6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.red)
        .padding(.horizontal, MacTheme.spacing16)
        .padding(.vertical, MacTheme.spacing6)
    }

    // MARK: - Signature

    /// Appends the per-account signature to the body the first time the compose
    /// view appears with a known From connection. The substring check is the
    /// final guard: if the user has already pasted the signature elsewhere we
    /// won't double-up the sign-off.
    private func appendSignatureIfNeeded() {
        guard !didApplySignature else { return }
        guard let connectionId = draft.fromConnectionId,
              let block = MacSignatureStore.shared.formattedSignatureBlock(for: connectionId) else { return }
        didApplySignature = true
        // Trim leading/trailing whitespace before substring comparison so a
        // signature buried inside an existing draft doesn't get a second copy
        // welded onto the end.
        if !draft.body.contains(block.trimmingCharacters(in: .whitespacesAndNewlines)) {
            draft.body.append(block)
        }
    }

    // MARK: - Attachment Send Bridge

    /// Single-POST send path for composes that include attachments. Routes through
    /// `MacDraftService.send` so the inline attachments ride along on the same
    /// `mail.send` request — never alongside the legacy `emailService.sendEmail`
    /// path, which would double-send the message to recipients.
    /// Returns true on a successful POST, false on any error so the caller can
    /// surface the same alert as the legacy path.
    private func sendViaDraftServiceWithAttachments() async -> Bool {
        let recipients = draft.to.map { MacDraftService.Recipient(name: nil, email: $0) }
        let ccRecipients = draft.cc.map { MacDraftService.Recipient(name: nil, email: $0) }
        let bccRecipients = draft.bcc.map { MacDraftService.Recipient(name: nil, email: $0) }
        let payload = MacDraftService.DraftPayload(
            to: recipients,
            cc: ccRecipients,
            bcc: bccRecipients,
            subject: draft.subject,
            body: draft.body
        )
        let attachmentPayloads = attachments.map { att in
            MacDraftService.AttachmentPayload(
                filename: att.filename,
                mimeType: att.mimeType,
                base64: att.data.base64EncodedString()
            )
        }
        do {
            // Pass a stable per-compose-session `draftId` so the backend
            // (`mail.send`) and the offline retry path can correlate the
            // outbound message. Backend currently does NOT dedupe by
            // `draftId` — it generates a fresh `messageId` per request — so
            // this is informational, not a true idempotency guard.
            // Double-send risk in practice is constrained to the
            // `MacDraftService.flushPending` retry path, which is already
            // gated by a 5-minute "orphan" window in flushPending. Direct
            // compose-initiated sends (this path) don't create a
            // `DraftRecord` to retry, so there's no retry-driven duplicate.
            try await services.draftService.send(
                draftId: composeIdempotencyKey,
                payload: payload,
                threadId: draft.replyToThreadId,
                connectionId: draft.fromConnectionId,
                fromEmail: draft.fromEmail,
                attachments: attachmentPayloads
            )
            return true
        } catch {
            AppLogger.shared.log("[MacEmailCompose] attachment send failed: \(error)")
            return false
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

    // MARK: - Draft Autosave

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1000))
            guard !Task.isCancelled else { return }
            persistAutosaveSnapshot()
        }
    }

    private func persistAutosaveSnapshot() {
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
            // Sticky "user-cleared" markers — restore consults these so it doesn't
            // resurrect Cc/Bcc the user explicitly emptied earlier in the session.
            "clearedCc": hasUserClearedCc,
            "clearedBcc": hasUserClearedBcc,
        ]
        UserDefaults.standard.set(payload, forKey: autosaveKey)
    }

    private func restoreAutosavedDraft() {
        guard let payload = UserDefaults.standard.dictionary(forKey: autosaveKey) else { return }
        // Hydrate the "user cleared" markers first so the Cc/Bcc restore decisions
        // below can honour them. Without this, a previous-session restore would
        // resurrect addresses the user had explicitly deleted.
        let savedClearedCc = (payload["clearedCc"] as? Bool) ?? false
        let savedClearedBcc = (payload["clearedBcc"] as? Bool) ?? false
        hasUserClearedCc = savedClearedCc
        hasUserClearedBcc = savedClearedBcc
        // Track whether we actually pulled real content back from the snapshot
        // so the user-facing "Restored from last draft" banner only appears
        // when there's something to be surprised by.
        var restoredSomething = false
        if draft.to.isEmpty || (draft.to.first ?? "").isEmpty,
           let saved = payload["to"] as? [String], !saved.isEmpty {
            draft.to = saved
            restoredSomething = true
        }
        if !savedClearedCc,
           draft.cc.isEmpty, let saved = payload["cc"] as? [String], !saved.isEmpty {
            draft.cc = saved
            showCcBcc = true
            restoredSomething = true
        }
        if !savedClearedBcc,
           draft.bcc.isEmpty, let saved = payload["bcc"] as? [String], !saved.isEmpty {
            draft.bcc = saved
            showCcBcc = true
            restoredSomething = true
        }
        if draft.subject.isEmpty, let saved = payload["subject"] as? String, !saved.isEmpty {
            draft.subject = saved
            restoredSomething = true
        }
        if draft.body.isEmpty, let saved = payload["body"] as? String, !saved.isEmpty {
            draft.body = saved
            restoredSomething = true
        }
        if restoredSomething {
            didRestoreFromAutosave = true
        }
    }

    private func clearAutosavedDraft() {
        UserDefaults.standard.removeObject(forKey: autosaveKey)
    }

    private var autosaveKey: String {
        "\(Self.autosaveKeyPrefix)\(draftStorageKey)"
    }
}
