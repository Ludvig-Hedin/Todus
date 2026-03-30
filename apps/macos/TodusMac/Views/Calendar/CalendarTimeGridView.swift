import SwiftUI

/// A reusable 24-hour time grid with positioned event blocks.
/// Modeled after Apple Calendar's day/week grid:
/// - Left gutter with "HH:00" hour labels in light weight
/// - Horizontal hairline grid lines — very subtle, almost invisible
/// - Events as filled colored pill blocks positioned by time
/// - Red current-time indicator with time label badge
struct CalendarTimeGridView: View {
    let columns: [CalendarTimeGridColumn]
    /// Highlight today's column with a subtle accent wash
    var highlightToday: Bool = true
    /// Callback when an event block is tapped
    var onEventTap: ((CalendarEvent) -> Void)? = nil

    private let totalHeight: CGFloat = 24 * MacTheme.calendarHourHeight

    // Current time — updates every 60 seconds for the now indicator
    @State private var now = Date()
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    // Hour grid lines + labels (spans full width)
                    hourGridLayer

                    // Event columns — to the right of the gutter
                    HStack(spacing: 0) {
                        // Gutter spacer — matches the label column width
                        Color.clear
                            .frame(width: MacTheme.calendarGutterWidth)

                        // One column per date
                        ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                            ZStack(alignment: .topLeading) {
                                // Subtle today highlight — near-invisible wash, no color tint
                                if highlightToday && Calendar.current.isDateInToday(column.date) {
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.015))
                                }

                                // Positioned event blocks
                                eventBlocksLayer(for: column)

                                // Now indicator — only in today's column
                                if Calendar.current.isDateInToday(column.date) {
                                    nowIndicator
                                }
                            }
                            .frame(maxWidth: .infinity)

                            // Vertical column separator (not after last column)
                            if index < columns.count - 1 {
                                Rectangle()
                                    .fill(MacTheme.calendarGridLine)
                                    .frame(width: 0.5)
                            }
                        }
                    }
                    .frame(height: totalHeight)
                }
                .frame(height: totalHeight)
                // Invisible scroll anchor at ~7 AM
                .overlay(alignment: .topLeading) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .offset(y: 7 * MacTheme.calendarHourHeight - 20)
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

    // MARK: - Hour Grid

    /// Apple Calendar-style hour grid: light-weight "HH:00" labels in a gutter,
    /// hairline horizontal separators spanning the full width.
    private var hourGridLayer: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                ZStack(alignment: .topLeading) {
                    // Hairline separator at the top of each hour row
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(MacTheme.calendarGridLine)
                            .frame(height: 0.5)
                        Spacer(minLength: 0)
                    }

                    // Hour label — right-aligned in gutter, vertically centered on the line
                    if hour > 0 {
                        Text(MacTheme.hourLabel(hour))
                            .font(MacTheme.calendarHourFont())
                            .foregroundStyle(MacTheme.mutedText)
                            .frame(width: MacTheme.calendarGutterWidth - 10, alignment: .trailing)
                            .offset(y: -6)
                    }
                }
                .frame(height: MacTheme.calendarHourHeight)
            }
        }
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

    /// Apple Calendar-style: red line spanning the column width, with a small red
    /// time badge at the left edge showing the current time.
    private var nowIndicator: some View {
        let cal = Calendar.current
        let minutesSinceMidnight = CGFloat(cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now))
        let yOffset = minutesSinceMidnight * (MacTheme.calendarHourHeight / 60)

        return ZStack(alignment: .leading) {
            // The red line
            Rectangle()
                .fill(MacTheme.calendarNowIndicator)
                .frame(height: 1.5)

            // Leading circle dot (Apple Calendar places a small dot at the left edge)
            Circle()
                .fill(MacTheme.calendarNowIndicator)
                .frame(width: 8, height: 8)
                .offset(x: -4)
        }
        .offset(y: yOffset)
    }

    // MARK: - Event Layout Algorithm

    /// Column-packing overlap resolution: sort by start time, assign each event
    /// to the leftmost column where it doesn't overlap, then divide width equally
    /// among all columns in the overlap group.
    private func layoutEvents(_ events: [CalendarEvent], in date: Date) -> [LayoutItem] {
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

        return timedEvents.enumerated().map { index, event in
            let startMinutes = max(CGFloat(event.startDate.timeIntervalSince(dayStart) / 60), 0)
            let endMinutes = max(CGFloat(event.endDate.timeIntervalSince(dayStart) / 60), 0)
            let duration = max(endMinutes - startMinutes, CGFloat(MacTheme.calendarMinEventHeight) / (MacTheme.calendarHourHeight / 60))

            let yOffset = startMinutes * (MacTheme.calendarHourHeight / 60)
            let height = duration * (MacTheme.calendarHourHeight / 60)
            let col = eventColumns[index]

            return LayoutItem(
                event: event,
                yOffset: yOffset,
                height: max(height, MacTheme.calendarMinEventHeight),
                xOffsetFraction: CGFloat(col) / CGFloat(totalColumns),
                widthFraction: 1.0 / CGFloat(totalColumns)
            )
        }
    }
}

// MARK: - Supporting Types

/// Represents a single column of events for a specific date in the time grid.
struct CalendarTimeGridColumn {
    let date: Date
    let events: [CalendarEvent]
}

/// Internal layout item — positions an event block within the grid.
struct LayoutItem: Identifiable {
    let event: CalendarEvent
    let yOffset: CGFloat
    let height: CGFloat
    let xOffsetFraction: CGFloat
    let widthFraction: CGFloat

    var id: String { event.id }
}
