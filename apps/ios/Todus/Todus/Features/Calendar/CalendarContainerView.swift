import SwiftUI
import UIKit

/// Bridges the UIKit-based CalendarViewController (CalendarKit) into SwiftUI.
/// This wraps the existing CalendarApp's DayViewController as a tab in the unified app.
struct CalendarContainerView: UIViewControllerRepresentable {

    /// Top inset in points to apply as additionalSafeAreaInsets.top on the CalendarViewController.
    /// Measured dynamically from the SwiftUI AppTopHeader overlay so CalendarKit's scroll
    /// content starts below our custom header rather than sliding under it.
    var topInset: CGFloat = 90
    var bottomInset: CGFloat = 130

    /// Called on the main thread when an EventKit save fails (e.g. permission denied,
    /// locked calendar). Use this to surface an error alert in the parent SwiftUI view.
    var onSaveError: ((Error) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onSaveError: onSaveError)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let calendarVC = CalendarViewController()
        calendarVC.onSaveError = { [weak coordinator = context.coordinator] error in
            coordinator?.onSaveError?(error)
        }
        let nav = UINavigationController(rootViewController: calendarVC)
        // Hide the UIKit nav bar — our SwiftUI AppTopHeader overlay handles the top
        nav.setNavigationBarHidden(true, animated: false)
        // Match white content background throughout the nav controller
        nav.view.backgroundColor = .systemBackground
        // Push CalendarKit's scroll content below the SwiftUI AppTopHeader overlay
        calendarVC.additionalSafeAreaInsets.top = topInset
        calendarVC.additionalSafeAreaInsets.bottom = bottomInset
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        // Keep the inset and callbacks in sync if the parent view updates
        if let calendarVC = uiViewController.viewControllers.first as? CalendarViewController {
            calendarVC.additionalSafeAreaInsets.top = topInset
            calendarVC.additionalSafeAreaInsets.bottom = bottomInset
        }
        context.coordinator.onSaveError = onSaveError
    }

    // MARK: - Coordinator

    final class Coordinator {
        var onSaveError: ((Error) -> Void)?
        init(onSaveError: ((Error) -> Void)?) {
            self.onSaveError = onSaveError
        }
    }
}
