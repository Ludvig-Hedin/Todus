import SwiftUI

/// Year view — 3×4 grid of mini-month calendars per year.
/// Today is circled in red, current month name in red.
/// Tapping a mini-month navigates to Month view for that month.
struct CalendarYearView: View {
    @Binding var selectedDate: Date
    @Binding var viewMode: CalendarViewMode
    let events: [CalendarEvent]

    var body: some View {
        let cal = Calendar.current
        let currentYear = cal.component(.year, from: selectedDate)
        // Show ± 2 years for scrolling
        let yearRange = (currentYear - 2)...(currentYear + 2)

        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 28) {
                    ForEach(Array(yearRange), id: \.self) { year in
                        yearSection(year: year)
                            .id("year-\(year)")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onAppear {
                proxy.scrollTo("year-\(currentYear)", anchor: .top)
            }
        }
    }

    // MARK: - Year Section

    private func yearSection(year: Int) -> some View {
        let cal = Calendar.current
        let currentYear = cal.component(.year, from: Date())
        let isCurrentYear = year == currentYear

        return VStack(alignment: .leading, spacing: 10) {
            Text(String(year))
                .font(.system(size: 22, weight: isCurrentYear ? .bold : .regular))
                .foregroundStyle(isCurrentYear ? Color(red: 0.92, green: 0.23, blue: 0.21) : .primary)
                .padding(.leading, 4)

            // 3 columns of mini months (iPhone is narrower than Mac, so 3 instead of 4)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                spacing: 12
            ) {
                ForEach(1...12, id: \.self) { month in
                    miniMonthCell(year: year, month: month)
                }
            }
        }
    }

    // MARK: - Mini Month Cell

    private func miniMonthCell(year: Int, month: Int) -> some View {
        let cal = Calendar.current
        let today = Date()
        let todayComps = cal.dateComponents([.year, .month, .day], from: today)

        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let firstOfMonth = cal.date(from: comps) else {
            return AnyView(EmptyView())
        }

        guard let daysInMonth = cal.range(of: .day, in: .month, for: firstOfMonth) else {
            return AnyView(EmptyView())
        }
        let firstWeekday = cal.component(.weekday, from: firstOfMonth)
        let firstWeekdayOffset = (firstWeekday - cal.firstWeekday + 7) % 7

        let monthName = firstOfMonth.formatted(.dateTime.month(.wide))
        let isCurrentMonth = year == todayComps.year && month == todayComps.month

        // Weekday initials rotated to locale
        let symbols = cal.veryShortWeekdaySymbols
        let offset = cal.firstWeekday - 1
        let rotated = Array(symbols[offset...]) + Array(symbols[..<offset])

        // Days with events for dot indicators
        let eventDates: Set<Int> = {
            var days = Set<Int>()
            for event in events {
                let ec = cal.dateComponents([.year, .month, .day], from: event.startDate)
                if ec.year == year && ec.month == month, let d = ec.day {
                    days.insert(d)
                }
            }
            return days
        }()

        return AnyView(
            VStack(alignment: .leading, spacing: 3) {
                // Month title
                Text(monthName)
                    .font(.system(size: 11, weight: isCurrentMonth ? .bold : .medium))
                    .foregroundStyle(isCurrentMonth ? Color(red: 0.92, green: 0.23, blue: 0.21) : .primary)

                // Weekday initials
                HStack(spacing: 0) {
                    ForEach(Array(rotated.enumerated()), id: \.offset) { _, sym in
                        Text(sym)
                            .font(.system(size: 8, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                // Day number grid
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                    spacing: 1
                ) {
                    // Empty offset cells
                    ForEach(0..<firstWeekdayOffset, id: \.self) { _ in
                        Text("")
                            .frame(height: 16)
                    }

                    // Day numbers
                    ForEach(Array(daysInMonth), id: \.self) { day in
                        let isToday = year == todayComps.year && month == todayComps.month && day == todayComps.day
                        let hasEvent = eventDates.contains(day)

                        VStack(spacing: 0) {
                            Text("\(day)")
                                .font(.system(size: 9, weight: isToday ? .bold : .regular))
                                .foregroundStyle(isToday ? .white : .primary)
                                .frame(width: 16, height: 16)
                                .background {
                                    if isToday {
                                        Circle().fill(Color(red: 0.92, green: 0.23, blue: 0.21))
                                    }
                                }

                            // Event dot
                            Circle()
                                .fill(hasEvent ? Color.accentColor : Color.clear)
                                .frame(width: 3, height: 3)
                        }
                        .frame(height: 20)
                    }
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.surfacePrimary.opacity(isCurrentMonth ? 1 : 0.5))
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if let date = cal.date(from: DateComponents(year: year, month: month, day: 1)) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedDate = date
                        viewMode = .month
                    }
                }
            }
        )
    }
}
