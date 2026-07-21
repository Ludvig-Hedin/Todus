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
                            NowIndicatorView(todayColumnIndex: todayIndex,
                                             totalColumns: columns.count,
                                             hourHeight: hourHeight,
                                             totalHeight: totalHeight)
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
                        // Clamp to a valid slot. A tap in the bottom padding / overscroll
                        // could otherwise yield hour 24 (or negative), making
                        // bySettingHour return nil → the tap silently does nothing.
                        let snappedMinutes = min(max((Int(minutesSinceMidnight) / 30) * 30, 0), 24 * 60 - 30)
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

    // MARK: - Event Layout Algorithm

    /// Cluster-based column layout: events that don't overlap any other event
    /// in the same cluster get full width.  Within a cluster of N mutually
    /// overlapping events, each gets 1/N width — but the cluster boundary is
    /// drawn precisely so a busy morning doesn't permanently squish the
    /// afternoon.
    private func layoutEvents(_ events: [CalendarEvent], in date: Date) -> [CalendarLayoutItem] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let dayMinutesPerPoint = hourHeight / 60
        let minEventHeight: CGFloat = 24

        // Sort by start, then by end (longer-first within the same start) so
        // the column packer prefers the longest span as the cluster's anchor.
        let timedEvents = events
            .filter { !$0.isAllDay }
            .sorted {
                if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
                return $0.endDate > $1.endDate
            }

        guard !timedEvents.isEmpty else { return [] }

        // Helper: visual end is max(event.endDate, event.startDate + minHeight).
        // Two zero-duration events at the same instant should still be treated
        // as overlapping for column-packing purposes.
        let minDuration = TimeInterval((minEventHeight / dayMinutesPerPoint) * 60)
        func visualEnd(_ ev: CalendarEvent) -> Date {
            let raw = max(ev.endDate, ev.startDate.addingTimeInterval(minDuration))
            return raw
        }

        // Step 1 — split events into clusters of mutually-overlapping events.
        // A cluster is a maximal contiguous run where each event starts before
        // the running max-end of the cluster.
        var clusters: [[Int]] = []     // indices into `timedEvents`
        var currentCluster: [Int] = []
        var currentClusterEnd: Date = .distantPast
        for (idx, ev) in timedEvents.enumerated() {
            if currentCluster.isEmpty || ev.startDate < currentClusterEnd {
                currentCluster.append(idx)
                currentClusterEnd = max(currentClusterEnd, visualEnd(ev))
            } else {
                clusters.append(currentCluster)
                currentCluster = [idx]
                currentClusterEnd = visualEnd(ev)
            }
        }
        if !currentCluster.isEmpty { clusters.append(currentCluster) }

        // Step 2 — within each cluster, pack into columns greedily.  Each
        // event takes the lowest-numbered column whose latest event ends at
        // or before this event's start.  Cluster width = max columns used.
        var clusterColumn = [Int: Int](minimumCapacity: timedEvents.count)
        var clusterWidth = [Int: Int](minimumCapacity: clusters.count)
        for (clusterIdx, cluster) in clusters.enumerated() {
            var columnEnds: [Date] = []
            for evIdx in cluster {
                let ev = timedEvents[evIdx]
                var assigned = -1
                for (col, end) in columnEnds.enumerated() where ev.startDate >= end {
                    assigned = col
                    columnEnds[col] = visualEnd(ev)
                    break
                }
                if assigned == -1 {
                    assigned = columnEnds.count
                    columnEnds.append(visualEnd(ev))
                }
                clusterColumn[evIdx] = assigned
            }
            clusterWidth[clusterIdx] = max(columnEnds.count, 1)
        }

        // Step 3 — emit layout items.  Width fraction = 1 / cluster width.
        var clusterIndexFor = [Int: Int]()
        for (cIdx, cluster) in clusters.enumerated() {
            for evIdx in cluster { clusterIndexFor[evIdx] = cIdx }
        }

        return timedEvents.enumerated().map { index, event in
            let startMinutes = max(CGFloat(event.startDate.timeIntervalSince(dayStart) / 60), 0)
            // Compute the *visual* duration: at least minEventHeight tall, and
            // never negative even if endDate < startDate (corrupt input).
            // Cap end at 24:00 (1440 min) so multi-day events don't overflow past midnight.
            let rawEndMinutes = min(CGFloat(event.endDate.timeIntervalSince(dayStart) / 60), 24 * 60)
            let rawDuration = max(rawEndMinutes - startMinutes, 0)
            let duration = max(rawDuration, minEventHeight / dayMinutesPerPoint)

            let yOffset = startMinutes * dayMinutesPerPoint
            let height = duration * dayMinutesPerPoint
            let cluster = clusterIndexFor[index] ?? 0
            let totalColumns = clusterWidth[cluster] ?? 1
            let col = clusterColumn[index] ?? 0

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

// MARK: - Now Indicator

/// Red line spans the full content area (all visible columns), matching
/// Apple Calendar's multi-day behaviour. The leading red dot marks today's
/// column specifically.
///
/// Self-contained `TimelineView(.periodic)` so the 60s minute tick only
/// re-renders this thin layer — previously it mutated grid-level `@State`,
/// forcing the whole time grid (incl. the O(cluster²) event layout per
/// column) to re-run every minute.
private struct NowIndicatorView: View {
    let todayColumnIndex: Int
    let totalColumns: Int
    let hourHeight: CGFloat
    let totalHeight: CGFloat

    private static let lineColor = Color(red: 0.92, green: 0.23, blue: 0.21)

    var body: some View {
        // Align ticks to the next minute boundary so the line moves exactly
        // when the wall-clock minute changes.
        let nextMinute = Calendar.current.date(bySetting: .second, value: 0, of: .now) ?? .now
        TimelineView(.periodic(from: nextMinute, by: 60)) { context in
            let cal = Calendar.current
            let minutesSinceMidnight = CGFloat(cal.component(.hour, from: context.date) * 60 + cal.component(.minute, from: context.date))
            let yOffset = minutesSinceMidnight * (hourHeight / 60)

            GeometryReader { geo in
                let width = geo.size.width
                // Account for the 0.5pt separators between columns (HStack in the
                // grid) so the today-dot lands at the true start of today's
                // column, not drifted right.
                let separatorWidth: CGFloat = 0.5
                let separatorTotal = totalColumns > 1 ? separatorWidth * CGFloat(totalColumns - 1) : 0
                let columnWidth = totalColumns > 0 ? (width - separatorTotal) / CGFloat(totalColumns) : width
                let dotX = CGFloat(todayColumnIndex) * (columnWidth + separatorWidth)
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Self.lineColor)
                        .frame(width: width, height: 1.5)

                    Circle()
                        .fill(Self.lineColor)
                        .frame(width: 8, height: 8)
                        .offset(x: dotX - 4, y: -3.25)
                }
                .offset(y: yOffset)
            }
        }
        .frame(height: totalHeight)
        .allowsHitTesting(false)
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
