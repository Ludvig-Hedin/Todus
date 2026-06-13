import EventKit
import Foundation

/// Lightweight sendable representation of a calendar event.
/// Used to safely cross actor boundaries from CalendarService to @MainActor views.
struct CalendarEvent: Identifiable, Sendable {
    /// SwiftUI `Identifiable` identity. For events built from `UnifiedCalendarEvent`
    /// this is the namespaced composite id (`apple:…` / `google:…`) so an Apple and a
    /// Google event that happen to share a raw provider id don't collide in a `ForEach`.
    /// For events built directly from `CalendarService` (single-provider EventKit) it
    /// defaults to the raw provider id.
    let id: String
    /// Raw provider event id used for EKEventStore lookups + the folder map. NEVER the
    /// composite id — `EKEventStore.event(withIdentifier:)` only matches the raw id, and
    /// the folder map is keyed by the raw `EKEvent.eventIdentifier`.
    let providerEventId: String
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
    /// Event location string (`EKEvent.location`). Optional; nil/empty when the
    /// event has no location. Carried so the edit sheet can prefill it instead of
    /// discarding a user-typed location on save.
    let location: String?
    /// Event notes/body (`EKEvent.notes`). Optional; nil/empty when absent.
    let notes: String?
    /// Underlying `EKEvent.calendar.calendarIdentifier`, when available. Used by
    /// `UnifiedCalendarService` to build per-source ids that survive dedup so each
    /// Apple calendar (Home, Work, Holidays, etc.) can be toggled independently.
    /// Optional + defaulted to nil to preserve back-compat with existing call sites.
    let calendarIdentifier: String?
    /// Whether the underlying calendar accepts edits. Google (backend) events are
    /// read-only here — editing routes through EKEventStore and would 404, so the
    /// UI must show a read-only summary instead of an editor. Defaults to true so
    /// existing Apple/EventKit call sites keep their writable behavior.
    let isWritable: Bool

    init(
        id: String,
        providerEventId: String? = nil,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendarColorRed: Double,
        calendarColorGreen: Double,
        calendarColorBlue: Double,
        calendarName: String,
        folderID: UUID?,
        location: String? = nil,
        notes: String? = nil,
        calendarIdentifier: String? = nil,
        isWritable: Bool = true
    ) {
        self.id = id
        // Default to the raw `id` when no explicit provider id is given — preserves
        // behavior for direct CalendarService construction where `id` IS the raw id.
        self.providerEventId = providerEventId ?? id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.calendarColorRed = calendarColorRed
        self.calendarColorGreen = calendarColorGreen
        self.calendarColorBlue = calendarColorBlue
        self.calendarName = calendarName
        self.folderID = folderID
        self.location = location
        self.notes = notes
        self.calendarIdentifier = calendarIdentifier
        self.isWritable = isWritable
    }
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
    /// Pass a non-empty `hiddenCalendarIds` (composite ids `apple:{...}`) to
    /// exclude specific calendars.
    func events(
        from startDate: Date,
        to endDate: Date,
        hiddenCalendarIds: Set<String> = []
    ) -> [CalendarEvent] {
        let calendars: [EKCalendar]? = {
            guard !hiddenCalendarIds.isEmpty else { return nil }
            let prefix = "\(CalendarSourceIDPrefix.apple):"
            let hiddenAppleIds: Set<String> = Set(hiddenCalendarIds.compactMap { id in
                id.hasPrefix(prefix) ? String(id.dropFirst(prefix.count)) : nil
            })
            if hiddenAppleIds.isEmpty { return nil }
            return eventStore.calendars(for: .event)
                .filter { !hiddenAppleIds.contains($0.calendarIdentifier) }
        }()
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        let all = eventStore.events(matching: predicate).compactMap { $0.toCalendarEvent(folderID: folderID(for: $0.eventIdentifier)) }

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

    /// Enumerate every Apple calendar the user has on the machine.
    func listAppleSources() -> [CalendarSource] {
        let defaultId = eventStore.defaultCalendarForNewEvents?.calendarIdentifier
        return eventStore.calendars(for: .event).map { cal in
            var source = CalendarSource.from(appleCalendar: cal)
            if cal.calendarIdentifier == defaultId {
                source = CalendarSource(
                    id: source.id,
                    kind: source.kind,
                    displayName: source.displayName,
                    accountEmail: source.accountEmail,
                    colorRed: source.colorRed,
                    colorGreen: source.colorGreen,
                    colorBlue: source.colorBlue,
                    isWritable: source.isWritable,
                    isPrimary: true
                )
            }
            return source
        }
    }

    /// Per-Apple-calendar source metadata used by `UnifiedCalendarService` for
    /// dedup against connected Gmail accounts.
    func appleCalendarSourceMetadata() -> [String: (sourceType: EKSourceType, sourceTitle: String)] {
        var out: [String: (sourceType: EKSourceType, sourceTitle: String)] = [:]
        for cal in eventStore.calendars(for: .event) {
            out[cal.calendarIdentifier] = (cal.source.sourceType, cal.source.title)
        }
        return out
    }

    /// Fetch today's events (from midnight to midnight).
    func todaysEvents() -> [CalendarEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        return events(from: startOfDay, to: endOfDay)
    }

    /// Create a new event with the given title and optional dates.
    /// Pass `calendarIdentifier` (an `EKCalendar.calendarIdentifier`) to target a
    /// specific Apple calendar; otherwise the user's `defaultCalendarForNewEvents`
    /// is used. Unknown identifiers also fall back to the default.
    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date? = nil,
        location: String? = nil,
        notes: String? = nil,
        folderID: UUID? = nil,
        calendarIdentifier: String? = nil
    ) throws {
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate ?? startDate.addingTimeInterval(3600)
        // Empty strings are skipped so a blank field doesn't write an empty location/notes.
        if let location, !location.isEmpty { event.location = location }
        if let notes, !notes.isEmpty { event.notes = notes }
        if let calendarIdentifier,
           let target = eventStore.calendars(for: .event)
               .first(where: { $0.calendarIdentifier == calendarIdentifier }) {
            event.calendar = target
        } else {
            event.calendar = eventStore.defaultCalendarForNewEvents
        }
        do {
            try eventStore.save(event, span: .thisEvent)
        } catch {
            AppLogger.shared.log("[CalendarService] createEvent save failed: \(error)")
            throw error
        }
        if let folderID, let identifier = event.eventIdentifier {
            setFolderID(folderID, for: identifier)
        }
    }

    /// Update fields on an existing event. Nil fields are left unchanged.
    /// Throws if the event can't be found or the save fails.
    /// Pass `calendarIdentifier` to move the event to a different Apple calendar;
    /// nil leaves the existing calendar untouched. Unknown identifiers are
    /// ignored (no reassignment) rather than silently moving to default.
    func updateEvent(
        identifier: String,
        title: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        location: String? = nil,
        notes: String? = nil,
        calendarIdentifier: String? = nil
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
        if let location { event.location = location }
        if let notes { event.notes = notes }
        if let calendarIdentifier,
           calendarIdentifier != event.calendar?.calendarIdentifier,
           let target = eventStore.calendars(for: .event)
               .first(where: { $0.calendarIdentifier == calendarIdentifier }) {
            event.calendar = target
        }
        do {
            try eventStore.save(event, span: .thisEvent)
        } catch {
            AppLogger.shared.log("[CalendarService] updateEvent save failed (id=\(identifier)): \(error)")
            throw error
        }
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
        do {
            try eventStore.remove(event, span: .thisEvent)
        } catch {
            AppLogger.shared.log("[CalendarService] deleteEvent remove failed (id=\(identifier)): \(error)")
            throw error
        }
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
    func toCalendarEvent(folderID: UUID?) -> CalendarEvent? {
        // `startDate`/`endDate` are implicitly-unwrapped (`Date!`) and can be nil
        // for a corrupt EventKit record — skip those rather than crashing on the
        // non-optional `CalendarEvent` init.
        guard let startDate, let endDate else { return nil }
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
            folderID: folderID,
            location: location,
            notes: notes,
            calendarIdentifier: calendar?.calendarIdentifier
        )
    }
}
