import Foundation

/// Calendar view modes — matches the segmented picker options.
/// Default is `.day` (existing CalendarKit view). The `.multiDay` mode
/// shows 2 or 3 days side-by-side based on user preference.
enum CalendarViewMode: String, CaseIterable, Identifiable {
    case day = "Day"
    case multiDay = "Multi"
    case month = "Mo"
    case year = "Yr"
    case list = "List"

    var id: String { rawValue }

    /// Short label for the compact picker inside AppTopHeader
    func pickerLabel(multiDayCount: Int) -> String {
        displayLabel(multiDayCount: multiDayCount)
    }

    /// Dynamic label for multi-day mode based on configured day count
    func displayLabel(multiDayCount: Int) -> String {
        if self == .multiDay {
            return "\(multiDayCount)D"
        }
        return rawValue
    }

    /// Full-length label for dropdown menu display
    func menuLabel(multiDayCount: Int) -> String {
        switch self {
        case .day: return "Day"
        case .multiDay: return "\(multiDayCount)-Day"
        case .month: return "Month"
        case .year: return "Year"
        case .list: return "List"
        }
    }
}
