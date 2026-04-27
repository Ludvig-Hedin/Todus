import Foundation

public struct WidgetDataStore: Codable, Sendable {
    public var lastUpdated: Date
    public var calendar: CalendarWidgetSnapshot?
    public var tasks: TaskWidgetSnapshot?
    public var email: EmailWidgetSnapshot?
    public var overview: DailyOverviewWidgetSnapshot?
    public var insight: SmartInsightWidgetSnapshot?

    public init(
        lastUpdated: Date = Date(),
        calendar: CalendarWidgetSnapshot? = nil,
        tasks: TaskWidgetSnapshot? = nil,
        email: EmailWidgetSnapshot? = nil,
        overview: DailyOverviewWidgetSnapshot? = nil,
        insight: SmartInsightWidgetSnapshot? = nil
    ) {
        self.lastUpdated = lastUpdated
        self.calendar = calendar
        self.tasks = tasks
        self.email = email
        self.overview = overview
        self.insight = insight
    }
}

public struct CalendarWidgetSnapshot: Codable, Sendable {
    public struct Event: Codable, Identifiable, Sendable {
        public let id: String
        public let title: String
        public let startDate: Date
        public let endDate: Date
        public let isAllDay: Bool
        public let colorHex: UInt
        public let url: URL?

        public init(id: String, title: String, startDate: Date, endDate: Date, isAllDay: Bool, colorHex: UInt, url: URL?) {
            self.id = id
            self.title = title
            self.startDate = startDate
            self.endDate = endDate
            self.isAllDay = isAllDay
            self.colorHex = colorHex
            self.url = url
        }
    }
    public let upcomingEvents: [Event]

    public init(upcomingEvents: [Event]) {
        self.upcomingEvents = upcomingEvents
    }
}

public struct TaskWidgetSnapshot: Codable, Sendable {
    public struct TaskInfo: Codable, Identifiable, Sendable {
        public let id: String
        public let title: String
        public let isOverdue: Bool
        public let isUrgent: Bool

        public init(id: String, title: String, isOverdue: Bool, isUrgent: Bool) {
            self.id = id
            self.title = title
            self.isOverdue = isOverdue
            self.isUrgent = isUrgent
        }
    }
    public let todayProgress: Double
    public let topTasks: [TaskInfo]
    public let overdueCount: Int

    public init(todayProgress: Double, topTasks: [TaskInfo], overdueCount: Int) {
        self.todayProgress = todayProgress
        self.topTasks = topTasks
        self.overdueCount = overdueCount
    }
}

public struct EmailWidgetSnapshot: Codable, Sendable {
    public struct EmailInfo: Codable, Identifiable, Sendable {
        public let id: String
        public let senderName: String
        public let subject: String

        public init(id: String, senderName: String, subject: String) {
            self.id = id
            self.senderName = senderName
            self.subject = subject
        }
    }
    public let unreadImportantCount: Int
    public let topEmails: [EmailInfo]

    public init(unreadImportantCount: Int, topEmails: [EmailInfo]) {
        self.unreadImportantCount = unreadImportantCount
        self.topEmails = topEmails
    }
}

public struct DailyOverviewWidgetSnapshot: Codable, Sendable {
    public let nextEvent: CalendarWidgetSnapshot.Event?
    public let urgentTaskCount: Int
    public let unreadImportantEmailCount: Int

    public init(nextEvent: CalendarWidgetSnapshot.Event?, urgentTaskCount: Int, unreadImportantEmailCount: Int) {
        self.nextEvent = nextEvent
        self.urgentTaskCount = urgentTaskCount
        self.unreadImportantEmailCount = unreadImportantEmailCount
    }
}

public struct SmartInsightWidgetSnapshot: Codable, Sendable {
    public let insightText: String
    public let recommendedActionText: String?

    public init(insightText: String, recommendedActionText: String?) {
        self.insightText = insightText
        self.recommendedActionText = recommendedActionText
    }
}
