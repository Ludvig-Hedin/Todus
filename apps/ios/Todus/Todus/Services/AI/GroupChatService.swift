import Foundation

// MARK: - Response / Input types

struct GroupSummary: Decodable, Identifiable {
    let id: String
    let name: String
    let slug: String
    let inviteToken: String
    let aiMode: String   // "mention" | "always"
    let maxMembers: Int
    let createdAt: Date
}

struct GroupMessage: Decodable, Identifiable {
    let id: String
    let content: String
    let senderType: String   // "user" | "ai" | "system"
    let senderUserId: String?
    let senderName: String?
    let senderImage: String?
    let createdAt: Date
}

struct GroupMember: Decodable {
    let userId: String
    let role: String  // "owner" | "member"
    let joinedAt: Date
    let name: String?
    let image: String?
}

struct GroupDetails: Decodable {
    let id: String
    let name: String
    let aiMode: String
    let inviteToken: String
    let maxMembers: Int
    let members: [GroupMember]
}

struct MessagePage: Decodable {
    let messages: [GroupMessage]
    let nextCursor: String?
}

// MARK: - Service

/// Manages group chats: create, join, send messages, and poll for updates.
/// Polling interval is 5 seconds — see the TODO comment in startPolling for the
/// Durable Object WebSocket upgrade path.
@MainActor
@Observable
final class GroupChatService {
    private weak var apiClient: TodosAPIClient?

    var myGroups: [GroupSummary] = []
    var currentMessages: [GroupMessage] = []
    var currentGroupDetails: GroupDetails?
    var isPolling: Bool = false
    var errorMessage: String?

    private var pollingTask: Task<Void, Never>?

    init(apiClient: TodosAPIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Groups CRUD

    private func client() throws -> TodosAPIClient {
        guard let client = apiClient else { throw GroupChatServiceError.missingAPIClient }
        return client
    }

    func loadMyGroups() async throws {
        myGroups = try await client().trpcQuery("groups.listMine")
    }

    func createGroup(name: String, aiMode: String = "mention") async throws -> GroupSummary {
        struct Input: Encodable { let name: String; let aiMode: String }
        struct CreateResponse: Decodable { let id: String; let slug: String; let inviteToken: String }
        let response: CreateResponse = try await client().trpcMutation("groups.create", input: Input(name: name, aiMode: aiMode))
        try await loadMyGroups()
        // Match the newly created group by id from the server response
        guard let group = myGroups.first(where: { $0.id == response.id }) else {
            throw GroupChatServiceError.groupNotFound
        }
        return group
    }

    func getGroupByInvite(token: String) async throws -> GroupInviteInfo {
        struct Input: Encodable { let token: String }
        return try await client().trpcQuery("groups.getByInvite", input: Input(token: token))
    }

    func joinGroup(token: String) async throws -> String {
        struct Input: Encodable { let token: String }
        struct JoinResponse: Decodable { let groupId: String; let alreadyMember: Bool }
        let response: JoinResponse = try await client().trpcMutation("groups.join", input: Input(token: token))
        try await loadMyGroups()
        return response.groupId
    }

    func leaveGroup(groupId: String) async throws {
        struct Input: Encodable { let groupId: String }
        let _: EmptyResponse = try await client().trpcMutation("groups.leave", input: Input(groupId: groupId))
        try await loadMyGroups()
    }

    func deleteGroup(groupId: String) async throws {
        struct Input: Encodable { let groupId: String }
        let _: EmptyResponse = try await client().trpcMutation("groups.delete", input: Input(groupId: groupId))
        try await loadMyGroups()
    }

    func loadGroupDetails(groupId: String) async throws {
        struct Input: Encodable { let groupId: String }
        currentGroupDetails = try await client().trpcQuery("groups.get", input: Input(groupId: groupId))
    }

    // MARK: - Messages

    func loadMessages(groupId: String) async throws {
        struct Input: Encodable { let groupId: String; let limit: Int }
        let page: MessagePage = try await client().trpcQuery("groups.listMessages", input: Input(groupId: groupId, limit: 50))
        currentMessages = page.messages
    }

    func sendMessage(groupId: String, content: String) async throws {
        struct Input: Encodable { let groupId: String; let content: String }
        struct SendResponse: Decodable { let id: String }
        let _: SendResponse = try await client().trpcMutation("groups.sendMessage", input: Input(groupId: groupId, content: content))
    }

    // MARK: - Polling

    /// Start polling the message list every 5 seconds.
    ///
    /// TODO(realtime): Replace with a Durable Object WebSocket subscription.
    /// When DO rooms are available, connect via URLSessionWebSocketTask here,
    /// receive broadcast messages, and append them to `currentMessages` directly.
    /// Call stopPolling() before disconnecting.
    ///
    /// Polling uses adaptive intervals: 5s when the view is active, 30s when backgrounded.
    /// Call setActive(false) when the GroupChatView disappears to reduce battery drain.
    private var isViewActive: Bool = true

    func setActive(_ active: Bool) {
        isViewActive = active
    }

    private var pollingInterval: Duration {
        isViewActive ? .seconds(5) : .seconds(30)
    }

    func startPolling(groupId: String) {
        stopPolling()
        isPolling = true
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await self.loadMessages(groupId: groupId)
                } catch {
                    // Non-fatal: keep polling even if one request fails
                }
                try? await Task.sleep(for: self.pollingInterval)
            }
            await MainActor.run { self.isPolling = false }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
    }
}

// MARK: - Errors

enum GroupChatServiceError: Error, LocalizedError {
    case missingAPIClient
    case groupNotFound

    var errorDescription: String? {
        switch self {
        case .missingAPIClient: return "API client is not available."
        case .groupNotFound: return "The created group could not be found."
        }
    }
}

// MARK: - Supporting types

struct GroupInviteInfo: Decodable {
    let id: String
    let name: String
    let aiMode: String
    let memberCount: Int
    let alreadyMember: Bool
}
