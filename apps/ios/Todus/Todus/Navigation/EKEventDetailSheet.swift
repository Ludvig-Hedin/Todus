import SwiftUI
import EventKit
import EventKitUI

/// UIKit bridge — wraps EKEventViewController in a SwiftUI sheet.
/// Presented via .sheet(item: $selectedCalendarEvent) in HomeView.
struct EKEventDetailSheet: UIViewControllerRepresentable {
    let eventId: String
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let store = EKEventStore()
        let eventVC = EKEventViewController()
        if let ekEvent = store.event(withIdentifier: eventId) {
            eventVC.event = ekEvent
        }
        eventVC.allowsCalendarPreview = true
        eventVC.allowsEditing = true
        eventVC.delegate = context.coordinator
        return UINavigationController(rootViewController: eventVC)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    class Coordinator: NSObject, EKEventViewDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }

        func eventViewController(_ controller: EKEventViewController, didCompleteWith action: EKEventViewAction) {
            dismiss()
        }
    }
}
