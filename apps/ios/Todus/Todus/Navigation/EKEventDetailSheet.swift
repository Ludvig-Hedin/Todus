import SwiftUI
import EventKit
import EventKitUI

/// UIKit bridge — wraps EKEventViewController in a SwiftUI sheet.
/// Presented via .sheet(item: $selectedCalendarEvent) in HomeView.
///
/// `EKEventStore()` is a synchronous XPC call to the calendardd daemon that can
/// block the calling thread for up to 9 seconds ("Fence Hang"). It MUST be
/// created off the main thread; we do that via `Task.detached` and ferry the
/// result back to the main actor inside `EKStoreHolder` (`@unchecked Sendable`
/// since EKEventStore is not Sendable but is safe to hand off once created).
struct EKEventDetailSheet: UIViewControllerRepresentable {
    let eventId: String
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let eventVC = EKEventViewController()
        eventVC.allowsCalendarPreview = true
        eventVC.allowsEditing = true
        eventVC.delegate = context.coordinator
        let nav = UINavigationController(rootViewController: eventVC)
        context.coordinator.eventVC = eventVC

        // Create the store off main (XPC fence) and assign on main once ready —
        // the navigation controller returns immediately and the event populates
        // a short time later. Without the detach, the sheet presentation freezes
        // the UI for several seconds on first calendar XPC.
        let coordinator = context.coordinator
        let id = eventId
        Task { @MainActor in
            let holder = await Task.detached(priority: .userInitiated) {
                EKStoreHolder()
            }.value
            coordinator.store = holder.store
            if let ekEvent = holder.store.event(withIdentifier: id) {
                eventVC.event = ekEvent
            }
        }

        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, EKEventViewDelegate {
        let dismiss: DismissAction
        /// Retained for the controller's lifetime so the EKEvent stays valid.
        var store: EKEventStore?
        weak var eventVC: EKEventViewController?

        init(dismiss: DismissAction) { self.dismiss = dismiss }

        nonisolated func eventViewController(
            _ controller: EKEventViewController,
            didCompleteWith action: EKEventViewAction
        ) {
            let performDismiss = dismiss
            Task { @MainActor in
                performDismiss()
            }
        }
    }
}

/// Carries an `EKEventStore` across the actor boundary from a detached task back
/// to the main actor. EKEventStore is not Sendable but is safe to hand off once
/// constructed; `@unchecked Sendable` documents that we've checked this.
private final class EKStoreHolder: @unchecked Sendable {
    let store = EKEventStore()
}
