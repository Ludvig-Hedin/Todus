import Foundation
import SwiftData

@Model
final class DraftRecord {
    @Attribute(.unique) var id: String
    var toRecipients: String      // comma-separated email addresses
    var ccRecipients: String
    var subject: String
    var htmlBody: String
    var threadId: String?         // non-nil for replies/forwards
    var connectionId: String      // which email account to send from
    var createdAt: Date
    var syncState: String         // "pendingSend" | "sending" | "failed"

    init(
        id: String = UUID().uuidString,
        toRecipients: String,
        ccRecipients: String = "",
        subject: String,
        htmlBody: String,
        threadId: String?,
        connectionId: String
    ) {
        self.id = id
        self.toRecipients = toRecipients
        self.ccRecipients = ccRecipients
        self.subject = subject
        self.htmlBody = htmlBody
        self.threadId = threadId
        self.connectionId = connectionId
        self.createdAt = Date()
        self.syncState = "pendingSend"
    }
}
