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
    var briefingEnabled: Bool
    var showHomeBriefing: Bool
    var trackWaitingOnThreads: Bool
    var peopleMemoryEnabled: Bool
    var batchApprovalEnabled: Bool
    var workdayStartHour: Int
    var workdayEndHour: Int
    var excludedSenderPatterns: [String]
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
        briefingEnabled: true,
        showHomeBriefing: true,
        trackWaitingOnThreads: true,
        peopleMemoryEnabled: true,
        batchApprovalEnabled: false,
        workdayStartHour: 8,
        workdayEndHour: 18,
        excludedSenderPatterns: [],
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

    init(
        type: AssistantNudgeType,
        title: String,
        description: String,
        count: Int,
        threadIds: [String],
        id: String? = nil
    ) {
        self.type = type
        self.title = title
        self.description = description
        self.count = count
        self.threadIds = threadIds
        self.id = (id?.isEmpty == false ? id : nil) ?? "\(type.rawValue)-\(title)"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            type: try c.decode(AssistantNudgeType.self, forKey: .type),
            title: try c.decode(String.self, forKey: .title),
            description: try c.decode(String.self, forKey: .description),
            count: try c.decode(Int.self, forKey: .count),
            threadIds: try c.decode([String].self, forKey: .threadIds),
            id: try? c.decode(String.self, forKey: .id)
        )
    }
}

struct MailAssistantDraftResult: Codable, Sendable {
    let draftId: String?
    let created: Bool
    let reason: String
    let preview: String?
}

struct AssistantEvidence: Codable, Hashable, Sendable {
    let kind: String
    let id: String
    let label: String?
}

struct AssistantOpenLoop: Codable, Identifiable, Sendable {
    let id: String
    let type: String
    let queue: String
    let status: String
    let title: String
    let summary: String
    let confidence: Double
    let reason: String
    let suggestedActionLabel: String?
    let threadId: String?
    let meetingId: String?
    let personEmail: String?
    let workstreamKey: String?
    let lastReviewedAt: String?
    let snoozedUntil: String?
    let evidence: [AssistantEvidence]
}

struct AssistantPreparedAction: Codable, Identifiable, Sendable {
    let id: String
    let type: String
    let status: String
    let title: String
    let summary: String
    let confidence: Double
    let reason: String
    let preview: String?
    let threadId: String?
    let meetingId: String?
    let personEmail: String?
    let workstreamKey: String?
    let payload: [String: JSONValue]
    let evidence: [AssistantEvidence]
}

struct AssistantPersonContext: Codable, Identifiable, Sendable {
    var id: String { email }
    let email: String
    let displayName: String
    let company: String?
    let relationshipSummary: String
    let unresolvedAsks: [String]
    let promises: [String]
    let recentThreadIds: [String]
    let recentMeetingIds: [String]
    let recentTaskIds: [String]
    let openLoopCount: Int
    let lastInteractionAt: String?
}

struct AssistantMeetingSummary: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let startsAt: String
    let status: String
    let aiSummaryReady: Bool
}

struct AssistantChangeFeedItem: Codable, Identifiable, Sendable {
    let id: String
    let type: String
    let title: String
    let summary: String
    let occurredAt: String
}

struct AssistantBriefPriority: Codable, Identifiable, Sendable {
    let kind: String
    let id: String
    let title: String
    let summary: String
}

struct AssistantBriefing: Codable, Sendable {
    struct Today: Codable, Sendable {
        struct TopTask: Codable, Sendable {
            let id: String
            let title: String
            let dueDate: String?
            let priority: String
        }

        let nextEvent: AssistantMeetingSummary?
        let topTask: TopTask?
        let urgentReply: AssistantOpenLoop?
    }

    let generatedAt: String
    let today: Today
    let topPriorities: [AssistantBriefPriority]
    let needsYou: [AssistantOpenLoop]
    let waitingOn: [AssistantOpenLoop]
    let prepared: [AssistantPreparedAction]
    let upcomingMeetings: [AssistantMeetingSummary]
    let changedSinceLastTime: [AssistantChangeFeedItem]
}

struct AssistantThreadContext: Codable, Sendable {
    struct Recommendation: Codable, Sendable {
        let label: String
        let reason: String
    }

    struct RelatedTask: Codable, Identifiable, Sendable {
        let id: String
        let title: String
        let status: String
        let dueDate: String?
    }

    let threadId: String
    let subject: String
    let summary: String
    let recommendation: Recommendation
    let waitingState: String
    let confidence: Double
    let riskLevel: AssistantRiskLevel
    let reason: String
    let replyNeeded: Bool
    let followUpNeeded: Bool
    let meetingRequested: Bool
    let existingDraft: Bool
    let actionItems: [String]
    let researchQueries: [String]
    let suggestedTasks: [MailAssistantSuggestedTask]
    let suggestedEvent: MailAssistantSuggestedEvent?
    let relatedTasks: [RelatedTask]
    let relatedMeetings: [AssistantMeetingSummary]
    let people: [AssistantPersonContext]
    let openLoops: [AssistantOpenLoop]
    let preparedActions: [AssistantPreparedAction]
    let changedSinceLastOpen: [String]
}

struct AssistantPreparedActionApplyResult: Codable, Sendable {
    let success: Bool
    let actionType: String
    let createdTaskIds: [String]?
    let createdEventId: String?
    let draftId: String?
    let researchQueries: [String]?
}

enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct MailAssistantSettingsResponse: Decodable, Sendable {
    struct Settings: Decodable, Sendable {
        let contextAboutYou: String
        let customPrompt: String
        let assistantAutomationPolicy: AssistantAutomationPolicy
        /// Server-synced calendar visibility prefs. Optional for backward compat.
        let calendarPreferences: CalendarPreferences?
    }

    let settings: Settings
}
