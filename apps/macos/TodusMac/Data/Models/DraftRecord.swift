import Foundation
import SwiftData

@Model
final class DraftRecord {
    @Attribute(.unique) var id: String
    var toRecipients: String
    var ccRecipients: String
    /// Comma-separated Bcc recipients. Default `""` keeps backward compatibility with rows
    /// persisted before this field existed — SwiftData will hydrate them with the default.
    var bccRecipients: String = ""
    var subject: String
    var htmlBody: String
    var threadId: String?
    var connectionId: String
    var createdAt: Date
    var syncState: String   // "pendingSend" | "sending" | "failed"
    /// Optional JSON-encoded attachment payload (array of `{filename, mimeType, base64}`).
    /// Stored as a string so the SwiftData migration is forward-compatible — older rows
    /// hydrate with `nil` and just skip the attachments leg of the send pipeline.
    var attachmentsJSON: String? = nil

    init(
        id: String = UUID().uuidString,
        toRecipients: String,
        ccRecipients: String = "",
        bccRecipients: String = "",
        subject: String,
        htmlBody: String,
        threadId: String?,
        connectionId: String,
        attachmentsJSON: String? = nil
    ) {
        self.id = id
        self.toRecipients = toRecipients
        self.ccRecipients = ccRecipients
        self.bccRecipients = bccRecipients
        self.subject = subject
        self.htmlBody = htmlBody
        self.threadId = threadId
        self.connectionId = connectionId
        self.createdAt = Date()
        self.syncState = "pendingSend"
        self.attachmentsJSON = attachmentsJSON
    }
}
