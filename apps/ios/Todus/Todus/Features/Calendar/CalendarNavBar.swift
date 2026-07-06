import SwiftUI

/// Navigation bar for the calendar — sits below AppTopHeader.
/// Shows prev/next arrows, context-aware title, and optional go-to-today control (icon).
/// Omitted in Day mode (handled in `CalendarTabView`) and Month mode.
struct CalendarNavBar: View {
    @Binding var selectedDate: Date
    let viewMode: CalendarViewMode
    let multiDayCount: Int
    /// When false, the go-to-today control is omitted (e.g. already showing today).
    var showTodayButton: Bool = true
    /// Day view uses a text label in the separate header row; other modes use a compact icon.
    var todayUsesIconOnly: Bool = true
    var onToday: () -> Void
    /// Optional handler for the leading "Calendars" picker button. Hidden when nil
    /// (e.g. previews that don't have AppServices).
    var onCalendars: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            // Navigation arrows
            HStack(spacing: 2) {
                navButton(icon: "chevron.left", accessibilityLabel: String(localized: "Previous")) { navigate(by: -1) }
                navButton(icon: "chevron.right", accessibilityLabel: String(localized: "Next")) { navigate(by: 1) }
            }

            Text(headerTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            if let onCalendars {
                Button(action: onCalendars) {
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.75))
                        .frame(width: 36, height: 32)
                }
                .buttonStyle(LiquidGlassButtonStyle(cornerRadius: AppTheme.Radius.row))
                .accessibilityLabel(String(localized: "Calendars"))
            }

            if showTodayButton {
                Button {
                    withAnimation(AppTheme.Motion.base) { onToday() }
                } label: {
                    if todayUsesIconOnly {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.75))
                            .frame(width: 36, height: 32)
                    } else {
                        Text(String(localized: "Today"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.75))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                }
                .buttonStyle(LiquidGlassButtonStyle(cornerRadius: AppTheme.Radius.row))
                .accessibilityLabel(String(localized: "Go to today"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var headerTitle: String {
        let cal = Calendar.current
        switch viewMode {
        case .day:
            // Day mode hidden, but provide a fallback
            return selectedDate.formatted(.dateTime.day().month(.wide).year())
        case .multiDay:
            let endDate = cal.date(byAdding: .day, value: multiDayCount - 1, to: selectedDate) ?? selectedDate
            let sameMonth = cal.component(.month, from: selectedDate) == cal.component(.month, from: endDate)
            if sameMonth {
                let startDay = selectedDate.formatted(.dateTime.day())
                let endDay = endDate.formatted(.dateTime.day())
                let monthYear = selectedDate.formatted(.dateTime.month(.wide).year())
                return "\(startDay) – \(endDay) \(monthYear)"
            } else {
                let start = selectedDate.formatted(.dateTime.day().month(.abbreviated))
                let end = endDate.formatted(.dateTime.day().month(.abbreviated).year())
                return "\(start) – \(end)"
            }
        case .month:
            return selectedDate.formatted(.dateTime.month(.wide).year())
        case .year:
            return selectedDate.formatted(.dateTime.year())
        case .list:
            return selectedDate.formatted(.dateTime.month(.wide).year())
        }
    }

    private func navButton(icon: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.65))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(LiquidGlassButtonStyle(cornerRadius: AppTheme.Radius.row))
        .accessibilityLabel(accessibilityLabel)
    }

    private func navigate(by offset: Int) {
        // Light haptic gives tap feedback on par with the Calendars/Today
        // buttons alongside it, which already fire via their own action closures.
        AppHaptic.light.play()
        let cal = Calendar.current
        let animated = viewMode != .month
        if animated {
            withAnimation(AppTheme.Motion.base) {
                applyNavigation(offset: offset, cal: cal)
            }
        } else {
            applyNavigation(offset: offset, cal: cal)
        }
    }

    private func applyNavigation(offset: Int, cal: Calendar) {
        switch viewMode {
        case .day:
            selectedDate = cal.date(byAdding: .day, value: offset, to: selectedDate) ?? selectedDate
        case .multiDay:
            selectedDate = cal.date(byAdding: .day, value: offset * multiDayCount, to: selectedDate) ?? selectedDate
        case .month:
            selectedDate = cal.date(byAdding: .month, value: offset, to: selectedDate) ?? selectedDate
        case .year:
            selectedDate = cal.date(byAdding: .year, value: offset, to: selectedDate) ?? selectedDate
        case .list:
            selectedDate = cal.date(byAdding: .month, value: offset, to: selectedDate) ?? selectedDate
        }
    }
}
