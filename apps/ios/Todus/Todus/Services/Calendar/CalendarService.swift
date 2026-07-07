import CryptoKit
import EventKit
import Foundation

extension Notification.Name {
    /// Posted after `requestAccess()` completes so UI (e.g. `MainTabView`) can re-check
    /// `EKEventStore.authorizationStatus` while the app stays in the foreground.
    static let todusCalendarAuthorizationDidChange = Notification.Name("TodusCalendarAuthorizationDidChange")
}

/// Lightweight sendable representation of a calendar event.
/// Used to safely cross actor boundaries from CalendarService to @MainActor views.
struct CalendarEvent: Identifiable, Sendable, Equatable {
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
    /// EKCalendar.calendarIdentifier for Apple events (nil for non-Apple sources).
    /// Used to build a real per-source id instead of a synthetic "apple:unknown".
    let calendarId: String?

    /// Strips the `#<start>` occurrence suffix appended to recurring-event ids,
    /// returning the raw EventKit `eventIdentifier` usable for store lookups.
    static func ekEventIdentifier(fromEventId id: String) -> String {
        guard let hash = id.firstIndex(of: "#") else { return id }
        return String(id[..<hash])
    }
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
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = (try? await eventStore.requestFullAccessToEvents()) ?? false
        } else {
            granted = await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
        await MainActor.run {
            NotificationCenter.default.post(name: .todusCalendarAuthorizationDidChange, object: nil)
        }
        return granted
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
    /// Pass a non-empty `hiddenCalendarIds` to exclude specific Apple calendars
    /// (composite ids of the form `apple:{EKCalendar.calendarIdentifier}`).
    /// An empty set fetches across all calendars (the legacy behavior).
    func events(
        from startDate: Date,
        to endDate: Date,
        hiddenCalendarIds: Set<String> = []
    ) -> [CalendarEvent] {
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
        return eventStore.events(matching: predicate).map { $0.toCalendarEvent(folderID: folderID(for: $0.eventIdentifier)) }
    }

    /// Enumerate every Apple calendar the user has on the device, mapped to
    /// our unified `CalendarSource` model. Drives the "Calendars" picker UI
    /// and the Settings → Calendar Accounts list. Cheap (in-memory EventKit lookup).
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

    /// The `EKSource.title` (e.g. "iCloud", "Gmail") + `EKSource.sourceType` for
    /// each Apple calendar. Used by `UnifiedCalendarService` to dedupe Apple
    /// calendars whose underlying account is also a Todus Google connection.
    func appleCalendarSourceMetadata() -> [String: (sourceType: EKSourceType, sourceTitle: String)] {
        var out: [String: (sourceType: EKSourceType, sourceTitle: String)] = [:]
        for cal in eventStore.calendars(for: .event) {
            out[cal.calendarIdentifier] = (cal.source.sourceType, cal.source.title)
        }
        return out
    }

    /// Fetch upcoming events starting from today's midnight for `days` calendar days.
    func upcomingEvents(days: Int = 7) -> [CalendarEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: days, to: start) ?? start
        return events(from: start, to: end)
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
    /// `attachmentFilenames` are written to the event's notes since EKEvent
    /// has no first-class attachment storage — the underlying files remain
    /// in AttachmentService for any future use.
    /// `targetCalendarId` is the EKCalendar.calendarIdentifier to save into;
    /// `nil` falls back to the user's default calendar for new events.
    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date? = nil,
        folderID: UUID? = nil,
        location: String? = nil,
        attachmentFilenames: [String] = [],
        targetCalendarId: String? = nil
    ) throws {
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate ?? startDate.addingTimeInterval(3600)
        event.calendar = resolveCalendar(forTargetId: targetCalendarId)
        if let location, !location.isEmpty {
            event.location = location
        }
        if !attachmentFilenames.isEmpty {
            let listing = attachmentFilenames.map { "• \($0)" }.joined(separator: "\n")
            event.notes = "Attachments:\n\(listing)"
        }
        try eventStore.save(event, span: .thisEvent)
        invalidateTodayCache()
        if let folderID, let identifier = event.eventIdentifier {
            setFolderID(folderID, for: identifier)
        }
    }

    /// Resolve a target Apple calendar, falling back to the user's default for
    /// new events when the requested identifier isn't found / isn't writable.
    private func resolveCalendar(forTargetId targetId: String?) -> EKCalendar? {
        let defaultCal = eventStore.defaultCalendarForNewEvents
        guard let targetId, !targetId.isEmpty else { return defaultCal }
        // Strip the `apple:` prefix if a composite id was passed in.
        let stripped: String = {
            let prefix = "\(CalendarSourceIDPrefix.apple):"
            return targetId.hasPrefix(prefix) ? String(targetId.dropFirst(prefix.count)) : targetId
        }()
        if let cal = eventStore.calendars(for: .event).first(where: { $0.calendarIdentifier == stripped }),
           cal.allowsContentModifications {
            return cal
        }
        // Silent fallback can leave the user staring at "I picked Work but it
        // saved to Personal" with no explanation. Log so the bug is reproducible
        // — callers may want to surface a friendlier alert in the future.
        AppLogger.shared.log("[CalendarService] target calendar '\(stripped)' missing or read-only — falling back to defaultCalendarForNewEvents (\(defaultCal?.title ?? "nil"))")
        return defaultCal
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
        // Callers pass `CalendarEvent.id`, which carries a `#<start>` suffix for
        // recurring occurrences — normalize to the raw identifier so the map
        // matches the bare `eventIdentifier` keys used on read.
        let key = CalendarEvent.ekEventIdentifier(fromEventId: eventIdentifier)
        var map = folderMap
        if let folderID {
            map[key] = folderID.uuidString
        } else {
            map.removeValue(forKey: key)
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
            // Clamp to 0...1 — converting a P3/extended color to sRGB can produce
            // out-of-gamut components that render as over-saturated colors via Color(red:…).
            let clamp = { (v: CGFloat) in Double(max(0, min(1, v))) }
            return (clamp(comps[0]), clamp(comps[1]), clamp(comps[2]))
        }()

        // Every occurrence of a recurring event shares the same
        // `eventIdentifier`, so a window query returns N events with identical
        // ids — SwiftUI `ForEach`/`Identifiable` then collapse or mis-anchor
        // rows. Disambiguate occurrences with a `#<start>` suffix; consumers
        // that need the raw EventKit identifier strip it via
        // `CalendarEvent.ekEventIdentifier(fromEventId:)`.
        let occurrenceID: String? = eventIdentifier.map { base in
            (hasRecurrenceRules || isDetached)
                ? "\(base)#\(Int(startDate.timeIntervalSinceReferenceDate))"
                : base
        }
        return CalendarEvent(
            // EventKit usually returns a stable `eventIdentifier`; when it
            // doesn't (very rare — unsaved events surfaced through some APIs)
            // build a deterministic id from the calendar/title/start so
            // `Identifiable` views like ScrollViewReader and ForEach don't
            // see new ids every refresh and lose anchors/animations.
            id: occurrenceID ?? Self.derivedID(
                calendarTitle: calendar?.title,
                title: title,
                start: startDate,
                end: endDate
            ),
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
            folderID: folderID,
            calendarId: calendar?.calendarIdentifier
        )
    }

    /// Stable fallback identifier: hash of calendar+title+start+end. Same
    /// across refreshes AND across process restarts (Swift's `Hasher` is
    /// process-seeded, so it would give different IDs on each cold launch and
    /// break SwiftUI identity continuity for events without an EKEvent
    /// identifier).
    private static func derivedID(
        calendarTitle: String?,
        title: String?,
        start: Date,
        end: Date
    ) -> String {
        let payload = "\(calendarTitle ?? "")|\(title ?? "")|\(start.timeIntervalSinceReferenceDate)|\(end.timeIntervalSinceReferenceDate)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
        return "derived-\(hex.prefix(16))"
    }
}
