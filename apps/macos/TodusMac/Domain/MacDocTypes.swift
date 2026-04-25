import Foundation

// MARK: - Flexible JSON (Tiptap / API)

/// Arbitrary JSON for doc `content` and TRPC `z.any()` payloads.
enum DocJSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([DocJSONValue])
    case object([String: DocJSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(Double.self) {
            self = .number(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode([DocJSONValue].self) {
            self = .array(v)
        } else if let v = try? c.decode([String: DocJSONValue].self) {
            self = .object(v)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "DocJSONValue: unsupported"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

// MARK: - DTOs

struct DocWorkspaceDTO: Decodable, Identifiable, Hashable, Sendable, Equatable {
    let id: String
    let userId: String
    let name: String
    let emoji: String?
    let createdAt: Date
    let updatedAt: Date
}

struct DocRecordDTO: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let userId: String
    let workspaceId: String?
    let parentId: String?
    var title: String
    var emoji: String?
    var content: DocJSONValue?
    var contentText: String?
    let order: Int
    var isStarred: Bool
    var linkedThreadId: String?
    var linkedEventId: String?
    var linkedTaskId: String?
    let createdAt: Date
    let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, userId, workspaceId, parentId, title, emoji, content, contentText, order, isStarred
        case linkedThreadId, linkedEventId, linkedTaskId, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        userId = try c.decode(String.self, forKey: .userId)
        workspaceId = try c.decodeIfPresent(String.self, forKey: .workspaceId)
        parentId = try c.decodeIfPresent(String.self, forKey: .parentId)
        title = try c.decode(String.self, forKey: .title)
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji)
        content = try c.decodeIfPresent(DocJSONValue.self, forKey: .content)
        contentText = try c.decodeIfPresent(String.self, forKey: .contentText)
        order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
        isStarred = try c.decodeIfPresent(Bool.self, forKey: .isStarred) ?? false
        linkedThreadId = try c.decodeIfPresent(String.self, forKey: .linkedThreadId)
        linkedEventId = try c.decodeIfPresent(String.self, forKey: .linkedEventId)
        linkedTaskId = try c.decodeIfPresent(String.self, forKey: .linkedTaskId)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}

struct DocListResponse: Decodable, Sendable {
    let docs: [DocRecordDTO]
}

struct DocWorkspacesListResponse: Decodable, Sendable {
    let workspaces: [DocWorkspaceDTO]
}

struct SingleDocResponse: Decodable, Sendable {
    let doc: DocRecordDTO
}

struct DocMutationResponse: Decodable, Sendable {
    let doc: DocRecordDTO
}

struct DocWorkspaceMutationResponse: Decodable, Sendable {
    let workspace: DocWorkspaceDTO
}

// MARK: - tRPC inputs

struct DocsListInput: Encodable, Sendable {
    var workspaceId: String?
    var parentId: String?

    private enum C: String, CodingKey {
        case workspaceId, parentId
    }

    /// Omits null keys so the server does not add `IS NULL` filters by mistake.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: C.self)
        if let workspaceId { try c.encode(workspaceId, forKey: .workspaceId) }
        if let parentId { try c.encode(parentId, forKey: .parentId) }
    }
}

struct DocGetInput: Encodable, Sendable {
    let id: String
}

struct DocWorkspaceCreateInput: Encodable, Sendable {
    let name: String
    var emoji: String?
}

struct DocCreateInput: Encodable, Sendable {
    var workspaceId: String?
    var parentId: String?
    var title: String?
    var emoji: String?
}

struct DocUpdateInput: Encodable, Sendable {
    let id: String
    var title: String?
    var content: DocJSONValue?
    var contentText: String?
    var emoji: String?
    var order: Int?
    var parentId: String?
    var workspaceId: String?
    var isStarred: Bool?
    var linkedThreadId: String?
    var linkedEventId: String?
    var linkedTaskId: String?
}

struct DocDeleteInput: Encodable, Sendable {
    let id: String
}

struct DocSearchResponse: Decodable, Sendable {
    let docs: [DocRecordDTO]
}

struct DocSearchInput: Encodable, Sendable {
    let query: String
}

struct DocDeleteSuccess: Decodable, Sendable {
    let success: Bool
}
