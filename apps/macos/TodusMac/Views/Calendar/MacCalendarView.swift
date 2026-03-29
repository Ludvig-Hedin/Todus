import SwiftUI
import EventKit

/// Calendar view — supports Day, Week, and Month modes with event display.
/// Desktop-optimized: multi-column layout, hover states, keyboard navigation.
struct MacCalendarView: View {
    @Environment(MacAppServices.self) private var services

    @Binding var viewMode: String
    @State private var selectedDate = Date()
    @State private var events: [CalendarEvent] = []
    @State private var isLoading = false
    @State private var hasAccess = false
    @State private var hoveredEventId: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !hasAccess {
                permissionView
            } else {
                // Navigation header
                navigationHeader
                    .padding(.bottom, MacTheme.spacing16)

                // View content based on mode
                switch viewMode {
                case "Day":
                    dayView
                case "Month":
                    monthView
                default:
                    weekView
                }
            }
        }
        .task {
            hasAccess = services.calendarService.canReadEvents()
            if !hasAccess {
                hasAccess = await services.calendarService.requestAccess()
            }
            await loadEvents()
        }
        .onChange(of: selectedDate) {
            Task { await loadEvents() }
        }
        .onChange(of: viewMode) {
            Task { await loadEvents() }
        }
    }

    // MARK: - Permission View

    private var permissionView: some View {
        VStack(spacing: MacTheme.spacing16) {
            Spacer()

            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(MacTheme.mutedText.opacity(0.5))

            Text("Calendar Access Required")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MacTheme.textPrimary)

            Text("Todus needs access to your calendar to show events.")
                .font(MacTheme.cardSubtitleFont())
                .foregroundStyle(MacTheme.textSecondary)
                .multilineTextAlignment(.center)

            Button("Grant Access") {
                Task {
                    hasAccess = await services.calendarService.requestAccess()
                    if hasAccess { await loadEvents() }
                }
            }
            .font(.system(size: 13, weight: .medium))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Navigation Header

    private var navigationHeader: some View {
        HStack(spacing: MacTheme.spacing12) {
            Button { navigate(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacTheme.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius))
                    .overlay(RoundedRectangle(cornerRadius: MacTheme.buttonRadius).stroke(MacTheme.cardBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Text(headerText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MacTheme.textPrimary)

            Button { navigate(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacTheme.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius))
                    .overlay(RoundedRectangle(cornerRadius: MacTheme.buttonRadius).stroke(MacTheme.cardBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Spacer()

            Button("Today") {
                withAnimation(.easeOut(duration: 0.2)) {
                    selectedDate = Date()
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(MacTheme.accent)
            .padding(.horizontal, MacTheme.spacing12)
            .padding(.vertical, MacTheme.spacing4)
            .background(MacTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius))

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var headerText: String {
        let cal = Calendar.current
        switch viewMode {
        case "Day":
            return selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        case "Month":
            return selectedDate.formatted(.dateTime.month(.wide).year())
        default:
            let weekDates = self.weekDates
            guard let first = weekDates.first, let last = weekDates.last else { return "" }
            if cal.component(.month, from: first) == cal.component(.month, from: last) {
                return "\(first.formatted(.dateTime.month(.wide))) \(first.formatted(.dateTime.day()))–\(last.formatted(.dateTime.day())), \(first.formatted(.dateTime.year()))"
            } else {
                return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day())), \(last.formatted(.dateTime.year()))"
            }
        }
    }

    private func navigate(by offset: Int) {
        let cal = Calendar.current
        withAnimation(.easeOut(duration: 0.2)) {
            switch viewMode {
            case "Day":
                selectedDate = cal.date(byAdding: .day, value: offset, to: selectedDate) ?? selectedDate
            case "Month":
                selectedDate = cal.date(byAdding: .month, value: offset, to: selectedDate) ?? selectedDate
            default:
                selectedDate = cal.date(byAdding: .weekOfYear, value: offset, to: selectedDate) ?? selectedDate
            }
        }
    }

    // MARK: - Day View

    private var dayView: some View {
        let cal = Calendar.current
        let dayEvents = events.filter { cal.isDate($0.startDate, inSameDayAs: selectedDate) }
            .sorted { $0.startDate < $1.startDate }

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // All-day events at top
                let allDayEvents = dayEvents.filter(\.isAllDay)
                if !allDayEvents.isEmpty {
                    VStack(alignment: .leading, spacing: MacTheme.spacing4) {
                        Text("ALL DAY")
                            .font(MacTheme.sectionHeaderFont())
                            .foregroundStyle(MacTheme.mutedText)
                            .tracking(0.8)

                        ForEach(allDayEvents) { event in
                            dayEventRow(event)
                        }
                    }
                    .padding(.bottom, MacTheme.spacing12)
                }

                // Time-based events — show 24-hour timeline
                let timedEvents = dayEvents.filter { !$0.isAllDay }
                ForEach(timeSlots, id: \.self) { hour in
                    let hourEvents = timedEvents.filter {
                        cal.component(.hour, from: $0.startDate) == hour
                    }

                    HStack(alignment: .top, spacing: MacTheme.spacing12) {
                        // Hour label
                        Text(hourLabel(hour))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MacTheme.mutedText)
                            .frame(width: 50, alignment: .trailing)

                        // Events or empty slot
                        VStack(alignment: .leading, spacing: MacTheme.spacing4) {
                            if hourEvents.isEmpty {
                                Rectangle()
                                    .fill(MacTheme.cardBorder)
                                    .frame(height: 0.5)
                                    .frame(maxWidth: .infinity)
                            } else {
                                ForEach(hourEvents) { event in
                                    dayEventRow(event)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(minHeight: 36)
                }

                if dayEvents.isEmpty {
                    VStack(spacing: MacTheme.spacing8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(MacTheme.mutedText.opacity(0.5))
                        Text("No events")
                            .font(.system(size: 13))
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, MacTheme.spacing24)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var timeSlots: [Int] {
        // Show 7am to 10pm by default
        Array(7...22)
    }

    private func hourLabel(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        var components = DateComponents()
        components.hour = hour
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(hour):00"
    }

    private func dayEventRow(_ event: CalendarEvent) -> some View {
        HStack(spacing: MacTheme.spacing8) {
            Circle()
                .fill(eventColor(event))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MacTheme.textPrimary)
                    .lineLimit(1)

                if event.isAllDay {
                    Text("All day")
                        .font(.system(size: 11))
                        .foregroundStyle(MacTheme.textSecondary)
                } else {
                    Text("\(event.startDate.formatted(date: .omitted, time: .shortened)) – \(event.endDate.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11))
                        .foregroundStyle(MacTheme.textSecondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, MacTheme.spacing12)
        .padding(.vertical, MacTheme.spacing8)
        .background(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .fill(hoveredEventId == event.id ? MacTheme.surfaceHover : MacTheme.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
        .onHover { hovering in
            hoveredEventId = hovering ? event.id : nil
        }
    }

    // MARK: - Week View

    private var weekDates: [Date] {
        let cal = Calendar.current
        let startOfWeek = cal.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: startOfWeek) }
    }

    private var weekView: some View {
        HStack(alignment: .top, spacing: MacTheme.spacing4) {
            ForEach(weekDates, id: \.self) { date in
                weekDayColumn(date)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func weekDayColumn(_ date: Date) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(date)
        let dayEvents = events.filter { cal.isDate($0.startDate, inSameDayAs: date) }
            .sorted { $0.startDate < $1.startDate }

        return VStack(alignment: .leading, spacing: MacTheme.spacing6) {
            // Day header
            VStack(spacing: 2) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isToday ? MacTheme.accent : MacTheme.mutedText)
                    .tracking(0.5)

                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: 16, weight: isToday ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isToday ? MacTheme.accent : MacTheme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, MacTheme.spacing4)

            // Events
            if dayEvents.isEmpty {
                Text("—")
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.mutedText.opacity(0.4))
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: MacTheme.spacing4) {
                        ForEach(dayEvents) { event in
                            weekEventCard(event)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(MacTheme.spacing8)
        .background(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .fill(isToday ? MacTheme.accent.opacity(0.03) : MacTheme.emptyStateSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(isToday ? MacTheme.accent.opacity(0.15) : MacTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func weekEventCard(_ event: CalendarEvent) -> some View {
        HStack(spacing: MacTheme.spacing4) {
            Circle()
                .fill(eventColor(event))
                .frame(width: 5, height: 5)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MacTheme.textPrimary)
                    .lineLimit(1)

                Text(event.isAllDay ? "All day" : event.startDate.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(MacTheme.mutedText)
            }
        }
        .padding(.horizontal, MacTheme.spacing6)
        .padding(.vertical, MacTheme.spacing4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MacTheme.pillRadius, style: .continuous)
                .fill(hoveredEventId == event.id ? MacTheme.surfaceHover : MacTheme.surfaceCard)
        )
        .onHover { hovering in
            hoveredEventId = hovering ? event.id : nil
        }
    }

    // MARK: - Month View

    private var monthView: some View {
        let cal = Calendar.current
        let monthInterval = cal.dateInterval(of: .month, for: selectedDate)!
        let daysInMonth = cal.range(of: .day, in: .month, for: selectedDate)!
        let firstDayOfMonth = monthInterval.start
        let firstWeekdayOffset = (cal.component(.weekday, from: firstDayOfMonth) - cal.firstWeekday + 7) % 7

        // Rotate weekday symbols to match locale's first weekday
        let symbols = cal.shortWeekdaySymbols
        let offset = cal.firstWeekday - 1
        let rotatedSymbols = Array(symbols[offset...]) + Array(symbols[..<offset])

        return VStack(spacing: 0) {
            // Weekday headers
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 1) {
                ForEach(rotatedSymbols, id: \.self) { symbol in
                    Text(symbol.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MacTheme.mutedText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MacTheme.spacing4)
                }
            }
            .padding(.bottom, MacTheme.spacing4)

            // Day cells
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 1) {
                // Empty cells before month start
                ForEach(0..<firstWeekdayOffset, id: \.self) { _ in
                    monthDayCell(nil)
                }

                // Actual days
                ForEach(Array(daysInMonth), id: \.self) { day in
                    let date = cal.date(bySetting: .day, value: day, of: firstDayOfMonth) ?? firstDayOfMonth
                    monthDayCell(date)
                }
            }

            Spacer()
        }
    }

    private func monthDayCell(_ date: Date?) -> some View {
        let cal = Calendar.current
        let isToday = date.map { cal.isDateInToday($0) } ?? false
        let dayEvents = date.map { d in
            events.filter { cal.isDate($0.startDate, inSameDayAs: d) }
        } ?? []

        return VStack(alignment: .leading, spacing: 2) {
            if let date {
                HStack {
                    Text(date.formatted(.dateTime.day()))
                        .font(.system(size: 12, weight: isToday ? .bold : .regular, design: .rounded))
                        .foregroundStyle(isToday ? MacTheme.accent : MacTheme.textPrimary)
                        .padding(4)
                        .background(
                            isToday ? MacTheme.accent.opacity(0.12) : Color.clear,
                            in: Circle()
                        )
                    Spacer()
                }

                // Event dots (max 3 visible)
                ForEach(dayEvents.prefix(3)) { event in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(eventColor(event))
                            .frame(width: 4, height: 4)
                        Text(event.title)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(MacTheme.textSecondary)
                            .lineLimit(1)
                    }
                }

                if dayEvents.count > 3 {
                    Text("+\(dayEvents.count - 3) more")
                        .font(.system(size: 8))
                        .foregroundStyle(MacTheme.mutedText)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: 70, alignment: .topLeading)
        .padding(MacTheme.spacing4)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isToday ? MacTheme.accent.opacity(0.03) : MacTheme.emptyStateSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(isToday ? MacTheme.accent.opacity(0.15) : MacTheme.cardBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Helpers

    private func eventColor(_ event: CalendarEvent) -> Color {
        Color(hue: Double(event.calendarColor % 360) / 360.0, saturation: 0.5, brightness: 0.75)
    }

    private func loadEvents() async {
        guard hasAccess else { return }
        isLoading = true
        let cal = Calendar.current

        let (start, end): (Date, Date)
        switch viewMode {
        case "Day":
            let dayStart = cal.startOfDay(for: selectedDate)
            start = dayStart
            end = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        case "Month":
            let monthInterval = cal.dateInterval(of: .month, for: selectedDate)!
            start = monthInterval.start
            end = monthInterval.end
        default:
            let weekStart = cal.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
            start = weekStart
            end = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        }

        events = await services.calendarService.events(from: start, to: end)
        isLoading = false
    }
}
