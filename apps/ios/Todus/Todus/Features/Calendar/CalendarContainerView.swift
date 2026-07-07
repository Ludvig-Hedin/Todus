import SwiftUI
import UIKit
import EventKitUI

/// Bridges the UIKit-based CalendarViewController (CalendarKit) into SwiftUI.
/// This wraps the existing CalendarApp's DayViewController as a tab in the unified app.
struct CalendarContainerView: UIViewControllerRepresentable {

    /// Top inset in points to apply as additionalSafeAreaInsets.top on the CalendarViewController.
    /// Measured dynamically from the SwiftUI AppTopHeader overlay so CalendarKit's scroll
    /// content starts below our custom header rather than sliding under it.
    var topInset: CGFloat = 90
    var bottomInset: CGFloat = 130

    /// Start-of-day for the day currently shown in CalendarKit (day strip + timeline).
    @Binding var displayedDay: Date

    /// Increment from SwiftUI to jump the day view to today (`move(to: Date())`).
    @Binding var goToTodayTick: Int

    /// True when EKEventViewController is on top of the embedded nav stack — drives
    /// hiding the SwiftUI AppTopHeader overlay and the outer tab bar so the event
    /// detail looks like Apple's Calendar (just back + edit, no app chrome).
    @Binding var isShowingEventDetail: Bool

    /// Called on the main thread when an EventKit save fails (e.g. permission denied,
    /// locked calendar). Use this to surface an error alert in the parent SwiftUI view.
    var onSaveError: ((Error) -> Void)?

    /// Composite calendar id (`apple:{...}` ok) the user picked as their default
    /// for new Apple events. Threaded into CalendarKit's day-view long-press flow.
    var preferredDefaultAppleCalendarId: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            displayedDay: $displayedDay,
            initialGoToTodayTick: goToTodayTick,
            isShowingEventDetail: $isShowingEventDetail,
            onSaveError: onSaveError
        )
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let calendarVC = CalendarViewController()
        calendarVC.onSaveError = { [weak coordinator = context.coordinator] error in
            coordinator?.onSaveError?(error)
        }
        calendarVC.onDisplayedDateChanged = { [weak coordinator = context.coordinator] day in
            Task { @MainActor in
                coordinator?.displayedDayBinding.wrappedValue = day
            }
        }
        let nav = UINavigationController(rootViewController: calendarVC)
        // Day timeline uses the SwiftUI AppTopHeader overlay; the system nav bar is
        // unhidden later (in the delegate) only when EKEventViewController is on top.
        nav.setNavigationBarHidden(true, animated: false)
        // Match the AppTheme.backgroundTop dynamic color so the navigation
        // container doesn't flash a different shade from the CalendarKit timeline.
        nav.view.backgroundColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 0.109, alpha: 1)
                : UIColor(white: 0.94, alpha: 1)
        }
        nav.delegate = context.coordinator
        // Transparent nav bar so the event detail's grouped-background blends with it
        // — matches Apple Calendar where the back/Edit row sits flush with the page.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        nav.navigationBar.compactAppearance = appearance
        // Push CalendarKit's scroll content below the SwiftUI AppTopHeader overlay
        calendarVC.additionalSafeAreaInsets.top = topInset
        calendarVC.additionalSafeAreaInsets.bottom = bottomInset
        calendarVC.preferredDefaultAppleCalendarId = preferredDefaultAppleCalendarId
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        context.coordinator.displayedDayBinding = $displayedDay
        context.coordinator.isShowingEventDetailBinding = $isShowingEventDetail
        // Keep the inset and callbacks in sync if the parent view updates
        if let calendarVC = uiViewController.viewControllers.first as? CalendarViewController {
            calendarVC.additionalSafeAreaInsets.top = topInset
            calendarVC.additionalSafeAreaInsets.bottom = bottomInset
            calendarVC.preferredDefaultAppleCalendarId = preferredDefaultAppleCalendarId
            calendarVC.onDisplayedDateChanged = { [weak coordinator = context.coordinator] day in
                Task { @MainActor in
                    coordinator?.displayedDayBinding.wrappedValue = day
                }
            }
            if goToTodayTick != context.coordinator.lastGoToTodayTick {
                context.coordinator.lastGoToTodayTick = goToTodayTick
                calendarVC.move(to: Date())
            }
        }
        context.coordinator.onSaveError = onSaveError
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UINavigationControllerDelegate {
        var displayedDayBinding: Binding<Date>
        var lastGoToTodayTick: Int
        var isShowingEventDetailBinding: Binding<Bool>
        var onSaveError: ((Error) -> Void)?

        init(
            displayedDay: Binding<Date>,
            initialGoToTodayTick: Int,
            isShowingEventDetail: Binding<Bool>,
            onSaveError: ((Error) -> Void)?
        ) {
            self.displayedDayBinding = displayedDay
            self.lastGoToTodayTick = initialGoToTodayTick
            self.isShowingEventDetailBinding = isShowingEventDetail
            self.onSaveError = onSaveError
        }

        // Toggle the system nav bar — and our SwiftUI overlay — based on whether
        // we're on the day timeline or inside an event detail.
        func navigationController(
            _ navigationController: UINavigationController,
            willShow viewController: UIViewController,
            animated: Bool
        ) {
            let isEventDetail = viewController is EKEventViewController
            navigationController.setNavigationBarHidden(!isEventDetail, animated: animated)
            // Keep the interactive pop gesture working even after we hide/show the nav
            // bar — without this it can desync and the swipe-back stops responding.
            // Guard the root VC like didShow does: enabling the pop gesture with
            // nothing to pop can wedge the nav controller's gesture state on a
            // left-edge swipe (intermittently frozen calendar on return-to-root).
            if navigationController.viewControllers.count > 1 {
                navigationController.interactivePopGestureRecognizer?.isEnabled = true
                navigationController.interactivePopGestureRecognizer?.delegate = nil
            }

            // Reach into the binding inside the Task so we always read/write the
            // freshest reference — capturing it locally would lock onto a copy that
            // updateUIViewController could race past before the Task fires.
            if isShowingEventDetailBinding.wrappedValue != isEventDetail {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.isShowingEventDetailBinding.wrappedValue != isEventDetail {
                        self.isShowingEventDetailBinding.wrappedValue = isEventDetail
                    }
                }
            }
        }

        // EKEventViewController may override the swipe-back gesture in viewDidAppear.
        // Re-enable it after the transition completes so left-edge swipe always works.
        func navigationController(
            _ navigationController: UINavigationController,
            didShow viewController: UIViewController,
            animated: Bool
        ) {
            guard navigationController.viewControllers.count > 1 else { return }
            navigationController.interactivePopGestureRecognizer?.isEnabled = true
            navigationController.interactivePopGestureRecognizer?.delegate = nil
        }
    }
}
