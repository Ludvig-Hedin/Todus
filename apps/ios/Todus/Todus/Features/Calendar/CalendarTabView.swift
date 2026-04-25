import SwiftUI
import UIKit
import EventKit
import EventKitUI

/// Master coordinator for the Calendar tab — manages view mode, date selection,
/// event loading, and switches between CalendarKit (Day) and pure SwiftUI views.
///
/// A `highPriorityGesture` on the root ZStack detects pinch gestures and switches
/// between view modes (day ↔ 3-day ↔ month ↔ year) when the accumulated pinch
/// magnitude crosses a threshold, with haptic feedback and a spring transition.
/// The picker and nav bar provide a secondary entry point for mode switching.
struct CalendarTabView: View {
    @Environment(AppServices.self) private var services

    @State private var viewMode: CalendarViewMode = .day
    @State private var previousViewMode: CalendarViewMode = .day
    @State private var selectedDate: Date = Date()
    @State private var events: [CalendarEvent] = []
    @State private var isLoading = false
    @State private var calendarHeaderHeight: CGFloat = 90
    @AppStorage("calendarMultiDayCount") private var multiDayCount: Int = 3
    @State private var eventSaveError: Error?

    /// In-flight event-load task. Cancelled and replaced on every reload so
    /// rapid date/mode changes don't race; whichever task finishes last
    /// previously won, including stale ones.
    @State private var loadTask: Task<Void, Never>?

    // MARK: - Pinch-to-switch zoom state
    /// Magnification at the last mode switch (or gesture start). Re-arms after each
    /// switch so the user can chain day → 3-day → month → year in one gesture.
    @State private var pinchAnchorMag: CGFloat = 1.0
    /// Live scale applied to the content view during a pinch (follows the finger,
    /// springs back when the gesture ends or a mode switch fires).
    @State private var contentScale: CGFloat = 1.0
    /// Zoom hierarchy for pinch: most detailed (day) → least detailed (year).
    /// `.list` is intentionally excluded — it sits outside the zoom axis.
    private static let zoomLevels: [CalendarViewMode] = [.day, .multiDay, .month, .year]

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

    // MARK: - Pinch gesture

    /// Recognises a pinch anywhere on the calendar tab and switches view modes
    /// when the accumulated magnification crosses a threshold.  After each switch
    /// the anchor is reset so the user can keep pinching through multiple levels
    /// in one continuous gesture (day → 3-day → month → year).
    private var pinchModeGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                handlePinchChange(value.magnification)
            }
            .onEnded { _ in
                // Spring the scale back to neutral if no switch was triggered.
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    contentScale = 1.0
                }
                pinchAnchorMag = 1.0
            }
    }

    /// Processes one pinch frame.  Updates the live scale feedback and fires a
    /// mode switch — with haptics and a spring animation — when the threshold is met.
    private func handlePinchChange(_ magnitude: CGFloat) {
        let relative = magnitude / pinchAnchorMag

        // Mirror 12 % of the pinch movement as a subtle visual scale (±6 % max)
        // so the content gently "breathes" with the gesture before snapping.
        contentScale = max(0.94, min(1.06, 1.0 + (relative - 1.0) * 0.12))

        guard let idx = Self.zoomLevels.firstIndex(of: viewMode) else { return }

        if relative < 0.72, idx < Self.zoomLevels.count - 1 {
            // Pinching (contracting) → less detail → step toward year
            triggerModeSwitch(to: Self.zoomLevels[idx + 1], anchorMag: magnitude)
        } else if relative > 1.38, idx > 0 {
            // Spreading (expanding) → more detail → step toward day
            triggerModeSwitch(to: Self.zoomLevels[idx - 1], anchorMag: magnitude)
        }
    }

    /// Atomic mode switch — resets `contentScale` synchronously so a follow-up
    /// `onChanged` from the same continuing pinch can't override an in-flight
    /// spring animation mid-flight (which produced a visible pop).
    private func triggerModeSwitch(to newMode: CalendarViewMode, anchorMag: CGFloat) {
        pinchAnchorMag = anchorMag
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // Snap scale back to neutral *outside* the animation so subsequent
        // `onChanged` deltas start from a clean 1.0 baseline.
        contentScale = 1.0
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            previousViewMode = viewMode
            viewMode = newMode
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Scale only the calendar content — header stays fixed while the
            // content gently breathes during a pinch.
            contentView
                .scaleEffect(contentScale)

            headerOverlay
        }
        .highPriorityGesture(pinchModeGesture)
        .onAppear {
            // Route the initial load through the same task slot used by all
            // subsequent reloads so a fast user interaction (pinch / picker
            // tap) on appear can cancel the in-flight initial fetch.
            scheduleLoadEvents()
        }
        .onChange(of: selectedDate) {
            if viewMode != .day {
                scheduleLoadEvents()
            }
        }
        .onChange(of: viewMode) {
            scheduleLoadEvents()
        }
        // External calendar changes (event added in another app, permission
        // toggled in Settings) — refresh so we don't render stale state.
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            scheduleLoadEvents()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    /// Cancel any in-flight load and start a fresh one. Prevents stale results
    /// from a slow earlier task overwriting the freshly fetched window.
    private func scheduleLoadEvents() {
        loadTask?.cancel()
        loadTask = Task { await loadEvents() }
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
            CalendarContainerView(topInset: calendarHeaderHeight, onSaveError: { error in
                eventSaveError = error
            })
            .ignoresSafeArea(.container, edges: .bottom)
            .transition(viewTransition)
            .alert("Could not save event", isPresented: Binding(
                get: { eventSaveError != nil },
                set: { if !$0 { eventSaveError = nil } }
            )) {
                Button("OK", role: .cancel) { eventSaveError = nil }
            } message: {
                Text(eventSaveError?.localizedDescription ?? "")
            }

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
        guard services.calendarService.canReadEvents() else {
            // Permission was revoked — clear stale events so the UI doesn't
            // continue to render results that no longer reflect reality.
            if !events.isEmpty { events = [] }
            return
        }
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
            // Pad end by an extra day so all-day events stored with an
            // exclusive end-of-day boundary aren't dropped by the predicate.
            end = cal.date(byAdding: .day, value: multiDayCount + 1, to: dayStart) ?? dayStart
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

        let fetched = await services.calendarService.events(from: start, to: end)
        // Drop the result if a newer reload superseded us mid-fetch.
        guard !Task.isCancelled else { return }
        events = fetched
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
        // EventKitUI normally delivers this on the main actor, but using an
        // explicit hop keeps us safe even if a future iOS version delivers
        // the callback off-main (which `MainActor.assumeIsolated` would trap).
        Task { @MainActor in
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
