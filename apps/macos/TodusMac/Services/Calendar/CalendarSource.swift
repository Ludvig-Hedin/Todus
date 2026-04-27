import EventKit
import Foundation
import SwiftUI

enum CalendarSourceIDPrefix {
    static let apple = "apple"
    static let google = "google"
}

enum CalendarSourceKind: Sendable, Equatable, Hashable {
    case apple
    case google(connectionId: String)

    var accountKey: String {
        switch self {
        case .apple: return CalendarSourceIDPrefix.apple
        case .google(let connectionId): return "\(CalendarSourceIDPrefix.google):\(connectionId)"
        }
    }
}

struct CalendarSource: Identifiable, Sendable, Equatable, Hashable {
    let id: String
    let kind: CalendarSourceKind
    let displayName: String
    let accountEmail: String?
    let colorRed: Double
    let colorGreen: Double
    let colorBlue: Double
    let isWritable: Bool
    let isPrimary: Bool

    var color: Color {
        Color(red: colorRed, green: colorGreen, blue: colorBlue)
    }

    var groupLabel: String {
        switch kind {
        case .apple: return "Apple Calendar"
        case .google: return accountEmail ?? "Google Calendar"
        }
    }
}

extension CalendarSource {
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
            isPrimary: false
        )
    }

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
              let converted = cgColor.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
              let comps = converted.components,
              comps.count >= 3 else {
            return (0.357, 0.553, 0.937)
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

    func defaultId(forAccountKey accountKey: String) -> String? {
        defaultCalendarByAccount[accountKey] ?? defaultCalendarId
    }
}
