import EventKit
import Foundation
import SwiftUI

/// Composite-ID prefix for Apple (EventKit) calendars.
/// Encoded as `apple:{EKCalendar.calendarIdentifier}`.
enum CalendarSourceIDPrefix {
    static let apple = "apple"
    static let google = "google"
}

/// Discriminator for a calendar source — Apple (EventKit) or a backend Google
/// connection (keyed by `connectionId`).
enum CalendarSourceKind: Sendable, Equatable, Hashable {
    case apple
    case google(connectionId: String)

    /// Account key used in `defaultCalendarByAccount`. `apple` for the local
    /// EventKit store, `google:{connectionId}` for each connected Gmail account.
    var accountKey: String {
        switch self {
        case .apple: return CalendarSourceIDPrefix.apple
        case .google(let connectionId): return "\(CalendarSourceIDPrefix.google):\(connectionId)"
        }
    }
}

/// Unified, sendable representation of a single calendar (a single
/// `EKCalendar` or one entry in a Google account's calendar list).
///
/// Stable, composite `id` lets us key visibility prefs in user settings,
/// drive `Identifiable`-based SwiftUI lists, and round-trip across
/// iOS / macOS / web without ambiguity.
struct CalendarSource: Identifiable, Sendable, Equatable, Hashable {
    /// Composite id:
    ///   - Apple:  `apple:{EKCalendar.calendarIdentifier}`
    ///   - Google: `google:{connectionId}:{googleCalendarId}`
    let id: String
    let kind: CalendarSourceKind
    let displayName: String
    /// Email of the connected account (Google only). `nil` for Apple sources.
    let accountEmail: String?
    /// 0–1 RGB components for the source color dot.
    let colorRed: Double
    let colorGreen: Double
    let colorBlue: Double
    /// Whether the user can create / modify / delete events on this calendar.
    /// For Apple this maps to `EKCalendar.allowsContentModifications`.
    /// For Google this maps to `accessRole in {writer, owner}`.
    let isWritable: Bool
    /// Whether this is the user's primary / default calendar in its account.
    let isPrimary: Bool

    /// SwiftUI Color from the RGB components.
    var color: Color {
        Color(red: colorRed, green: colorGreen, blue: colorBlue)
    }

    /// Human-readable label for grouping the picker UI.
    /// Apple: "On This iPhone". Google: the connection email.
    var groupLabel: String {
        switch kind {
        case .apple: return "Apple Calendar"
        case .google: return accountEmail ?? "Google Calendar"
        }
    }
}

extension CalendarSource {
    /// Build a CalendarSource from an EKCalendar.
    static func from(appleCalendar cal: EKCalendar) -> CalendarSource {
        let (r, g, b) = Self.rgb(from: cal.cgColor)
        return CalendarSource(
            id: "\(CalendarSourceIDPrefix.apple):\(cal.calendarIdentifier)",
            kind: .apple,
            displayName: cal.title,
            accountEmail: nil,
            colorRed: r,
            colorGreen: g,
            colorBlue: b,
            isWritable: cal.allowsContentModifications,
            // EventKit doesn't expose a single "primary" flag — treat the
            // store's default calendar for new events as primary.
            isPrimary: false
        )
    }

    /// Build a Google-backed source from the backend payload.
    static func google(
        connectionId: String,
        connectionEmail: String,
        calendarId: String,
        name: String,
        hexColor: String,
        accessRole: String,
        isPrimary: Bool
    ) -> CalendarSource {
        let (r, g, b) = Self.rgb(fromHex: hexColor)
        let writable = (accessRole == "writer" || accessRole == "owner")
        return CalendarSource(
            id: "\(CalendarSourceIDPrefix.google):\(connectionId):\(calendarId)",
            kind: .google(connectionId: connectionId),
            displayName: name,
            accountEmail: connectionEmail,
            colorRed: r,
            colorGreen: g,
            colorBlue: b,
            isWritable: writable,
            isPrimary: isPrimary
        )
    }

    private static func rgb(from cgColor: CGColor?) -> (Double, Double, Double) {
        guard let cgColor,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = cgColor.converted(to: colorSpace, intent: .defaultIntent, options: nil),
              let comps = converted.components,
              comps.count >= 3 else {
            return (0.357, 0.553, 0.937) // Default blue (0x5B8DEF)
        }
        return (Double(comps[0]), Double(comps[1]), Double(comps[2]))
    }

    private static func rgb(fromHex hex: String) -> (Double, Double, Double) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else {
            return (0.357, 0.553, 0.937)
        }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return (r, g, b)
    }
}

// MARK: - Calendar preferences (mirrors backend `calendarPreferences` schema)

/// Per-user calendar visibility prefs synced via `settings.save` / `settings.get`.
/// Mirrors `calendarPreferencesSchema` in `apps/server/src/lib/schemas.ts`.
struct CalendarPreferences: Codable, Equatable, Sendable {
    var hiddenCalendarIds: [String]
    var defaultCalendarId: String?
    var defaultCalendarByAccount: [String: String]
    var preferGoogleOverAppleDuplicates: Bool

    init(
        hiddenCalendarIds: [String] = [],
        defaultCalendarId: String? = nil,
        defaultCalendarByAccount: [String: String] = [:],
        preferGoogleOverAppleDuplicates: Bool = true
    ) {
        self.hiddenCalendarIds = hiddenCalendarIds
        self.defaultCalendarId = defaultCalendarId
        self.defaultCalendarByAccount = defaultCalendarByAccount
        self.preferGoogleOverAppleDuplicates = preferGoogleOverAppleDuplicates
    }

    static let `default` = CalendarPreferences()

    var hiddenIdSet: Set<String> { Set(hiddenCalendarIds) }

    func isHidden(_ id: String) -> Bool { hiddenIdSet.contains(id) }

    /// Returns the user's preferred default calendar id for the given account
    /// (Apple or `google:{connectionId}`), falling back to the global default.
    func defaultId(forAccountKey accountKey: String) -> String? {
        defaultCalendarByAccount[accountKey] ?? defaultCalendarId
    }
}
