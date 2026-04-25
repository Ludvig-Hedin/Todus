import AppKit
import SwiftUI

// MARK: - NSEvent local monitor (horizontal = navigate; vertical = pass through)

/// Listens to trackpad / Magic Mouse scroll. When the gesture is clearly *horizontal*, events are
/// swallowed and a single step navigation fires at gesture end. Vertical scroll is unchanged so
/// nested `ScrollView`s (time grid) keep working.
enum CalendarTrackpadScroll {
    fileprivate static let horizontalVsVertical: CGFloat = 1.12
    fileprivate static let minAccum: CGFloat = 20
    fileprivate static let minDebounce: TimeInterval = 0.2
}

final class CalendarTrackpadScrollCoordinator {
    var onHorizontalNavigate: ((Int) -> Void)?
    /// In key window’s base NSView coordinates, or `.null` to use whole window
    var targetRectInWindow: CGRect = .null
    var isEnabled: Bool = true
    var lastFired: TimeInterval = 0
    var accum: CGFloat = 0
    var monitor: Any?
}

extension CalendarTrackpadScrollCoordinator {
    func install() {
        guard monitor == nil else { return }
        let coordinator = self
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard event.type == .scrollWheel, coordinator.isEnabled, coordinator.onHorizontalNavigate != nil else {
                return event
            }
            guard let win = event.window, win == NSApp.keyWindow else { return event }
            if !coordinator.targetRectInWindow.isNull {
                if !coordinator.targetRectInWindow.contains(event.locationInWindow) {
                    return event
                }
            }
            let adx = abs(event.scrollingDeltaX)
            let ady = abs(event.scrollingDeltaY)
            let horizontalLike = adx * CalendarTrackpadScroll.horizontalVsVertical >= ady
            guard horizontalLike, adx > 0.05 else {
                if event.phase == .ended || event.momentumPhase == .ended { coordinator.resetAccum() }
                return event
            }
            // Horizontal-dominant: accumulate; swallow to avoid other views reacting
            coordinator.accum += event.scrollingDeltaX
            let fingerEnded = (event.phase == .ended) && event.momentumPhase == .none
            let momentumEnded = event.momentumPhase == .ended
            let legacyNoPhase = event.phase.isEmpty && !event.hasPreciseScrollingDeltas
            if fingerEnded || momentumEnded {
                if abs(coordinator.accum) >= CalendarTrackpadScroll.minAccum {
                    let now = Date.timeIntervalSinceReferenceDate
                    if now - coordinator.lastFired > CalendarTrackpadScroll.minDebounce {
                        // Swipe left (negative X) → next
                        let dir = coordinator.accum < 0 ? 1 : -1
                        coordinator.onHorizontalNavigate?(dir)
                        coordinator.lastFired = now
                    }
                }
                coordinator.resetAccum()
            } else if legacyNoPhase, abs(coordinator.accum) >= CalendarTrackpadScroll.minAccum {
                let now = Date.timeIntervalSinceReferenceDate
                if now - coordinator.lastFired > CalendarTrackpadScroll.minDebounce {
                    let dir = coordinator.accum < 0 ? 1 : -1
                    coordinator.onHorizontalNavigate?(dir)
                    coordinator.lastFired = now
                }
                coordinator.resetAccum()
            }
            return nil
        }
    }

    func remove() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }

    fileprivate func resetAccum() { accum = 0 }
}

// MARK: - Window-space rect (hit test) preference

struct CalendarContentWindowRectKey: PreferenceKey {
    static var defaultValue: CGRect { .null }
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct CalendarTrackpadNavigationModifier<Sync: Equatable>: ViewModifier {
    let isEnabled: Bool
    let onHorizontalNavigate: (Int) -> Void
    @Binding var targetRectInWindow: CGRect
    /// When this value changes, the scroll handler is re-bound (e.g. ``(viewMode, selectedDate)``).
    let updateWhen: Sync
    @State private var coordinator = CalendarTrackpadScrollCoordinator()

    func body(content: Content) -> some View {
        content
            .onAppear {
                coordinator.onHorizontalNavigate = onHorizontalNavigate
                coordinator.isEnabled = isEnabled
                if !targetRectInWindow.isNull { coordinator.targetRectInWindow = targetRectInWindow }
                if isEnabled { coordinator.install() }
            }
            .onDisappear {
                coordinator.isEnabled = false
                coordinator.remove()
            }
            .onChange(of: isEnabled) { _, e in
                coordinator.isEnabled = e
                coordinator.onHorizontalNavigate = onHorizontalNavigate
                if e, coordinator.monitor == nil { coordinator.install() }
                if !e { coordinator.remove() }
            }
            .onChange(of: updateWhen) { _, _ in
                coordinator.onHorizontalNavigate = onHorizontalNavigate
            }
            .onChange(of: targetRectInWindow) { _, r in
                coordinator.targetRectInWindow = r
            }
    }
}

extension View {
    /// Horizontal two-finger scroll (dominant) steps the calendar. Bind `targetRectInWindow` from
    /// a `GeometryReader` + `CalendarContentWindowRectKey` in window coordinates, or use `.null`
    /// to accept the whole key window.
    func calendarTrackpadNavigation<Sync: Equatable>(
        isEnabled: Bool,
        targetRectInWindow: Binding<CGRect>,
        updateWhen: Sync,
        onHorizontalNavigate: @escaping (Int) -> Void
    ) -> some View {
        modifier(
            CalendarTrackpadNavigationModifier(
                isEnabled: isEnabled,
                onHorizontalNavigate: onHorizontalNavigate,
                targetRectInWindow: targetRectInWindow,
                updateWhen: updateWhen
            )
        )
    }
}
