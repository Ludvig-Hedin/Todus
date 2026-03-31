import Foundation

// MARK: - Response / Input types

struct ShareCreateInput: Encodable {
    let conversationId: String
    let title: String
    let password: String?
    let expiresInDays: String // "never" | "1" | "7" | "30"
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

/// Flexible response — passwordRequired may be true before messages are revealed
struct ShareGetResponse: Decodable {
    let passwordRequired: Bool?
    let title: String?
    let createdAt: Date?
    let messages: [[String: String]]?
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
    let status: String  // "active" | "expired" | "revoked"
}

// MARK: - Service

/// Manages creation, retrieval, and management of shared AI conversation links.
/// All API calls go through TodosAPIClient using the tRPC pattern.
@MainActor
@Observable
final class ShareConversationService {
    private weak var apiClient: TodosAPIClient?

    init(apiClient: TodosAPIClient) {
        self.apiClient = apiClient
    }

    /// Create a new share link for a conversation owned by the authenticated user.
    func createShare(_ input: ShareCreateInput) async throws -> ShareCreateResponse {
        try await apiClient!.trpcMutation("sharing.create", input: input)
    }

    /// Fetch the snapshot for a share slug.
    /// Returns `passwordRequired: true` if the link is protected and no password is provided.
    func getShare(slug: String, password: String? = nil) async throws -> ShareGetResponse {
        try await apiClient!.trpcQuery("sharing.get", input: ShareGetInput(slug: slug, password: password))
    }

    /// Import a shared conversation as a new conversation owned by the current user.
    func importShare(slug: String, password: String? = nil) async throws -> ShareImportResponse {
        struct Input: Encodable { let slug: String; let password: String? }
        return try await apiClient!.trpcMutation("sharing.import", input: Input(slug: slug, password: password))
    }

    /// List all share links created by the current user.
    func listMyShares() async throws -> [ShareListItem] {
        try await apiClient!.trpcQuery("sharing.listMine")
    }

    /// Immediately revoke a share link so it can no longer be accessed.
    func revokeShare(id: String) async throws {
        struct Input: Encodable { let id: String }
        let _: EmptyResponse = try await apiClient!.trpcMutation("sharing.revoke", input: Input(id: id))
    }
}
