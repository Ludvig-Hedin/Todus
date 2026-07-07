import Foundation
import SwiftData

/// Thin wrapper around the backend's drafts router.
/// Used by the AI chat's InlineComposeCard for autosave + send.
@MainActor
final class DraftService {
    private let api: TodosAPIClient
    /// Set while `flushPending` is processing. Re-entrant calls (rapid network
    /// flapping triggering multiple onReconnect events) bail out early so we
    /// don't reset in-flight `"sending"` rows back to `"pendingSend"` and
    /// fire a second `mail.send` for the same draft.
    private var isFlushing = false

    init(api: TodosAPIClient) {
        self.api = api
    }

    struct Recipient: Codable {
        let name: String?
        let email: String
    }

    struct DraftPayload: Decodable {
        let to: [Recipient]
        let cc: [Recipient]
        let bcc: [Recipient]
        let subject: String
        let body: String
    }

    /// Decode the JSON-encoded payload string emitted by InlineComposeCardView.encodePayload().
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

    /// Calls drafts.update. Mirrors the createDraftData shape used on the server.
    func update(draftId: String, payload: DraftPayload) async throws {
        let input = UpdateInput(
            id: draftId,
            to: payload.to.compactMap { recipientHeader($0) }.joined(separator: ", "),
            cc: payload.cc.isEmpty ? nil : payload.cc.compactMap { recipientHeader($0) }.joined(separator: ", "),
            bcc: payload.bcc.isEmpty ? nil : payload.bcc.compactMap { recipientHeader($0) }.joined(separator: ", "),
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
    }

    /// Calls mail.send. The backend deletes the draft when draftId is provided.
    func send(draftId: String?, payload: DraftPayload) async throws {
        let input = SendInput(
            to: payload.to,
            cc: payload.cc.isEmpty ? nil : payload.cc,
            bcc: payload.bcc.isEmpty ? nil : payload.bcc,
            subject: payload.subject,
            message: payload.body,
            draftId: draftId
        )
        let _: EmptyResult = try await api.trpcMutation("mail.send", input: input)
    }

    /// Saves the draft locally and attempts to send. If send fails (offline or error),
    /// the draft remains with syncState "pendingSend" for later retry.
    func saveAndSend(_ draft: DraftRecord, in context: ModelContext) async {
        // Only insert when the draft isn't already managed by the context — flushPending
        // re-runs this against drafts fetched from disk, where another insert can produce
        // duplicate rows or undefined SwiftData behavior.
        if draft.modelContext == nil {
            context.insert(draft)
            try? context.save()
        }

        draft.syncState = "sending"
        try? context.save()

        // Convert comma-separated address strings back into Recipient arrays.
        let toRecipients = parseRecipients(draft.toRecipients)
        let ccRecipients = parseRecipients(draft.ccRecipients)
        let payload = DraftPayload(
            to: toRecipients,
            cc: ccRecipients,
            bcc: [],
            subject: draft.subject,
            body: draft.htmlBody
        )

        do {
            try await send(draftId: nil, payload: payload)
            context.delete(draft)
            try? context.save()
        } catch {
            draft.syncState = "failed"
            try? context.save()
        }
    }

    /// Retry all pending/failed drafts. Call on reconnect.
    /// Records stuck in "sending" (in-flight at last crash) are intentionally
    /// left alone — see the duplicate-delivery note below.
    func flushPending(in context: ModelContext) async {
        // Re-entrant guard. Without this, a rapid offline→online→offline→online
        // bounce could fire two concurrent flushes: the second would reset a
        // draft currently mid-flight in the first ("sending" → "pendingSend")
        // and re-send the same email. See the related fix in MacDraftService.
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        // Deliberately do NOT reset stuck "sending" records for retry. A draft
        // that was mid-flight when the app was killed may already have been
        // delivered server-side (mail.send has no idempotency key), so
        // auto-resending it risked DUPLICATE delivery to the recipient — worse
        // than a rare lost send.
        // TODO(bug-hunt): add a client idempotency key to mail.send (server
        // dedupe) so stuck "sending" drafts can be replayed safely, and surface
        // them in the UI for manual retry until then.

        // Auto-retry drafts that never completed a send attempt: "pendingSend"
        // (never reached the wire) and "failed" (the send call itself errored).
        let descriptor = FetchDescriptor<DraftRecord>(
            predicate: #Predicate { $0.syncState == "pendingSend" || $0.syncState == "failed" }
        )
        let pending = (try? context.fetch(descriptor)) ?? []
        for draft in pending {
            await saveAndSend(draft, in: context)
        }
    }

    /// Splits a comma-separated address string into Recipient values.
    private func parseRecipients(_ raw: String) -> [Recipient] {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return raw.split(separator: ",").compactMap { part in
            let email = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !email.isEmpty else { return nil }
            return Recipient(name: nil, email: email)
        }
    }

    private func recipientHeader(_ r: Recipient) -> String? {
        let email = r.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { return nil }
        // Reject characters that could break RFC 5322 framing or inject extra
        // recipients (e.g. "victim@x.com>, <attacker@y.com").
        let illegal: Set<Character> = ["<", ">", ",", ";", ":", "\"", "\r", "\n", "\t"]
        guard !email.contains(where: { illegal.contains($0) }) else { return nil }
        if let rawName = r.name?.trimmingCharacters(in: .whitespacesAndNewlines), !rawName.isEmpty {
            // Names go inside a quoted-string, but \r / \n still terminate the
            // To: header line and let an attacker inject an extra Bcc:. Drop the
            // display name when the input contains any control character — the
            // address itself is still delivered, just without a "Display Name <…>" wrapper.
            let nameInjectionChars: Set<Character> = ["\r", "\n", "\0"]
            guard !rawName.contains(where: { nameInjectionChars.contains($0) }) else {
                return email
            }
            let escaped = rawName
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\" <\(email)>"
        }
        return email
    }
}
