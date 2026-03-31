import SwiftUI
import SwiftData
import EventKit

/// Calendar view — Day, Week, Month, and Year modes.
/// Visual language modeled after Apple Calendar (macOS dark mode):
/// - Large "Month Year" title with lightweight font
/// - Colored pill event blocks (filled background, white text)
/// - Subtle grid lines, airy spacing
/// - Red current-time indicator
/// - Glass/material segmented control for view mode switching
struct MacCalendarView: View {
    @Environment(MacAppServices.self) private var services
    @Query(sort: \FolderRecord.createdAt) private var folders: [FolderRecord]

    @Binding var viewMode: String
    @Binding var selectedDate: Date
    @State private var events: [CalendarEvent] = []
    @State private var isLoading = false
    @State private var hasAccess = false
    @State private var selectedEvent: CalendarEvent? = nil
    /// Date passed from tap-to-create on the time grid — opens system Calendar's event creation
    @State private var createEventDate: Date? = nil

    var body: some View {
        VStack(spacing: 0) {
            if !hasAccess {
                permissionView
            } else {
                // Apple Calendar-style header: large title left, controls right
                calendarHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                // View content
                switch viewMode {
                case "Day":
                    dayView
                case "Month":
                    monthView
                case "Year":
                    yearView
                default:
                    weekView
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        // Keyboard shortcuts
        .background {
            Group {
                Button("") {
                    withAnimation(.easeOut(duration: 0.2)) { selectedDate = Date() }
                }
                .keyboardShortcut("t", modifiers: [])
                Button("") { navigate(by: -1) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
                Button("") { navigate(by: 1) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Permission View

    private var permissionView: some View {
        VStack {
            Spacer()
            // Single card containing prompt + grant access button
            VStack(spacing: MacTheme.spacing16) {
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
                Button {
                    Task {
                        hasAccess = await services.calendarService.requestAccess()
                        if hasAccess { await loadEvents() }
                    }
                } label: {
                    Text("Grant Access")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background(MacTheme.accent, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .pointerStyle(.link)
            }
            .padding(MacTheme.spacing24)
            .frame(maxWidth: 360)
            .background(MacTheme.emptyStateSurface, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Calendar Header
    // Modeled after Apple Calendar: "March 2026" large left, nav arrows + Today + picker right

    /// Shared control height — matches the segmented picker's inner height for visual alignment
    private let headerControlHeight: CGFloat = 30

    /// Shared background color for header controls — matches the segmented picker outer bg
    private var controlBg: Color {
        Color(light: Color(white: 0.88), dark: Color(white: 0.13))
    }

    private var calendarHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            // Large month/date title — Apple Calendar uses ~24pt regular weight
            Text(headerText)
                .font(MacTheme.calendarTitleFont())
                .foregroundStyle(MacTheme.textPrimary)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            // Navigation arrows — circular, same surface as picker
            HStack(spacing: 4) {
                calendarNavButton(icon: "chevron.left") { navigate(by: -1) }
                calendarNavButton(icon: "chevron.right") { navigate(by: 1) }
            }

            // Today — pill button, same surface as other controls
            Button {
                withAnimation(.easeOut(duration: 0.2)) { selectedDate = Date() }
            } label: {
                Text("Today")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .padding(.horizontal, 12)
                    .frame(height: headerControlHeight)
                    .background(controlBg, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .pointerStyle(.link)

            // Apple Calendar-style segmented control
            CalendarViewModePicker(selection: $viewMode)
        }
    }

    private var headerText: String {
        switch viewMode {
        case "Day":
            let dayNum = selectedDate.formatted(.dateTime.day())
            let month = selectedDate.formatted(.dateTime.month(.wide))
            let year = selectedDate.formatted(.dateTime.year())
            return "\(dayNum) \(month) \(year)"
        case "Month":
            return selectedDate.formatted(.dateTime.month(.wide).year())
        case "Year":
            return selectedDate.formatted(.dateTime.year())
        default:
            return selectedDate.formatted(.dateTime.month(.wide).year())
        }
    }

    private func folderName(for folderID: UUID?) -> String? {
        guard let folderID else { return nil }
        return folders.first(where: { $0.id == folderID })?.name
    }

    /// Fully circular chevron nav button — same surface color as picker & Today button
    private func calendarNavButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.65))
                .frame(width: headerControlHeight, height: headerControlHeight)
                .background(controlBg, in: Circle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .pointerStyle(.link)
    }

    private func navigate(by offset: Int) {
        let cal = Calendar.current
        // Month view uses instant swap (no animation) to avoid confusing grid cell movement.
        // Other views use a subtle transition.
        let animated = viewMode != "Month"
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
        case "Day":
            selectedDate = cal.date(byAdding: .day, value: offset, to: selectedDate) ?? selectedDate
        case "Month":
            selectedDate = cal.date(byAdding: .month, value: offset, to: selectedDate) ?? selectedDate
        case "Year":
            selectedDate = cal.date(byAdding: .year, value: offset, to: selectedDate) ?? selectedDate
        default:
            selectedDate = cal.date(byAdding: .weekOfYear, value: offset, to: selectedDate) ?? selectedDate
        }
    }

    // MARK: - Day View

    private var dayView: some View {
        let cal = Calendar.current
        let dayEvents = events.filter { cal.isDate($0.startDate, inSameDayAs: selectedDate) }
        let allDayEvents = dayEvents.filter(\.isAllDay)
        let timedEvents = dayEvents.filter { !$0.isAllDay }

        return VStack(spacing: 0) {
            // Day-of-week subtitle
            HStack {
                Text(selectedDate.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(MacTheme.mutedText)
                    .padding(.leading, 16)
                Spacer()
            }
            .padding(.bottom, 4)

            // All-day events bar — Apple style: colored pill blocks
            if !allDayEvents.isEmpty {
                allDayBar(allDayEvents)
            }

            Divider()

            // Time grid — single column for day view
            CalendarTimeGridView(
                columns: [
                    CalendarTimeGridColumn(date: selectedDate, events: timedEvents)
                ],
                highlightToday: true,
                onEventTap: { event in selectedEvent = event },
                onGridTap: { date in openNewEvent(at: date) }
            )
        }
        .popover(item: $selectedEvent, arrowEdge: .trailing) { event in
            eventPopover(event)
        }
    }

    // MARK: - Week View

    private var weekDates: [Date] {
        let cal = Calendar.current
        let startOfWeek = cal.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: startOfWeek) }
    }

    private var weekView: some View {
        let cal = Calendar.current
        // Group all-day events by their day column
        let weekAllDay = events.filter(\.isAllDay)
        let allDayByDay: [Date: [CalendarEvent]] = Dictionary(
            grouping: weekAllDay,
            by: { cal.startOfDay(for: $0.startDate) }
        )
        let hasAnyAllDay = !weekAllDay.isEmpty

        return VStack(spacing: 0) {
            // ── Compact header area (day names + all-day events) ──
            // fixedSize prevents Color-based spacers from expanding vertically
            VStack(spacing: 0) {
                // Day header row — Apple Calendar style: "Mon", "Tue" with date number
                HStack(spacing: 0) {
                    // Gutter spacer — invisible text so it doesn't expand vertically
                    // (Color.clear expands greedily in both axes, causing the tall header bug)
                    Text("")
                        .frame(width: MacTheme.calendarGutterWidth)

                    ForEach(Array(weekDates.enumerated()), id: \.offset) { index, date in
                        let isToday = cal.isDateInToday(date)

                        VStack(spacing: 1) {
                            Text(date.formatted(.dateTime.weekday(.abbreviated)))
                                .font(MacTheme.calendarWeekdayFont())
                                .foregroundStyle(isToday ? MacTheme.calendarNowIndicator : MacTheme.mutedText)

                            Text(date.formatted(.dateTime.day()))
                                .font(MacTheme.calendarDayNumberFont(isToday: isToday))
                                .foregroundStyle(isToday ? .white : MacTheme.textPrimary)
                                .frame(width: 22, height: 22)
                                .background {
                                    if isToday {
                                        Circle().fill(MacTheme.calendarNowIndicator)
                                    }
                                }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) {
                                selectedDate = date
                                viewMode = "Day"
                            }
                        }

                        if index < 6 {
                            Rectangle()
                                .fill(MacTheme.calendarGridLine)
                                .frame(width: 0.5)
                        }
                    }
                }

                // All-day events row — compact, one row per day column
                if hasAnyAllDay {
                    Divider()

                    HStack(alignment: .top, spacing: 0) {
                        Text("all-day")
                            .font(.system(size: 10, weight: .light))
                            .foregroundStyle(MacTheme.mutedText)
                            .frame(width: MacTheme.calendarGutterWidth, alignment: .trailing)
                            .padding(.trailing, 4)
                            .padding(.top, 2)

                        ForEach(Array(weekDates.enumerated()), id: \.offset) { index, date in
                            let dayStart = cal.startOfDay(for: date)
                            let dayAllDay = allDayByDay[dayStart] ?? []

                            VStack(alignment: .leading, spacing: 1) {
                                ForEach(dayAllDay) { event in
                                    let color = Color(red: event.calendarColorRed, green: event.calendarColorGreen, blue: event.calendarColorBlue)
                                    Text(event.title)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 1.5)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                                .fill(color.opacity(0.85))
                                        )
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedEvent = event
                                        }
                                        .contextMenu {
                                            eventContextMenu(event)
                                        }
                                }
                            }
                            .padding(.horizontal, 1)
                            .frame(maxWidth: .infinity, alignment: .topLeading)

                            if index < 6 {
                                Rectangle()
                                    .fill(MacTheme.calendarGridLine)
                                    .frame(width: 0.5)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                    .background(MacTheme.calendarAllDayBg)
                }
            }
            // CRITICAL: forces the header area to use only its intrinsic content height,
            // preventing Color/Rectangle spacers from expanding vertically
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            // ── 7-column time grid (fills remaining space) ──
            let columns = weekDates.map { date in
                let dayEvents = events.filter { !$0.isAllDay && cal.isDate($0.startDate, inSameDayAs: date) }
                return CalendarTimeGridColumn(date: date, events: dayEvents)
            }

            CalendarTimeGridView(
                columns: columns,
                highlightToday: true,
                onEventTap: { event in selectedEvent = event },
                onGridTap: { date in openNewEvent(at: date) }
            )
        }
        .popover(item: $selectedEvent, arrowEdge: .trailing) { event in
            eventPopover(event)
        }
    }

    // MARK: - All-Day Events Bar

    /// Apple Calendar style: full-width colored pill blocks for all-day events
    private func allDayBar(_ allDayEvents: [CalendarEvent]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // "all-day" label in the gutter area
            Text("all-day")
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(MacTheme.mutedText)
                .frame(width: MacTheme.calendarGutterWidth - 6, alignment: .trailing)
                .padding(.top, 4)

            // Event pills
            VStack(alignment: .leading, spacing: 2) {
                ForEach(allDayEvents) { event in
                    let color = Color(red: event.calendarColorRed, green: event.calendarColorGreen, blue: event.calendarColorBlue)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(color)
                            .frame(width: 6, height: 6)
                        Text(event.title)
                            .font(MacTheme.calendarMonthEventFont())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule(style: .continuous).fill(color.opacity(0.85)))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedEvent = event
                    }
                    .contextMenu {
                        eventContextMenu(event)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)

            Spacer(minLength: 0)
        }
        .background(MacTheme.calendarAllDayBg)
    }

    // MARK: - Month View

    /// Apple Calendar-style month grid: weekday headers, bordered cells,
    /// events as colored pill blocks. Shows prev/next month days muted.
    /// No animation on month swap — instant transition to avoid confusing grid movement.
    private var monthView: some View {
        let cal = Calendar.current

        // Weekday symbols rotated to locale's first weekday
        let symbols = cal.shortWeekdaySymbols
        let offset = cal.firstWeekday - 1
        let rotatedSymbols = Array(symbols[offset...]) + Array(symbols[..<offset])

        return VStack(spacing: 0) {
            // Weekday header row — fixed at top
            HStack(spacing: 0) {
                ForEach(Array(rotatedSymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(MacTheme.calendarWeekdayFont())
                        .foregroundStyle(MacTheme.mutedText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            // Month grid — fills remaining height, scrollable vertically
            GeometryReader { geo in
                let gridDates = monthGridDates(for: selectedDate)
                let totalRows = gridDates.count / 7
                let rowHeight = max(80, geo.size.height / CGFloat(totalRows))
                let selectedMonth = cal.component(.month, from: selectedDate)

                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                        spacing: 0
                    ) {
                        ForEach(Array(gridDates.enumerated()), id: \.offset) { _, date in
                            let isCurrentMonth = cal.component(.month, from: date) == selectedMonth
                            monthDayCell(date, rowHeight: rowHeight, isMuted: !isCurrentMonth)
                        }
                    }
                }
                // Disable animation on the grid content itself — prevents the "circus" effect
                // when navigating months. The grid swaps instantly.
                .animation(.none, value: selectedDate)
            }
        }
    }

    /// Builds the full 6-row (42-cell) grid of dates for a month view.
    /// Includes trailing days from the previous month and leading days from the next month,
    /// so the grid is always complete with no empty cells — matching Apple Calendar.
    private func monthGridDates(for date: Date) -> [Date] {
        let cal = Calendar.current
        let monthInterval = cal.dateInterval(of: .month, for: date)!
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
        let daysInMonth = cal.range(of: .day, in: .month, for: date)!
        for day in daysInMonth {
            if let d = cal.date(bySetting: .day, value: day, of: firstDayOfMonth) {
                dates.append(d)
            }
        }

        // Next month's leading days — fill to complete the last row (multiple of 7)
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

    // MARK: - Year View

    /// Infinite-scroll year view — shows years as rows of 4×3 mini-month grids.
    /// Scrolls vertically through multiple years, auto-centering on the current year.
    private var yearView: some View {
        let cal = Calendar.current
        let currentYear = cal.component(.year, from: selectedDate)
        // Range: 10 years back to 10 years forward for effectively infinite scrolling
        let yearRange = (currentYear - 10)...(currentYear + 10)

        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 32) {
                    ForEach(Array(yearRange), id: \.self) { year in
                        yearSection(year: year)
                            .id("year-\(year)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onAppear {
                // Auto-scroll to the selected year
                proxy.scrollTo("year-\(currentYear)", anchor: .top)
            }
        }
    }

    /// A full year section: year label + 4×3 grid of mini-month calendars
    private func yearSection(year: Int) -> some View {
        let cal = Calendar.current
        let currentYear = cal.component(.year, from: Date())
        let isCurrentYear = year == currentYear

        return VStack(alignment: .leading, spacing: 12) {
            // Year label
            Text(String(year))
                .font(.system(size: 20, weight: isCurrentYear ? .semibold : .regular))
                .foregroundStyle(isCurrentYear ? MacTheme.textPrimary : MacTheme.textSecondary)
                .padding(.leading, 4)

            // 4 rows × 3 columns of mini months
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4),
                spacing: 16
            ) {
                ForEach(1...12, id: \.self) { month in
                    miniMonthCell(year: year, month: month)
                }
            }
        }
    }

    /// A compact mini-month calendar for the year view.
    /// Shows month name + weekday initials + day number grid.
    /// Days with events get a small colored dot. Today is circled in red.
    private func miniMonthCell(year: Int, month: Int) -> some View {
        let cal = Calendar.current
        let today = Date()
        let todayComps = cal.dateComponents([.year, .month, .day], from: today)

        // Build the first day of this month
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let firstOfMonth = cal.date(from: comps) else {
            return AnyView(EmptyView())
        }

        let daysInMonth = cal.range(of: .day, in: .month, for: firstOfMonth)!
        let firstWeekday = cal.component(.weekday, from: firstOfMonth)
        let firstWeekdayOffset = (firstWeekday - cal.firstWeekday + 7) % 7

        // Month name
        let monthName = firstOfMonth.formatted(.dateTime.month(.wide))
        let isCurrentMonth = year == todayComps.year && month == todayComps.month

        // Weekday initials (M T W T F S S) rotated to locale
        let symbols = cal.veryShortWeekdaySymbols
        let offset = cal.firstWeekday - 1
        let rotated = Array(symbols[offset...]) + Array(symbols[..<offset])

        // Dates that have events (for dot indicators)
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
            VStack(alignment: .leading, spacing: 4) {
                // Month title — tappable to navigate to month view
                Text(monthName)
                    .font(.system(size: 12, weight: isCurrentMonth ? .semibold : .medium))
                    .foregroundStyle(isCurrentMonth ? MacTheme.calendarNowIndicator : MacTheme.textPrimary)

                // Weekday initials header
                HStack(spacing: 0) {
                    ForEach(Array(rotated.enumerated()), id: \.offset) { _, sym in
                        Text(sym)
                            .font(.system(size: 8, weight: .regular))
                            .foregroundStyle(MacTheme.mutedText)
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
                            .frame(height: 14)
                    }

                    // Day numbers
                    ForEach(Array(daysInMonth), id: \.self) { day in
                        let isToday = year == todayComps.year && month == todayComps.month && day == todayComps.day
                        let hasEvent = eventDates.contains(day)

                        VStack(spacing: 0) {
                            Text("\(day)")
                                .font(.system(size: 9, weight: isToday ? .bold : .regular))
                                .foregroundStyle(isToday ? .white : MacTheme.textPrimary)
                                .frame(width: 14, height: 14)
                                .background {
                                    if isToday {
                                        Circle().fill(MacTheme.calendarNowIndicator)
                                    }
                                }

                            // Event dot indicator
                            Circle()
                                .fill(hasEvent ? MacTheme.accent : Color.clear)
                                .frame(width: 3, height: 3)
                        }
                        .frame(height: 18)
                    }
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(MacTheme.surfaceCard.opacity(isCurrentMonth ? 1 : 0.5))
            )
            .contentShape(Rectangle())
            .onTapGesture {
                // Navigate to this month in Month view
                if let date = cal.date(from: DateComponents(year: year, month: month, day: 1)) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedDate = date
                        viewMode = "Month"
                    }
                }
            }
        )
    }

    /// Calculate how many rows the month grid needs
    private func numberOfRows(firstWeekdayOffset: Int, daysInMonth: Int) -> Int {
        let totalCells = firstWeekdayOffset + daysInMonth
        return (totalCells + 6) / 7
    }

    /// A single month grid cell — Apple Calendar style.
    /// Shows day number top-right, events as colored pill blocks.
    /// `isMuted` dims the cell for days belonging to the adjacent months (prev/next).
    private func monthDayCell(_ date: Date, rowHeight: CGFloat, isMuted: Bool = false) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(date)
        let dayEvents = events.filter { cal.isDate($0.startDate, inSameDayAs: date) }
            .sorted { $0.startDate < $1.startDate }

        return VStack(alignment: .leading, spacing: 2) {
            // Day number — top-right aligned like Apple Calendar
            HStack {
                Spacer()
                Text(date.formatted(.dateTime.day()))
                    .font(MacTheme.calendarDayNumberFont(isToday: isToday))
                    .foregroundStyle(isToday ? .white : isMuted ? MacTheme.mutedText : MacTheme.textPrimary)
                    .frame(width: 20, height: 20)
                    .background {
                        if isToday {
                            Circle().fill(MacTheme.calendarNowIndicator)
                        }
                    }
            }
            .padding(.trailing, 4)
            .padding(.top, 2)

            // Events as colored pill blocks — dimmed for non-current month days
            VStack(alignment: .leading, spacing: 1) {
                let maxVisible = max(1, Int((rowHeight - 32) / 16))
                let visible = Array(dayEvents.prefix(maxVisible))
                let remaining = dayEvents.count - visible.count

                ForEach(visible) { event in
                    monthEventPill(event)
                }

                if remaining > 0 {
                    Text("+\(remaining) more")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                        .padding(.leading, 4)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(height: rowHeight, alignment: .topLeading)
        .padding(.horizontal, 2)
        .opacity(isMuted ? 0.35 : 1.0)
        // Grid border — Apple Calendar uses thin cell borders
        .overlay(
            Rectangle()
                .stroke(MacTheme.calendarGridLine, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // Tapping a muted day navigates to that day (which also changes the month)
            selectedDate = date
            viewMode = "Day"
        }
    }

    /// Individual event pill in the month grid.
    /// All-day: full-width colored bar with white text (Apple style).
    /// Timed: colored left bar + title + time right-aligned.
    private func monthEventPill(_ event: CalendarEvent) -> some View {
        let color = Color(red: event.calendarColorRed, green: event.calendarColorGreen, blue: event.calendarColorBlue)

        return Group {
            if event.isAllDay {
                // All-day: full colored bar — Apple Calendar signature
                HStack(spacing: 3) {
                    Circle()
                        .fill(.white.opacity(0.9))
                        .frame(width: 4, height: 4)
                    Text(event.title)
                        .font(MacTheme.calendarMonthEventFont())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: MacTheme.calendarEventRadius, style: .continuous)
                        .fill(color.opacity(0.85))
                )
            } else {
                // Timed event: colored left bar + title + time
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(width: 2.5, height: 10)
                    Text(event.title)
                        .font(MacTheme.calendarMonthEventFont())
                        .foregroundStyle(MacTheme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text(event.startDate.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(MacTheme.mutedText)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedEvent = event
        }
        .contextMenu {
            eventContextMenu(event)
        }
    }

    // MARK: - Event Popover

    private func eventPopover(_ event: CalendarEvent) -> some View {
        let color = Color(red: event.calendarColorRed, green: event.calendarColorGreen, blue: event.calendarColorBlue)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 4, height: 20)
                Text(event.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
            }

            if event.isAllDay {
                Label("All day", systemImage: "clock")
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.textSecondary)
            } else {
                Label {
                    Text("\(event.startDate.formatted(date: .abbreviated, time: .shortened)) – \(event.endDate.formatted(date: .omitted, time: .shortened))")
                } icon: {
                    Image(systemName: "clock")
                }
                .font(.system(size: 12))
                .foregroundStyle(MacTheme.textSecondary)
            }

            Label(event.calendarName, systemImage: "calendar")
                .font(.system(size: 12))
                .foregroundStyle(MacTheme.textSecondary)

            if let folderName = folderName(for: event.folderID) {
                Label(folderName, systemImage: "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.textSecondary)
            }

            Menu {
                Button("Unfiled") {
                    moveEvent(event, to: nil)
                }
                if !folders.isEmpty {
                    Divider()
                }
                ForEach(folders) { folder in
                    Button(folder.name) {
                        moveEvent(event, to: folder.id)
                    }
                }
            } label: {
                Label("Move to Folder", systemImage: "folder")
                    .font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
        }
        .padding(14)
        .frame(minWidth: 220, alignment: .leading)
    }

    // MARK: - Tap-to-Create

    /// Opens the system Calendar app with a new event at the given date/time.
    /// Uses the calshow: URL scheme to open Calendar.app to the correct date,
    /// then AppleScript to open the new-event dialog. Falls back to just opening Calendar.
    private func openNewEvent(at date: Date) {
        // Apple Calendar uses seconds since 2001-01-01 (Core Data reference date) for calshow:
        let refDate = date.timeIntervalSinceReferenceDate
        if let url = URL(string: "x-apple-calevent://new?startDate=\(refDate)") {
            NSWorkspace.shared.open(url)
        } else if let fallback = URL(string: "ical://") {
            NSWorkspace.shared.open(fallback)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func eventContextMenu(_ event: CalendarEvent) -> some View {
        Button {
            if let url = URL(string: "x-apple-calevent://\(event.id)") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Label("Open in Calendar", systemImage: "arrow.up.forward.app")
        }
        Divider()
        Button(role: .destructive) {
            // TODO: wire calendar event deletion once the calendar service exposes it.
        } label: {
            Label("Delete Event", systemImage: "trash")
        }
        .disabled(true)
    }

    // MARK: - Data Loading

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
            // Load extra for prev/next month days visible in the grid (up to 6 days each side)
            let monthInterval = cal.dateInterval(of: .month, for: selectedDate)!
            start = cal.date(byAdding: .day, value: -10, to: monthInterval.start) ?? monthInterval.start
            end = cal.date(byAdding: .day, value: 10, to: monthInterval.end) ?? monthInterval.end
        case "Year":
            // Load the full selected year for event dot indicators on mini-months
            let year = cal.component(.year, from: selectedDate)
            start = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? selectedDate
            end = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? selectedDate
        default:
            let weekStart = cal.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
            start = weekStart
            end = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        }

        events = await services.calendarService.events(from: start, to: end)
        isLoading = false
    }

    private func moveEvent(_ event: CalendarEvent, to folderID: UUID?) {
        Task {
            await services.calendarService.setFolderID(folderID, for: event.id)
            await loadEvents()
        }
    }
}

// MARK: - Apple Calendar-Style Glass Segmented Control

/// Custom segmented control matching Apple Calendar's glass/material design:
/// - Rounded pill container with frosted glass material
/// - Selected segment highlighted with a visible lighter capsule pill + shadow
/// - Smooth animated selection via `matchedGeometryEffect`
/// - Respects light/dark mode automatically via Material
/// - Height matches the header nav buttons for visual consistency
///
/// Reference: https://developer.apple.com/design/human-interface-guidelines/segmented-controls
struct CalendarViewModePicker: View {
    @Binding var selection: String
    @Namespace private var pickerNamespace

    private let modes = ["Day", "Week", "Month", "Year"]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(modes, id: \.self) { mode in
                let isSelected = selection == mode

                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        selection = mode
                    }
                } label: {
                    Text(mode)
                        .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if isSelected {
                                // Visible pill highlight — solid surface with shadow for clear contrast
                                Capsule(style: .continuous)
                                    .fill(Color(light: Color.white, dark: Color(white: 0.22)))
                                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "picker-highlight", in: pickerNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
            }
        }
        .padding(3)
        .background(
            Color(light: Color(white: 0.88), dark: Color(white: 0.13)),
            in: Capsule(style: .continuous)
        )
    }
}
