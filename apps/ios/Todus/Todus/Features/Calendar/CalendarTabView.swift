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
    /// True while EKEventViewController is on top of the calendar's nav stack —
    /// hides the SwiftUI AppTopHeader overlay and outer tab bar so the event detail
    /// reads like Apple's Calendar. `presentEvent` pushes the detail onto the UIKit
    /// nav stack outside SwiftUI, so this currently stays false (matching the
    /// Multi-Day flow); kept so the chrome-hiding plumbing remains available.
    @State private var isShowingEventDetail: Bool = false
    /// Presents the multi-calendar source picker (visibility toggles).
    @State private var showCalendarPicker: Bool = false
    /// Banner state for "Reconnect Gmail to enable calendar editing" — set when
    /// any backend calendar call returns `scopeMissing: true`. Cleared once the
    /// user reconnects (`connections.list` no longer flags the account) or
    /// dismisses the banner.
    @State private var showScopeMissingBanner: Bool = false
    /// Alert state for when an external calendar event (Google / CalDAV) cannot
    /// be opened via EKEventStore — usually because it lives in a different
    /// account or hasn't been synced down to Apple's calendar store yet.
    @State private var showCannotOpenEventAlert: Bool = false

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

    /// True when the visible calendar scope already includes “today”.
    private var calendarAnchoredOnToday: Bool {
        let cal = Calendar.current
        let now = Date()
        switch viewMode {
        case .day:
            return cal.isDate(selectedDate, inSameDayAs: now)
        case .multiDay:
            let start = cal.startOfDay(for: selectedDate)
            guard let lastDay = cal.date(byAdding: .day, value: multiDayCount - 1, to: start) else { return false }
            let todayStart = cal.startOfDay(for: now)
            let endStart = cal.startOfDay(for: lastDay)
            return todayStart >= start && todayStart <= endStart
        case .month:
            return cal.isDate(selectedDate, equalTo: now, toGranularity: .month)
        case .year:
            return cal.isDate(selectedDate, equalTo: now, toGranularity: .year)
        case .list:
            return cal.isDate(selectedDate, equalTo: now, toGranularity: .month)
        }
    }

    /// Whether to show the go-to-today FAB — hidden when today is already in view.
    private var showGoToTodayControl: Bool {
        !calendarAnchoredOnToday
    }

    private func goToToday() {
        // All modes (including Day, now a unified SwiftUI grid) anchor on
        // `selectedDate`; the Multi-Day pager moves to the new date via its binding.
        withAnimation(AppTheme.Motion.base) {
            selectedDate = Date()
        }
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
                withAnimation(AppTheme.Motion.base) {
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
        withAnimation(AppTheme.Motion.slow) {
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
                .overlay(alignment: .center) {
                    // Initial-fetch loading state for non-day modes that
                    // render an empty view while waiting on the backend.
                    // CalendarKit's Day view ships its own loading affordance,
                    // so we skip the overlay there.
                    if isLoading, events.isEmpty, viewMode != .day {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("Loading events…")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, calendarHeaderHeight)
                        .transition(.opacity)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Loading events")
                    }
                }

            if !isShowingEventDetail {
                headerOverlay
                    .transition(.opacity)
            }

            // Today FAB — bottom-center, liquid glass, only when today isn't visible.
            if showGoToTodayControl && !isShowingEventDetail {
                VStack {
                    Spacer()
                    HStack {
                        // Centered so it sits in the gap between the create FAB
                        // (bottom-leading) and the AI FAB (bottom-trailing) — it
                        // previously hid behind the create "+" in the corner.
                        Spacer()
                        Button {
                            AppHaptic.light.play()
                            goToToday()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Today")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(LiquidGlassButtonStyle(cornerRadius: 22))
                        .accessibilityLabel(String(localized: "Go to today"))
                        Spacer()
                    }
                    .padding(.bottom, 16)
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .toolbar(isShowingEventDetail ? .hidden : .automatic, for: .tabBar)
        .accessibilityIdentifier("calendar.surface")
        .animation(AppTheme.Motion.slow, value: showGoToTodayControl)
        .animation(AppTheme.Motion.base, value: isShowingEventDetail)
        // `.simultaneousGesture` (not `.highPriorityGesture`) so the multi-day
        // UIPageViewController's horizontal pan still wins for single-finger swipes
        // — only true two-finger pinches reach the magnify recogniser.
        .simultaneousGesture(pinchModeGesture)
        .onAppear {
            // Route the initial load through the same task slot used by all
            // subsequent reloads so a fast user interaction (pinch / picker
            // tap) on appear can cancel the in-flight initial fetch.
            scheduleLoadEvents()
        }
        .onChange(of: selectedDate) {
            // All modes (Day included, now a unified SwiftUI grid keyed on
            // `selectedDate`) reload their event window when the date changes.
            scheduleLoadEvents()
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
        // Header ellipsis menu actions
        .onChange(of: services.calendarGoToTodayTick) { _, _ in
            goToToday()
        }
        .onChange(of: services.calendarRefreshTick) { _, _ in
            scheduleLoadEvents()
        }
        .onChange(of: services.calendarRequestedViewMode) { _, requested in
            guard let requested else { return }
            withAnimation(AppTheme.Motion.slow) {
                previousViewMode = viewMode
                viewMode = requested
            }
            services.calendarRequestedViewMode = nil
        }
        // Re-fetch events when the user toggles a calendar's visibility.
        .onChange(of: services.calendarPreferences) { _, _ in
            scheduleLoadEvents()
        }
        .sheet(isPresented: $showCalendarPicker) {
            CalendarSourcePickerView(
                isSheet: true,
                onAddAccount: {
                    services.showsSettings = true
                }
            )
            .environment(services)
        }
        // Surface a non-blocking banner when Google Calendar returns scopeMissing.
        .onReceive(NotificationCenter.default.publisher(for: .todusCalendarScopeMissing)) { _ in
            showScopeMissingBanner = true
        }
        .overlay(alignment: .top) {
            if showScopeMissingBanner {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("Reconnect Gmail to create and edit events on Google Calendar.")
                        .font(.subheadline)
                    Spacer(minLength: 8)
                    Button("Reconnect") {
                        services.showsSettings = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Button {
                        showScopeMissingBanner = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Dismiss")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Reconnect Gmail to create and edit events on Google Calendar")
                .onAppear {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                }
            }
        }
        .animation(AppTheme.Motion.base, value: showScopeMissingBanner)
        .alert(
            String(localized: "Could not open event"),
            isPresented: $showCannotOpenEventAlert
        ) {
            Button(String(localized: "OK"), role: .cancel) { }
        } message: {
            Text("Google Calendar and subscribed events are read-only. Only events on your Apple calendars can be opened and edited here.")
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
            .overlay(alignment: .topTrailing) {
                // Refresh indicator for reloads over already-visible events —
                // the center overlay above only covers the initial (empty-state)
                // fetch, so without this a background refresh was invisible.
                if isLoading, !events.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 20)
                        .padding(.top, 8)
                        .transition(.opacity)
                        .accessibilityLabel("Refreshing events")
                }
            }
            .animation(AppTheme.Motion.fast, value: isLoading)

            if viewMode != .month {
                // Day mode now renders a unified SwiftUI grid (like Multi-Day), so it
                // gets the nav bar too — it provides the date label + prev/next/today
                // controls the old CalendarKit day strip used to own.
                CalendarNavBar(
                    selectedDate: $selectedDate,
                    viewMode: viewMode,
                    multiDayCount: multiDayCount,
                    showTodayButton: false,
                    todayUsesIconOnly: true,
                    onToday: goToToday,
                    onCalendars: { showCalendarPicker = true }
                )
            }
        }
        .background(
            AppTheme.backgroundTop
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
            // Unified single-day grid (reuses the Multi-Day renderer with a single
            // column) so Google / CalDAV events appear alongside Apple events. The
            // previous CalendarKit day view owned its own EKEventStore and therefore
            // only rendered Apple events; the `events` list here is the unified set
            // (Apple + Google + CalDAV), so every source now shows. Event taps go
            // through `presentEvent` (same EKEventViewController flow Multi-Day uses
            // for editing Apple events); non-Apple taps surface the "can't open" alert.
            CalendarMultiDayView(
                selectedDate: $selectedDate,
                events: events,
                dayCount: 1,
                onEventTap: { event in presentEvent(event) },
                onCreateEventAt: { date in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    // Seed the tapped slot's time into CreateSheet — otherwise it
                    // defaults to "now" and the tap-a-slot gesture loses its point.
                    services.createSheetSeedDate = date
                    services.requestCreateSheet = .event
                }
            )
            .padding(.top, calendarHeaderHeight)
            .transition(viewTransition)

        case .multiDay:
            CalendarMultiDayView(
                selectedDate: $selectedDate,
                events: events,
                dayCount: multiDayCount,
                onEventTap: { event in presentEvent(event) },
                onCreateEventAt: { date in
                    // Light haptic mirrors CalendarKit's long-press feel.
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    // Seed the tapped slot's time into CreateSheet — otherwise it
                    // defaults to "now" and the tap-a-slot gesture loses its point.
                    services.createSheetSeedDate = date
                    services.requestCreateSheet = .event
                }
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
                selectedDate: $selectedDate,
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

    /// True when at least one Google account is connected — Google events come
    /// from the backend and don't need Apple Calendar (EventKit) permission.
    private var hasGoogleCalendarConnection: Bool {
        services.connectionsService.connections.contains { $0.providerId == "google" }
    }

    private func loadEvents() async {
        // Apple permission alone must not gate the whole tab: a Gmail-first user
        // who declined EventKit access still has fetchable Google events
        // (fetchAppleEvents safely returns [] without permission).
        guard services.calendarService.canReadEvents() || hasGoogleCalendarConnection else {
            // No readable source at all — clear stale events so the UI doesn't
            // continue to render results that no longer reflect reality.
            if !events.isEmpty { events = [] }
            return
        }

        isLoading = true
        // Always clear `isLoading` even if this task is cancelled mid-flight
        // (e.g. rapid mode/date changes). Without `defer` the spinner stuck.
        defer { isLoading = false }
        let cal = Calendar.current

        let (start, end): (Date, Date)
        switch viewMode {
        case .day:
            // Single-day window for the unified day grid. Pad the end by an extra
            // day (same as Multi-Day) so all-day events stored with an exclusive
            // end-of-day boundary aren't dropped by the fetch predicate.
            let dayStart = cal.startOfDay(for: selectedDate)
            start = dayStart
            end = cal.date(byAdding: .day, value: 2, to: dayStart) ?? dayStart
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

        let unified = await services.unifiedCalendarService.events(
            from: start,
            to: end,
            preferences: services.calendarPreferences
        )
        // Drop the result if a newer reload superseded us mid-fetch.
        guard !Task.isCancelled else { return }
        events = unified.map { $0.legacyCalendarEvent }
    }

    private func loadMoreListEvents() async {
        guard services.calendarService.canReadEvents() || hasGoogleCalendarConnection else { return }
        guard let lastEventDate = events.last?.startDate else { return }
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: lastEventDate)) ?? lastEventDate
        let end = cal.date(byAdding: .month, value: 3, to: start) ?? start
        let moreUnified = await services.unifiedCalendarService.events(
            from: start,
            to: end,
            preferences: services.calendarPreferences
        )
        // Dedupe by id — overlapping windows can re-return the tail of the previous
        // page, and appending blindly would duplicate rows. If nothing new comes back
        // the list doesn't grow, so the bottom load-more trigger won't re-fire.
        let existingIDs = Set(events.map(\.id))
        let newEvents = moreUnified.map { $0.legacyCalendarEvent }.filter { !existingIDs.contains($0.id) }
        events.append(contentsOf: newEvents)
    }

    // MARK: - Event Presentation

    /// Present EKEventViewController for a calendar event from SwiftUI views.
    /// Creates EKEventStore on a background thread to avoid the XPC-fence hang
    /// (up to 9+ seconds) that occurs when EKEventStore() is called on the main thread.
    private func presentEvent(_ event: CalendarEvent) {
        // Unified ids are namespaced `<provider>:<...>`. EKEventStore only
        // knows about Apple identifiers, so strip the `apple:` prefix; for
        // any other provider (e.g. Google) the lookup will simply fail and
        // we fall through to the alert below.
        let applePrefix = "\(CalendarSourceIDPrefix.apple):"
        let namespacedID: String? = event.id.hasPrefix(applePrefix)
            ? String(event.id.dropFirst(applePrefix.count))
            : (event.id.contains(":") ? nil : event.id)
        // Recurring occurrences carry a `#<start>` suffix — strip it back to the
        // raw EventKit identifier for the store lookup.
        let ekEventID = namespacedID.map { CalendarEvent.ekEventIdentifier(fromEventId: $0) }

        Task { @MainActor in
            let holder = await Task.detached(priority: .userInitiated) {
                EKStoreHolder()
            }.value

            // Two-step lookup: EKEventStore can return nil immediately after a
            // store change (cache hasn't been hydrated yet). One short retry
            // covers that race; if it still isn't there the event lives in a
            // calendar account we can't open via EventKit (Google/CalDAV).
            var ekEvent: EKEvent? = nil
            if let id = ekEventID {
                ekEvent = holder.store.event(withIdentifier: id)
                if ekEvent == nil {
                    try? await Task.sleep(for: .milliseconds(200))
                    ekEvent = holder.store.event(withIdentifier: id)
                }
            }
            guard let ekEvent else {
                showCannotOpenEventAlert = true
                return
            }
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
    /// Robust key-window lookup that walks *every* window in the active scene
    /// instead of relying on `UIWindowScene.keyWindow` (which can be nil on
    /// iPadOS multi-window setups and during scene transitions).
    static func keyWindowRoot() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .rootViewController
    }

    static func topViewController(
        base: UIViewController? = UIApplication.keyWindowRoot()
    ) -> UIViewController? {
        // Recurse presented modals first — they sit on top of every other
        // container, so any subsequent traversal must happen relative to them.
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(base: selected)
        }
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController ?? nav.topViewController)
        }
        return base
    }
}
