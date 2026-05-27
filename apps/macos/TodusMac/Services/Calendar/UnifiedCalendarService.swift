import EventKit
import Foundation

struct UnifiedCalendarEvent: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let sourceId: String
    let calendarName: String
    let colorRed: Double
    let colorGreen: Double
    let colorBlue: Double
    let isWritable: Bool
    let providerEventId: String
    let googleCalendarId: String?
    let googleConnectionId: String?
}

extension UnifiedCalendarEvent {
    var legacyCalendarEvent: CalendarEvent {
        CalendarEvent(
            // Use the raw provider id, not the composite `apple:`/`google:` id —
            // edit/delete pass this straight to `EKEventStore.event(withIdentifier:)`,
            // which never matches a prefixed id (every grid edit/delete 404'd).
            id: providerEventId,
            title: title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            calendarColorRed: colorRed,
            calendarColorGreen: colorGreen,
            calendarColorBlue: colorBlue,
            calendarName: calendarName,
            folderID: nil,
            isWritable: isWritable
        )
    }
}

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

    func events(
        from startDate: Date,
        to endDate: Date,
        preferences: CalendarPreferences
    ) async -> [UnifiedCalendarEvent] {
        async let appleEventsTask = fetchAppleEvents(from: startDate, to: endDate, preferences: preferences)
        async let googleEventsTask = fetchGoogleEvents(from: startDate, to: endDate, preferences: preferences)
        let (apple, google) = await (appleEventsTask, googleEventsTask)
        var merged: [UnifiedCalendarEvent] = []
        merged.reserveCapacity(apple.count + google.count)
        merged.append(contentsOf: apple)
        merged.append(contentsOf: google)
        merged.sort { $0.startDate < $1.startDate }
        return merged
    }

    private func fetchAppleEvents(
        from startDate: Date,
        to endDate: Date,
        preferences: CalendarPreferences
    ) async -> [UnifiedCalendarEvent] {
        guard calendarService.canReadEvents() else { return [] }

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
                // Use the per-calendar identifier so each Apple calendar gets its
                // own sourceId (was previously collapsed to a single "unknown"
                // bucket, breaking per-source visibility toggles).
                sourceId: "\(CalendarSourceIDPrefix.apple):\(ev.calendarIdentifier ?? "unknown")",
                calendarName: ev.calendarName,
                colorRed: ev.calendarColorRed,
                colorGreen: ev.calendarColorGreen,
                colorBlue: ev.calendarColorBlue,
                isWritable: true,
                providerEventId: ev.id,
                googleCalendarId: nil,
                googleConnectionId: nil
            )
        }
    }

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

        let (events, scopeMissing) = await googleService.events(
            from: startDate,
            to: endDate,
            connections: googleConnections,
            hiddenCalendarIds: Set(preferences.hiddenCalendarIds)
        )

        // Surface scope-missing so MacCalendarView can show a reconnect banner.
        // We post regardless of whether `events` came back empty, since the
        // backend signal is independent of cached results.
        if scopeMissing {
            NotificationCenter.default.post(
                name: .todusCalendarScopeMissing,
                object: nil,
                userInfo: [:]
            )
        }

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
                  let end = parseDate(ev.endTime, isoFormatter, isoFormatterFallback, dateOnly) else {
                return nil
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
