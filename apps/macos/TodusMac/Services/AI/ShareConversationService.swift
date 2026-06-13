import Foundation

struct ShareCreateInput: Encodable {
    let conversationId: String
    let title: String
    let password: String?
    let expiresInDays: String
}

struct ShareCreateResponse: Decodable {
    let id: String
    let slug: String
    let title: String
    let expiresAt: Date?
    let passwordProtected: Bool
}

struct ShareGetInput: Encodable {
    let slug: String
    let password: String?
}

/// Decodes JSON of unknown shape so one structured message field (e.g. an
/// Anthropic content-block array) can't fail the entire share payload — which
/// previously surfaced valid shared conversations as "Link not available".
private enum ShareJSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: ShareJSONValue])
    case array([ShareJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode([String: ShareJSONValue].self) { self = .object(v); return }
        if let v = try? c.decode([ShareJSONValue].self) { self = .array(v); return }
        self = .null
    }

    /// Flattens to display text — plain strings pass through; content-block
    /// arrays/objects contribute their `text` fields.
    var displayText: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): return String(b)
        case .null: return ""
        case .array(let arr): return arr.map { $0.displayText }.joined()
        case .object(let obj):
            if case .string(let t)? = obj["text"] { return t }
            if let content = obj["content"] { return content.displayText }
            // Don't dump arbitrary nested values — that leaks envelope metadata
            // (role/type/id…) into the displayed text and in nondeterministic
            // order. Only fall back to non-metadata fields, sorted for stability.
            let metadataKeys: Set<String> = [
                "type", "role", "id", "name", "index",
                "cache_control", "citations", "tool_use_id"
            ]
            return obj
                .filter { !metadataKeys.contains($0.key) }
                .sorted { $0.key < $1.key }
                .map { $0.value.displayText }
                .joined()
        }
    }
}

struct ShareGetResponse: Decodable {
    let passwordRequired: Bool?
    let title: String?
    let createdAt: Date?
    let messages: [[String: String]]?

    private enum CodingKeys: String, CodingKey {
        case passwordRequired, title, createdAt, messages
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        passwordRequired = try c.decodeIfPresent(Bool.self, forKey: .passwordRequired)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        // Decode each message flexibly, then project to the [role/content: String]
        // shape the view expects so a structured `content` can't throw.
        if let raw = try c.decodeIfPresent([[String: ShareJSONValue]].self, forKey: .messages) {
            messages = raw.map { dict in
                var out: [String: String] = [:]
                for (key, value) in dict { out[key] = value.displayText }
                return out
            }
        } else {
            messages = nil
        }
    }
}

struct ShareImportResponse: Decodable {
    let newConversationId: String
}

struct ShareListItem: Decodable, Identifiable {
    let id: String
    let slug: String
    let title: String
    let passwordProtected: Bool
    let expiresAt: Date?
    let revokedAt: Date?
    let createdAt: Date
    let conversationId: String
    let status: String
}

@MainActor
@Observable
final class ShareConversationService {
    private weak var apiClient: TodosAPIClient?

    init(apiClient: TodosAPIClient) {
        self.apiClient = apiClient
    }

    func createShare(_ input: ShareCreateInput) async throws -> ShareCreateResponse {
        guard let client = apiClient else { throw URLError(.userAuthenticationRequired) }
        return try await client.trpcMutation("sharing.create", input: input)
    }

    func getShare(slug: String, password: String? = nil) async throws -> ShareGetResponse {
        guard let client = apiClient else { throw URLError(.userAuthenticationRequired) }
        return try await client.trpcQuery(
            "sharing.get",
            input: ShareGetInput(slug: slug, password: password)
        )
    }

    func importShare(slug: String, password: String? = nil) async throws -> ShareImportResponse {
        guard let client = apiClient else { throw URLError(.userAuthenticationRequired) }
        return try await client.trpcMutation(
            "sharing.import",
            input: ShareGetInput(slug: slug, password: password)
        )
    }

    func listMyShares() async throws -> [ShareListItem] {
        guard let client = apiClient else { throw URLError(.userAuthenticationRequired) }
        return try await client.trpcQuery("sharing.listMine")
    }

    func revokeShare(id: String) async throws {
        guard let client = apiClient else { throw URLError(.userAuthenticationRequired) }
        struct Input: Encodable {
            let id: String
        }

        let _: EmptyResponse = try await client.trpcMutation(
            "sharing.revoke",
            input: Input(id: id)
        )
    }
}
