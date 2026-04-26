import Foundation
import SwiftData

/// Thin wrapper around the backend's drafts router for macOS.
/// Mirrors iOS DraftService — used by the AI chat's InlineComposeCard for autosave + send.
@MainActor
final class MacDraftService {
    private let api: TodosAPIClient

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
    }

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
        context.insert(draft)
        try? context.save()
        draft.syncState = "sending"
        try? context.save()
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
            let payload = DraftPayload(
                to: toList,
                cc: ccList,
                bcc: [],
                subject: draft.subject,
                body: draft.htmlBody
            )
            try await send(draftId: nil, payload: payload)
            context.delete(draft)
            try? context.save()
        } catch {
            draft.syncState = "failed"
            try? context.save()
        }
    }

    /// Re-attempts all pending or failed draft records. Call on network reconnect.
    func flushPending(in context: ModelContext) async {
        let descriptor = FetchDescriptor<DraftRecord>(
            predicate: #Predicate { $0.syncState == "pendingSend" || $0.syncState == "failed" }
        )
        let pending = (try? context.fetch(descriptor)) ?? []
        for draft in pending { await saveAndSend(draft, in: context) }
    }
}
