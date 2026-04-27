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

        // Match CalendarKit backgrounds to the white page content background
        // so the all-day events area and timeline aren't a different gray.
        view.backgroundColor = .systemBackground
        dayView.backgroundColor = .systemBackground

        // Customize CalendarKit event styling — slightly more rounded event pills
        var style = CalendarStyle()
        style.timeline.eventGap = 2
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
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(true, animated: false)
    }

    private func requestAccessToCalendar() {
        guard let store = eventStore else { return }
        let completionHandler: EKEventStoreRequestAccessCompletionHandler = { granted, error in
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
        backgroundQueue.async { [weak self, store, date] in
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
        // Slide the outer tab bar off while the event detail is on top — matches
        // Apple Calendar where the event page is full-bleed.
        eventController.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(eventController,
                                                 animated: true)
    }

    // MARK: Event Editing

    override func dayView(dayView: DayView, didLongPressTimelineAt date: Date) {
        endEventEditing()
        guard let newEKWrapper = createNewEvent(at: date) else { return }
        create(event: newEKWrapper, animated: true)
    }

    private func createNewEvent(at date: Date) -> EKWrapper? {
        guard let store = eventStore else { return nil }
        let newEKEvent = EKEvent(eventStore: store)
        newEKEvent.calendar = resolveDefaultCalendar(in: store)

        var components = DateComponents()
        components.hour = 1
        let endDate = calendar.date(byAdding: components, to: date)

        newEKEvent.startDate = date
        newEKEvent.endDate = endDate
        newEKEvent.title = "New event"

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
        endEventEditing()
        guard let newEKWrapper = createNewEvent(at: date) else { return }
        create(event: newEKWrapper, animated: true)
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

// MARK: - EKEventEditViewDelegate
extension CalendarViewController: @MainActor EKEventEditViewDelegate {
    nonisolated func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
        DispatchQueue.main.async { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.endEventEditing()
            self.reloadData()
            controller.dismiss(animated: true, completion: nil)
        }
    }
}
