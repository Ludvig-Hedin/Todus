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
    let folderID: UUID?
}

/// Shared calendar service actor that manages a single EKEventStore instance.
/// Used by both the Calendar tab and the Home tab for fetching today's events.
/// Actor isolation prevents main-thread blocking (same pattern as RemindersStorageActor).
actor CalendarService {
    private lazy var eventStore = EKEventStore()
    private let folderMapKey = "com.todus.calendar.eventFolderMap"

    /// Request full access to calendar events. Returns true if authorized.
    func requestAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            return (try? await eventStore.requestFullAccessToEvents()) ?? false
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    /// Current authorization status for calendar events.
    nonisolated func authorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    /// Whether the app can read calendar events for list/detail UI.
    nonisolated func canReadEvents() -> Bool {
        let status = authorizationStatus()
        if #available(iOS 17.0, *) {
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }

    /// Whether the app can create events. On iOS 17+, write-only access is enough.
    nonisolated func canCreateEvents() -> Bool {
        let status = authorizationStatus()
        if #available(iOS 17.0, *) {
            return status == .fullAccess || status == .writeOnly
        } else {
            return status == .authorized
        }
    }

    /// Fetch events for a given date range, returned as sendable CalendarEvent structs.
    func events(from startDate: Date, to endDate: Date) -> [CalendarEvent] {
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        return eventStore.events(matching: predicate).map { $0.toCalendarEvent(folderID: folderID(for: $0.eventIdentifier)) }
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
        get {
            UserDefaults.standard.dictionary(forKey: folderMapKey) as? [String: String] ?? [:]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: folderMapKey)
        }
    }
}

private extension EKEvent {
    func toCalendarEvent(folderID: UUID?) -> CalendarEvent {
        CalendarEvent(
            id: eventIdentifier ?? UUID().uuidString,
            title: title ?? "Untitled",
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            // Extract a stable packed-RGB UInt from the calendar color.
            // hashValue is unstable across launches; use the actual RGB components instead.
            calendarColor: {
                guard let cgColor = calendar?.cgColor,
                      let converted = cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
                      let comps = converted.components, comps.count >= 3 else {
                    return 0x5B8DEF // default blue
                }
                let r = UInt(max(0, min(255, Int(comps[0] * 255))))
                let g = UInt(max(0, min(255, Int(comps[1] * 255))))
                let b = UInt(max(0, min(255, Int(comps[2] * 255))))
                return (r << 16) | (g << 8) | b
            }(),
            folderID: folderID
        )
    }
}
