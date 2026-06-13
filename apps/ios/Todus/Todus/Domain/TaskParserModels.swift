import Foundation

struct ParsedTaskResult: Codable, Equatable, Sendable {
    let title: String
    let dueDate: Date?
    let confidence: Double
    let originalText: String
    let suggestedFolderName: String?
    /// True when the result came from the local NLP fallback after the remote parser failed,
    /// or when the remote parser reported a low confidence score. UI can use this to soft-warn
    /// the user that fields like `dueDate` may be wrong.
    var lowConfidence: Bool = false
    /// True when `dueDate` carries a *specific time-of-day* the user stated (e.g. "2pm",
    /// "kl 13"), as opposed to a bare calendar day ("Tuesday", "tomorrow") where the time
    /// component is a synthesized default. Lets callers distinguish "timed appointment"
    /// from "deadline" when auto-classifying intent. (B-036.)
    var hasTime: Bool = false

    enum CodingKeys: String, CodingKey {
        case title, dueDate, confidence, originalText, suggestedFolderName, lowConfidence, hasTime
    }

    init(
        title: String,
        dueDate: Date?,
        confidence: Double,
        originalText: String,
        suggestedFolderName: String?,
        lowConfidence: Bool = false,
        hasTime: Bool = false
    ) {
        self.title = title
        self.dueDate = dueDate
        self.confidence = confidence
        self.originalText = originalText
        self.suggestedFolderName = suggestedFolderName
        self.lowConfidence = lowConfidence
        self.hasTime = hasTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        confidence = try container.decode(Double.self, forKey: .confidence)
        originalText = try container.decode(String.self, forKey: .originalText)
        suggestedFolderName = try container.decodeIfPresent(String.self, forKey: .suggestedFolderName)
        // lowConfidence is a client-side annotation — older payloads (and the remote API) do
        // not include it. Default to false when missing so we stay backwards-compatible.
        lowConfidence = try container.decodeIfPresent(Bool.self, forKey: .lowConfidence) ?? false
        // hasTime is likewise a client-side annotation; the remote API doesn't send it.
        // Default false when absent so a date-only remote result isn't misread as timed.
        hasTime = try container.decodeIfPresent(Bool.self, forKey: .hasTime) ?? false
    }
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
