import Foundation
import Observation

extension Notification.Name {
    /// Posted when a Google Calendar request returns `scopeMissing: true`,
    /// so UI surfaces (calendar tab, settings, event composer) can show a
    /// non-blocking "Reconnect to enable editing" banner.
    static let todusCalendarScopeMissing = Notification.Name("TodusCalendarScopeMissing")
}

/// User-info key on `todusCalendarScopeMissing` notifications carrying the
/// affected `connectionId: String?` (nil means "any/unknown — show generic banner").
let TodusCalendarScopeMissingConnectionIdKey = "connectionId"

/// Backend-shaped calendar event from `calendar.eventsMulti`.
struct GoogleCalendarEvent: Decodable, Sendable {
    let id: String
    let title: String
    let description: String?
    let location: String?
    let startTime: String
    let endTime: String
    let allDay: Bool
    let color: String
    let htmlLink: String?
    let organizer: String?
    let isOrganizer: Bool
    let connectionId: String
    let connectionEmail: String
    let connectionColor: String?
    let calendarId: String
}

/// Backend-shaped calendar list entry from `calendar.calendars`.
struct GoogleCalendarListEntry: Decodable, Sendable {
    let id: String
    let name: String
    let color: String
    let primary: Bool
}

/// Service for fetching Google Calendar data through our backend tRPC routes.
///
/// Calls `connections.list` (Google only) + `calendar.calendars` per connection
/// to enumerate sources, and `calendar.eventsMulti` to fetch events from many
/// connections in one round-trip.
///
/// Caches the per-connection calendar list in memory + UserDefaults so the
/// picker can render instantly on cold start, and refreshes in the background.
@MainActor
@Observable
final class GoogleCalendarService {
    private let api: TodosAPIClient
    private let defaults = UserDefaults.standard

    /// Map of `connectionId -> [CalendarSource]` for that connection.
    private(set) var sourcesByConnection: [String: [CalendarSource]] = [:]
    /// Connection IDs whose calendar fetch reported `scopeMissing: true`.
    private(set) var scopeMissingConnectionIds: Set<String> = []
    /// Last successful refresh time, for TTL.
    private var lastRefreshAt: Date?
    private let refreshTTL: TimeInterval = 5 * 60

    private enum Keys {
        static let cachedSources = "Todus.googleCalendarSourcesV1"
    }

    /// Cached snapshot keyed by connection id, used to render the picker
    /// before the first network refresh completes. Codable wrapper.
    private struct CachedSources: Codable {
        let connectionId: String
        let connectionEmail: String
        let entries: [Entry]
        struct Entry: Codable {
            let calendarId: String
            let name: String
            let color: String
            let accessRole: String
            let primary: Bool
        }
    }

    init(api: TodosAPIClient) {
        self.api = api
        loadCacheFromDisk()
    }

    /// Returns true when there's no fresh data and the caller should kick a refresh.
    var isStale: Bool {
        guard let lastRefreshAt else { return true }
        return Date().timeIntervalSince(lastRefreshAt) > refreshTTL
    }

    /// Sources for the given connection, in display order (primary first).
    func sources(forConnectionId id: String) -> [CalendarSource] {
        (sourcesByConnection[id] ?? []).sorted { lhs, rhs in
            if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    /// Refresh the per-connection calendar lists. Safe to call repeatedly;
    /// fetches in parallel.
    func refresh(googleConnections: [ConnectionAccount]) async {
        guard !googleConnections.isEmpty else {
            sourcesByConnection = [:]
            scopeMissingConnectionIds = []
            saveCacheToDisk()
            lastRefreshAt = Date()
            return
        }

        var newSources: [String: [CalendarSource]] = [:]
        var newScopeMissing: Set<String> = []

        await withTaskGroup(of: (String, [CalendarSource], Bool).self) { group in
            for conn in googleConnections {
                group.addTask { [weak self] in
                    guard let self else { return (conn.id, [], false) }
                    return await self.fetchCalendars(for: conn)
                }
            }
            for await (connectionId, sources, scopeMissing) in group {
                newSources[connectionId] = sources
                if scopeMissing { newScopeMissing.insert(connectionId) }
            }
        }

        sourcesByConnection = newSources
        scopeMissingConnectionIds = newScopeMissing
        lastRefreshAt = Date()
        saveCacheToDisk()

        if !newScopeMissing.isEmpty {
            // Surface the first one — UI dedupes if multiple come in quick succession.
            if let connId = newScopeMissing.first {
                NotificationCenter.default.post(
                    name: .todusCalendarScopeMissing,
                    object: nil,
                    userInfo: [TodusCalendarScopeMissingConnectionIdKey: connId]
                )
            }
        }
    }

    /// Fetch events across all Google connections in parallel via the
    /// backend's `calendar.eventsMulti`. Honors `hiddenCalendarIds` by
    /// excluding any matching `google:{connId}:{calId}` ids from the per-connection
    /// fetch list. Connections with no remaining visible calendars are skipped.
    func events(
        from startDate: Date,
        to endDate: Date,
        connections: [ConnectionAccount],
        hiddenCalendarIds: Set<String>
    ) async -> (events: [GoogleCalendarEvent], scopeMissing: Bool) {
        guard !connections.isEmpty else { return ([], false) }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Build the per-connection calendarIds map. Connection with no entry =>
        // backend defaults to `primary`. Pass an explicit empty array to skip.
        var calendarIds: [String: [String]] = [:]
        for conn in connections {
            let sources = self.sources(forConnectionId: conn.id)
            if sources.isEmpty {
                // Don't constrain — backend will fetch from `primary` for safety.
                continue
            }
            let visible = sources
                .filter { !hiddenCalendarIds.contains($0.id) }
                .compactMap { source -> String? in
                    let prefix = "\(CalendarSourceIDPrefix.google):\(conn.id):"
                    guard source.id.hasPrefix(prefix) else { return nil }
                    return String(source.id.dropFirst(prefix.count))
                }
            calendarIds[conn.id] = visible // may be []; backend skips
        }

        struct Input: Encodable {
            let timeMin: String
            let timeMax: String
            let connectionIds: [String]
            let calendarIds: [String: [String]]
        }
        struct Response: Decodable {
            let events: [GoogleCalendarEvent]
            let scopeMissing: Bool
        }

        let input = Input(
            timeMin: isoFormatter.string(from: startDate),
            timeMax: isoFormatter.string(from: endDate),
            connectionIds: connections.map(\.id),
            calendarIds: calendarIds
        )

        do {
            let response: Response = try await api.trpcQuery("calendar.eventsMulti", input: input)
            if response.scopeMissing {
                NotificationCenter.default.post(
                    name: .todusCalendarScopeMissing,
                    object: nil,
                    userInfo: [TodusCalendarScopeMissingConnectionIdKey: NSNull()]
                )
            }
            return (response.events, response.scopeMissing)
        } catch {
            print("[GoogleCalendarService] eventsMulti failed: \(error)")
            return ([], false)
        }
    }

    // MARK: - Mutations

    struct CreatedEventResult: Sendable {
        let scopeMissing: Bool
        let eventId: String?
    }

    /// Create an event on a Google calendar via `calendar.createEvent`.
    /// Note: the backend resolves the active connection from the request's
    /// `connectionId` cookie/header, so the caller is responsible for ensuring
    /// the right connection is active before invoking. (This mirrors how
    /// `calendar.events` works today.)
    func createEvent(
        calendarId: String,
        summary: String,
        description: String?,
        location: String?,
        start: Date,
        end: Date,
        allDay: Bool,
        attendees: [(email: String, displayName: String?)] = []
    ) async throws -> CreatedEventResult {
        struct EventDateTime: Encodable {
            let dateTime: String?
            let date: String?
            let timeZone: String?
        }
        struct Attendee: Encodable {
            let email: String
            let displayName: String?
        }
        struct Input: Encodable {
            let calendarId: String
            let summary: String
            let description: String?
            let location: String?
            let start: EventDateTime
            let end: EventDateTime
            let attendees: [Attendee]?
        }
        struct Response: Decodable {
            let scopeMissing: Bool
            struct Event: Decodable { let id: String }
            let event: Event?
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let dateOnly: (Date) -> String = { d in
            let fmt = DateFormatter()
            fmt.calendar = Calendar(identifier: .gregorian)
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = "yyyy-MM-dd"
            return fmt.string(from: d)
        }

        let tz = TimeZone.current.identifier
        let startTime: EventDateTime = allDay
            ? EventDateTime(dateTime: nil, date: dateOnly(start), timeZone: nil)
            : EventDateTime(dateTime: iso.string(from: start), date: nil, timeZone: tz)
        let endTime: EventDateTime = allDay
            ? EventDateTime(dateTime: nil, date: dateOnly(end), timeZone: nil)
            : EventDateTime(dateTime: iso.string(from: end), date: nil, timeZone: tz)

        let input = Input(
            calendarId: calendarId,
            summary: summary,
            description: description,
            location: location,
            start: startTime,
            end: endTime,
            attendees: attendees.isEmpty ? nil : attendees.map { Attendee(email: $0.email, displayName: $0.displayName) }
        )
        let response: Response = try await api.trpcMutation("calendar.createEvent", input: input)
        return CreatedEventResult(scopeMissing: response.scopeMissing, eventId: response.event?.id)
    }

    /// Delete a Google Calendar event.
    func deleteEvent(calendarId: String, eventId: String) async throws -> Bool {
        struct Input: Encodable {
            let calendarId: String
            let eventId: String
        }
        struct Response: Decodable {
            let scopeMissing: Bool
            let success: Bool
        }
        let response: Response = try await api.trpcMutation(
            "calendar.deleteEvent",
            input: Input(calendarId: calendarId, eventId: eventId)
        )
        return response.success
    }

    // MARK: - Cache helpers

    private func fetchCalendars(for conn: ConnectionAccount) async -> (String, [CalendarSource], Bool) {
        struct Response: Decodable {
            let calendars: [GoogleCalendarListEntry]?
            let scopeMissing: Bool?
        }
        do {
            let response: Response = try await api.trpcQuery("calendar.calendars")
            if response.scopeMissing == true {
                return (conn.id, [], true)
            }
            let sources = (response.calendars ?? []).map { entry in
                CalendarSource.google(
                    connectionId: conn.id,
                    connectionEmail: conn.email,
                    calendarId: entry.id,
                    name: entry.name,
                    hexColor: entry.color,
                    accessRole: "reader", // backend doesn't echo accessRole in `calendar.calendars` today
                    isPrimary: entry.primary
                )
            }
            return (conn.id, sources, false)
        } catch {
            print("[GoogleCalendarService] calendars fetch failed for \(conn.email): \(error)")
            return (conn.id, [], false)
        }
    }

    private func saveCacheToDisk() {
        let snapshots: [CachedSources] = sourcesByConnection.compactMap { (connectionId, sources) -> CachedSources? in
            guard let firstEmail = sources.first?.accountEmail else { return nil }
            let entries = sources.map { source -> CachedSources.Entry in
                let prefix = "\(CalendarSourceIDPrefix.google):\(connectionId):"
                let calId = source.id.hasPrefix(prefix) ? String(source.id.dropFirst(prefix.count)) : source.id
                let hex = String(format: "#%02X%02X%02X",
                                 Int(source.colorRed * 255), Int(source.colorGreen * 255), Int(source.colorBlue * 255))
                return CachedSources.Entry(
                    calendarId: calId,
                    name: source.displayName,
                    color: hex,
                    accessRole: source.isWritable ? "writer" : "reader",
                    primary: source.isPrimary
                )
            }
            return CachedSources(connectionId: connectionId, connectionEmail: firstEmail, entries: entries)
        }
        if let data = try? JSONEncoder().encode(snapshots) {
            defaults.set(data, forKey: Keys.cachedSources)
        }
    }

    private func loadCacheFromDisk() {
        guard let data = defaults.data(forKey: Keys.cachedSources),
              let snapshots = try? JSONDecoder().decode([CachedSources].self, from: data) else { return }
        var rebuilt: [String: [CalendarSource]] = [:]
        for snapshot in snapshots {
            rebuilt[snapshot.connectionId] = snapshot.entries.map { entry in
                CalendarSource.google(
                    connectionId: snapshot.connectionId,
                    connectionEmail: snapshot.connectionEmail,
                    calendarId: entry.calendarId,
                    name: entry.name,
                    hexColor: entry.color,
                    accessRole: entry.accessRole,
                    isPrimary: entry.primary
                )
            }
        }
        sourcesByConnection = rebuilt
    }
}
