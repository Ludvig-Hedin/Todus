import SwiftUI

/// Multi-day view — shows 2 or 3 days side-by-side with a time grid.
/// Configurable day count via @AppStorage("calendarMultiDayCount").
/// Supports horizontal swipe to navigate between day groups.
/// All-day bar is a single compact row matching CalendarKit's 1-day style.
struct CalendarMultiDayView: View {
    @Binding var selectedDate: Date
    let events: [CalendarEvent]
    let dayCount: Int
    var onEventTap: ((CalendarEvent) -> Void)? = nil

    // Swipe navigation state
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        let cal = Calendar.current
        let dates = (0..<dayCount).compactMap { cal.date(byAdding: .day, value: $0, to: selectedDate) }
        let weekNumber = cal.component(.weekOfYear, from: selectedDate)

        VStack(spacing: 0) {
            // Column headers — "Fri 3" / "Sat 4" / "Sun 5" with week number
            columnHeaders(dates: dates, weekNumber: weekNumber, cal: cal)

            // All-day events bar — compact single row matching CalendarKit
            let allDayByDay = allDayEventsGrouped(dates: dates, cal: cal)
            if allDayByDay.values.contains(where: { !$0.isEmpty }) {
                allDayBar(dates: dates, allDayByDay: allDayByDay, cal: cal)
            }

            Divider()

            // Time grid with columns
            let gridColumns = dates.map { date in
                let dayEvents = events.filter { !$0.isAllDay && cal.isDate($0.startDate, inSameDayAs: date) }
                return CalendarTimeGridColumn(date: date, events: dayEvents)
            }

            CalendarTimeGridView(
                columns: gridColumns,
                highlightToday: true,
                onEventTap: { event in onEventTap?(event) },
                onGridTap: nil
            )
        }
        .offset(x: dragOffset)
        .gesture(
            // Horizontal swipe to navigate between day groups
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onChanged { value in
                    // Only respond to mostly-horizontal drags to avoid conflicting
                    // with the vertical time grid scroll
                    if abs(value.translation.width) > abs(value.translation.height) {
                        dragOffset = value.translation.width * 0.3
                    }
                }
                .onEnded { value in
                    let threshold: CGFloat = 50
                    let isHorizontal = abs(value.translation.width) > abs(value.translation.height)

                    withAnimation(.easeOut(duration: 0.2)) {
                        dragOffset = 0
                        if isHorizontal && value.translation.width < -threshold {
                            // Swipe left → go forward by dayCount
                            let cal = Calendar.current
                            selectedDate = cal.date(byAdding: .day, value: dayCount, to: selectedDate) ?? selectedDate
                        } else if isHorizontal && value.translation.width > threshold {
                            // Swipe right → go back by dayCount
                            let cal = Calendar.current
                            selectedDate = cal.date(byAdding: .day, value: -dayCount, to: selectedDate) ?? selectedDate
                        }
                    }
                }
        )
        .animation(.easeOut(duration: 0.2), value: selectedDate)
    }

    // MARK: - Column Headers

    private func columnHeaders(dates: [Date], weekNumber: Int, cal: Calendar) -> some View {
        HStack(spacing: 0) {
            // Week number in gutter
            Text("W\(weekNumber)")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
                .padding(.trailing, 4)

            ForEach(Array(dates.enumerated()), id: \.offset) { index, date in
                let isToday = cal.isDateInToday(date)

                VStack(spacing: 1) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(isToday ? Color(red: 0.92, green: 0.23, blue: 0.21) : .secondary)

                    Text(date.formatted(.dateTime.day()))
                        .font(.system(size: 16, weight: isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? .white : .primary)
                        .frame(width: 28, height: 28)
                        .background {
                            if isToday {
                                Circle().fill(Color(red: 0.92, green: 0.23, blue: 0.21))
                            }
                        }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

                if index < dates.count - 1 {
                    Rectangle()
                        .fill(Color(UIColor.separator).opacity(0.15))
                        .frame(width: 0.5)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - All-Day Events Bar

    /// Ultra-compact all-day bar matching CalendarKit's 1-day style.
    /// Shows a single row per column with just 1 event title; extras shown as "+N".
    /// Total height ~22pt — same as the CalendarKit day view all-day strip.
    private func allDayBar(dates: [Date], allDayByDay: [Date: [CalendarEvent]], cal: Calendar) -> some View {
        VStack(spacing: 0) {
            Divider()

            HStack(alignment: .center, spacing: 0) {
                // "all-day" gutter label
                Text(
                    String(
                        localized: "calendar.all-day",
                        defaultValue: "all-day",
                        comment: "Label for all-day calendar events"
                    )
                )
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
                    .padding(.trailing, 4)

                ForEach(Array(dates.enumerated()), id: \.offset) { index, date in
                    let dayStart = cal.startOfDay(for: date)
                    let dayAllDay = allDayByDay[dayStart] ?? []

                    // Single compact row: first event title + overflow count
                    HStack(spacing: 3) {
                        if let first = dayAllDay.first {
                            let color = Color(
                                red: first.calendarColorRed,
                                green: first.calendarColorGreen,
                                blue: first.calendarColorBlue
                            )
                            Text(first.title)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(color.opacity(0.85))
                                )
                                .onTapGesture { onEventTap?(first) }
                        }
                        if dayAllDay.count > 1 {
                            Text("+\(dayAllDay.count - 1)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 1)

                    if index < dates.count - 1 {
                        Rectangle()
                            .fill(Color(UIColor.separator).opacity(0.15))
                            .frame(width: 0.5)
                    }
                }
            }
            .padding(.vertical, 2)
            .frame(height: 22) // Fixed compact height matching CalendarKit
            .background(
                Color(UIColor { trait in
                    trait.userInterfaceStyle == .dark
                        ? UIColor(white: 0.115, alpha: 1)
                        : UIColor(white: 0.965, alpha: 1)
                })
            )
        }
    }

    // MARK: - Helpers

    private func allDayEventsGrouped(dates: [Date], cal: Calendar) -> [Date: [CalendarEvent]] {
        let visibleDates = Set(dates.map { cal.startOfDay(for: $0) })
        var grouped: [Date: [CalendarEvent]] = [:]

        for event in events where event.isAllDay {
            var currentDay = cal.startOfDay(for: event.startDate)
            let endReference = max(event.startDate, event.endDate.addingTimeInterval(-1))
            let lastDay = cal.startOfDay(for: endReference)

            while currentDay <= lastDay {
                if visibleDates.contains(currentDay) {
                    grouped[currentDay, default: []].append(event)
                }
                guard let nextDay = cal.date(byAdding: .day, value: 1, to: currentDay) else { break }
                currentDay = nextDay
            }
        }

        return grouped
    }
}
