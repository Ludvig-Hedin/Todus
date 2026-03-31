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
        myGroups = try await apiClient!.trpcQuery("groups.listMine")
    }

    func createGroup(name: String, aiMode: String = "mention") async throws -> GroupSummary {
        struct Input: Encodable {
            let name: String
            let aiMode: String
        }

        struct CreateResponse: Decodable {
            let id: String
            let slug: String
            let inviteToken: String
        }

        let _: CreateResponse = try await apiClient!.trpcMutation(
            "groups.create",
            input: Input(name: name, aiMode: aiMode)
        )
        try await loadMyGroups()
        guard let createdGroup = myGroups.last ?? myGroups.first else {
            throw URLError(.badServerResponse)
        }
        return createdGroup
    }

    func getGroupByInvite(token: String) async throws -> GroupInviteInfo {
        struct Input: Encodable {
            let token: String
        }

        return try await apiClient!.trpcQuery("groups.getByInvite", input: Input(token: token))
    }

    func joinGroup(token: String) async throws -> String {
        struct Input: Encodable {
            let token: String
        }

        struct JoinResponse: Decodable {
            let groupId: String
            let alreadyMember: Bool
        }

        let response: JoinResponse = try await apiClient!.trpcMutation(
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

        let _: EmptyResponse = try await apiClient!.trpcMutation(
            "groups.leave",
            input: Input(groupId: groupId)
        )
        try await loadMyGroups()
    }

    func deleteGroup(groupId: String) async throws {
        struct Input: Encodable {
            let groupId: String
        }

        let _: EmptyResponse = try await apiClient!.trpcMutation(
            "groups.delete",
            input: Input(groupId: groupId)
        )
        try await loadMyGroups()
    }

    func loadGroupDetails(groupId: String) async throws {
        struct Input: Encodable {
            let groupId: String
        }

        currentGroupDetails = try await apiClient!.trpcQuery("groups.get", input: Input(groupId: groupId))
    }

    func loadMessages(groupId: String) async throws {
        struct Input: Encodable {
            let groupId: String
            let limit: Int
        }

        let page: MessagePage = try await apiClient!.trpcQuery(
            "groups.listMessages",
            input: Input(groupId: groupId, limit: 50)
        )
        currentMessages = page.messages
    }

    func sendMessage(groupId: String, content: String) async throws {
        struct Input: Encodable {
            let groupId: String
            let content: String
        }

        struct SendResponse: Decodable {
            let id: String
        }

        let _: SendResponse = try await apiClient!.trpcMutation(
            "groups.sendMessage",
            input: Input(groupId: groupId, content: content)
        )
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
                }
                try? await Task.sleep(for: .seconds(5))
            }
            await MainActor.run {
                self.isPolling = false
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
