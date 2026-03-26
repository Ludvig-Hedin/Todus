import Foundation

struct ParsedTaskResult: Codable, Equatable, Sendable {
    let title: String
    let dueDate: Date?
    let confidence: Double
    let originalText: String
    let suggestedFolderName: String?
}

struct ParseTasksRequest: Codable, Sendable {
    let rawText: String
    let localeIdentifier: String
    let timeZoneIdentifier: String
    let installID: String
    let preferredModels: [String]
}

struct ParseTasksResponse: Codable, Sendable {
    let tasks: [ParsedTaskResult]
}

struct SyncTasksRequest: Codable, Sendable {
    let installID: String
    let userID: String?
    let mutations: [SyncMutation]
}

struct SyncTasksResponse: Codable, Sendable {
    let syncedTaskIDs: [UUID]
}

struct UpgradeAnonymousUserRequest: Codable, Sendable {
    let anonymousID: String
    let authenticatedUserID: String
}
