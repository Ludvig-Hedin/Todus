import Foundation
import SwiftData

/// Local mirror of the backend `folder_item` polymorphic table.
/// Used to track which emails / events / docs belong to a folder so the
/// folder detail view can render mixed-type contents offline.
@Model
final class FolderItemRecord: Identifiable {
    @Attribute(.unique) var id: UUID
    var folder: FolderRecord?
    /// One of "email", "event", "doc". Tasks and chats use their own column on TaskRecord / AIConversationRecord.
    var itemType: String
    /// Remote identifier for the underlying entity (Gmail thread ID, EKEvent ID, doc ID).
    var itemId: String
    var titleCache: String?
    var subtitleCache: String?
    var position: Int = 0
    var createdAt: Date

    init(
        id: UUID = UUID(),
        folder: FolderRecord? = nil,
        itemType: String,
        itemId: String,
        titleCache: String? = nil,
        subtitleCache: String? = nil,
        position: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.folder = folder
        self.itemType = itemType
        self.itemId = itemId
        self.titleCache = titleCache
        self.subtitleCache = subtitleCache
        self.position = position
        self.createdAt = createdAt
    }
}

enum FolderItemKind: String, CaseIterable, Codable {
    case task
    case chat
    case email
    case event
    case doc
}

/// Value type used by views to render a folder's contents as a mixed list.
/// Built from TaskRecord / AIConversationRecord / FolderItemRecord by the service layer.
enum FolderContentItem: Identifiable, Equatable {
    case task(TaskRecord)
    case chat(id: String, title: String, updatedAt: Date)
    case email(threadId: String, subject: String, sender: String?, date: Date)
    case event(eventId: String, title: String, start: Date)
    case doc(docId: String, title: String, updatedAt: Date)

    var id: String {
        switch self {
        case .task(let t): return "task-\(t.id.uuidString)"
        case .chat(let id, _, _): return "chat-\(id)"
        case .email(let id, _, _, _): return "email-\(id)"
        case .event(let id, _, _): return "event-\(id)"
        case .doc(let id, _, _): return "doc-\(id)"
        }
    }

    var kind: FolderItemKind {
        switch self {
        case .task: return .task
        case .chat: return .chat
        case .email: return .email
        case .event: return .event
        case .doc: return .doc
        }
    }

    var sortDate: Date {
        switch self {
        case .task(let t): return t.updatedAt
        case .chat(_, _, let d): return d
        case .email(_, _, _, let d): return d
        case .event(_, _, let s): return s
        case .doc(_, _, let d): return d
        }
    }

    var title: String {
        switch self {
        case .task(let t): return t.title
        case .chat(_, let title, _): return title
        case .email(_, let subject, _, _): return subject
        case .event(_, let title, _): return title
        case .doc(_, let title, _): return title
        }
    }

    static func == (lhs: FolderContentItem, rhs: FolderContentItem) -> Bool {
        switch (lhs, rhs) {
        case let (.task(left), .task(right)):
            return left.id == right.id
                && left.title == right.title
                && left.taskDescription == right.taskDescription
                && left.status == right.status
                && left.priority == right.priority
                && left.completed == right.completed
                && left.updatedAt == right.updatedAt
                && left.dueDate == right.dueDate
        case let (.chat(leftID, leftTitle, leftUpdatedAt), .chat(rightID, rightTitle, rightUpdatedAt)):
            return leftID == rightID
                && leftTitle == rightTitle
                && leftUpdatedAt == rightUpdatedAt
        case let (.email(leftID, leftSubject, leftSender, leftDate), .email(rightID, rightSubject, rightSender, rightDate)):
            return leftID == rightID
                && leftSubject == rightSubject
                && leftSender == rightSender
                && leftDate == rightDate
        case let (.event(leftID, leftTitle, leftStart), .event(rightID, rightTitle, rightStart)):
            return leftID == rightID
                && leftTitle == rightTitle
                && leftStart == rightStart
        case let (.doc(leftID, leftTitle, leftUpdatedAt), .doc(rightID, rightTitle, rightUpdatedAt)):
            return leftID == rightID
                && leftTitle == rightTitle
                && leftUpdatedAt == rightUpdatedAt
        default:
            return false
        }
    }
}
