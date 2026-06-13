//
//  CalendarViewController.swift
//  Calendar
//
//  Created by Richard Topchii on 09.05.2021.
//

import UIKit
import CalendarKit
import EventKit
import EventKitUI

/// EKEventStore isn't Sendable, but each store is owned by a single
/// `CalendarViewController` and only touched on its serial `backgroundQueue` or
/// the main thread — never concurrently. Box it so `@Sendable` closures can
/// carry it across the queue hop without a false data-race warning.
private struct SendableStoreBox: @unchecked Sendable {
    let store: EKEventStore
}

final class CalendarViewController: DayViewController {
    // nil until initialized off the main thread in viewDidLoad.
    // EKEventStore() is a synchronous XPC call to the calendardd daemon that blocks
    // the calling thread for up to 9+ seconds ("Fence Hang"). Initializing it here
    // off the main thread prevents the startup hang visible in the iOS Performance HUD.
    private var eventStore: EKEventStore?

    /// Called on the main thread whenever an EventKit save fails (e.g. permission denied,
    /// locked calendar). Callers can observe this to show error UI.
    var onSaveError: ((Error) -> Void)?
    /// User-preferred Apple calendar identifier for new events. When set and
    /// matches a writable calendar in the store, new events default to it
    /// instead of `defaultCalendarForNewEvents`. Set from `CalendarTabView`
    /// based on `calendarPreferences.defaultCalendarByAccount["apple"]`.
    var preferredDefaultAppleCalendarId: String?

    /// Fired when the user swipes the day strip or the visible day otherwise changes.
    /// Date is normalized to start-of-day in the current calendar.
    var onDisplayedDateChanged: ((Date) -> Void)?

    /// Cached events keyed by the start-of-day Date. `eventsForDate(_:)` returns cached
    /// data instantly (no main-thread XPC) and triggers a background fetch on cache miss.
    private var cachedEvents: [Date: [EventDescriptor]] = [:]

    /// Background queue for EventKit XPC calls — keeps the main thread free.
    private let backgroundQueue = DispatchQueue(label: "calendar.events", qos: .userInitiated)

    /// Tracks dates with in-flight background fetches to prevent duplicate concurrent requests
    /// for the same day (e.g. when CalendarKit calls eventsForDate multiple times during scroll).
    private var inFlightDates: Set<Date> = []

    /// Debounce work item for EKEventStoreChanged notifications.
    private var debounceWorkItem: DispatchWorkItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Calendar"

        // Match CalendarKit backgrounds to AppTheme.backgroundTop so the
        // timeline background matches the SwiftUI header overlay above it.
        let pageBg = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 0.109, alpha: 1)
                : UIColor(white: 0.94, alpha: 1)
        }
        view.backgroundColor = pageBg
        dayView.backgroundColor = pageBg

        // Customize CalendarKit event styling — slightly more rounded event pills.
        // CalendarStyle defaults the timeline + day-header backgrounds to
        // `.systemBackground` (pure black in dark mode). Those paint OVER
        // `dayView.backgroundColor`, so without overriding them the timeline read
        // black instead of the app's #1c1c1e page surface. Pin both to `pageBg`
        // so the calendar matches every other screen.
        var style = CalendarStyle()
        style.timeline.eventGap = 2
        style.timeline.backgroundColor = pageBg
        style.header.backgroundColor = pageBg
        updateStyle(style)

        // Create EKEventStore off the main thread — its constructor makes a synchronous
        // XPC call to calendardd that blocks the calling thread for up to 9+ seconds.
        // Once ready, wire up notifications and request calendar access.
        backgroundQueue.async { [weak self] in
            let store = EKEventStore()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.eventStore = store
                self.subscribeToNotifications()
                self.requestAccessToCalendar()
            }
        }

        // Re-check permission whenever the app returns from background so a
        // user who toggled Calendar access in Settings sees the right state
        // (revoked → clear; granted → reload).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(true, animated: false)
        // Authorization can flip while the app is suspended. Drop cached
        // events if the user revoked access since the last appearance so we
        // don't render stale data.
        reconcileAuthorizationState()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // End any in-flight long-press edit and drop the editing buffer so
        // the next appearance starts from a clean slate. Without this the
        // half-edited wrapper stays referenced and re-renders on return.
        endEventEditing()
    }

    @objc private func handleWillEnterForeground() {
        reconcileAuthorizationState()
    }

    /// If the user revoked calendar access (e.g. in Settings) clear cached
    /// events and notify the SwiftUI host so it can swap in the permission
    /// view. On (re-)grant, reload data so the timeline refreshes immediately.
    private func reconcileAuthorizationState() {
        let status = EKEventStore.authorizationStatus(for: .event)
        let authorized: Bool
        if #available(iOS 17.0, *) {
            authorized = status == .fullAccess
        } else {
            authorized = status == .authorized
        }
        if !authorized {
            cachedEvents.removeAll()
            inFlightDates.removeAll()
            reloadData()
            NotificationCenter.default.post(
                name: .todusCalendarAuthorizationDidChange,
                object: nil
            )
        }
    }

    private func requestAccessToCalendar() {
        guard let store = eventStore else { return }
        let completionHandler: @Sendable (Bool, (any Error)?) -> Void = { granted, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = granted; _ = error
                self.initializeStore()
            }
        }

        if #available(iOS 17.0, *) {
            store.requestFullAccessToEvents(completion: completionHandler)
        } else {
            store.requestAccess(to: .event, completion: completionHandler)
        }
    }

    private func subscribeToNotifications() {
        guard let store = eventStore else { return }
        NotificationCenter.default.removeObserver(self, name: .EKEventStoreChanged, object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(storeChanged(_:)),
                                               name: .EKEventStoreChanged,
                                               object: store)
    }

    private func initializeStore() {
        // Create a fresh store after authorization — also off main thread.
        backgroundQueue.async { [weak self] in
            let store = EKEventStore()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.eventStore = store
                self.subscribeToNotifications()
                // A fresh store (created after an authorization change) makes any
                // prior cache stale — pre-grant fetches returned empty arrays that
                // would otherwise stick. Drop them so visible days re-fetch against
                // the new store instead of staying blank until EKEventStoreChanged.
                self.cachedEvents.removeAll()
                self.inFlightDates.removeAll()
                self.reloadData()
            }
        }
    }

    /// Debounced handler for EKEventStoreChanged — avoids rapid-fire reloads when
    /// multiple calendar changes arrive in quick succession.
    @objc private func storeChanged(_ notification: Notification) {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.cachedEvents.removeAll()
            self?.inFlightDates.removeAll()
            self?.reloadData()
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: - DayViewDataSource

    /// Returns cached events instantly (no main-thread XPC) and triggers a background fetch on cache miss.
    override func eventsForDate(_ date: Date) -> [EventDescriptor] {
        let key = Calendar.current.startOfDay(for: date)
        if let cached = cachedEvents[key] {
            return cached
        }
        guard !inFlightDates.contains(key) else { return [] }
        fetchEvents(for: date)
        return []
    }

    /// Fetches EventKit events on a background queue and updates the cache + UI on main.
    private func fetchEvents(for date: Date) {
        guard let store = eventStore else { return }
        let key = Calendar.current.startOfDay(for: date)
        inFlightDates.insert(key)
        let boxedStore = SendableStoreBox(store: store)
        backgroundQueue.async { [weak self, boxedStore, date] in
            let store = boxedStore.store
            let startDate = date
            var oneDayComponents = DateComponents()
            oneDayComponents.day = 1
            guard let endDate = Calendar.current.date(byAdding: oneDayComponents, to: startDate) else { return }

            let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
            let eventKitEvents = store.events(matching: predicate)
            let calendarKitEvents = eventKitEvents.map(EKWrapper.init)

            DispatchQueue.main.async { [weak self, key] in
                guard let self else { return }
                self.inFlightDates.remove(key)
                self.cachedEvents[key] = calendarKitEvents
                self.reloadData()
            }
        }
    }

    // MARK: - DayViewDelegate

    // MARK: Event Selection

    override func dayViewDidSelectEventView(_ eventView: EventView) {
        guard let ckEvent = eventView.descriptor as? EKWrapper else {
            return
        }
        presentDetailViewForEvent(ckEvent.ekEvent)
    }

    private func presentDetailViewForEvent(_ ekEvent: EKEvent) {
        let eventController = EKEventViewController()
        eventController.event = ekEvent
        eventController.allowsCalendarPreview = true
        eventController.allowsEditing = true
        eventController.delegate = self
        // Slide the outer tab bar off while the event detail is on top — matches
        // Apple Calendar where the event page is full-bleed.
        eventController.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(eventController,
                                                 animated: true)
    }

    // MARK: Event Editing

    override func dayView(dayView: DayView, didLongPressTimelineAt date: Date) {
        endEventEditing()
        // Light haptic confirms the long-press registered before the new
        // event pill drops into the timeline.
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard let newEKWrapper = createNewEvent(at: date) else { return }
        create(event: newEKWrapper, animated: true)
    }

    private func createNewEvent(at date: Date) -> EKWrapper? {
        guard let store = eventStore else { return nil }
        let newEKEvent = EKEvent(eventStore: store)
        newEKEvent.calendar = resolveDefaultCalendar(in: store)

        var components = DateComponents()
        components.hour = 1
        // EKEvent.endDate is an implicitly-unwrapped Date!; a nil here would later
        // trap when EKWrapper builds a DateInterval(start:end:). Guard the optional.
        guard let endDate = calendar.date(byAdding: components, to: date) else { return nil }

        newEKEvent.startDate = date
        newEKEvent.endDate = endDate
        newEKEvent.title = String(localized: "New event")

        let newEKWrapper = EKWrapper(eventKitEvent: newEKEvent)
        newEKWrapper.editedEvent = newEKWrapper
        return newEKWrapper
    }

    /// Resolve the user's preferred Apple calendar for new events.
    /// Strips any `apple:` prefix from the composite id; falls back to
    /// `defaultCalendarForNewEvents` if the preferred calendar isn't writable.
    private func resolveDefaultCalendar(in store: EKEventStore) -> EKCalendar? {
        guard let preferred = preferredDefaultAppleCalendarId, !preferred.isEmpty else {
            return store.defaultCalendarForNewEvents
        }
        let prefix = "apple:"
        let stripped = preferred.hasPrefix(prefix) ? String(preferred.dropFirst(prefix.count)) : preferred
        if let cal = store.calendars(for: .event).first(where: { $0.calendarIdentifier == stripped }),
           cal.allowsContentModifications {
            return cal
        }
        return store.defaultCalendarForNewEvents
    }

    override func dayViewDidLongPressEventView(_ eventView: EventView) {
        guard let descriptor = eventView.descriptor as? EKWrapper else {
            return
        }
        endEventEditing()
        beginEditing(event: descriptor,
                     animated: true)
    }

    override func dayView(dayView: DayView, didUpdate event: EventDescriptor) {
        guard let editingEvent = event as? EKWrapper else { return }
        if let originalEvent = event.editedEvent {
            editingEvent.commitEditing()

            if originalEvent === editingEvent {
                presentEditingViewForEvent(editingEvent.ekEvent)
            } else {
                guard let store = eventStore else { return }
                do {
                    try store.save(editingEvent.ekEvent, span: .thisEvent)
                } catch {
                    print("[CalendarViewController] Failed to save edited event: \(error)")
                    onSaveError?(error)
                }
            }
        }
        reloadData()
    }


    private func presentEditingViewForEvent(_ ekEvent: EKEvent) {
        guard let store = eventStore else { return }
        let eventEditViewController = EKEventEditViewController()
        eventEditViewController.event = ekEvent
        eventEditViewController.eventStore = store
        eventEditViewController.editViewDelegate = self
        present(eventEditViewController, animated: true, completion: nil)
    }

    override func dayView(dayView: DayView, didTapTimelineAt date: Date) {
        // Only end any in-progress edit. Apple Calendar requires a long-press to
        // create a new event; spawning one on every casual tap (e.g. trying to
        // dismiss something or scroll) made it trivial to pollute the calendar
        // with phantom "New Event" entries.
        endEventEditing()
    }

    override func dayViewDidBeginDragging(dayView: DayView) {
        endEventEditing()
    }

    override func dayView(dayView: DayView, didMoveTo date: Date) {
        super.dayView(dayView: dayView, didMoveTo: date)
        let day = Calendar.current.startOfDay(for: date)
        onDisplayedDateChanged?(day)
    }

}

// MARK: - EKEventViewDelegate

extension CalendarViewController: @MainActor EKEventViewDelegate {
    nonisolated func eventViewController(
        _ controller: EKEventViewController,
        didCompleteWith action: EKEventViewAction
    ) {
        Task { @MainActor [weak self, weak controller] in
            guard let self else { return }
            controller?.navigationController?.popViewController(animated: true)
            self.reloadData()
        }
    }
}

// MARK: - EKEventEditViewDelegate
extension CalendarViewController: @MainActor EKEventEditViewDelegate {
    nonisolated func eventEditViewController(
        _ controller: EKEventEditViewController,
        didCompleteWith action: EKEventEditViewAction
    ) {
        DispatchQueue.main.async { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.endEventEditing()
            self.reloadData()
            controller.dismiss(animated: true, completion: nil)
        }
    }
}
