import SwiftUI
import UIKit

/// Multi-day view — shows 2 or 3 days side-by-side with a time grid.
/// Configurable day count via @AppStorage("calendarMultiDayCount").
///
/// Horizontal paging uses UIPageViewController under the hood (the same
/// technology CalendarKit's day view uses) so swipes feel identical to the
/// one-day view: native page-snap animation, proper gesture disambiguation,
/// and full parallax between headers and the time grid.
struct CalendarMultiDayView: View {
    @Binding var selectedDate: Date
    let events: [CalendarEvent]
    let dayCount: Int
    var onEventTap: ((CalendarEvent) -> Void)? = nil

    // Shared observable — lets pinch-to-zoom update every visible page instantly.
    @State private var shared = MultiDayShared()
    @State private var baseHourHeight: CGFloat = 48
    private let minHourHeight: CGFloat = 28
    private let maxHourHeight: CGFloat = 110

    var body: some View {
        MultiDayPager(
            selectedDate: $selectedDate,
            dayCount: dayCount,
            events: events,
            shared: shared,
            onEventTap: onEventTap
        )
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    let proposed = baseHourHeight * value.magnification
                    shared.hourHeight = min(max(proposed, minHourHeight), maxHourHeight)
                }
                .onEnded { _ in
                    baseHourHeight = shared.hourHeight
                }
        )
    }
}

// MARK: - Shared observable state

@Observable
final class MultiDayShared {
    var hourHeight: CGFloat = 48
}

// MARK: - Pager

private struct MultiDayPager: UIViewControllerRepresentable {
    @Binding var selectedDate: Date
    let dayCount: Int
    let events: [CalendarEvent]
    let shared: MultiDayShared
    let onEventTap: ((CalendarEvent) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 0]
        )
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        pvc.view.backgroundColor = .clear

        let start = context.coordinator.startOfPage(for: selectedDate)
        let page = context.coordinator.makePage(startDate: start)
        pvc.setViewControllers([page], direction: .forward, animated: false)
        return pvc
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        context.coordinator.parent = self

        guard let current = pvc.viewControllers?.first as? MultiDayPageVC else { return }

        let desired = context.coordinator.startOfPage(for: selectedDate)
        let cal = Calendar.current

        if !cal.isDate(current.startDate, inSameDayAs: desired) {
            let direction: UIPageViewController.NavigationDirection =
                desired > current.startDate ? .forward : .reverse
            let replacement = context.coordinator.makePage(startDate: desired)
            pvc.setViewControllers([replacement], direction: direction, animated: false)
        } else {
            // Same page — just refresh content (events, etc.)
            current.refresh(
                dayCount: dayCount,
                events: events,
                shared: shared,
                onEventTap: onEventTap
            )
        }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: MultiDayPager

        init(_ parent: MultiDayPager) { self.parent = parent }

        func startOfPage(for date: Date) -> Date {
            Calendar.current.startOfDay(for: date)
        }

        func makePage(startDate: Date) -> MultiDayPageVC {
            MultiDayPageVC(
                startDate: startDate,
                dayCount: parent.dayCount,
                events: parent.events,
                shared: parent.shared,
                onEventTap: parent.onEventTap
            )
        }

        func pageViewController(
            _ pvc: UIPageViewController,
            viewControllerBefore vc: UIViewController
        ) -> UIViewController? {
            guard let current = vc as? MultiDayPageVC,
                  let prev = Calendar.current.date(
                    byAdding: .day,
                    value: -parent.dayCount,
                    to: current.startDate
                  ) else { return nil }
            return makePage(startDate: prev)
        }

        func pageViewController(
            _ pvc: UIPageViewController,
            viewControllerAfter vc: UIViewController
        ) -> UIViewController? {
            guard let current = vc as? MultiDayPageVC,
                  let next = Calendar.current.date(
                    byAdding: .day,
                    value: parent.dayCount,
                    to: current.startDate
                  ) else { return nil }
            return makePage(startDate: next)
        }

        func pageViewController(
            _ pvc: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed,
                  let current = pvc.viewControllers?.first as? MultiDayPageVC else { return }
            // Push the new start date up to the binding so nav bar / state sync.
            parent.selectedDate = current.startDate
        }
    }
}

// MARK: - Page Hosting Controller

private final class MultiDayPageVC: UIHostingController<MultiDayPageView> {
    let startDate: Date

    init(
        startDate: Date,
        dayCount: Int,
        events: [CalendarEvent],
        shared: MultiDayShared,
        onEventTap: ((CalendarEvent) -> Void)?
    ) {
        self.startDate = startDate
        super.init(
            rootView: MultiDayPageView(
                startDate: startDate,
                dayCount: dayCount,
                events: events,
                shared: shared,
                onEventTap: onEventTap
            )
        )
        view.backgroundColor = .clear
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh(
        dayCount: Int,
        events: [CalendarEvent],
        shared: MultiDayShared,
        onEventTap: ((CalendarEvent) -> Void)?
    ) {
        rootView = MultiDayPageView(
            startDate: startDate,
            dayCount: dayCount,
            events: events,
            shared: shared,
            onEventTap: onEventTap
        )
    }
}

// MARK: - Single Page

private struct MultiDayPageView: View {
    let startDate: Date
    let dayCount: Int
    let events: [CalendarEvent]
    let shared: MultiDayShared
    let onEventTap: ((CalendarEvent) -> Void)?

    var body: some View {
        let cal = Calendar.current
        let dates = (0..<dayCount).compactMap {
            cal.date(byAdding: .day, value: $0, to: startDate)
        }
        let weekNumber = cal.component(.weekOfYear, from: startDate)
        let allDayByDay = allDayEventsGrouped(dates: dates, cal: cal)

        VStack(spacing: 0) {
            columnHeaders(dates: dates, weekNumber: weekNumber, cal: cal)

            if allDayByDay.values.contains(where: { !$0.isEmpty }) {
                allDayBar(dates: dates, allDayByDay: allDayByDay, cal: cal)
            }

            Divider()

            let columns = dates.map { date in
                let dayEvents = events.filter {
                    !$0.isAllDay && cal.isDate($0.startDate, inSameDayAs: date)
                }
                return CalendarTimeGridColumn(date: date, events: dayEvents)
            }
            CalendarTimeGridView(
                columns: columns,
                highlightToday: true,
                hourHeight: shared.hourHeight,
                onEventTap: { event in onEventTap?(event) }
            )
        }
    }

    // MARK: - Column Headers

    private func columnHeaders(dates: [Date], weekNumber: Int, cal: Calendar) -> some View {
        HStack(spacing: 0) {
            Text("W\(weekNumber)")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
                .padding(.trailing, 4)

            ForEach(Array(dates.enumerated()), id: \.offset) { index, date in
                let isToday = cal.isDateInToday(date)

                VStack(spacing: 1) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(isToday ? Color(red: 0.92, green: 0.23, blue: 0.21) : .secondary)

                    Text(date.formatted(.dateTime.day()))
                        .font(.system(size: 16, weight: isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? .white : .primary)
                        .frame(width: 28, height: 28)
                        .background {
                            if isToday {
                                Circle().fill(Color(red: 0.92, green: 0.23, blue: 0.21))
                            }
                        }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

                if index < dates.count - 1 {
                    Rectangle()
                        .fill(columnSeparatorColor)
                        .frame(width: 0.5)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - All-Day Bar

    private func allDayBar(dates: [Date], allDayByDay: [Date: [CalendarEvent]], cal: Calendar) -> some View {
        VStack(spacing: 0) {
            Divider()

            HStack(alignment: .center, spacing: 0) {
                Text(
                    String(
                        localized: "calendar.all-day",
                        defaultValue: "all-day",
                        comment: "Label for all-day calendar events"
                    )
                )
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, 4)

                ForEach(Array(dates.enumerated()), id: \.offset) { index, date in
                    let dayStart = cal.startOfDay(for: date)
                    let dayAllDay = allDayByDay[dayStart] ?? []

                    HStack(spacing: 3) {
                        if let first = dayAllDay.first {
                            let color = Color(
                                red: first.calendarColorRed,
                                green: first.calendarColorGreen,
                                blue: first.calendarColorBlue
                            )
                            Text(first.title)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(color.opacity(0.85))
                                )
                                .onTapGesture { onEventTap?(first) }
                        }
                        if dayAllDay.count > 1 {
                            Text("+\(dayAllDay.count - 1)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 1)

                    if index < dates.count - 1 {
                        Rectangle()
                            .fill(columnSeparatorColor)
                            .frame(width: 0.5)
                    }
                }
            }
            .padding(.vertical, 2)
            .frame(height: 22)
            .background(
                Color(UIColor { trait in
                    trait.userInterfaceStyle == .dark
                        ? UIColor(white: 0.115, alpha: 1)
                        : UIColor(white: 0.965, alpha: 1)
                })
            )
        }
    }

    // MARK: - Helpers

    private func allDayEventsGrouped(dates: [Date], cal: Calendar) -> [Date: [CalendarEvent]] {
        let visibleDates = Set(dates.map { cal.startOfDay(for: $0) })
        var grouped: [Date: [CalendarEvent]] = [:]

        for event in events where event.isAllDay {
            var currentDay = cal.startOfDay(for: event.startDate)
            let endReference = max(event.startDate, event.endDate.addingTimeInterval(-1))
            let lastDay = cal.startOfDay(for: endReference)

            while currentDay <= lastDay {
                if visibleDates.contains(currentDay) {
                    grouped[currentDay, default: []].append(event)
                }
                guard let nextDay = cal.date(byAdding: .day, value: 1, to: currentDay) else { break }
                currentDay = nextDay
            }
        }

        return grouped
    }

    private var columnSeparatorColor: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.22)
                : UIColor(white: 0.0, alpha: 0.15)
        })
    }
}
