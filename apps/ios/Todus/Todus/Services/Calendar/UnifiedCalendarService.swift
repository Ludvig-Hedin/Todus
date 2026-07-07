import EventKit
import Foundation

/// Sendable, source-agnostic event used by all calendar views.
struct UnifiedCalendarEvent: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    /// Composite source id (`apple:{...}` or `google:{connId}:{calId}`).
    let sourceId: String
    /// Human-readable calendar name (e.g. "Work").
    let calendarName: String
    /// 0–1 RGB.
    let colorRed: Double
    let colorGreen: Double
    let colorBlue: Double
    /// Whether the user can edit this event in-place.
    let isWritable: Bool
    /// For Apple events: the underlying `eventIdentifier` for opening in EventKit.
    /// For Google events: the GCal `event.id`.
    let providerEventId: String
    /// For Google events: the Google calendar id (e.g. "primary"). nil for Apple.
    let googleCalendarId: String?
    /// For Google events: connection id. nil for Apple.
    let googleConnectionId: String?
}

extension UnifiedCalendarEvent {
    /// View as the legacy `CalendarEvent` for code paths that haven't migrated.
    var legacyCalendarEvent: CalendarEvent {
        let packed = (UInt(max(0, min(255, Int(colorRed * 255)))) << 16)
                   | (UInt(max(0, min(255, Int(colorGreen * 255)))) << 8)
                   | UInt(max(0, min(255, Int(colorBlue * 255))))
        return CalendarEvent(
            id: id,
            title: title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            calendarColor: packed,
            calendarColorRed: colorRed,
            calendarColorGreen: colorGreen,
            calendarColorBlue: colorBlue,
            calendarName: calendarName,
            folderID: nil,
            calendarId: nil
        )
    }
}

/// Aggregates events across Apple (EventKit) and Google (backend tRPC) sources,
/// applying the user's per-calendar visibility prefs.
///
/// Owned by AppServices and used by the Calendar tab + Home tab. Stateless
/// from the caller's perspective — every call re-fetches.
@MainActor
final class UnifiedCalendarService {
    private let calendarService: CalendarService
    private let googleService: GoogleCalendarService
    private let connectionsService: ConnectionsService

    init(
        calendarService: CalendarService,
        googleService: GoogleCalendarService,
        connectionsService: ConnectionsService
    ) {
        self.calendarService = calendarService
        self.googleService = googleService
        self.connectionsService = connectionsService
    }

    /// Fetch events across every visible calendar source for the given window.
    /// Apple and Google fetch in parallel; Google duplicates are removed when
    /// `preferGoogleOverAppleDuplicates` is true and the Apple calendar's source
    /// title matches one of the connected Google account emails.
    func events(
        from startDate: Date,
        to endDate: Date,
        preferences: CalendarPreferences
    ) async -> [UnifiedCalendarEvent] {
        async let appleEventsTask = fetchAppleEvents(
            from: startDate,
            to: endDate,
            preferences: preferences
        )
        async let googleEventsTask = fetchGoogleEvents(
            from: startDate,
            to: endDate,
            preferences: preferences
        )

        let (apple, google) = await (appleEventsTask, googleEventsTask)

        // Sort merged results by start; stable ordering helps the timeline UI.
        var merged: [UnifiedCalendarEvent] = []
        merged.reserveCapacity(apple.count + google.count)
        merged.append(contentsOf: apple)
        merged.append(contentsOf: google)
        merged.sort { $0.startDate < $1.startDate }
        return merged
    }

    // MARK: - Apple

    private func fetchAppleEvents(
        from startDate: Date,
        to endDate: Date,
        preferences: CalendarPreferences
    ) async -> [UnifiedCalendarEvent] {
        let canRead = calendarService.canReadEvents()
        guard canRead else { return [] }

        // Compute the effective hidden-Apple set: explicit user hides + any
        // Apple calendars whose underlying source matches a Google connection
        // email (when preferGoogleOverAppleDuplicates is on, the default).
        var hidden = Set(preferences.hiddenCalendarIds.filter { $0.hasPrefix("\(CalendarSourceIDPrefix.apple):") })

        if preferences.preferGoogleOverAppleDuplicates {
            let googleEmails: Set<String> = Set(connectionsService.connections
                .filter { $0.providerId == "google" }
                .map { $0.email.lowercased() })
            if !googleEmails.isEmpty {
                let metadata = await calendarService.appleCalendarSourceMetadata()
                for (calId, info) in metadata where info.sourceType == .calDAV {
                    if googleEmails.contains(info.sourceTitle.lowercased()) {
                        hidden.insert("\(CalendarSourceIDPrefix.apple):\(calId)")
                    }
                }
            }
        }

        let raw = await calendarService.events(from: startDate, to: endDate, hiddenCalendarIds: hidden)
        return raw.map { ev in
            UnifiedCalendarEvent(
                id: "\(CalendarSourceIDPrefix.apple):\(ev.id)",
                title: ev.title,
                startDate: ev.startDate,
                endDate: ev.endDate,
                isAllDay: ev.isAllDay,
                sourceId: "\(CalendarSourceIDPrefix.apple):\(ev.calendarId ?? "unknown")",
                calendarName: ev.calendarName,
                colorRed: ev.calendarColorRed,
                colorGreen: ev.calendarColorGreen,
                colorBlue: ev.calendarColorBlue,
                isWritable: true,
                // Strip the `#<start>` occurrence suffix so EventKit lookups
                // via providerEventId keep working for recurring events.
                providerEventId: CalendarEvent.ekEventIdentifier(fromEventId: ev.id),
                googleCalendarId: nil,
                googleConnectionId: nil
            )
        }
    }

    // MARK: - Google

    private func fetchGoogleEvents(
        from startDate: Date,
        to endDate: Date,
        preferences: CalendarPreferences
    ) async -> [UnifiedCalendarEvent] {
        let googleConnections = connectionsService.connections.filter { $0.providerId == "google" }
        guard !googleConnections.isEmpty else { return [] }

        if googleService.isStale {
            await googleService.refresh(googleConnections: googleConnections)
        }

        // TODO(bug-hunt): If a connection's calendar list isn't loaded yet (cold start /
        // isStale race not fully resolved by the refresh above), GoogleCalendarService.events
        // falls back to fetching `primary` and ignores hiddenCalendarIds, so a hidden primary
        // can briefly reappear. Ensure refresh() populates sources for every connection
        // before events() runs, or make the primary fallback respect hiddenCalendarIds.
        let (events, _) = await googleService.events(
            from: startDate,
            to: endDate,
            connections: googleConnections,
            hiddenCalendarIds: Set(preferences.hiddenCalendarIds)
        )

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFormatterFallback = ISO8601DateFormatter()
        isoFormatterFallback.formatOptions = [.withInternetDateTime]
        let dateOnly = DateFormatter()
        dateOnly.calendar = Calendar(identifier: .gregorian)
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.dateFormat = "yyyy-MM-dd"

        return events.compactMap { ev -> UnifiedCalendarEvent? in
            guard let start = parseDate(ev.startTime, isoFormatter, isoFormatterFallback, dateOnly),
                  var end = parseDate(ev.endTime, isoFormatter, isoFormatterFallback, dateOnly) else {
                return nil
            }
            // Google's all-day `end.date` is EXCLUSIVE (a one-day event runs
            // 07-07 → 07-08) while EventKit's all-day end is inclusive, so
            // unadjusted Google events painted one extra day in every view.
            // Pull the end back one second (to 23:59:59 of the true last day),
            // matching EventKit's inclusive semantics.
            if ev.allDay {
                let adjusted = end.addingTimeInterval(-1)
                if adjusted > start { end = adjusted }
            }
            let (r, g, b) = Self.rgbFromHex(ev.color)
            return UnifiedCalendarEvent(
                id: "\(CalendarSourceIDPrefix.google):\(ev.connectionId):\(ev.calendarId):\(ev.id)",
                title: ev.title,
                startDate: start,
                endDate: end,
                isAllDay: ev.allDay,
                sourceId: "\(CalendarSourceIDPrefix.google):\(ev.connectionId):\(ev.calendarId)",
                calendarName: ev.connectionEmail,
                colorRed: r,
                colorGreen: g,
                colorBlue: b,
                // We don't know the per-calendar accessRole at event time;
                // start conservative — write/edit gated separately by source.
                isWritable: false,
                providerEventId: ev.id,
                googleCalendarId: ev.calendarId,
                googleConnectionId: ev.connectionId
            )
        }
    }

    private func parseDate(
        _ s: String,
        _ a: ISO8601DateFormatter,
        _ b: ISO8601DateFormatter,
        _ c: DateFormatter
    ) -> Date? {
        if let d = a.date(from: s) { return d }
        if let d = b.date(from: s) { return d }
        if let d = c.date(from: s) { return d }
        return nil
    }

    private static func rgbFromHex(_ hex: String) -> (Double, Double, Double) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return (0.357, 0.553, 0.937) }
        return (
            Double((value >> 16) & 0xFF) / 255.0,
            Double((value >> 8) & 0xFF) / 255.0,
            Double(value & 0xFF) / 255.0
        )
    }
}
