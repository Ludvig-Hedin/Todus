import SwiftUI

/// Reusable 24-hour time grid with positioned event blocks.
/// Ported from macOS CalendarTimeGridView with iOS-specific adaptations:
/// - 60pt hour height (vs macOS 52pt) for better touch targets
/// - AppTheme colors instead of MacTheme
/// - iOS-appropriate interaction patterns
struct CalendarTimeGridView: View {
    let columns: [CalendarTimeGridColumn]
    var highlightToday: Bool = true
    var onEventTap: ((CalendarEvent) -> Void)? = nil
    var onGridTap: ((Date) -> Void)? = nil

    private let hourHeight: CGFloat = 60
    private let gutterWidth: CGFloat = 50
    private let totalHeight: CGFloat = 24 * 60 // 24 hours × 60pt

    // Current time — updates every 60 seconds for the now indicator
    @State private var now = Date()
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    // Hour grid lines + labels
                    hourGridLayer

                    // Event columns
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: gutterWidth)

                        ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                            ZStack(alignment: .topLeading) {
                                // Subtle today highlight
                                if highlightToday && Calendar.current.isDateInToday(column.date) {
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.015))
                                }

                                // Tappable background for creating events
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

                                // Positioned event blocks
                                eventBlocksLayer(for: column)

                                // Now indicator
                                if Calendar.current.isDateInToday(column.date) {
                                    nowIndicator
                                }
                            }
                            .frame(maxWidth: .infinity)

                            // Column separator
                            if index < columns.count - 1 {
                                Rectangle()
                                    .fill(Color(UIColor.separator).opacity(0.15))
                                    .frame(width: 0.5)
                            }
                        }
                    }
                    .frame(height: totalHeight)
                }
                .frame(height: totalHeight)
                // Scroll anchor at ~7 AM
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

    // MARK: - Hour Grid

    private var hourGridLayer: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color(UIColor.separator).opacity(0.15))
                            .frame(height: 0.5)
                        Spacer(minLength: 0)
                    }

                    if hour > 0 {
                        Text(hourLabel(hour))
                            .font(.system(size: 10, weight: .light))
                            .foregroundStyle(.secondary)
                            .frame(width: gutterWidth - 10, alignment: .trailing)
                            .offset(y: -6)
                    }
                }
                .frame(height: hourHeight)
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

    private var nowIndicator: some View {
        let cal = Calendar.current
        let minutesSinceMidnight = CGFloat(cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now))
        let yOffset = minutesSinceMidnight * (hourHeight / 60)

        return ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color(red: 0.92, green: 0.23, blue: 0.21))
                .frame(height: 1.5)

            Circle()
                .fill(Color(red: 0.92, green: 0.23, blue: 0.21))
                .frame(width: 8, height: 8)
                .offset(x: -4)
        }
        .offset(y: yOffset)
    }

    // MARK: - Event Layout Algorithm

    /// Column-packing overlap resolution — same algorithm as macOS CalendarTimeGridView.
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

    private func hourLabel(_ hour: Int) -> String {
        var comps = DateComponents()
        comps.hour = hour
        if let date = Calendar.current.date(from: comps) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return "\(hour):00"
    }
}

// MARK: - Supporting Types

/// Represents a single column of events for a specific date in the time grid.
struct CalendarTimeGridColumn {
    let date: Date
    let events: [CalendarEvent]
}

/// Internal layout item — positions an event block within the grid.
struct CalendarLayoutItem: Identifiable {
    let event: CalendarEvent
    let yOffset: CGFloat
    let height: CGFloat
    let xOffsetFraction: CGFloat
    let widthFraction: CGFloat

    var id: String { event.id }
}
