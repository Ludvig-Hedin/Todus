import SwiftUI
import EventKit

/// Calendar view — shows events grouped by day with week navigation.
/// Desktop-optimized: multi-day view, wider event cards, hover states.
struct MacCalendarView: View {
    @Environment(MacAppServices.self) private var services

    @State private var selectedDate = Date()
    @State private var events: [CalendarEvent] = []
    @State private var isLoading = false
    @State private var hasAccess = false
    @State private var hoveredEventId: String? = nil

    /// Which week range to display
    private var weekDates: [Date] {
        let cal = Calendar.current
        let startOfWeek = cal.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: startOfWeek) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !hasAccess {
                permissionView
            } else {
                // Week navigation
                weekNavigation
                    .padding(.bottom, MacTheme.spacing16)

                // Day columns
                dayGrid
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

    // MARK: - Week Navigation

    private var weekNavigation: some View {
        HStack(spacing: MacTheme.spacing12) {
            Button {
                moveWeek(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacTheme.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius))
                    .overlay(RoundedRectangle(cornerRadius: MacTheme.buttonRadius).stroke(MacTheme.cardBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Text(weekRangeText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MacTheme.textPrimary)

            Button {
                moveWeek(by: 1)
            } label: {
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

    private var weekRangeText: String {
        guard let first = weekDates.first, let last = weekDates.last else { return "" }
        let cal = Calendar.current
        if cal.component(.month, from: first) == cal.component(.month, from: last) {
            return "\(first.formatted(.dateTime.month(.wide))) \(first.formatted(.dateTime.day()))–\(last.formatted(.dateTime.day())), \(first.formatted(.dateTime.year()))"
        } else {
            return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day())), \(last.formatted(.dateTime.year()))"
        }
    }

    // MARK: - Day Grid

    private var dayGrid: some View {
        HStack(alignment: .top, spacing: MacTheme.spacing4) {
            ForEach(weekDates, id: \.self) { date in
                dayColumn(date)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func dayColumn(_ date: Date) -> some View {
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
                            eventCard(event)
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

    private func eventCard(_ event: CalendarEvent) -> some View {
        HStack(spacing: MacTheme.spacing4) {
            Circle()
                .fill(Color(hue: Double(event.calendarColor % 360) / 360.0, saturation: 0.5, brightness: 0.75))
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

    // MARK: - Helpers

    private func moveWeek(by weeks: Int) {
        withAnimation(.easeOut(duration: 0.2)) {
            selectedDate = Calendar.current.date(byAdding: .weekOfYear, value: weeks, to: selectedDate) ?? selectedDate
        }
    }

    private func loadEvents() async {
        guard hasAccess else { return }
        isLoading = true
        let cal = Calendar.current
        let weekStart = cal.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        events = await services.calendarService.events(from: weekStart, to: weekEnd)
        isLoading = false
    }
}
