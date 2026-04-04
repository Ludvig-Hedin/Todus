import SwiftUI
import EventKit
import EventKitUI

/// Master coordinator for the Calendar tab — manages view mode, date selection,
/// event loading, and switches between CalendarKit (Day) and pure SwiftUI views.
struct CalendarTabView: View {
    @Environment(AppServices.self) private var services

    @State private var viewMode: CalendarViewMode = .day
    @State private var selectedDate: Date = Date()
    @State private var events: [CalendarEvent] = []
    @State private var isLoading = false
    @State private var calendarHeaderHeight: CGFloat = 90
    @AppStorage("calendarMultiDayCount") private var multiDayCount: Int = 3

    var body: some View {
        ZStack(alignment: .top) {
            // Content area — switches based on view mode
            contentView

            // Header overlay — AppTopHeader with mode picker + nav bar
            headerOverlay
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .task {
            await loadEvents()
        }
        .onChange(of: selectedDate) {
            // Only reload for non-Day modes (CalendarKit handles its own events)
            if viewMode != .day {
                Task { await loadEvents() }
            }
        }
        .onChange(of: viewMode) {
            Task { await loadEvents() }
        }
    }

    // MARK: - Header

    private var headerOverlay: some View {
        VStack(spacing: 0) {
            AppTopHeader(title: "Calendar") {
                // Dropdown menu picker — replaces the cramped segmented pill
                CalendarViewModePicker(
                    selection: $viewMode,
                    multiDayCount: multiDayCount
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 4)

            // Navigation bar — hidden in Day mode (CalendarKit has its own nav)
            // and Month mode (uses infinite vertical scroll instead of arrows)
            if viewMode != .day && viewMode != .month {
                CalendarNavBar(
                    selectedDate: $selectedDate,
                    viewMode: viewMode,
                    multiDayCount: multiDayCount
                )
            }
        }
        .background(
            Color(UIColor.systemBackground)
                .ignoresSafeArea(edges: .top)
        )
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            calendarHeaderHeight = height
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch viewMode {
        case .day:
            // Existing CalendarKit day view — completely unchanged
            CalendarContainerView(topInset: calendarHeaderHeight)

        case .multiDay:
            CalendarMultiDayView(
                selectedDate: $selectedDate,
                events: events,
                dayCount: multiDayCount,
                onEventTap: { event in presentEvent(event) }
            )
            .padding(.top, calendarHeaderHeight)

        case .month:
            CalendarMonthView(
                selectedDate: $selectedDate,
                viewMode: $viewMode,
                events: events
            )
            .padding(.top, calendarHeaderHeight)

        case .year:
            CalendarYearView(
                selectedDate: $selectedDate,
                viewMode: $viewMode,
                events: events
            )
            .padding(.top, calendarHeaderHeight)

        case .list:
            CalendarListView(
                events: events,
                onEventTap: { event in presentEvent(event) },
                onLoadMore: { await loadMoreListEvents() }
            )
            .padding(.top, calendarHeaderHeight)
        }
    }

    // MARK: - Event Loading

    private func loadEvents() async {
        guard services.calendarService.canReadEvents() else { return }
        // Day mode uses CalendarKit's own event pipeline
        guard viewMode != .day else { return }

        isLoading = true
        let cal = Calendar.current

        let (start, end): (Date, Date)
        switch viewMode {
        case .day:
            return
        case .multiDay:
            let dayStart = cal.startOfDay(for: selectedDate)
            start = dayStart
            end = cal.date(byAdding: .day, value: multiDayCount, to: dayStart) ?? dayStart
        case .month:
            // Load ±12 months to cover the infinite scroll buffer
            start = cal.date(byAdding: .month, value: -12, to: selectedDate) ?? selectedDate
            end = cal.date(byAdding: .month, value: 12, to: selectedDate) ?? selectedDate
        case .year:
            let year = cal.component(.year, from: selectedDate)
            start = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? selectedDate
            end = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? selectedDate
        case .list:
            let dayStart = cal.startOfDay(for: selectedDate)
            start = dayStart
            end = cal.date(byAdding: .month, value: 3, to: dayStart) ?? dayStart
        }

        events = await services.calendarService.events(from: start, to: end)
        isLoading = false
    }

    private func loadMoreListEvents() async {
        guard services.calendarService.canReadEvents() else { return }
        guard let lastEventDate = events.last?.startDate else { return }
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: lastEventDate)) ?? lastEventDate
        let end = cal.date(byAdding: .month, value: 3, to: start) ?? start
        let moreEvents = await services.calendarService.events(from: start, to: end)
        events.append(contentsOf: moreEvents)
    }

    // MARK: - Event Presentation

    /// Present EKEventViewController for a calendar event from SwiftUI views.
    /// Uses a local EKEventStore on the main thread to avoid sending non-Sendable
    /// EKEvent across actor boundaries (Swift 6 strict concurrency).
    private func presentEvent(_ event: CalendarEvent) {
        let store = EKEventStore()
        guard let ekEvent = store.event(withIdentifier: event.id) else { return }
        guard let topVC = UIApplication.topViewController() else { return }
        let eventVC = EKEventViewController()
        eventVC.event = ekEvent
        eventVC.allowsCalendarPreview = true
        eventVC.allowsEditing = true
        if let nav = topVC.navigationController {
            nav.pushViewController(eventVC, animated: true)
        } else {
            let nav = UINavigationController(rootViewController: eventVC)
            topVC.present(nav, animated: true)
        }
    }
}

// MARK: - UIApplication Helper

extension UIApplication {
    /// Finds the topmost presented view controller for presenting UIKit views from SwiftUI.
    static func topViewController(
        base: UIViewController? = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
    ) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(base: selected)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}
