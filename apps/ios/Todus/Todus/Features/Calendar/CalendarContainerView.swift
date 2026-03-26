import SwiftUI
import UIKit

/// Bridges the UIKit-based CalendarViewController (CalendarKit) into SwiftUI.
/// This wraps the existing CalendarApp's DayViewController as a tab in the unified app.
struct CalendarContainerView: UIViewControllerRepresentable {

    func makeUIViewController(context: Context) -> UINavigationController {
        let calendarVC = CalendarViewController()
        let nav = UINavigationController(rootViewController: calendarVC)
        // Hide the UIKit nav bar — SwiftUI's NavigationStack handles the top
        nav.setNavigationBarHidden(true, animated: false)
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        // No dynamic updates needed — CalendarKit manages its own state via EventKit
    }
}
