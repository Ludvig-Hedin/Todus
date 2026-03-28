import SwiftUI
import UIKit

/// Bridges the UIKit-based CalendarViewController (CalendarKit) into SwiftUI.
/// This wraps the existing CalendarApp's DayViewController as a tab in the unified app.
struct CalendarContainerView: UIViewControllerRepresentable {

    /// Top inset in points to apply as additionalSafeAreaInsets.top on the CalendarViewController.
    /// Measured dynamically from the SwiftUI AppTopHeader overlay so CalendarKit's scroll
    /// content starts below our custom header rather than sliding under it.
    var topInset: CGFloat = 90

    func makeUIViewController(context: Context) -> UINavigationController {
        let calendarVC = CalendarViewController()
        let nav = UINavigationController(rootViewController: calendarVC)
        // Hide the UIKit nav bar — our SwiftUI AppTopHeader overlay handles the top
        nav.setNavigationBarHidden(true, animated: false)
        // Push CalendarKit's scroll content below the SwiftUI AppTopHeader overlay
        calendarVC.additionalSafeAreaInsets.top = topInset
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        // Keep the inset in sync if the header height changes (e.g. orientation change)
        if let calendarVC = uiViewController.viewControllers.first as? CalendarViewController {
            calendarVC.additionalSafeAreaInsets.top = topInset
        }
    }
}
