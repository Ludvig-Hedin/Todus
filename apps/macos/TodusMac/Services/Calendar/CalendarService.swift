import EventKit
import Foundation

/// Lightweight sendable representation of a calendar event.
/// Used to safely cross actor boundaries from CalendarService to @MainActor views.
struct CalendarEvent: Identifiable, Sendable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarColor: UInt
}

/// Shared calendar service actor that manages a single EKEventStore instance.
/// Used by both the Calendar tab and the Home tab for fetching today's events.
/// Actor isolation prevents main-thread blocking.
actor CalendarService {
    private lazy var eventStore = EKEventStore()

    /// Request full access to calendar events. Returns true if authorized.
    func requestAccess() async -> Bool {
        // macOS 15+ always has requestFullAccessToEvents
        return (try? await eventStore.requestFullAccessToEvents()) ?? false
    }

    /// Current authorization status for calendar events.
    nonisolated func authorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    /// Whether the app can read calendar events for list/detail UI.
    nonisolated func canReadEvents() -> Bool {
        authorizationStatus() == .fullAccess
    }

    /// Whether the app can create events.
    nonisolated func canCreateEvents() -> Bool {
        let status = authorizationStatus()
        return status == .fullAccess || status == .writeOnly
    }

    /// Fetch events for a given date range, returned as sendable CalendarEvent structs.
    func events(from startDate: Date, to endDate: Date) -> [CalendarEvent] {
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        return eventStore.events(matching: predicate).map { $0.toCalendarEvent() }
    }

    /// Fetch today's events (from midnight to midnight).
    func todaysEvents() -> [CalendarEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        return events(from: startOfDay, to: endOfDay)
    }

    /// Create a new event with the given title and optional dates.
    func createEvent(title: String, startDate: Date, endDate: Date? = nil) throws {
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate ?? startDate.addingTimeInterval(3600)
        event.calendar = eventStore.defaultCalendarForNewEvents
        try eventStore.save(event, span: .thisEvent)
    }
}

private extension EKEvent {
    func toCalendarEvent() -> CalendarEvent {
        CalendarEvent(
            id: eventIdentifier ?? UUID().uuidString,
            title: title ?? "Untitled",
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            calendarColor: UInt(calendar?.cgColor?.hashValue ?? 0)
        )
    }
}
