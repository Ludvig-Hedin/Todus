import Foundation

struct GroupSummary: Decodable, Identifiable {
    let id: String
    let name: String
    let slug: String
    let inviteToken: String
    let aiMode: String
    let maxMembers: Int
    let createdAt: Date
}

struct GroupMessage: Decodable, Identifiable {
    let id: String
    let content: String
    let senderType: String
    let senderUserId: String?
    let senderName: String?
    let senderImage: String?
    let createdAt: Date
}

struct GroupMember: Decodable {
    let userId: String
    let role: String
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

@MainActor
@Observable
final class GroupChatService {
    private weak var apiClient: TodosAPIClient?

    var myGroups: [GroupSummary] = []
    var currentMessages: [GroupMessage] = []
    var currentGroupDetails: GroupDetails?
    var isPolling = false
    var errorMessage: String?

    private var pollingTask: Task<Void, Never>?

    init(apiClient: TodosAPIClient) {
        self.apiClient = apiClient
    }

    func loadMyGroups() async throws {
        guard let client = apiClient else { throw URLError(.userAuthenticationRequired) }
        myGroups = try await client.trpcQuery("groups.listMine")
    }

    func createGroup(name: String, aiMode: String = "mention") async throws -> GroupSummary {
        guard let client = apiClient else { throw URLError(.userAuthenticationRequired) }

        struct Input: Encodable {
            let name: String
            let aiMode: String
        }

        struct CreateResponse: Decodable {
            let id: String
            let slug: String
            let inviteToken: String
        }

        let createResp: CreateResponse = try await client.trpcMutation(
            "groups.create",
            input: Input(name: name, aiMode: aiMode)
        )
        try await loadMyGroups()
        // Match by the id returned from the server — don't rely on list ordering
        guard let createdGroup = myGroups.first(where: { $0.id == createResp.id }) else {
            throw URLError(.badServerResponse)
        }
        return createdGroup
    }

    func getGroupByInvite(token: String) async throws -> GroupInviteInfo {
        struct Input: Encodable {
            let token: String
        }

        guard let client = apiClient else { throw URLError(.userAuthenticationRequired) }
        return try await client.trpcQuery("groups.getByInvite", input: Input(token: token))
    }

    func joinGroup(token: String) async throws -> String {
        struct Input: Encodable {
            let token: String
        }

        struct JoinResponse: Decodable {
            let groupId: String
            let alreadyMember: Bool
        }

        guard let client = apiClient else { throw URLError(.userAuthenticationRequired) }
        let response: JoinResponse = try await client.trpcMutation(
            "groups.join",
            input: Input(token: token)
        )
        try await loadMyGroups()
        return response.groupId
    }

    func leaveGroup(groupId: String) async throws {
        struct Input: Encodable {
            let groupId: String
        }

        guard let client = apiClient else { throw URLError(.userAuthenticationRequired) }
        let _: EmptyResponse = try await client.trpcMutation(
            "groups.leave",
            input: Input(groupId: groupId)
        )
        try await loadMyGroups()
    }

    func deleteGroup(groupId: String) async throws {
        guard let client = apiClient else { throw URLError(.userAuthenticationRequired) }
        struct Input: Encodable {
            let groupId: String
        }

        let _: EmptyResponse = try await client.trpcMutation(
            "groups.delete",
            input: Input(groupId: groupId)
        )
        try await loadMyGroups()
    }

    func loadGroupDetails(groupId: String) async throws {
        guard let client = apiClient else { throw URLError(.userAuthenticationRequired) }
        struct Input: Encodable {
            let groupId: String
        }

        currentGroupDetails = try await client.trpcQuery("groups.get", input: Input(groupId: groupId))
    }

    func loadMessages(groupId: String) async throws {
        guard let client = apiClient else { throw URLError(.userAuthenticationRequired) }
        struct Input: Encodable {
            let groupId: String
            let limit: Int
        }

        let page: MessagePage = try await client.trpcQuery(
            "groups.listMessages",
            input: Input(groupId: groupId, limit: 50)
        )
        currentMessages = page.messages
    }

    func sendMessage(groupId: String, content: String) async throws {
        guard let client = apiClient else { throw URLError(.userAuthenticationRequired) }
        struct Input: Encodable {
            let groupId: String
            let content: String
        }

        struct SendResponse: Decodable {
            let id: String
        }

        let _: SendResponse = try await client.trpcMutation(
            "groups.sendMessage",
            input: Input(groupId: groupId, content: content)
        )
        try await loadMessages(groupId: groupId)
    }

    func startPolling(groupId: String) {
        stopPolling()
        isPolling = true
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                // Re-check self each iteration — service may be deallocated between polls
                guard let self else { break }
                do {
                    try await self.loadMessages(groupId: groupId)
                } catch { }
                try? await Task.sleep(for: .seconds(5))
            }
            await MainActor.run { [weak self] in
                self?.isPolling = false
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
    }
}

struct GroupInviteInfo: Decodable {
    let id: String
    let name: String
    let aiMode: String
    let memberCount: Int
    let alreadyMember: Bool
}
