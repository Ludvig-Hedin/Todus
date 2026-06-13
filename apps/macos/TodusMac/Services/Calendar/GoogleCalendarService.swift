import Foundation
import Observation

extension Notification.Name {
    static let todusCalendarScopeMissing = Notification.Name("TodusCalendarScopeMissing")
}

let TodusCalendarScopeMissingConnectionIdKey = "connectionId"

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

struct GoogleCalendarListEntry: Decodable, Sendable {
    let id: String
    let name: String
    let color: String
    let primary: Bool
    /// Google Calendar access role for this calendar (e.g. "owner", "writer",
    /// "reader", "freeBusyReader"). Optional for backward compatibility with
    /// older backend responses; falls back to "reader" when missing.
    let accessRole: String?
}

@MainActor
@Observable
final class GoogleCalendarService {
    private let api: TodosAPIClient
    private let defaults = UserDefaults.standard

    private(set) var sourcesByConnection: [String: [CalendarSource]] = [:]
    private(set) var scopeMissingConnectionIds: Set<String> = []
    private var lastRefreshAt: Date?
    private let refreshTTL: TimeInterval = 5 * 60
    /// Deduplicates concurrent refresh calls — multiple callers awaiting `refresh()`
    /// during a refresh storm all wait on the same Task instead of firing N requests.
    private var inflightRefresh: Task<Void, Never>?

    private enum Keys {
        static let cachedSources = "Todus.macos.googleCalendarSourcesV1"
    }

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

    var isStale: Bool {
        guard let lastRefreshAt else { return true }
        return Date().timeIntervalSince(lastRefreshAt) > refreshTTL
    }

    func sources(forConnectionId id: String) -> [CalendarSource] {
        (sourcesByConnection[id] ?? []).sorted { lhs, rhs in
            if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    func refresh(googleConnections: [ConnectionAccount]) async {
        // If a refresh is already in flight, await its result instead of starting a new one.
        if let inflight = inflightRefresh {
            await inflight.value
            return
        }

        let task: Task<Void, Never> = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRefresh(googleConnections: googleConnections)
        }
        inflightRefresh = task
        await task.value
        if inflightRefresh == task { inflightRefresh = nil }
    }

    private func performRefresh(googleConnections: [ConnectionAccount]) async {
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

        if let connId = newScopeMissing.first {
            NotificationCenter.default.post(
                name: .todusCalendarScopeMissing,
                object: nil,
                userInfo: [TodusCalendarScopeMissingConnectionIdKey: connId]
            )
        }
    }

    func events(
        from startDate: Date,
        to endDate: Date,
        connections: [ConnectionAccount],
        hiddenCalendarIds: Set<String>
    ) async -> (events: [GoogleCalendarEvent], scopeMissing: Bool) {
        guard !connections.isEmpty else { return ([], false) }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var calendarIds: [String: [String]] = [:]
        for conn in connections {
            let sources = self.sources(forConnectionId: conn.id)
            if sources.isEmpty { continue }
            let visible = sources
                .filter { !hiddenCalendarIds.contains($0.id) }
                .compactMap { source -> String? in
                    let prefix = "\(CalendarSourceIDPrefix.google):\(conn.id):"
                    guard source.id.hasPrefix(prefix) else { return nil }
                    return String(source.id.dropFirst(prefix.count))
                }
            calendarIds[conn.id] = visible
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
            return (response.events, response.scopeMissing)
        } catch {
            print("[GoogleCalendarService] eventsMulti failed: \(error)")
            return ([], false)
        }
    }

    private func fetchCalendars(for conn: ConnectionAccount) async -> (String, [CalendarSource], Bool) {
        struct Response: Decodable {
            let calendars: [GoogleCalendarListEntry]?
            let scopeMissing: Bool?
        }
        do {
            // TODO(bug-hunt): `calendar.calendars` is queried with NO connection
            // input, but every returned calendar is tagged with `conn.id`. With
            // 2+ Google accounts this fetches the same (default) account's
            // calendars for each connection and mislabels them. Fix needs the
            // backend query to accept + scope by `connectionId` (verify schema
            // before wiring) — deferred pending backend support.
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
                    accessRole: entry.accessRole ?? "reader",
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
