import SwiftUI

/// Apple Calendar-style month view with infinite vertical scroll.
/// Shows multiple months in a continuous scrollable list.
/// Pinch-to-resize adjusts row height (like Apple Calendar / Google Maps zoom):
///   - Pinch in (spread fingers) = taller rows, showing event titles
///   - Pinch out (pinch fingers) = shorter rows, falling back to dots
/// Default row height fits 3 event titles per day cell.
/// Tapping a day switches to Day view.
struct CalendarMonthView: View {
    @Binding var selectedDate: Date
    @Binding var viewMode: CalendarViewMode
    let events: [CalendarEvent]

    // Pinch-to-resize row height.
    // Default 90pt fits day number (28pt) + 3 event pills (~14pt each) + spacing.
    // Min 40pt shows only day number + dots. Max 140pt for extra room.
    @State private var rowHeight: CGFloat = 90
    @State private var baseRowHeight: CGFloat = 90
    @State private var hasPerformedInitialScroll = false
    private let minRowHeight: CGFloat = 40
    private let maxRowHeight: CGFloat = 140

    /// Threshold below which we show dots instead of event titles
    private let dotModeThreshold: CGFloat = 60

    /// How many months to show before/after the selected month
    private let monthBuffer = 12

    var body: some View {
        VStack(spacing: 0) {
            weekdayHeader
            Divider()
            monthScrollView
    }

    // MARK: - Weekday Header

    private var weekdayHeader: some View {
        let cal = Calendar.current
        let symbols = cal.shortWeekdaySymbols
        let offset = cal.firstWeekday - 1
        let rotated = Array(symbols[offset...]) + Array(symbols[..<offset])

        return HStack(spacing: 0) {
            ForEach(Array(rotated.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Infinite Month Scroll

    private var monthScrollView: some View {
        let cal = Calendar.current
        let monthOffsets = Array(-monthBuffer...monthBuffer)

        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    ForEach(monthOffsets, id: \.self) { offset in
                        if let monthDate = cal.date(byAdding: .month, value: offset, to: anchorMonth) {
                            monthSection(for: monthDate)
                                .id(monthID(for: monthDate))
                        }
                    }
                }
            }
            .onAppear {
                guard !hasPerformedInitialScroll else { return }
                hasPerformedInitialScroll = true
                proxy.scrollTo(monthID(for: anchorMonth), anchor: .top)
            }
        }
    }

    /// The first day of the selected month — used as scroll anchor
    private var anchorMonth: Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: selectedDate)
        return cal.date(from: comps) ?? cal.startOfDay(for: selectedDate)
    }

    private func monthID(for date: Date) -> String {
        let cal = Calendar.current
        let year = cal.component(.year, from: date)
        let month = cal.component(.month, from: date)
        return "month-\(year)-\(month)"
    }

    // MARK: - Month Section

    private func monthSection(for monthDate: Date) -> some View {
        let cal = Calendar.current
        let gridDates = monthGridDates(for: monthDate)
        let monthNum = cal.component(.month, from: monthDate)

        return VStack(spacing: 0) {
            monthHeader(for: monthDate)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                spacing: 0
            ) {
                ForEach(Array(gridDates.enumerated()), id: \.offset) { _, date in
                    let isCurrentMonth = cal.component(.month, from: date) == monthNum
                    monthDayCell(date, isMuted: !isCurrentMonth)
                }
            }
        }
    }

    private func monthHeader(for monthDate: Date) -> some View {
        let cal = Calendar.current
        let isCurrentMonth = cal.isDate(monthDate, equalTo: Date(), toGranularity: .month)

        return HStack {
            Text(monthDate.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isCurrentMonth ? Color(red: 0.92, green: 0.23, blue: 0.21) : .primary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    // MARK: - Day Cell

    /// Whether rows are tall enough to show event title pills vs. compact dots
    private var showEventTitles: Bool {
        rowHeight >= dotModeThreshold
    }

    /// How many event pills fit in the available space below the day number
    private var maxVisibleEvents: Int {
        // Day number takes ~24pt, each event pill ~14pt, spacing ~2pt
        let availableHeight = rowHeight - 26
        let eventSlotHeight: CGFloat = 14
        return max(0, Int(availableHeight / eventSlotHeight))
    }

    private func monthDayCell(_ date: Date, isMuted: Bool) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(date)
        let dayEvents = events.filter { cal.isDate($0.startDate, inSameDayAs: date) }
            .sorted { $0.startDate < $1.startDate }

        return VStack(spacing: 1) {
            // Day number
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 14, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? .white : isMuted ? .secondary : .primary)
                .frame(width: 28, height: 24)
                .background {
                    if isToday {
                        Circle().fill(Color(red: 0.92, green: 0.23, blue: 0.21))
                    }
                }

            if !dayEvents.isEmpty {
                if showEventTitles {
                    // Show event title pills when rows are tall enough
                    eventTitlesList(dayEvents: dayEvents, isMuted: isMuted)
                } else {
                    // Compact dots when rows are short
                    eventDots(dayEvents: dayEvents)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(height: rowHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.2)) {
                selectedDate = date
                viewMode = .day
            }
        }
    }

    // MARK: - Event Title Pills (shown when rows are tall enough)

    private func eventTitlesList(dayEvents: [CalendarEvent], isMuted: Bool) -> some View {
        let visible = Array(dayEvents.prefix(maxVisibleEvents))
        let overflow = dayEvents.count - maxVisibleEvents

        return VStack(alignment: .leading, spacing: 1) {
            ForEach(visible) { event in
                let color = Color(
                    red: event.calendarColorRed,
                    green: event.calendarColorGreen,
                    blue: event.calendarColorBlue
                )
                Text(event.title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(color.opacity(isMuted ? 0.4 : 0.85))
                    )
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
        }
        .padding(.horizontal, 1)
    }

    // MARK: - Event Dots (compact fallback)

    private func eventDots(dayEvents: [CalendarEvent]) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(dayEvents.prefix(3).enumerated()), id: \.offset) { _, event in
                Circle()
                    .fill(Color(
                        red: event.calendarColorRed,
                        green: event.calendarColorGreen,
                        blue: event.calendarColorBlue
                    ))
                    .frame(width: 4, height: 4)
            }
        }
    }

    // MARK: - Grid Date Calculation

    /// Builds the full grid of dates for a month view (always a multiple of 7).
    private func monthGridDates(for date: Date) -> [Date] {
        let cal = Calendar.current
        guard let monthInterval = cal.dateInterval(of: .month, for: date) else {
            return [cal.startOfDay(for: date)]
        }
        let firstDayOfMonth = monthInterval.start
        let firstWeekdayOffset = (cal.component(.weekday, from: firstDayOfMonth) - cal.firstWeekday + 7) % 7

        var dates: [Date] = []

        // Previous month's trailing days
        for i in (0..<firstWeekdayOffset).reversed() {
            if let d = cal.date(byAdding: .day, value: -(i + 1), to: firstDayOfMonth) {
                dates.append(d)
            }
        }

        // Current month's days
        guard let daysInMonth = cal.range(of: .day, in: .month, for: date) else {
            return dates.isEmpty ? [firstDayOfMonth] : dates
        }
        for day in daysInMonth {
            if let d = cal.date(bySetting: .day, value: day, of: firstDayOfMonth) {
                dates.append(d)
            }
        }

        // Next month's leading days — fill to complete last row
        let remainder = dates.count % 7
        if remainder > 0 {
            let lastDay = dates.last ?? firstDayOfMonth
            for i in 1...(7 - remainder) {
                if let d = cal.date(byAdding: .day, value: i, to: lastDay) {
                    dates.append(d)
                }
            }
        }

        return dates
    }
}
