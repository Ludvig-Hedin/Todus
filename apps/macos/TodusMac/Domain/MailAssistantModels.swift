import Foundation

enum AssistantRiskLevel: String, Codable, Sendable {
    case low
    case medium
    case high
}

enum AssistantNudgeType: String, Codable, Sendable {
    case replyNeeded = "reply_needed"
    case meetingRequest = "meeting_request"
    case followUp = "follow_up"
    case draftReady = "draft_ready"
}

enum AssistantAutoSendScenario: String, Codable, CaseIterable, Identifiable, Sendable {
    case acknowledgment
    case simpleConfirmation = "simple_confirmation"
    case schedulingConfirmation = "scheduling_confirmation"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .acknowledgment: return "Acknowledgments"
        case .simpleConfirmation: return "Simple confirmations"
        case .schedulingConfirmation: return "Scheduling confirmations"
        }
    }
}

struct AssistantQuietHours: Codable, Sendable {
    var startHour: Int
    var endHour: Int

    static let `default` = AssistantQuietHours(startHour: 22, endHour: 7)
}

struct AssistantAutomationPolicy: Codable, Sendable {
    var autoSummarizeLongThreads: Bool
    var suggestTasksFromEmail: Bool
    var suggestEventsFromEmail: Bool
    var autoDraftReplies: Bool
    var smartReplyNudges: Bool
    var smartDeadlineNudges: Bool
    var assistantThreadActionsVisible: Bool
    var autoSendExperimentEnabled: Bool
    var autoSendAllowedScenarios: [AssistantAutoSendScenario]
    var autoSendQuietHours: AssistantQuietHours

    static let recommended = AssistantAutomationPolicy(
        autoSummarizeLongThreads: true,
        suggestTasksFromEmail: true,
        suggestEventsFromEmail: true,
        autoDraftReplies: true,
        smartReplyNudges: true,
        smartDeadlineNudges: true,
        assistantThreadActionsVisible: true,
        autoSendExperimentEnabled: false,
        autoSendAllowedScenarios: [.acknowledgment],
        autoSendQuietHours: .default
    )
}

struct MailAssistantSuggestedTask: Codable, Hashable, Sendable {
    let title: String
    let description: String?
    let priority: String
    let dueDate: String?
}

struct MailAssistantSuggestedEvent: Codable, Hashable, Sendable {
    let title: String
    let startAt: String?
    let endAt: String?
    let location: String?
    let notes: String?
}

struct MailAssistantThread: Codable, Sendable {
    let threadId: String
    let subject: String
    let summary: String
    let actionItems: [String]
    let suggestedTasks: [MailAssistantSuggestedTask]
    let suggestedEvent: MailAssistantSuggestedEvent?
    let replyNeeded: Bool
    let followUpNeeded: Bool
    let meetingRequested: Bool
    let draftEligible: Bool
    let existingDraft: Bool
    let riskLevel: AssistantRiskLevel
    let confidence: Double
    let reason: String
    let researchQueries: [String]
    let autoSendCandidate: Bool
    let autoSendReason: String?
    let relatedTaskCount: Int
}

struct MailAssistantNudge: Codable, Identifiable, Sendable {
    let type: AssistantNudgeType
    let title: String
    let description: String
    let count: Int
    let threadIds: [String]

    // Stable stored id — avoids id changing when title changes mid-decode
    let id: String

    enum CodingKeys: String, CodingKey {
        case type, title, description, count, threadIds, id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(AssistantNudgeType.self, forKey: .type)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decode(String.self, forKey: .description)
        count = try c.decode(Int.self, forKey: .count)
        threadIds = try c.decode([String].self, forKey: .threadIds)
        // Use server-provided id if present, otherwise derive from type + title
        if let serverId = try? c.decode(String.self, forKey: .id), !serverId.isEmpty {
            id = serverId
        } else {
            id = "\(type.rawValue)-\(title)"
        }
    }
}

struct MailAssistantDraftResult: Codable, Sendable {
    let draftId: String?
    let created: Bool
    let reason: String
    let preview: String?
}

struct MailAssistantSettingsResponse: Decodable, Sendable {
    struct Settings: Decodable, Sendable {
        let contextAboutYou: String
        let customPrompt: String
        let assistantAutomationPolicy: AssistantAutomationPolicy
    }

    let settings: Settings
}
