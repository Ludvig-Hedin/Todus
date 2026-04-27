import Foundation
import SwiftData

@Model
final class FolderRecord: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String?
    var iconName: String?
    var position: Int = 0
    var createdAt: Date
    var updatedAt: Date = Date()

    var cachedItemCount: Int = 0
    var cachedBreakdownData: Data?
    var cachedRecentItemsData: Data?

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String? = nil,
        iconName: String? = nil,
        position: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.iconName = iconName
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct FolderTypeBreakdown: Codable, Equatable {
    var tasks: Int
    var chats: Int
    var emails: Int
    var events: Int
    var docs: Int

    static let zero = FolderTypeBreakdown(tasks: 0, chats: 0, emails: 0, events: 0, docs: 0)

    var total: Int { tasks + chats + emails + events + docs }
}

struct FolderRecentItem: Codable, Equatable, Identifiable {
    var type: String
    var id: String
    var title: String
    var subtitle: String?
    var sortAt: Date
}

extension FolderRecord {
    var breakdown: FolderTypeBreakdown {
        guard let data = cachedBreakdownData,
              let decoded = try? JSONDecoder().decode(FolderTypeBreakdown.self, from: data)
        else { return .zero }
        return decoded
    }

    var recentItems: [FolderRecentItem] {
        guard let data = cachedRecentItemsData,
              let decoded = try? JSONDecoder().decode([FolderRecentItem].self, from: data)
        else { return [] }
        return decoded
    }

    func setBreakdown(_ value: FolderTypeBreakdown) {
        cachedBreakdownData = try? JSONEncoder().encode(value)
    }

    func setRecentItems(_ value: [FolderRecentItem]) {
        cachedRecentItemsData = try? JSONEncoder().encode(value)
    }
}
