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
    private var eventStore = EKEventStore()

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

        requestAccessToCalendar()
        subscribeToNotifications()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(true, animated: false)
    }

    private func requestAccessToCalendar() {
        let completionHandler: EKEventStoreRequestAccessCompletionHandler = { granted, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = granted; _ = error
                self.initializeStore()
                self.subscribeToNotifications()
                self.reloadData()
            }
        }

        if #available(iOS 17.0, *) {
            eventStore.requestFullAccessToEvents(completion: completionHandler)
        } else {
            eventStore.requestAccess(to: .event, completion: completionHandler)
        }
    }

    private func subscribeToNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(storeChanged(_:)),
                                               name: .EKEventStoreChanged,
                                               object: eventStore)
    }

    private func initializeStore() {
        eventStore = EKEventStore()
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

    /// Returns cached events instantly (no main-thread blocking). On cache miss, returns
    /// an empty array and kicks off a background EventKit fetch that triggers `reloadData()`
    /// when complete. This eliminates the 100-500ms+ synchronous XPC calls that were
    /// blocking the main thread on every tab switch and calendar scroll.
    override func eventsForDate(_ date: Date) -> [EventDescriptor] {
        let key = Calendar.current.startOfDay(for: date)
        if let cached = cachedEvents[key] {
            return cached
        }
        // Cache miss — fetch on background queue, return empty for now.
        // Skip if a fetch for this date is already in flight to avoid duplicate XPC calls.
        guard !inFlightDates.contains(key) else { return [] }
        fetchEvents(for: date)
        return []
    }

    /// Fetches EventKit events on a background queue and updates the cache + UI on main.
    /// Captures `eventStore` locally to avoid accessing @MainActor-isolated self from
    /// the background queue (EKEventStore is thread-safe for read operations).
    private func fetchEvents(for date: Date) {
        let key = Calendar.current.startOfDay(for: date)
        inFlightDates.insert(key)
        let store = self.eventStore
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
        navigationController?.pushViewController(eventController,
                                                 animated: true)
    }
    
    // MARK: Event Editing
    
    override func dayView(dayView: DayView, didLongPressTimelineAt date: Date) {
        // Cancel editing current event and start creating a new one
        endEventEditing()
        let newEKWrapper = createNewEvent(at: date)
        create(event: newEKWrapper, animated: true)
    }
    
    private func createNewEvent(at date: Date) -> EKWrapper {
        let newEKEvent = EKEvent(eventStore: eventStore)
        newEKEvent.calendar = eventStore.defaultCalendarForNewEvents
        
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
                // If editing event is the same as the original one, it has just been created.
                // Showing editing view controller
                presentEditingViewForEvent(editingEvent.ekEvent)
            } else {
                // If editing event is different from the original,
                // then it's pointing to the event already in the `eventStore`
                // Let's save changes to oriignal event to the `eventStore`
                do {
                    try eventStore.save(editingEvent.ekEvent, span: .thisEvent)
                } catch {
                    print("[CalendarViewController] Failed to save edited event: \(error)")
                }
            }
        }
        reloadData()
    }
    
    
    private func presentEditingViewForEvent(_ ekEvent: EKEvent) {
        let eventEditViewController = EKEventEditViewController()
        eventEditViewController.event = ekEvent
        eventEditViewController.eventStore = eventStore
        eventEditViewController.editViewDelegate = self
        present(eventEditViewController, animated: true, completion: nil)
    }
    
    override func dayView(dayView: DayView, didTapTimelineAt date: Date) {
        // Single tap on an empty timeline slot should create an event immediately.
        // This matches native-feeling quick scheduling behavior and avoids requiring long press.
        endEventEditing()
        let newEKWrapper = createNewEvent(at: date)
        create(event: newEKWrapper, animated: true)
    }
    
    override func dayViewDidBeginDragging(dayView: DayView) {
        endEventEditing()
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
