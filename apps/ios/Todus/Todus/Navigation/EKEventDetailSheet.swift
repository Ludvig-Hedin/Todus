import SwiftUI
import EventKit
import EventKitUI

/// UIKit bridge — wraps EKEventViewController in a SwiftUI sheet.
/// Presented via .sheet(item: $selectedCalendarEvent) in HomeView.
///
/// `EKEventStore()` can block briefly on first XPC. Loading on the main actor
/// keeps Swift 6 isolation valid for `EKEventStore` (it is not `Sendable`).
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

        // Async hop so the navigation controller returns immediately; event
        // populates on the next main run-loop turn.
        let coordinator = context.coordinator
        Task { @MainActor in
            let store = EKEventStore()
            coordinator.store = store
            if let ekEvent = store.event(withIdentifier: eventId) {
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
