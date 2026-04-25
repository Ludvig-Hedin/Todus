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
    /// RGB components (0.0–1.0) for SwiftUI Color construction
    let calendarColorRed: Double
    let calendarColorGreen: Double
    let calendarColorBlue: Double
    let calendarName: String
    let folderID: UUID?
}

/// Shared calendar service actor that manages a single EKEventStore instance.
/// Used by both the Calendar tab and the Home tab for fetching today's events.
/// Actor isolation prevents main-thread blocking (same pattern as RemindersStorageActor).
actor CalendarService {
    private lazy var eventStore = EKEventStore()
    private let folderMapKey = "com.todus.calendar.eventFolderMap"
    private var lastFolderPruneAt: Date?
    private let folderPruneInterval: TimeInterval = 6 * 60 * 60
    private let folderPrunePastWindow: TimeInterval = 60 * 60 * 24 * 365
    private let folderPruneFutureWindow: TimeInterval = 60 * 60 * 24 * 365
    private var cachedTodayDate: Date?
    private var cachedTodayEvents: [CalendarEvent] = []
    private var cachedTodayFetchedAt: Date?
    private let todayCacheInterval: TimeInterval = 30

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
        let trace = PerformanceTrace.beginInterval(
            PerformanceTrace.calendarEventsFetch,
            message: "CalendarService.events begin"
        )
        defer {
            PerformanceTrace.endInterval(
                PerformanceTrace.calendarEventsFetch,
                trace,
                message: "CalendarService.events end"
            )
        }
        scheduleFolderMapPruneIfNeeded()
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        return eventStore.events(matching: predicate).map { $0.toCalendarEvent(folderID: folderID(for: $0.eventIdentifier)) }
    }

    /// Fetch today's events (from midnight to midnight).
    /// All-day timezone correctness: `Calendar.current.startOfDay(for:)` returns local-time
    /// midnight in the user's current timezone, and `byAdding: .day, value: 1` does proper
    /// DST-aware arithmetic (it's not a flat 86400s addition). EKEventStore's
    /// `predicateForEvents(withStart:end:)` then matches any event that *overlaps* this
    /// range — including all-day events stored with floating timezones — which is the
    /// behaviour we want. Do not switch this to UTC boundaries: that would drop all-day
    /// events for users east of UTC and double-count them west of UTC.
    func todaysEvents() -> [CalendarEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        if cachedTodayDate == startOfDay,
           let cachedTodayFetchedAt,
           Date().timeIntervalSince(cachedTodayFetchedAt) < todayCacheInterval {
            return cachedTodayEvents
        }
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        let events = events(from: startOfDay, to: endOfDay)
        cachedTodayDate = startOfDay
        cachedTodayFetchedAt = Date()
        cachedTodayEvents = events
        return events
    }

    /// Create a new event with the given title and optional dates.
    func createEvent(title: String, startDate: Date, endDate: Date? = nil, folderID: UUID? = nil) throws {
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate ?? startDate.addingTimeInterval(3600)
        event.calendar = eventStore.defaultCalendarForNewEvents
        try eventStore.save(event, span: .thisEvent)
        invalidateTodayCache()
        if let folderID, let identifier = event.eventIdentifier {
            setFolderID(folderID, for: identifier)
        }
    }

    /// Fetch the underlying EKEvent by identifier — used by SwiftUI views to present EKEventViewController.
    func ekEvent(for identifier: String) -> EKEvent? {
        eventStore.event(withIdentifier: identifier)
    }

    /// Sendable event snapshot for inline AI chat cards (avoids passing `EKEvent` off the actor).
    func chatDisplayEvent(for identifier: String) -> CalendarEvent? {
        guard let ev = eventStore.event(withIdentifier: identifier) else { return nil }
        return ev.toCalendarEvent(folderID: folderID(for: ev.eventIdentifier))
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
            throw NSError(domain: "CalendarService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Event not found"])
        }
        if let title { event.title = title }
        if let startDate { event.startDate = startDate }
        if let endDate { event.endDate = endDate }
        if let notes { event.notes = notes }
        if event.endDate < event.startDate {
            throw NSError(
                domain: "CalendarService",
                code: 422,
                userInfo: [NSLocalizedDescriptionKey: "Event end date must not be before start date"]
            )
        }
        try eventStore.save(event, span: .thisEvent)
        invalidateTodayCache()
    }

    /// Delete an event by identifier. Throws if not found or save fails.
    func deleteEvent(identifier: String) throws {
        guard let event = eventStore.event(withIdentifier: identifier) else {
            throw NSError(domain: "CalendarService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Event not found"])
        }
        try eventStore.remove(event, span: .thisEvent)
        setFolderID(nil, for: identifier)
        invalidateTodayCache()
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
        invalidateTodayCache()
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

    private func scheduleFolderMapPruneIfNeeded() {
        let now = Date()
        if let lastPrune = lastFolderPruneAt, now.timeIntervalSince(lastPrune) <= folderPruneInterval {
            return
        }
        lastFolderPruneAt = now
        pruneStaleFolderMapEntries(referenceDate: now)
    }

    private func pruneStaleFolderMapEntries(referenceDate: Date) {
        guard canReadEvents() else { return }
        let trace = PerformanceTrace.beginInterval(
            PerformanceTrace.calendarFolderPrune,
            message: "CalendarService.pruneFolderMap begin"
        )
        defer {
            PerformanceTrace.endInterval(
                PerformanceTrace.calendarFolderPrune,
                trace,
                message: "CalendarService.pruneFolderMap end"
            )
        }

        let startDate = referenceDate.addingTimeInterval(-folderPrunePastWindow)
        let endDate = referenceDate.addingTimeInterval(folderPruneFutureWindow)

        let existingIdentifiers = Set(
            eventStore
                .events(
                    matching: eventStore.predicateForEvents(
                        withStart: startDate,
                        end: endDate,
                        calendars: nil
                    )
                )
                .compactMap(\.eventIdentifier)
        )

        guard !existingIdentifiers.isEmpty else { return }

        let currentMap = folderMap
        let prunedMap = currentMap.filter { existingIdentifiers.contains($0.key) }
        if prunedMap.count != currentMap.count {
            folderMap = prunedMap
        }
    }

    private func invalidateTodayCache() {
        cachedTodayDate = nil
        cachedTodayFetchedAt = nil
        cachedTodayEvents = []
    }
}

private extension EKEvent {
    func toCalendarEvent(folderID: UUID?) -> CalendarEvent {
        // Extract RGB components from the calendar color for both packed UInt and individual doubles
        let (r, g, b): (Double, Double, Double) = {
            guard let cgColor = calendar?.cgColor,
                  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let converted = cgColor.converted(to: colorSpace, intent: .defaultIntent, options: nil),
                  let comps = converted.components, comps.count >= 3 else {
                // Default blue (0x5B8DEF)
                return (0.357, 0.553, 0.937)
            }
            return (comps[0], comps[1], comps[2])
        }()

        return CalendarEvent(
            id: eventIdentifier ?? UUID().uuidString,
            title: title ?? "Untitled",
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            calendarColor: (UInt(max(0, min(255, Int(r * 255)))) << 16)
                         | (UInt(max(0, min(255, Int(g * 255)))) << 8)
                         | UInt(max(0, min(255, Int(b * 255)))),
            calendarColorRed: r,
            calendarColorGreen: g,
            calendarColorBlue: b,
            calendarName: calendar?.title ?? "Calendar",
            folderID: folderID
        )
    }
}
