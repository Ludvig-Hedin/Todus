import Foundation

/// Shared DTOs decoded from the `folders.*` tRPC endpoints.
/// Used by `MacAppServices` for `folders.list` / `folders.summary`.

struct RemoteFolder: Decodable {
    let id: String
    let name: String
    let color: String?
    let icon: String?
    let position: Int?
    let createdAt: Date
    let updatedAt: Date?
}

struct MacFolderSummaryBreakdown: Decodable {
    let tasks: Int
    let chats: Int
    let emails: Int
    let events: Int
    let docs: Int
}

struct MacFolderSummaryItem: Decodable {
    let type: String
    let id: String
    let title: String
    let subtitle: String?
    let sortAt: Date
}

struct MacFolderSummaryEntry: Decodable {
    let folder: RemoteFolder
    let itemCount: Int
    let breakdown: MacFolderSummaryBreakdown
    let recentItems: [MacFolderSummaryItem]
}

struct MacFolderSummaryResponse: Decodable {
    let folders: [MacFolderSummaryEntry]
}

struct MacFolderContentsItem: Decodable {
    let type: String
    let id: String
    let title: String
    let subtitle: String?
    let sortAt: Date
}

struct MacFolderContentsResponse: Decodable {
    let items: [MacFolderContentsItem]
    let folder: RemoteFolder
}
