import SwiftUI

/// Reusable 24-hour time grid with positioned event blocks.
/// Ported from macOS CalendarTimeGridView with iOS-specific adaptations:
/// - configurable hourHeight (60pt for day view, 48pt for multi-day)
/// - AppTheme colors instead of MacTheme
/// - iOS-appropriate interaction patterns
struct CalendarTimeGridView: View {
    let columns: [CalendarTimeGridColumn]
    var highlightToday: Bool = true
    var hourHeight: CGFloat = 60
    var onEventTap: ((CalendarEvent) -> Void)? = nil
    var onGridTap: ((Date) -> Void)? = nil

    private let gutterWidth: CGFloat = 50
    private var totalHeight: CGFloat { 24 * hourHeight }

    @State private var now = Date()
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    // Left gutter: hour labels only. No separator lines here so the
                    // time column reads as negative space, matching CalendarKit's
                    // DayView.
                    hourLabelsGutter
                        .frame(width: gutterWidth)

                    // Content area: hour lines + event columns + now line.
                    ZStack(alignment: .topLeading) {
                        hourLinesLayer

                        HStack(spacing: 0) {
                            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                                columnView(column: column)

                                if index < columns.count - 1 {
                                    Rectangle()
                                        .fill(columnSeparatorColor)
                                        .frame(width: 0.5)
                                }
                            }
                        }
                        .frame(height: totalHeight)

                        // Now line spans the full content area (all columns), with
                        // a red dot placed at the start of today's column.
                        if let todayIndex = todayColumnIndex {
                            nowIndicator(todayColumnIndex: todayIndex,
                                         totalColumns: columns.count)
                        }
                    }
                }
                .frame(height: totalHeight)
                .overlay(alignment: .topLeading) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .offset(y: 7 * hourHeight - 20)
                        .id("scroll-anchor-7am")
                }
            }
            .onAppear {
                proxy.scrollTo("scroll-anchor-7am", anchor: .top)
            }
            .onReceive(timer) { _ in
                now = Date()
            }
        }
    }

    // MARK: - Gutter (Hour Labels)

    private var hourLabelsGutter: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear.frame(height: totalHeight)
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    ZStack(alignment: .topTrailing) {
                        Color.clear.frame(height: hourHeight)
                        if hour > 0 {
                            Text(hourLabel(hour))
                                .font(.system(size: 10, weight: .light))
                                .foregroundStyle(.secondary)
                                .padding(.trailing, 6)
                                .offset(y: -6)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Hour Lines (content area only)

    private var hourLinesLayer: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { _ in
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(hourLineColor)
                        .frame(height: 0.5)
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(halfHourLineColor)
                        .frame(height: 0.5)
                    Spacer(minLength: 0)
                }
                .frame(height: hourHeight)
            }
        }
    }

    // MARK: - Column

    private func columnView(column: CalendarTimeGridColumn) -> some View {
        ZStack(alignment: .topLeading) {
            if highlightToday && Calendar.current.isDateInToday(column.date) {
                Rectangle()
                    .fill(Color.primary.opacity(0.02))
            }

            if onGridTap != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let minutesSinceMidnight = location.y / (hourHeight / 60)
                        let snappedMinutes = (Int(minutesSinceMidnight) / 30) * 30
                        let hour = snappedMinutes / 60
                        let minute = snappedMinutes % 60
                        let cal = Calendar.current
                        let dayStart = cal.startOfDay(for: column.date)
                        if let tappedDate = cal.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart) {
                            onGridTap?(tappedDate)
                        }
                    }
            }

            eventBlocksLayer(for: column)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Event Blocks

    private func eventBlocksLayer(for column: CalendarTimeGridColumn) -> some View {
        let layoutItems = layoutEvents(column.events, in: column.date)

        return GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                ForEach(layoutItems) { item in
                    CalendarEventBlockView(
                        event: item.event,
                        height: item.height,
                        onTap: { onEventTap?(item.event) }
                    )
                    .frame(width: max(0, item.widthFraction * width - 2))
                    .offset(x: item.xOffsetFraction * width + 1, y: item.yOffset)
                }
            }
        }
        .frame(height: totalHeight)
    }

    // MARK: - Now Indicator

    /// Red line spans the full content area (all visible columns), matching
    /// Apple Calendar's multi-day behaviour. The leading red dot marks today's
    /// column specifically.
    private func nowIndicator(todayColumnIndex: Int, totalColumns: Int) -> some View {
        let cal = Calendar.current
        let minutesSinceMidnight = CGFloat(cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now))
        let yOffset = minutesSinceMidnight * (hourHeight / 60)

        return GeometryReader { geo in
            let width = geo.size.width
            let columnWidth = totalColumns > 0 ? width / CGFloat(totalColumns) : width
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color(red: 0.92, green: 0.23, blue: 0.21))
                    .frame(width: width, height: 1.5)

                Circle()
                    .fill(Color(red: 0.92, green: 0.23, blue: 0.21))
                    .frame(width: 8, height: 8)
                    .offset(x: columnWidth * CGFloat(todayColumnIndex) - 4, y: -3.25)
            }
            .offset(y: yOffset)
        }
        .frame(height: totalHeight)
        .allowsHitTesting(false)
    }

    // MARK: - Event Layout Algorithm

    private func layoutEvents(_ events: [CalendarEvent], in date: Date) -> [CalendarLayoutItem] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let timedEvents = events.filter { !$0.isAllDay }.sorted { $0.startDate < $1.startDate }

        guard !timedEvents.isEmpty else { return [] }

        var columnEnds: [Date] = []
        var eventColumns: [Int] = []

        for event in timedEvents {
            var assignedColumn = -1
            for (col, endDate) in columnEnds.enumerated() {
                if event.startDate >= endDate {
                    assignedColumn = col
                    columnEnds[col] = event.endDate
                    break
                }
            }
            if assignedColumn == -1 {
                assignedColumn = columnEnds.count
                columnEnds.append(event.endDate)
            }
            eventColumns.append(assignedColumn)
        }

        let totalColumns = columnEnds.count
        let minEventHeight: CGFloat = 24

        return timedEvents.enumerated().map { index, event in
            let startMinutes = max(CGFloat(event.startDate.timeIntervalSince(dayStart) / 60), 0)
            let endMinutes = max(CGFloat(event.endDate.timeIntervalSince(dayStart) / 60), 0)
            let duration = max(endMinutes - startMinutes, minEventHeight / (hourHeight / 60))

            let yOffset = startMinutes * (hourHeight / 60)
            let height = duration * (hourHeight / 60)
            let col = eventColumns[index]

            return CalendarLayoutItem(
                event: event,
                yOffset: yOffset,
                height: max(height, minEventHeight),
                xOffsetFraction: CGFloat(col) / CGFloat(totalColumns),
                widthFraction: 1.0 / CGFloat(totalColumns)
            )
        }
    }

    // MARK: - Helpers

    private var todayColumnIndex: Int? {
        let cal = Calendar.current
        return columns.firstIndex { cal.isDateInToday($0.date) }
    }

    private func hourLabel(_ hour: Int) -> String {
        var comps = DateComponents()
        comps.hour = hour
        if let date = Calendar.current.date(from: comps) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return "\(hour):00"
    }

    // MARK: - Colours

    /// Mid-grey hour line that stays visible in both light and dark mode.
    private var hourLineColor: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.18)
                : UIColor(white: 0.0, alpha: 0.12)
        })
    }

    private var halfHourLineColor: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.08)
                : UIColor(white: 0.0, alpha: 0.05)
        })
    }

    private var columnSeparatorColor: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.22)
                : UIColor(white: 0.0, alpha: 0.15)
        })
    }
}

// MARK: - Supporting Types

struct CalendarTimeGridColumn {
    let date: Date
    let events: [CalendarEvent]
}

struct CalendarLayoutItem: Identifiable {
    let event: CalendarEvent
    let yOffset: CGFloat
    let height: CGFloat
    let xOffsetFraction: CGFloat
    let widthFraction: CGFloat

    var id: String { event.id }
}
