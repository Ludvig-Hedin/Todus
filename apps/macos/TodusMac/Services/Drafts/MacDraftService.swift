import Foundation
import SwiftData

/// Thin wrapper around the backend's drafts router for macOS.
/// Mirrors iOS DraftService — used by the AI chat's InlineComposeCard for autosave + send.
@MainActor
final class MacDraftService {
    private let api: TodosAPIClient
    /// Set while `flushPending` is processing. Prevents a second concurrent
    /// flush (e.g. from a rapid network reconnect) from resetting in-flight
    /// `"sending"` rows back to `"pendingSend"` and re-sending them.
    private var isFlushing = false

    init(api: TodosAPIClient) {
        self.api = api
    }

    struct Recipient: Codable {
        let name: String?
        let email: String
    }

    /// Inline attachment payload. We send the raw bytes as base64 so the
    /// backend doesn't need a separate pre-signed upload step yet — matches the
    /// minimal additive shape requested for the compose parity work.
    struct AttachmentPayload: Codable {
        let filename: String
        let mimeType: String
        /// Base64-encoded file contents. Optional so callers can ship metadata-only
        /// records (e.g. an attachment that was deselected but should still appear
        /// in the local draft history) without exploding the wire payload.
        let base64: String?
    }

    struct DraftPayload: Decodable {
        let to: [Recipient]
        let cc: [Recipient]
        let bcc: [Recipient]
        let subject: String
        let body: String
    }

    /// Decode the JSON-encoded payload string emitted by MacInlineComposeCardView.encodePayload().
    static func decodePayload(_ raw: String) -> DraftPayload? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(DraftPayload.self, from: data)
    }

    private struct UpdateInput: Encodable {
        let id: String
        let to: String
        let cc: String?
        let bcc: String?
        let subject: String
        let message: String
        let threadId: String?
        let fromEmail: String?
    }

    private struct EmptyResult: Decodable {}

    func update(draftId: String, payload: DraftPayload) async throws {
        // Drop recipients with empty emails so we never produce malformed headers like ", a@b.com".
        let validTo = payload.to.filter { !$0.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let validCc = payload.cc.filter { !$0.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let validBcc = payload.bcc.filter { !$0.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let input = UpdateInput(
            id: draftId,
            to: validTo.map { recipientHeader($0) }.joined(separator: ", "),
            cc: validCc.isEmpty ? nil : validCc.map { recipientHeader($0) }.joined(separator: ", "),
            bcc: validBcc.isEmpty ? nil : validBcc.map { recipientHeader($0) }.joined(separator: ", "),
            subject: payload.subject,
            message: payload.body,
            threadId: nil,
            fromEmail: nil
        )
        let _: EmptyResult = try await api.trpcMutation("drafts.update", input: input)
    }

    private struct SendInput: Encodable {
        let to: [Recipient]
        let cc: [Recipient]?
        let bcc: [Recipient]?
        let subject: String
        let message: String
        let draftId: String?
        /// When set, the backend threads the reply into the existing conversation. Older
        /// backends that don't understand this field will simply ignore it.
        let threadId: String?
        /// Which connected account to send from. Optional — older backends ignore it.
        let connectionId: String?
        /// Email of the account to send from. This is the field `mail.send` reads
        /// to select the sending account (`connectionId` is not in its schema and
        /// is dropped), so multi-account sends need this set.
        let fromEmail: String?
        /// Optional inline attachments. Older backends that don't understand this field
        /// simply ignore it, so adding the field never breaks the existing wire format.
        let attachments: [AttachmentPayload]?
    }

    func send(
        draftId: String?,
        payload: DraftPayload,
        threadId: String? = nil,
        connectionId: String? = nil,
        fromEmail: String? = nil,
        attachments: [AttachmentPayload]? = nil
    ) async throws {
        // Collapse empty attachment lists to nil so we don't emit `"attachments": []`
        // to a backend that doesn't care — keeps the wire payload minimal.
        let normalizedAttachments = (attachments?.isEmpty ?? true) ? nil : attachments
        let trimmedFromEmail = fromEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = SendInput(
            to: payload.to,
            cc: payload.cc.isEmpty ? nil : payload.cc,
            bcc: payload.bcc.isEmpty ? nil : payload.bcc,
            subject: payload.subject,
            message: EmailBodyHTML.render(payload.body),
            draftId: draftId,
            threadId: threadId,
            connectionId: connectionId,
            fromEmail: (trimmedFromEmail?.isEmpty ?? true) ? nil : trimmedFromEmail,
            attachments: normalizedAttachments
        )
        let _: EmptyResult = try await api.trpcMutation("mail.send", input: input)
    }

    private func recipientHeader(_ r: Recipient) -> String {
        // Caller is responsible for filtering out empty emails before reaching this point.
        let email = r.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if let rawName = r.name?.trimmingCharacters(in: .whitespacesAndNewlines), !rawName.isEmpty {
            let escaped = rawName
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\" <\(email)>"
        }
        return email
    }

    // MARK: - Local-first draft persistence

    /// Persists `draft` locally, attempts to send it, then deletes the record on success.
    /// On failure the record remains with `syncState == "failed"` so `flushPending` can retry.
    func saveAndSend(_ draft: DraftRecord, in context: ModelContext) async {
        // `flushPending` re-runs this against drafts already managed by the
        // context — a second insert produces a duplicate row or undefined
        // SwiftData behavior. Mirror the iOS DraftService guard.
        if draft.modelContext == nil {
            context.insert(draft)
            saveContext(context, label: "saveAndSend.insert")
        }
        draft.syncState = "sending"
        saveContext(context, label: "saveAndSend.markSending")
        do {
            // Reconstruct a DraftPayload from the flat DraftRecord fields.
            let toList = draft.toRecipients
                .split(separator: ",")
                .map { Recipient(name: nil, email: String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
                .filter { !$0.email.isEmpty }
            let ccList = draft.ccRecipients
                .split(separator: ",")
                .map { Recipient(name: nil, email: String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
                .filter { !$0.email.isEmpty }
            let bccList = draft.bccRecipients
                .split(separator: ",")
                .map { Recipient(name: nil, email: String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
                .filter { !$0.email.isEmpty }
            let payload = DraftPayload(
                to: toList,
                cc: ccList,
                bcc: bccList,
                subject: draft.subject,
                body: draft.htmlBody
            )
            // Forward draftId so the backend can clear the corresponding remote draft on
            // send, plus threadId / connectionId so reply threading and outbound account
            // selection survive the local-first persistence hop. Empty connectionId
            // collapses to nil so we don't accidentally pin sends to a blank account id
            // when the field was never populated.
            let normalizedConnectionId = draft.connectionId.trimmingCharacters(in: .whitespacesAndNewlines)
            // Decode any attachments captured at compose time. Decode failures are
            // intentionally silent so a corrupt cache entry can't block a send — the
            // draft will simply go out without the attachment metadata.
            let attachments: [AttachmentPayload]? = {
                guard let raw = draft.attachmentsJSON,
                      !raw.isEmpty,
                      let data = raw.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode([AttachmentPayload].self, from: data)
            }()
            try await send(
                draftId: draft.id,
                payload: payload,
                threadId: draft.threadId,
                connectionId: normalizedConnectionId.isEmpty ? nil : normalizedConnectionId,
                attachments: attachments
            )
            context.delete(draft)
            saveContext(context, label: "saveAndSend.delete")
        } catch {
            draft.syncState = "failed"
            saveContext(context, label: "saveAndSend.markFailed")
        }
    }

    /// Threshold past which a `"sending"` row is treated as orphaned (the app was killed
    /// or crashed mid-send). Rows younger than this are assumed to be in-flight on another
    /// process and left alone so we don't double-send.
    private static let inflightSendCutoff: TimeInterval = 5 * 60

    /// Wraps `try modelContext.save()` so persistence failures surface via `AppLogger` instead
    /// of silently dropping state — without this, a SwiftData write error left the draft in
    /// memory but never on disk, and `flushPending` would retry an already-sent message.
    private func saveContext(_ context: ModelContext, label: String) {
        do {
            try context.save()
        } catch {
            AppLogger.shared.log("[MacDraftService] context.save failed at \(label): \(error)")
        }
    }

    /// Re-attempts all pending or failed draft records. Call on network reconnect.
    /// Also resets any "sending" records that have been stuck longer than
    /// `inflightSendCutoff` back to "pendingSend" — these were in-flight when the app
    /// last crashed. Rows younger than the cutoff are assumed to still be running
    /// inside another live `mail.send` call (or another app process) and are left
    /// alone, so we don't trigger a duplicate send.
    func flushPending(in context: ModelContext) async {
        // Re-entrant guard. Two concurrent flushes (e.g. from a rapid reconnect
        // bounce) could otherwise reset a draft mid-flight in the first call
        // back to "pendingSend" and trigger a second `mail.send` for it.
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        // Only treat *aged* "sending" records as orphans — younger rows may still be in
        // flight on another process or a parallel task that started before this flush.
        let stuckDescriptor = FetchDescriptor<DraftRecord>(
            predicate: #Predicate { $0.syncState == "sending" }
        )
        let stuck = (try? context.fetch(stuckDescriptor)) ?? []
        let now = Date()
        var didMutateStuck = false
        for draft in stuck where now.timeIntervalSince(draft.createdAt) >= Self.inflightSendCutoff {
            draft.syncState = "pendingSend"
            didMutateStuck = true
        }
        if didMutateStuck { saveContext(context, label: "flushPending.resetOrphans") }

        let descriptor = FetchDescriptor<DraftRecord>(
            predicate: #Predicate { $0.syncState == "pendingSend" || $0.syncState == "failed" }
        )
        let pending = (try? context.fetch(descriptor)) ?? []
        for draft in pending { await saveAndSend(draft, in: context) }
    }
}
