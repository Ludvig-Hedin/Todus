import SwiftUI

/// Navigation bar for the calendar — sits below AppTopHeader.
/// Shows prev/next arrows, context-aware title, and Today button.
/// Hidden in Day mode (CalendarKit has its own day navigation).
struct CalendarNavBar: View {
    @Binding var selectedDate: Date
    let viewMode: CalendarViewMode
    let multiDayCount: Int

    var body: some View {
        HStack(spacing: 8) {
            // Navigation arrows
            HStack(spacing: 2) {
                navButton(icon: "chevron.left") { navigate(by: -1) }
                navButton(icon: "chevron.right") { navigate(by: 1) }
            }

            Text(headerTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            // Today button
            Button {
                withAnimation(.easeOut(duration: 0.2)) { selectedDate = Date() }
            } label: {
                Text("Today")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.75))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(LiquidGlassButtonStyle(cornerRadius: 16))
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

    private func navButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.65))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(LiquidGlassButtonStyle(cornerRadius: 16))
    }

    private func navigate(by offset: Int) {
        let cal = Calendar.current
        let animated = viewMode != .month
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
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
