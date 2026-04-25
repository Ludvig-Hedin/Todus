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
    /// Actual calendar color RGB components (0.0–1.0), extracted from EKCalendar.cgColor
    let calendarColorRed: Double
    let calendarColorGreen: Double
    let calendarColorBlue: Double
    let calendarName: String
    let folderID: UUID?
}

/// Shared calendar service actor that manages a single EKEventStore instance.
/// Used by both the Calendar tab and the Home tab for fetching today's events.
/// Actor isolation prevents main-thread blocking.
actor CalendarService {
    private lazy var eventStore = EKEventStore()
    private let folderMapKey = "com.todus.macos.calendar.eventFolderMap"

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
    /// Deduplicates events with the same title on the same day (e.g. holidays from
    /// multiple calendar sources like iCloud + Google both showing "Långfredagen").
    func events(from startDate: Date, to endDate: Date) -> [CalendarEvent] {
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let all = eventStore.events(matching: predicate).map { $0.toCalendarEvent(folderID: folderID(for: $0.eventIdentifier)) }

        // Deduplicate all-day events only: same title on the same day can appear
        // from multiple calendar sources, but timed events should remain distinct.
        let cal = Calendar.current
        var seen = Set<String>()
        return all.filter { event in
            guard event.isAllDay else { return true }
            let dayKey = cal.startOfDay(for: event.startDate)
            let key = "\(event.title)|\(dayKey.timeIntervalSince1970)"
            return seen.insert(key).inserted
        }
    }

    /// Fetch today's events (from midnight to midnight).
    func todaysEvents() -> [CalendarEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        return events(from: startOfDay, to: endOfDay)
    }

    /// Create a new event with the given title and optional dates.
    func createEvent(title: String, startDate: Date, endDate: Date? = nil, folderID: UUID? = nil) throws {
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate ?? startDate.addingTimeInterval(3600)
        event.calendar = eventStore.defaultCalendarForNewEvents
        try eventStore.save(event, span: .thisEvent)
        if let folderID, let identifier = event.eventIdentifier {
            setFolderID(folderID, for: identifier)
        }
    }

    /// Update fields on an existing event. Nil fields are left unchanged.
    /// Throws if the event can't be found or the save fails.
    func updateEvent(
        identifier: String,
        title: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        notes: String? = nil
    ) throws {
        guard let event = eventStore.event(withIdentifier: identifier) else {
            throw NSError(
                domain: "CalendarService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Event not found"]
            )
        }
        if let title { event.title = title }
        if let startDate { event.startDate = startDate }
        if let endDate { event.endDate = endDate }
        if let notes { event.notes = notes }
        try eventStore.save(event, span: .thisEvent)
    }

    /// Delete an event by identifier. Throws if not found or save fails.
    func deleteEvent(identifier: String) throws {
        guard let event = eventStore.event(withIdentifier: identifier) else {
            throw NSError(
                domain: "CalendarService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Event not found"]
            )
        }
        try eventStore.remove(event, span: .thisEvent)
        setFolderID(nil, for: identifier)
    }

    func setFolderID(_ folderID: UUID?, for eventIdentifier: String?) {
        guard let eventIdentifier else { return }
        var map = folderMap
        if let folderID {
            map[eventIdentifier] = folderID.uuidString
        } else {
            map.removeValue(forKey: eventIdentifier)
        }
        folderMap = map
    }

    private func folderID(for eventIdentifier: String?) -> UUID? {
        guard let eventIdentifier,
              let raw = folderMap[eventIdentifier] else { return nil }
        return UUID(uuidString: raw)
    }

    private var folderMap: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: folderMapKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: folderMapKey) }
    }

    /// Remove stale entries from the folder map whose EKEvent no longer exists.
    /// Call periodically (e.g. on app foreground) to prevent unbounded growth.
    /// Skips pruning when calendar access is revoked to avoid wiping all associations.
    func pruneFolderMap() {
        guard canReadEvents() else { return }
        var map = folderMap
        let staleKeys = map.keys.filter { eventStore.event(withIdentifier: $0) == nil }
        guard !staleKeys.isEmpty else { return }
        for key in staleKeys { map.removeValue(forKey: key) }
        folderMap = map
    }
}

private extension EKEvent {
    func toCalendarEvent(folderID: UUID?) -> CalendarEvent {
        // Extract actual RGB from the calendar's CGColor, falling back to system blue
        let (r, g, b): (Double, Double, Double) = {
            guard let cgColor = calendar?.cgColor,
                  let converted = cgColor.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
                  let comps = converted.components, comps.count >= 3 else {
                return (0.35, 0.55, 0.9) // default blue
            }
            return (comps[0], comps[1], comps[2])
        }()

        return CalendarEvent(
            id: eventIdentifier ?? UUID().uuidString,
            title: title ?? "Untitled",
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            calendarColorRed: r,
            calendarColorGreen: g,
            calendarColorBlue: b,
            calendarName: calendar?.title ?? "Calendar",
            folderID: folderID
        )
    }
}
