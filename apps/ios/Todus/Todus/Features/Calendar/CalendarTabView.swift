import SwiftUI
import UIKit
import EventKit
import EventKitUI

/// Master coordinator for the Calendar tab — manages view mode, date selection,
/// event loading, and switches between CalendarKit (Day) and pure SwiftUI views.
///
/// Pinch-to-zoom now adjusts row height *inside* each view instead of switching
/// modes. Mode switching goes through the dropdown picker, with an animated
/// scale+fade transition whose direction reflects zoom-in vs zoom-out.
struct CalendarTabView: View {
    @Environment(AppServices.self) private var services

    @State private var viewMode: CalendarViewMode = .day
    @State private var previousViewMode: CalendarViewMode = .day
    @State private var selectedDate: Date = Date()
    @State private var events: [CalendarEvent] = []
    @State private var isLoading = false
    @State private var calendarHeaderHeight: CGFloat = 90
    @AppStorage("calendarMultiDayCount") private var multiDayCount: Int = 3

    /// Wrapped binding for the view-mode picker that records the previous mode
    /// before mutating `viewMode`, so the transition modifier can read both
    /// values in the same render pass and pick a direction.
    private var viewModeBinding: Binding<CalendarViewMode> {
        Binding(
            get: { viewMode },
            set: { newValue in
                previousViewMode = viewMode
                viewMode = newValue
            }
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            contentView

            headerOverlay
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .task {
            await loadEvents()
        }
        .onChange(of: selectedDate) {
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
                CalendarViewModePicker(
                    selection: viewModeBinding,
                    multiDayCount: multiDayCount
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 4)

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
            CalendarContainerView(topInset: calendarHeaderHeight)
                .transition(viewTransition)

        case .multiDay:
            CalendarMultiDayView(
                selectedDate: $selectedDate,
                events: events,
                dayCount: multiDayCount,
                onEventTap: { event in presentEvent(event) }
            )
            .padding(.top, calendarHeaderHeight)
            .transition(viewTransition)

        case .month:
            CalendarMonthView(
                selectedDate: $selectedDate,
                viewMode: viewModeBinding,
                events: events
            )
            .padding(.top, calendarHeaderHeight)
            .transition(viewTransition)

        case .year:
            CalendarYearView(
                selectedDate: $selectedDate,
                viewMode: viewModeBinding,
                events: events
            )
            .padding(.top, calendarHeaderHeight)
            .transition(viewTransition)

        case .list:
            CalendarListView(
                events: events,
                onEventTap: { event in presentEvent(event) },
                onLoadMore: { await loadMoreListEvents() }
            )
            .padding(.top, calendarHeaderHeight)
            .transition(viewTransition)
        }
    }

    // MARK: - Zoom transition

    /// Higher level = more zoomed out. Day is innermost, Year outermost.
    private func zoomLevel(_ mode: CalendarViewMode) -> Int {
        switch mode {
        case .day: return 0
        case .multiDay: return 1
        case .month: return 2
        case .year: return 3
        case .list: return 2
        }
    }

    /// Direction-aware transition. Zooming out → new view flies in from a
    /// larger size; zooming in → from a smaller size. Keeps the mental
    /// model "further = more context, closer = more detail".
    private var viewTransition: AnyTransition {
        let oldLevel = zoomLevel(previousViewMode)
        let newLevel = zoomLevel(viewMode)
        if newLevel > oldLevel {
            return .asymmetric(
                insertion: .scale(scale: 1.25).combined(with: .opacity),
                removal: .scale(scale: 0.75).combined(with: .opacity)
            )
        } else if newLevel < oldLevel {
            return .asymmetric(
                insertion: .scale(scale: 0.75).combined(with: .opacity),
                removal: .scale(scale: 1.25).combined(with: .opacity)
            )
        }
        return .opacity
    }

    // MARK: - Event Loading

    private func loadEvents() async {
        guard services.calendarService.canReadEvents() else { return }
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
            // Load a wide window to support the infinite-scroll buffer
            start = cal.date(byAdding: .month, value: -24, to: selectedDate) ?? selectedDate
            end = cal.date(byAdding: .month, value: 24, to: selectedDate) ?? selectedDate
        case .year:
            let year = cal.component(.year, from: selectedDate)
            start = cal.date(from: DateComponents(year: year - 1, month: 1, day: 1)) ?? selectedDate
            end = cal.date(from: DateComponents(year: year + 2, month: 1, day: 1)) ?? selectedDate
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
    /// Creates EKEventStore on a background thread to avoid the XPC-fence hang
    /// (up to 9+ seconds) that occurs when EKEventStore() is called on the main thread.
    private func presentEvent(_ event: CalendarEvent) {
        let eventID = event.id
        Task { @MainActor in
            let holder = await Task.detached(priority: .userInitiated) {
                EKStoreHolder()
            }.value
            guard let ekEvent = holder.store.event(withIdentifier: eventID) else { return }
            guard let topVC = UIApplication.topViewController() else { return }
            let eventVC = EKEventViewController()
            eventVC.event = ekEvent
            eventVC.allowsCalendarPreview = true
            eventVC.allowsEditing = true

            let coordinator = EKEventCoordinator()
            eventVC.delegate = coordinator
            // Retain coordinator and store for the lifetime of the presented controller.
            objc_setAssociatedObject(eventVC, &EKEventCoordinatorKey, coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            objc_setAssociatedObject(eventVC, &EKStoreHolderKey, holder, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

            if let nav = topVC.navigationController {
                nav.pushViewController(eventVC, animated: true)
            } else {
                let nav = UINavigationController(rootViewController: eventVC)
                topVC.present(nav, animated: true)
            }
        }
    }
}

// MARK: - EKEventStore Helper

private final class EKStoreHolder: @unchecked Sendable {
    let store = EKEventStore()
}

// MARK: - EKEventViewController Delegate

private final class EKEventCoordinator: NSObject, EKEventViewDelegate {
    nonisolated func eventViewController(_ controller: EKEventViewController, didCompleteWith action: EKEventViewAction) {
        MainActor.assumeIsolated {
            if let nav = controller.navigationController, nav.presentingViewController != nil {
                nav.dismiss(animated: true)
            } else {
                controller.navigationController?.popViewController(animated: true)
            }
        }
    }
}

nonisolated(unsafe) private var EKEventCoordinatorKey: UInt8 = 0
nonisolated(unsafe) private var EKStoreHolderKey: UInt8 = 0

// MARK: - UIApplication Helper

extension UIApplication {
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
