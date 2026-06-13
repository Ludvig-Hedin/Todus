import AppKit
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
    /// Drives the native in-app event create/edit sheet. When non-nil the
    /// `MacEventEditSheet` is presented in either `.create` or `.edit` mode.
    /// Replaces the previous "open in Calendar.app" delegation; the system
    /// Calendar app remains available as a context-menu fallback.
    @State private var eventSheetRequest: EventSheetRequest? = nil

    /// Identifiable wrapper so `.sheet(item:)` can present an
    /// `MacEventEditSheet.Mode` (enum without a stable identity).
    private struct EventSheetRequest: Identifiable {
        let id = UUID()
        let mode: MacEventEditSheet.Mode
    }
    /// Vertical month list scroll position (yyyy-MM) — `nil` before first layout.
    @State private var monthScrollID: String?
    /// AppKit window-space rect for trackpad hit testing; `.null` = whole key window
    @State private var trackpadContentRect: CGRect = .null
    /// Measured `ScrollView` width for week time grid (aligns day headers with grid columns)
    @State private var weekTimeGridViewportWidth: CGFloat? = nil
    /// Toggles the popover that lists every calendar source (Apple + each Google
    /// connection) with visibility checkboxes. Mirrors Apple Calendar's button.
    @State private var showCalendarPicker: Bool = false
    /// Surfaced when any backend Google Calendar call returns scopeMissing.
    @State private var showScopeMissingBanner: Bool = false
    /// Live horizontal pan offset while the user swipes in week view.
    @State private var weekDragOffset: CGFloat = 0
    /// Transient feedback for calendar actions (open-in-Calendar failures,
    /// move-event completion). Used via the shared `MacToast` overlay.
    @State private var calendarToast: MacToastMessage?
    /// Tracks an in-flight move-event request so the context-menu items
    /// disable rather than firing duplicate moves.
    @State private var isMovingEvent = false
    /// Measured width of the week view container — used for rubber-band and snap thresholds.
    @State private var weekViewWidth: CGFloat = 400
    /// Day-keyed event lookup for month view — avoids O(N) filter per cell during scroll.
    @State private var cachedEventsByDay: [String: [CalendarEvent]] = [:]

    /// Re-binds the trackpad / pinch handler when mode or focus date changes.
    private var trackpadActionSyncKey: String {
        "\(viewMode)|\(selectedDate.timeIntervalSince1970)"
    }

    private static let calendarViewModes: [String] = ["Day", "Week", "Month", "Year"]

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

                if showScopeMissingBanner {
                    scopeMissingBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

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
        .macToast($calendarToast)
        .sheet(item: $eventSheetRequest) { request in
            MacEventEditSheet(mode: request.mode) {
                // Reload events immediately after a save/delete so the new or
                // edited event appears without waiting for EKEventStoreChanged.
                Task { await loadEvents() }
            }
            .environment(services)
        }
        .onReceive(NotificationCenter.default.publisher(for: .todusCalendarScopeMissing)) { _ in
            // Show the banner so the user can reconnect Google Calendar scope.
            withAnimation(MacTheme.Motion.base) {
                showScopeMissingBanner = true
            }
        }
        // Trackpad: dominant horizontal two-finger scroll steps time; pinch changes Day↔…↔Year.
        // In Week mode, onHorizontalStream/onHorizontalGestureEnded drive real-time panning.
        .calendarTrackpadNavigation(
            isEnabled: hasAccess,
            targetRectInWindow: $trackpadContentRect,
            updateWhen: trackpadActionSyncKey,
            isTimeGridViewMode: viewMode == "Day" || viewMode == "Week",
            onHorizontalStream: viewMode == "Week" ? { d in handleWeekDragDelta(d) } : nil,
            onHorizontalGestureEnded: viewMode == "Week"
                ? { d in handleWeekGestureEnded(d) } : nil
        ) { direction in
            handleTrackpadHorizontalNavigate(direction)
        }
        .calendarPinchViewMode(
            isEnabled: hasAccess,
            targetRectInWindow: $trackpadContentRect,
            updateWhen: trackpadActionSyncKey
        ) { step in
            stepCalendarViewMode(step)
        }
        .help("In Day/Week, drag two fingers left/right to change day or week, or hold ⇧ and scroll. Pinch in or out to zoom the calendar (Day, Week, Month, Year). In Month, scroll up/down between months. ⌥⌘D/W/M/Y switches view; ⇧⌘T jumps to today.")
        .task {
            hasAccess = services.calendarService.canReadEvents()
            if !hasAccess {
                hasAccess = await services.calendarService.requestAccess()
            }
            await loadEvents()
        }
        .onChange(of: selectedDate) { _, d in
            weekDragOffset = 0
            if viewMode == "Month" {
                let t = weekToken(for: startOfWeek(for: d))
                if monthScrollID != t {
                    withAnimation(Self.calendarPageSpring) { monthScrollID = t }
                }
            }
            Task { await loadEvents() }
        }
        .onChange(of: viewMode) { _, newMode in
            weekDragOffset = 0
            if newMode == "Month" {
                monthScrollID = weekToken(for: startOfWeek(for: selectedDate))
            }
            if newMode != "Week" {
                weekTimeGridViewportWidth = nil
            }
            Task { await loadEvents() }
        }
        // Keyboard shortcuts. We deliberately avoid:
        //  - Bare "T" / "t" — would be swallowed even while typing in text fields.
        //  - ⌘1-4 — the root view binds these to top-level navigation; rebinding
        //    them here would fire BOTH (e.g. ⌘1 jumps to Home AND tries to
        //    switch view mode), giving the user unpredictable behaviour.
        //  - ⌘← / ⌘→ — those are macOS standard "start/end of line" inside any
        //    text field, including search and compose. Stealing them breaks
        //    text editing.
        // ⇧⌘T jumps to today (matches the visible "Today" button) and ⌥⌘D / ⌥⌘W
        // / ⌥⌘M / ⌥⌘Y switch view mode without colliding with the global
        // navigation shortcuts.
        .background {
            Group {
                Button("") {
                    withAnimation(MacTheme.Motion.base) { selectedDate = Date() }
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("") { setViewMode("Day") }
                    .keyboardShortcut("d", modifiers: [.command, .option])
                Button("") { setViewMode("Week") }
                    .keyboardShortcut("w", modifiers: [.command, .option])
                Button("") { setViewMode("Month") }
                    .keyboardShortcut("m", modifiers: [.command, .option])
                Button("") { setViewMode("Year") }
                    .keyboardShortcut("y", modifiers: [.command, .option])
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
                // Once the user has denied access, `requestAccess()` can no
                // longer re-prompt (the OS only asks once) — so the button would
                // silently no-op. Send them to System Settings instead.
                let isDenied = services.calendarService.authorizationStatus() == .denied
                Button {
                    if isDenied {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    } else {
                        Task {
                            hasAccess = await services.calendarService.requestAccess()
                            if hasAccess { await loadEvents() }
                        }
                    }
                } label: {
                    Text(isDenied ? "Open System Settings" : "Grant Access")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MacTheme.primaryButtonForeground)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background(MacTheme.accent, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .interactiveHitTarget(expansion: 6)
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

    // MARK: - Scope Missing Banner

    /// Shown above the calendar grid when the backend reports that a Google
    /// connection no longer has the Calendar OAuth scope. Provides a quick
    /// "Reconnect" entry point that reuses the existing Settings reconnect flow.
    private var scopeMissingBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
            Text("Google Calendar access expired. Reconnect to sync events.")
                .font(.system(size: 12))
                .foregroundStyle(MacTheme.textPrimary)
            Spacer()
            Button {
                NotificationCenter.default.post(name: .todusRequestReconnectGmail, object: nil)
            } label: {
                Text("Reconnect Google")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MacTheme.primaryButtonForeground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(MacTheme.accent, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .pointerStyle(.link)
            Button {
                withAnimation(MacTheme.Motion.base) {
                    showScopeMissingBanner = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MacTheme.mutedText)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .pointerStyle(.link)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.10))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(MacTheme.cardBorder),
            alignment: .bottom
        )
    }

    // MARK: - Calendar Header
    // Modeled after Apple Calendar: "March 2026" large left, nav arrows + Today + picker right

    /// Shared control height — matches the segmented picker's inner height for visual alignment
    private let headerControlHeight: CGFloat = 30

    /// Shared background color for header controls — matches the segmented picker outer bg
    private var controlBg: Color {
        MacTheme.segmentedTrack
    }

    private var calendarHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            // Large month/date title — Apple Calendar uses ~24pt regular weight (no app-icon tile: avoids duplicate branding with the sidebar)
            Text(headerText)
                .font(MacTheme.calendarTitleFont())
                .foregroundStyle(MacTheme.textPrimary)

            if isLoading {
                if events.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    MacInlineRefreshBadge()
                }
            }

            Spacer()

            // Navigation arrows — circular, same surface as picker
            HStack(spacing: 4) {
                calendarNavButton(icon: "chevron.left") { navigate(by: -1) }
                    .accessibilityLabel("Previous \(viewMode.lowercased())")
                calendarNavButton(icon: "chevron.right") { navigate(by: 1) }
                    .accessibilityLabel("Next \(viewMode.lowercased())")
            }

            // Today — pill button, same surface as other controls
            Button {
                withAnimation(MacTheme.Motion.base) { selectedDate = Date() }
            } label: {
                Text("Today")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .padding(.horizontal, 12)
                    .frame(height: headerControlHeight)
                    .background(controlBg, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .interactiveHitTarget(expansion: 6)
            .focusEffectDisabled()
            .pointerStyle(.link)
            .accessibilityLabel("Jump to today")

            // Calendars — popover button matching Apple Calendar's UX.
            Button {
                showCalendarPicker.toggle()
            } label: {
                Image(systemName: "list.bullet.indent")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .frame(width: headerControlHeight, height: headerControlHeight)
                    .background(controlBg, in: Circle())
            }
            .buttonStyle(.plain)
            .interactiveHitTarget(expansion: 6)
            .focusEffectDisabled()
            .pointerStyle(.link)
            .popover(isPresented: $showCalendarPicker, arrowEdge: .top) {
                MacCalendarSourcePicker(onAddAccount: {
                    showCalendarPicker = false
                    NotificationCenter.default.post(name: .todusRequestConnectGmail, object: nil)
                })
                .environment(services)
                .frame(minWidth: 320, idealWidth: 360, minHeight: 240, idealHeight: 480)
            }

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
        .interactiveHitTarget(expansion: 6)
        .focusEffectDisabled()
        .pointerStyle(.link)
    }

    private static let calendarPageSpring: Animation = .interpolatingSpring(
        stiffness: 280,
        damping: 32,
        initialVelocity: 0
    )

    private func navigate(by offset: Int) {
        let cal = Calendar.current
        withAnimation(Self.calendarPageSpring) {
            applyNavigation(offset: offset, cal: cal)
        }
    }

    private func handleTrackpadHorizontalNavigate(_ direction: Int) {
        navigate(by: direction)
    }

    // MARK: - Week view smooth swipe

    /// Called each trackpad frame while the user is panning horizontally in week view.
    /// Applies rubber-band dampening once the content is dragged past 40 % of the view width.
    private func handleWeekDragDelta(_ delta: CGFloat) {
        let softEdge = weekViewWidth * 0.40
        let newRaw = weekDragOffset + delta
        let clamped: CGFloat
        if abs(newRaw) > softEdge {
            let excess = abs(newRaw) - softEdge
            clamped = (newRaw < 0 ? -1 : 1) * (softEdge + excess * 0.25)
        } else {
            clamped = newRaw
        }
        weekDragOffset = min(max(clamped, -weekViewWidth * 0.55), weekViewWidth * 0.55)
    }

    /// Called once when the finger lifts. Decides whether to snap to the adjacent week or spring back.
    private func handleWeekGestureEnded(_ totalDelta: CGFloat) {
        let commitThreshold = weekViewWidth * 0.20
        if weekDragOffset > commitThreshold {
            snapWeekView(direction: -1)
        } else if weekDragOffset < -commitThreshold {
            snapWeekView(direction: 1)
        } else {
            withAnimation(.interpolatingSpring(stiffness: 420, damping: 36)) {
                weekDragOffset = 0
            }
        }
    }

    /// Slides the week content off-screen, navigates to the adjacent week, then resets the offset.
    private func snapWeekView(direction: Int) {
        let exitOffset = direction > 0 ? -weekViewWidth : weekViewWidth
        withAnimation(.easeIn(duration: 0.16), completionCriteria: .logicallyComplete) {
            weekDragOffset = exitOffset
        } completion: {
            applyNavigation(offset: direction, cal: Calendar.current)
            weekDragOffset = 0
        }
    }

    private func setViewMode(_ mode: String) {
        guard Self.calendarViewModes.contains(mode), viewMode != mode else { return }
        withAnimation(MacTheme.Motion.base) { viewMode = mode }
    }

    /// Pinch: `step` +1 = zoom out (toward Year), -1 = zoom in (toward Day).
    private func stepCalendarViewMode(_ step: Int) {
        guard let i = Self.calendarViewModes.firstIndex(of: viewMode) else { return }
        let ni = min(max(0, i + step), Self.calendarViewModes.count - 1)
        guard ni != i else { return }
        withAnimation(.interpolatingSpring(stiffness: 300, damping: 28, initialVelocity: 0)) {
            viewMode = Self.calendarViewModes[ni]
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

    /// Week-start anchors (calendar first weekday) for vertical month-mode scrolling, 2018…2036.
    private static let stackedWeekStarts: [Date] = {
        let c = Calendar.current
        guard let jan = c.date(from: DateComponents(year: 2018, month: 1, day: 1)),
              let wStart = c.dateInterval(of: .weekOfYear, for: jan)?.start,
              let end = c.date(from: DateComponents(year: 2036, month: 12, day: 31))
        else { return [] }
        var d = wStart
        var out: [Date] = []
        while d <= end {
            out.append(d)
            guard let n = c.date(byAdding: .day, value: 7, to: d) else { break }
            d = n
        }
        return out
    }()

    private func firstOfMonth(_ date: Date) -> Date {
        let c = Calendar.current
        return c.date(from: c.dateComponents([.year, .month], from: date)) ?? date
    }

    private func startOfWeek(for date: Date) -> Date {
        let c = Calendar.current
        return c.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    private func weekToken(for weekStart: Date) -> String {
        let c = Calendar.current
        let y = c.component(.year, from: weekStart)
        let m = c.component(.month, from: weekStart)
        let d = c.component(.day, from: weekStart)
        return String(format: "%d-%02d-%02d", y, m, d)
    }

    private func dateFromWeekToken(_ token: String) -> Date? {
        let parts = token.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        return Calendar.current.date(from: DateComponents(year: y, month: m, day: d))
    }

    /// Which calendar month a week “belongs to” (majority of the 7 days) — drives muted styling at month edges.
    private func dominantMonthInWeek(weekStart: Date) -> Int {
        let c = Calendar.current
        var counts: [Int: Int] = [:]
        for i in 0..<7 {
            guard let day = c.date(byAdding: .day, value: i, to: weekStart) else { continue }
            let m = c.component(.month, from: day)
            counts[m, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? c.component(.month, from: weekStart)
    }

    private func rotatedWeekdaySymbols() -> [String] {
        let cal = Calendar.current
        let symbols = cal.shortWeekdaySymbols
        let offset = cal.firstWeekday - 1
        return Array(symbols[offset...]) + Array(symbols[..<offset])
    }

    // MARK: - Day View

    private var dayView: some View {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: selectedDate)
        let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        // All-day pills use overlap so a multi-day all-day event (e.g. a trip)
        // shows on every day it spans, not just its first day. (EventKit stores
        // all-day end exclusively at the next midnight, so `endDate > startOfDay`.)
        let allDayEvents = events.filter { $0.isAllDay && $0.startDate < endOfDay && $0.endDate > startOfDay }
        // Timed events use overlap, not start-day equality, so a multi-day event
        // that began on an earlier day still appears here. Mirrors the week grid;
        // the time grid clips at midnight.
        let timedEvents = events.filter { !$0.isAllDay && $0.startDate < endOfDay && $0.endDate > startOfDay }

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
                onEventTap: { event in openEditEvent(event) },
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
        let weekAllDay = events.filter(\.isAllDay)
        // Map each weekday to every all-day event overlapping it (not just events
        // that *start* that day) so multi-day spans appear across all their days.
        let allDayByDay: [Date: [CalendarEvent]] = {
            var map: [Date: [CalendarEvent]] = [:]
            for day in weekDates {
                let dayStart = cal.startOfDay(for: day)
                let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
                map[dayStart] = weekAllDay.filter { $0.startDate < dayEnd && $0.endDate > dayStart }
            }
            return map
        }()
        let hasAnyAllDay = !weekAllDay.isEmpty
        let columnCount = weekDates.count

        return GeometryReader { geo in
            // Prefer the time grid’s measured width so all three rows share one column system.
            let totalW = (weekTimeGridViewportWidth ?? geo.size.width)
            let dayW = MacTheme.calendarDayColumnWidth(totalWidth: totalW, columnCount: columnCount)
            let columns = weekDates.map { date -> CalendarTimeGridColumn in
                // Use overlap rather than start-day equality so multi-day timed
                // events (e.g. an event spanning Tue → Thu) render in every
                // affected column. CalendarTimeGridView clips at midnight.
                let startOfDay = cal.startOfDay(for: date)
                let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
                let dayEvents = events.filter {
                    !$0.isAllDay && $0.startDate < endOfDay && $0.endDate > startOfDay
                }
                return CalendarTimeGridColumn(date: date, events: dayEvents)
            }
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(MacTheme.calendarGutterBackground)
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
                            .frame(width: dayW)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(MacTheme.Motion.base) {
                                    selectedDate = date
                                    viewMode = "Day"
                                }
                            }
                            if index < columnCount - 1 {
                                Rectangle()
                                    .fill(MacTheme.calendarGridLine)
                                    .frame(width: MacTheme.calendarColumnSeparatorWidth)
                            }
                        }
                    }

                    if hasAnyAllDay {
                        Divider()
                        HStack(alignment: .top, spacing: 0) {
                            // Fixed gutter — `frame` + `padding` must not add width (was shifting day columns a few pt right vs header/grid).
                            ZStack(alignment: .trailing) {
                                Text("all-day")
                                    .font(.system(size: 10, weight: .light))
                                    .foregroundStyle(MacTheme.mutedText)
                                    .padding(.trailing, 4)
                                    .padding(.top, 2)
                            }
                            .frame(width: MacTheme.calendarGutterWidth, height: nil, alignment: .top)
                            HStack(alignment: .top, spacing: 0) {
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
                                                .onTapGesture { openEditEvent(event) }
                                                .contextMenu { eventContextMenu(event) }
                                        }
                                    }
                                    .frame(width: dayW, alignment: .topLeading)
                                    if index < columnCount - 1 {
                                        Rectangle()
                                            .fill(MacTheme.calendarGridLine)
                                            .frame(width: MacTheme.calendarColumnSeparatorWidth)
                                    }
                                }
                            }
                            .background(MacTheme.calendarAllDayBg)
                        }
                        .padding(.vertical, 3)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: geo.size.width, alignment: .topLeading)
                Divider()
                CalendarTimeGridView(
                    columns: columns,
                    dayColumnWidth: dayW,
                    highlightToday: true,
                    onEventTap: { event in openEditEvent(event) },
                    onGridTap: { date in openNewEvent(at: date) }
                )
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .offset(x: weekDragOffset)
            .onPreferenceChange(WeekTimeGridViewportWidthKey.self) { w in
                if w > 0.5, abs((weekTimeGridViewportWidth ?? 0) - w) > 0.25 {
                    weekTimeGridViewportWidth = w
                }
            }
            .onAppear { weekViewWidth = geo.size.width }
            .onChange(of: geo.size.width) { _, w in weekViewWidth = w }
        }
        .clipped()
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
                        openEditEvent(event)
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

    /// Continuous month grid: scrolls through calendar weeks; snap aligns to each week (see week boundaries across months).
    private var monthView: some View {
        GeometryReader { outer in
            let pageH = max(1, outer.size.height)
            let headerAndDivider: CGFloat = 45
            let rowH = max(64, (pageH - headerAndDivider) / 5.5)
            let syms = rotatedWeekdaySymbols()
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(syms.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(MacTheme.calendarWeekdayFont())
                            .foregroundStyle(MacTheme.mutedText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Divider()
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        ForEach(Self.stackedWeekStarts, id: \.self) { weekStart in
                            monthViewWeekRow(weekStart: weekStart, rowHeight: rowH)
                        }
                    }
                    .scrollTargetLayout()
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $monthScrollID)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear {
                if monthScrollID == nil {
                    monthScrollID = weekToken(for: startOfWeek(for: selectedDate))
                }
            }
            .onChange(of: monthScrollID) { _, new in
                guard let new, let weekStart = dateFromWeekToken(new) else { return }
                let cal = Calendar.current
                let currentWeek = startOfWeek(for: selectedDate)
                if cal.isDate(weekStart, inSameDayAs: currentWeek) { return }
                let dayOffset = min(6, max(0, cal.dateComponents([.day], from: currentWeek, to: selectedDate).day ?? 0))
                if let d = cal.date(byAdding: .day, value: dayOffset, to: weekStart) {
                    selectedDate = d
                }
            }
        }
    }

    @ViewBuilder
    private func monthViewWeekRow(weekStart: Date, rowHeight: CGFloat) -> some View {
        let cal = Calendar.current
        let pageMonth = dominantMonthInWeek(weekStart: weekStart)
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                let date = cal.date(byAdding: .day, value: i, to: weekStart) ?? weekStart
                let isCurrentMonth = cal.component(.month, from: date) == pageMonth
                monthDayCell(date, rowHeight: rowHeight, isMuted: !isCurrentMonth)
            }
        }
        .frame(maxWidth: .infinity)
        .id(weekToken(for: weekStart))
    }

    // MARK: - Year View

    /// Infinite-scroll year view — shows years as rows of 4×3 mini-month grids.
    /// Scrolls vertically through multiple years; keeps the selected year in view when it changes.
    private var yearView: some View {
        let cal = Calendar.current
        let currentYear = cal.component(.year, from: selectedDate)
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
                scrollYearInYearView(proxy: proxy, year: currentYear, animated: false)
            }
            .onChange(of: selectedDate) { old, new in
                let oy = cal.component(.year, from: old)
                let ny = cal.component(.year, from: new)
                if oy != ny {
                    scrollYearInYearView(proxy: proxy, year: ny, animated: true)
                }
            }
            .onChange(of: viewMode) { _, new in
                if new == "Year" {
                    let y = cal.component(.year, from: selectedDate)
                    scrollYearInYearView(proxy: proxy, year: y, animated: true)
                }
            }
        }
    }

    private static let yearViewScrollAnimation = Animation.spring(response: 0.38, dampingFraction: 0.88, blendDuration: 0.15)

    private func scrollYearInYearView(proxy: ScrollViewProxy, year: Int, animated: Bool) {
        // Keep the user’s focus year centered for scanability (Apple Calendar–like).
        if animated {
            withAnimation(Self.yearViewScrollAnimation) {
                proxy.scrollTo("year-\(year)", anchor: .center)
            }
        } else {
            proxy.scrollTo("year-\(year)", anchor: .center)
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
                // Month title + “today” dot (Apple Calendar–style cue for the real-world month)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(monthName)
                        .font(.system(size: 12, weight: isCurrentMonth ? .semibold : .medium))
                        .foregroundStyle(isCurrentMonth ? MacTheme.calendarNowIndicator : MacTheme.textPrimary)
                    if isCurrentMonth {
                        Circle()
                            .fill(MacTheme.calendarNowIndicator)
                            .frame(width: 5, height: 5)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 0)
                }

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
                    withAnimation(MacTheme.Motion.base) {
                        selectedDate = date
                        viewMode = "Month"
                    }
                }
            }
        )
    }

    /// A single month grid cell — Apple Calendar style.
    /// Shows day number top-right, events as colored pill blocks.
    /// `isMuted` dims the cell for days belonging to the adjacent months (prev/next).
    private func monthDayCell(_ date: Date, rowHeight: CGFloat, isMuted: Bool = false) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(date)
        let dayEvents = cachedEventsByDay[monthDayKey(date)] ?? []

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
            openEditEvent(event)
        }
        .contextMenu {
            eventContextMenu(event)
        }
    }

    // MARK: - Event Popover

    private func eventPopover(_ event: CalendarEvent) -> some View {
        let color = Color(red: event.calendarColorRed, green: event.calendarColorGreen, blue: event.calendarColorBlue)

        return VStack(alignment: .leading, spacing: 0) {
            // Color header strip
            color.opacity(0.85)
                .frame(height: 5)

            VStack(alignment: .leading, spacing: 10) {
                // Title
                Text(event.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                // Date / time
                if event.isAllDay {
                    Label {
                        Text(event.startDate.formatted(date: .long, time: .omitted) + " · All day")
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.textSecondary)
                } else {
                    let sameDay = Calendar.current.isDate(event.startDate, inSameDayAs: event.endDate)
                    let startFmt = event.startDate.formatted(date: .abbreviated, time: .shortened)
                    let endShortFmt = event.endDate.formatted(date: .omitted, time: .shortened)
                    let endFullFmt = event.endDate.formatted(date: .abbreviated, time: .shortened)
                    Label {
                        if sameDay {
                            Text("\(startFmt) – \(endShortFmt)")
                        } else {
                            Text("\(startFmt) – \(endFullFmt)")
                        }
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.textSecondary)
                }

                // Calendar
                HStack(spacing: 5) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                    Text(event.calendarName)
                        .font(.system(size: 12))
                        .foregroundStyle(MacTheme.textSecondary)
                }

                // Folder
                if let folderName = folderName(for: event.folderID) {
                    Label(folderName, systemImage: "folder")
                        .font(.system(size: 12))
                        .foregroundStyle(MacTheme.textSecondary)
                }

                Divider()

                // Move to Folder
                Menu {
                    Button("Unfiled") { moveEvent(event, to: nil) }
                        .disabled(isMovingEvent)
                    if !folders.isEmpty { Divider() }
                    ForEach(folders) { folder in
                        Button(folder.name) { moveEvent(event, to: folder.id) }
                            .disabled(isMovingEvent)
                    }
                } label: {
                    Label("Move to Folder", systemImage: "folder.badge.gearshape")
                        .font(.system(size: 12))
                }
                .menuStyle(.borderlessButton)
                .disabled(isMovingEvent)

                // Edit (native in-app sheet) — primary action.
                Button {
                    openEditEvent(event)
                } label: {
                    Label("Edit Event", systemImage: "square.and.pencil")
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(MacTheme.accent)

                // Open in Calendar — fallback for users who prefer the
                // system Calendar.app surface.
                Button {
                    selectedEvent = nil
                    openInCalendarApp(event)
                } label: {
                    Label("Open in Calendar", systemImage: "arrow.up.forward.app")
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(MacTheme.accent)
            }
            .padding(14)
        }
        .frame(minWidth: 260, alignment: .leading)
    }

    // MARK: - Tap-to-Create / Edit

    /// Opens the native in-app event sheet pre-filled with the given start
    /// time. Mirrors the iOS long-press-to-create gesture: the user can pick
    /// title, all-day, end time, calendar source, folder, notes and location
    /// without ever leaving Todus. The system Calendar app remains reachable
    /// from the event context menu for users who prefer it.
    private func openNewEvent(at date: Date) {
        // Snap to a sane start: top of the hour when the suggested time isn't
        // already aligned (tap-to-create in the time grid passes the exact
        // pixel-mapped time, which often lands on awkward minutes like 09:23).
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        if let m = comps.minute, m != 0 {
            // Round to the nearest 15 minutes for a natural-feeling default.
            comps.minute = Int((Double(m) / 15.0).rounded()) * 15
            if comps.minute == 60 {
                comps.minute = 0
                comps.hour = (comps.hour ?? 0) + 1
            }
        }
        let snapped = cal.date(from: comps) ?? date

        // Ensure calendar permission before showing the sheet — without write
        // access createEvent will throw and the user will see an error alert.
        Task { @MainActor in
            if !services.calendarService.canCreateEvents() {
                _ = await services.calendarService.requestAccess()
            }
            eventSheetRequest = EventSheetRequest(mode: .create(suggestedStart: snapped))
        }
    }

    /// Opens the native in-app event sheet in edit mode for an existing event.
    /// Closes the read-only popover first so we don't stack two surfaces.
    private func openEditEvent(_ event: CalendarEvent) {
        // Read-only (e.g. Google) events can't be edited via EKEventStore — saving
        // would 404. Show the read-only summary popover instead of the editor.
        guard event.isWritable else {
            eventSheetRequest = nil
            selectedEvent = event
            return
        }
        selectedEvent = nil
        eventSheetRequest = EventSheetRequest(mode: .edit(event: event))
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func eventContextMenu(_ event: CalendarEvent) -> some View {
        // Primary action: native in-app editor (matches the left-click behavior).
        Button {
            openEditEvent(event)
        } label: {
            Label("Edit Event…", systemImage: "square.and.pencil")
        }

        // Quick read-only summary popover — preserves the old tap-to-show-info
        // affordance for users who don't want to open the full editor.
        Button {
            selectedEvent = event
        } label: {
            Label("Show Info", systemImage: "info.circle")
        }

        Divider()

        // Fallback escape hatch: launch the system Calendar app at the event's
        // start date for users who prefer it.
        Button {
            openInCalendarApp(event)
        } label: {
            Label("Open in Calendar", systemImage: "arrow.up.forward.app")
        }

        Button {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(event.title, forType: .string)
        } label: {
            Label("Copy Title", systemImage: "doc.on.doc")
        }

        Divider()

        if !event.isAllDay {
            Button {
                let start = event.startDate.formatted(date: .abbreviated, time: .shortened)
                let end = event.endDate.formatted(date: .omitted, time: .shortened)
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString("\(event.title): \(start) – \(end)", forType: .string)
            } label: {
                Label("Copy Date & Time", systemImage: "calendar.badge.clock")
            }
        } else {
            // All-day events have no time component, so offer a date-only
            // copy mirroring the timed variant for parity.
            Button {
                let start = event.startDate.formatted(date: .abbreviated, time: .omitted)
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString("\(event.title): \(start)", forType: .string)
            } label: {
                Label("Copy Date", systemImage: "calendar")
            }
        }
    }

    /// Navigate Apple Calendar to the event's start date using calshow: URL scheme.
    /// calshow: uses seconds since CoreData reference date (2001-01-01).
    private func openInCalendarApp(_ event: CalendarEvent) {
        let refInterval = Int(event.startDate.timeIntervalSinceReferenceDate)
        guard let url = URL(string: "calshow:\(refInterval)") else {
            calendarToast = .failure("Couldn't open Calendar.app")
            return
        }
        // NSWorkspace returns false when the URL scheme has no handler — surface
        // that as a toast so the user knows the click didn't quietly fail.
        if !NSWorkspace.shared.open(url) {
            calendarToast = .failure("Couldn't open Calendar.app")
        }
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
            // Previous + current + next month (vertical paging and grid bleed)
            let m0 = firstOfMonth(selectedDate)
            if let prevStart = cal.date(byAdding: .month, value: -1, to: m0),
               let endAfterNext = cal.date(byAdding: .month, value: 2, to: m0) {
                start = cal.startOfDay(for: prevStart)
                end = endAfterNext
            } else {
                let monthInterval = cal.dateInterval(of: .month, for: selectedDate)!
                start = monthInterval.start
                end = monthInterval.end
            }
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

        let unified = await services.unifiedCalendarService.events(
            from: start,
            to: end,
            preferences: services.calendarPreferences
        )
        events = unified.map { $0.legacyCalendarEvent }
        rebuildEventCache()
        isLoading = false
    }

    private func monthDayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    private func rebuildEventCache() {
        var dict: [String: [CalendarEvent]] = [:]
        for event in events {
            let key = monthDayKey(event.startDate)
            dict[key, default: []].append(event)
        }
        for key in dict.keys {
            dict[key]?.sort { $0.startDate < $1.startDate }
        }
        cachedEventsByDay = dict
    }

    private func moveEvent(_ event: CalendarEvent, to folderID: UUID?) {
        // Guard so rapid double-taps on the menu items can't kick off
        // overlapping moves while the previous request is in flight.
        guard !isMovingEvent else { return }
        isMovingEvent = true
        Task {
            await services.calendarService.setFolderID(folderID, for: event.id)
            await loadEvents()
            await MainActor.run {
                isMovingEvent = false
                let destination = folderID.flatMap { id in folders.first(where: { $0.id == id })?.name } ?? "Unfiled"
                calendarToast = .success("Moved to \(destination)")
            }
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
                    withAnimation(MacTheme.Motion.base) {
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
                                    .fill(MacTheme.segmentedSelectedPill)
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
        .background(MacTheme.segmentedTrack, in: Capsule(style: .continuous))
    }
}
