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
        try await apiClient!.trpcMutation("sharing.create", input: input)
    }

    func getShare(slug: String, password: String? = nil) async throws -> ShareGetResponse {
        try await apiClient!.trpcQuery(
            "sharing.get",
            input: ShareGetInput(slug: slug, password: password)
        )
    }

    func importShare(slug: String, password: String? = nil) async throws -> ShareImportResponse {
        struct Input: Encodable {
            let slug: String
            let password: String?
        }

        return try await apiClient!.trpcMutation(
            "sharing.import",
            input: Input(slug: slug, password: password)
        )
    }

    func listMyShares() async throws -> [ShareListItem] {
        try await apiClient!.trpcQuery("sharing.listMine")
    }

    func revokeShare(id: String) async throws {
        struct Input: Encodable {
            let id: String
        }

        let _: EmptyResponse = try await apiClient!.trpcMutation(
            "sharing.revoke",
            input: Input(id: id)
        )
    }
}
