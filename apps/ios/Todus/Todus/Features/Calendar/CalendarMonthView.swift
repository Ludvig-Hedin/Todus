import SwiftUI

/// Apple Calendar-style month view with infinite vertical scroll.
/// Shows multiple months in a continuous scrollable list.
/// Row height is fixed at 90pt — fits the day number plus 3 event title pills.
/// Pinch-to-zoom is handled at the parent `CalendarTabView` level and switches
/// between view modes (month → year, month → 3-day, etc.).
/// Tapping a day switches to Day view.
struct CalendarMonthView: View {
    @Binding var selectedDate: Date
    @Binding var viewMode: CalendarViewMode
    let events: [CalendarEvent]

    /// Row height: 90pt fits day number (28pt) + 3 event pills (~14pt each) + spacing.
    private let rowHeight: CGFloat = 90
    @State private var hasPerformedInitialScroll = false

    /// Cached `start-of-day → sorted events` lookup. Rebuilt only when
    /// `events` changes (Equatable: titles/times/ids, not just count),
    /// not on every body re-evaluation triggered by parent state changes
    /// (pinch scale, header geometry, etc.) during a swap transition.
    @State private var eventsByDay: [Date: [CalendarEvent]] = [:]

    /// Threshold below which we show dots instead of event titles
    private let dotModeThreshold: CGFloat = 60

    /// Months to show before/after the selected month. Was ±240 (~40 years);
    /// the larger buffer forced SwiftUI to build identity for ~480 LazyVStack
    /// rows on every body run, contributing to lag during pinch-to-swap.
    private let monthBuffer = 60

    var body: some View {
        VStack(spacing: 0) {
            weekdayHeader
            Divider()
            monthScrollView
        }
        .onAppear {
            if eventsByDay.isEmpty && !events.isEmpty {
                eventsByDay = Self.makeEventsByDay(events)
            }
        }
        .onChange(of: events) {
            eventsByDay = Self.makeEventsByDay(events)
        }
    }

    private static func makeEventsByDay(_ events: [CalendarEvent]) -> [Date: [CalendarEvent]] {
        let cal = Calendar.current
        var dict: [Date: [CalendarEvent]] = [:]
        for event in events {
            // Mark every day the event spans, not just its start day, so multi-day
            // events remain visible after day 1. EventKit stores all-day events with
            // an *exclusive* end (00:00 the next day), so `dayCursor < endDate`
            // naturally stops before bleeding onto the day after a single all-day
            // event. Guard-capped against runaway spans (mirrors CalendarYearView).
            var dayCursor = cal.startOfDay(for: event.startDate)
            var guardCount = 0
            while dayCursor < event.endDate && guardCount < 400 {
                dict[dayCursor, default: []].append(event)
                guard let next = cal.date(byAdding: .day, value: 1, to: dayCursor) else { break }
                dayCursor = next
                guardCount += 1
            }
            // Zero/negative-duration events still get their start day.
            if event.endDate <= event.startDate {
                dict[cal.startOfDay(for: event.startDate), default: []].append(event)
            }
        }
        for key in dict.keys {
            dict[key]?.sort { $0.startDate < $1.startDate }
        }
        return dict
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
        let byDay = eventsByDay  // captured into the ForEach closure

        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    ForEach(monthOffsets, id: \.self) { offset in
                        if let monthDate = cal.date(byAdding: .month, value: offset, to: anchorMonth) {
                            monthSection(for: monthDate, eventsByDay: byDay)
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

    private func monthSection(for monthDate: Date, eventsByDay: [Date: [CalendarEvent]]) -> some View {
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
                    let dayStart = cal.startOfDay(for: date)
                    let dayEvents = eventsByDay[dayStart] ?? []
                    monthDayCell(date, events: dayEvents, isMuted: !isCurrentMonth)
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

    private func monthDayCell(_ date: Date, events dayEvents: [CalendarEvent], isMuted: Bool) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(date)

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
        .padding(.top, 4)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(UIColor.separator).opacity(0.3))
                .frame(height: 0.5)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color(UIColor.separator).opacity(0.3))
                .frame(width: 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Light haptic confirms the mode flip — without it the zoom animation
            // alone can feel like the tap registered late on slow devices.
            AppHaptic.light.play()
            withAnimation(.easeOut(duration: 0.2)) {
                selectedDate = date
                viewMode = .day
            }
        }
        // The cell is activated by a bare tap gesture — surface it to VoiceOver
        // as a button with a spoken date + event count (TD-12).
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), \(dayEvents.count == 1 ? "1 event" : "\(dayEvents.count) events")")
        .accessibilityHint("Opens day view")
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
        // Use byAdding (offset from the first day) instead of bySetting:.day, which
        // searches forward for the next matching day-of-month and can jump into the
        // following month near boundaries / DST, producing a wrong or duplicated grid.
        for day in daysInMonth {
            if let d = cal.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
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
