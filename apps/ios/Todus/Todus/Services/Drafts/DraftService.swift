import Foundation
import SwiftData

/// Thin wrapper around the backend's drafts router.
/// Used by the AI chat's InlineComposeCard for autosave + send.
@MainActor
final class DraftService {
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
        context.insert(draft)
        try? context.save()

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
    /// Also resets any "sending" records back to "pendingSend" — these were in-flight when the app last crashed.
    func flushPending(in context: ModelContext) async {
        // Reset stuck "sending" records so they get retried
        let stuckDescriptor = FetchDescriptor<DraftRecord>(
            predicate: #Predicate { $0.syncState == "sending" }
        )
        let stuck = (try? context.fetch(stuckDescriptor)) ?? []
        for draft in stuck {
            draft.syncState = "pendingSend"
        }
        if !stuck.isEmpty { try? context.save() }

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
        if let rawName = r.name?.trimmingCharacters(in: .whitespacesAndNewlines), !rawName.isEmpty {
            let escaped = rawName
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\" <\(email)>"
        }
        return email
    }
}
