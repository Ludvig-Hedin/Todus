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

enum AssistantAutoSendScenario: String, Codable, CaseIterable, Identifiable, Sendable, Equatable {
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

struct AssistantQuietHours: Codable, Sendable, Equatable {
    var startHour: Int
    var endHour: Int

    static let `default` = AssistantQuietHours(startHour: 22, endHour: 7)
}

struct AssistantAutomationPolicy: Codable, Sendable, Equatable {
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

    /// Stable stored id — matches server when present; otherwise derived from type + title (same as macOS).
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
    /// LLM-generated verb-first sentence ("Reply to Sarah about Q4").
    /// Nullable — falls back to subject/title rendering when absent.
    let actionLine: String?
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
    /// Same as AssistantOpenLoop.actionLine — verb-first sentence; nullable.
    let actionLine: String?
    let threadId: String?
    let meetingId: String?
    let personEmail: String?
    let workstreamKey: String?
    let payload: [String: JSONValue]
    let evidence: [AssistantEvidence]
}

// MARK: - Briefing row display

/// What an assistant briefing row should *show* to the user.
///
/// The server gives us a `title` that's the AI's verb ("Double-check details",
/// "Research before acting") and a `summary` that's almost always the email
/// subject — i.e., the most identifying content. Showing the verb as the row's
/// headline makes every row look identical at a glance, so we flip it: subject
/// up top, AI verb demoted to caption, and a short stable badge so the user
/// can still tell Reply / Waiting / Draft apart.
struct BriefingRowDisplay: Sendable, Equatable {
    enum Badge: String, Sendable {
        case reply
        case waiting
        case draft
        case research
        case task
        case event
        case followUp
        case other

        var label: String {
            switch self {
            case .reply: return "Reply"
            case .waiting: return "Waiting"
            case .draft: return "Draft ready"
            case .research: return "Research"
            case .task: return "Task"
            case .event: return "Event"
            case .followUp: return "Follow-up"
            case .other: return "Briefing"
            }
        }
    }

    /// Primary line — the subject / identifying content. Bold and most prominent.
    let headline: String
    /// Secondary line — the AI's verb hint or rationale. Dimmer.
    let caption: String
    let badge: Badge
}

private func _briefingHeadline(summary: String, title: String) -> (headline: String, caption: String) {
    let s = summary.trimmingCharacters(in: .whitespacesAndNewlines)
    let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
    // Prefer the email subject (`summary`) as the headline. Fall back to the AI
    // verb if the server didn't populate a summary for this row.
    if !s.isEmpty {
        return (headline: s, caption: t)
    }
    return (headline: t.isEmpty ? "Email thread" : t, caption: "")
}

extension AssistantOpenLoop {
    var rowDisplay: BriefingRowDisplay {
        let (headline, caption) = _briefingHeadline(summary: summary, title: title)
        let badge: BriefingRowDisplay.Badge
        switch queue {
        case "needs_you": badge = .reply
        case "waiting_on": badge = .waiting
        case "drafts_ready": badge = .draft
        case "scheduling": badge = .followUp
        default:
            switch type {
            case "needs_reply": badge = .reply
            case "waiting_on_other": badge = .waiting
            case "draft_ready": badge = .draft
            case "research_needed": badge = .research
            case "meeting_follow_up", "follow_up": badge = .followUp
            default: badge = .other
            }
        }
        return BriefingRowDisplay(headline: headline, caption: caption, badge: badge)
    }
}

extension AssistantPreparedAction {
    var rowDisplay: BriefingRowDisplay {
        let (headline, caption) = _briefingHeadline(summary: summary, title: title)
        let badge: BriefingRowDisplay.Badge
        switch type {
        case "draft_reply": badge = .draft
        case "create_task": badge = .task
        case "create_event": badge = .event
        case "follow_up": badge = .followUp
        case "research": badge = .research
        default: badge = .other
        }
        return BriefingRowDisplay(headline: headline, caption: caption, badge: badge)
    }
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

/// High-level classification the backend assigns to a thread. Drives whether
/// we show the AI summary card and action buttons at all — non-conversational
/// kinds (verification codes, receipts, marketing, automated notifications)
/// render nothing assistant-related so the thread page stays quiet.
enum AssistantThreadKind: String, Codable, Sendable {
    case verification
    case receipt
    case marketing
    case notification
    case conversational

    /// Whether the thread is worth surfacing AI summary + action UI for.
    var isConversational: Bool { self == .conversational }
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

    /// Vendor + amount + date pulled from a receipt-style email. Lets the
    /// client render a clean inline chip instead of an empty AI card.
    struct ExtractedReceipt: Codable, Sendable, Equatable {
        let vendor: String
        let amount: String?
        let receivedAt: String?
    }

    let threadId: String
    let subject: String
    let summary: String
    /// Smart one-liner picked from the most useful signal in the thread —
    /// meeting time, first action item, first question, or summary fallback.
    /// Empty on non-conversational kinds and when nothing useful was found.
    /// Prefer this over `summary` when both are present.
    let aiLeadLine: String
    /// Optional for backward compatibility with older backends. Defaults to
    /// `.conversational` when the field is missing so existing UI keeps
    /// working until the backend is redeployed.
    let threadKind: AssistantThreadKind
    /// Verification code lifted out of the body for one-tap copy. nil on
    /// any non-verification thread or when extraction failed.
    let extractedCode: String?
    /// Receipt vendor + amount + date for receipt-style threads.
    let extractedReceipt: ExtractedReceipt?
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

    private enum CodingKeys: String, CodingKey {
        case threadId, subject, summary, aiLeadLine, threadKind, extractedCode, extractedReceipt,
             recommendation, waitingState,
             confidence, riskLevel, reason, replyNeeded, followUpNeeded,
             meetingRequested, existingDraft, actionItems, researchQueries,
             suggestedTasks, suggestedEvent, relatedTasks, relatedMeetings,
             people, openLoops, preparedActions, changedSinceLastOpen
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        threadId = try c.decode(String.self, forKey: .threadId)
        subject = try c.decode(String.self, forKey: .subject)
        summary = try c.decode(String.self, forKey: .summary)
        aiLeadLine = (try? c.decode(String.self, forKey: .aiLeadLine)) ?? ""
        threadKind = (try? c.decode(AssistantThreadKind.self, forKey: .threadKind)) ?? .conversational
        extractedCode = try c.decodeIfPresent(String.self, forKey: .extractedCode)
        extractedReceipt = try c.decodeIfPresent(ExtractedReceipt.self, forKey: .extractedReceipt)
        recommendation = try c.decode(Recommendation.self, forKey: .recommendation)
        waitingState = try c.decode(String.self, forKey: .waitingState)
        confidence = try c.decode(Double.self, forKey: .confidence)
        riskLevel = try c.decode(AssistantRiskLevel.self, forKey: .riskLevel)
        reason = try c.decode(String.self, forKey: .reason)
        replyNeeded = try c.decode(Bool.self, forKey: .replyNeeded)
        followUpNeeded = try c.decode(Bool.self, forKey: .followUpNeeded)
        meetingRequested = try c.decode(Bool.self, forKey: .meetingRequested)
        existingDraft = try c.decode(Bool.self, forKey: .existingDraft)
        actionItems = try c.decode([String].self, forKey: .actionItems)
        researchQueries = try c.decode([String].self, forKey: .researchQueries)
        suggestedTasks = try c.decode([MailAssistantSuggestedTask].self, forKey: .suggestedTasks)
        suggestedEvent = try c.decodeIfPresent(MailAssistantSuggestedEvent.self, forKey: .suggestedEvent)
        relatedTasks = try c.decode([RelatedTask].self, forKey: .relatedTasks)
        relatedMeetings = try c.decode([AssistantMeetingSummary].self, forKey: .relatedMeetings)
        people = try c.decode([AssistantPersonContext].self, forKey: .people)
        openLoops = try c.decode([AssistantOpenLoop].self, forKey: .openLoops)
        preparedActions = try c.decode([AssistantPreparedAction].self, forKey: .preparedActions)
        changedSinceLastOpen = try c.decode([String].self, forKey: .changedSinceLastOpen)
    }
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

struct MailAssistantSettingsResponse: Decodable {
    struct Settings: Decodable {
        let contextAboutYou: String
        let customPrompt: String
        /// City/country the user configured — optional for backward compat with
        /// server payloads that predate this field.
        let location: String?
        let assistantAutomationPolicy: AssistantAutomationPolicy
        /// Server-synced calendar visibility prefs. Optional for backward compat
        /// with older server payloads that predate this field.
        let calendarPreferences: CalendarPreferences?

        // Cross-device sync fields — all optional so older server payloads still decode.
        let aiCanReadTasks: Bool?
        let aiCanWriteTasks: Bool?
        let aiCanReadCalendar: Bool?
        let aiCanWriteCalendar: Bool?
        let aiCanReadEmail: Bool?
        let aiCanSendEmail: Bool?
        let accentColor: String?
        let defaultTaskView: String?
        let openOnLaunch: String?
        let resumeLastViewedPage: Bool?
        let compactSidebar: Bool?
        let showUnreadBadge: Bool?
        let focusModeEnabled: Bool?
        let groupByThread: Bool?
        let hideAppleSideGmailDuplicates: Bool?
    }

    let settings: Settings
}
