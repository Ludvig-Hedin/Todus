import AppKit
import SwiftUI

// MARK: - NSEvent local monitor (horizontal = navigate; vertical = pass through)

/// Listens to trackpad / Magic Mouse scroll. When the gesture is clearly *horizontal*, events are
/// swallowed and a single step navigation fires at gesture end. Vertical scroll is unchanged so
/// nested `ScrollView`s (time grid) keep working.
enum CalendarTrackpadScroll {
    /// Default: horizontal must slightly beat vertical (Month view: avoids fighting vertical month list).
    fileprivate static let horizontalDefaultWeight: CGFloat = 1.04
    /// Day/Week: time grid is vertically scrollable — easier to count as “horizontal” intent.
    fileprivate static let timeGridHorizontalWeight: CGFloat = 0.82
    fileprivate static let minAccum: CGFloat = 16
    fileprivate static let minDebounce: TimeInterval = 0.12
}

final class CalendarTrackpadScrollCoordinator {
    var onHorizontalNavigate: ((Int) -> Void)?
    /// Called each frame with raw scrollingDeltaX during a confirmed horizontal scroll.
    /// When set, takes over from `onHorizontalNavigate` for streaming (week view panning).
    var onHorizontalStream: ((CGFloat) -> Void)?
    /// Called once when the finger lifts, with total accumulated delta since gesture began.
    var onHorizontalGestureEnded: ((CGFloat) -> Void)?
    /// In key window’s base NSView coordinates, or `.null` to use whole window
    var targetRectInWindow: CGRect = .null
    var isEnabled: Bool = true
    var lastFired: TimeInterval = 0
    var accum: CGFloat = 0
    /// Set to true after `onHorizontalGestureEnded` fires — suppresses streaming until
    /// momentum drains or the next gesture begins.
    var isSnapping: Bool = false
    /// `true` for Day/Week: more lenient axis test + **⇧+scroll** maps to time navigation.
    var isTimeGridViewMode: Bool = false
    var shiftYAccum: CGFloat = 0
    var monitor: Any?

    var horizontalToVerticalWeight: CGFloat {
        isTimeGridViewMode ? CalendarTrackpadScroll.timeGridHorizontalWeight : CalendarTrackpadScroll.horizontalDefaultWeight
    }
}

extension CalendarTrackpadScrollCoordinator {
    func install() {
        guard monitor == nil else { return }
        let coordinator = self
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard event.type == .scrollWheel, coordinator.isEnabled, coordinator.onHorizontalNavigate != nil else {
                return event
            }
            guard let win = event.window else { return event }
            guard MainActor.assumeIsolated({ win.isKeyWindow }) else { return event }
            if !coordinator.targetRectInWindow.isNull {
                if !coordinator.targetRectInWindow.contains(event.locationInWindow) {
                    return event
                }
            }
            let adx = abs(event.scrollingDeltaX)
            let ady = abs(event.scrollingDeltaY)
            let w = coordinator.horizontalToVerticalWeight

            // Day / Week: Shift + scroll (usually vertical delta) = move in time without scrolling the hour grid.
            if coordinator.isTimeGridViewMode, event.modifierFlags.contains(.shift) {
                if adx < 0.01 && ady < 0.01 { return event }
                if event.phase == .began { coordinator.shiftYAccum = 0 }
                coordinator.shiftYAccum += event.scrollingDeltaY
                let sFinger = (event.phase == .ended) && event.momentumPhase.isEmpty
                let sMoment = event.momentumPhase == .ended
                let sLegacy = event.phase.isEmpty && !event.hasPreciseScrollingDeltas
                if sFinger || sMoment {
                    if abs(coordinator.shiftYAccum) >= CalendarTrackpadScroll.minAccum {
                        let now = Date.timeIntervalSinceReferenceDate
                        if now - coordinator.lastFired > CalendarTrackpadScroll.minDebounce {
                            // Same sign convention as two-finger horizontal
                            let dir = coordinator.shiftYAccum < 0 ? 1 : -1
                            coordinator.onHorizontalNavigate?(dir)
                            coordinator.lastFired = now
                        }
                    }
                    coordinator.shiftYAccum = 0
                    return nil
                }
                if sLegacy, abs(coordinator.shiftYAccum) >= CalendarTrackpadScroll.minAccum {
                    let now = Date.timeIntervalSinceReferenceDate
                    if now - coordinator.lastFired > CalendarTrackpadScroll.minDebounce {
                        let dir = coordinator.shiftYAccum < 0 ? 1 : -1
                        coordinator.onHorizontalNavigate?(dir)
                        coordinator.lastFired = now
                    }
                    coordinator.shiftYAccum = 0
                    return nil
                }
                // Swallow so the vertical time grid does not also scroll
                return nil
            } else {
                coordinator.shiftYAccum = 0
            }

            // Clear snapping flag when a new gesture begins so next swipe works immediately.
            if event.phase == .began { coordinator.isSnapping = false }

            // Two-finger (or any) scroll: if horizontal component wins by view-dependent weight, navigate.
            let horizontalLike = (adx * w >= ady) && adx > 0.05
            guard horizontalLike else {
                if event.phase == .ended || event.momentumPhase == .ended { coordinator.resetAccum() }
                return event
            }
            coordinator.accum += event.scrollingDeltaX
            let fingerEnded = (event.phase == .ended) && event.momentumPhase.isEmpty
            let momentumEnded = event.momentumPhase == .ended
            let legacyNoPhase = event.phase.isEmpty && !event.hasPreciseScrollingDeltas

            // Streaming mode — used by week view for real-time pan.
            if coordinator.onHorizontalGestureEnded != nil {
                if coordinator.isSnapping {
                    // Consume momentum events while snap/spring animation is running.
                    if momentumEnded { coordinator.isSnapping = false }
                    return nil
                }
                coordinator.onHorizontalStream?(event.scrollingDeltaX)
                if fingerEnded {
                    coordinator.onHorizontalGestureEnded?(coordinator.accum)
                    coordinator.isSnapping = true
                    coordinator.resetAccum()
                }
                return nil
            }

            // Legacy mode — single step navigate at gesture end (Day, Month, Year).
            if fingerEnded || momentumEnded {
                if abs(coordinator.accum) >= CalendarTrackpadScroll.minAccum {
                    let now = Date.timeIntervalSinceReferenceDate
                    if now - coordinator.lastFired > CalendarTrackpadScroll.minDebounce {
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
    var onHorizontalStream: ((CGFloat) -> Void)?
    var onHorizontalGestureEnded: ((CGFloat) -> Void)?
    @Binding var targetRectInWindow: CGRect
    /// When this value changes, the scroll handler is re-bound (e.g. ``(viewMode, selectedDate)``).
    let updateWhen: Sync
    /// Day + Week: easier horizontal two-finger recognition over the vertical hour grid, plus **⇧+scroll** for time.
    var isTimeGridViewMode: Bool
    @State private var coordinator = CalendarTrackpadScrollCoordinator()

    func body(content: Content) -> some View {
        content
            .onAppear {
                coordinator.onHorizontalNavigate = onHorizontalNavigate
                coordinator.onHorizontalStream = onHorizontalStream
                coordinator.onHorizontalGestureEnded = onHorizontalGestureEnded
                coordinator.isEnabled = isEnabled
                coordinator.isTimeGridViewMode = isTimeGridViewMode
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
                coordinator.onHorizontalStream = onHorizontalStream
                coordinator.onHorizontalGestureEnded = onHorizontalGestureEnded
                if e, coordinator.monitor == nil { coordinator.install() }
                if !e { coordinator.remove() }
            }
            .onChange(of: updateWhen) { _, _ in
                coordinator.onHorizontalNavigate = onHorizontalNavigate
                coordinator.onHorizontalStream = onHorizontalStream
                coordinator.onHorizontalGestureEnded = onHorizontalGestureEnded
                coordinator.isTimeGridViewMode = isTimeGridViewMode
            }
            .onChange(of: isTimeGridViewMode) { _, v in
                coordinator.isTimeGridViewMode = v
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
    ///
    /// When `onHorizontalStream` / `onHorizontalGestureEnded` are provided (week view), those take
    /// over for smooth real-time panning; `onHorizontalNavigate` is then only used by other modes.
    func calendarTrackpadNavigation<Sync: Equatable>(
        isEnabled: Bool,
        targetRectInWindow: Binding<CGRect>,
        updateWhen: Sync,
        isTimeGridViewMode: Bool = false,
        onHorizontalStream: ((CGFloat) -> Void)? = nil,
        onHorizontalGestureEnded: ((CGFloat) -> Void)? = nil,
        onHorizontalNavigate: @escaping (Int) -> Void
    ) -> some View {
        modifier(
            CalendarTrackpadNavigationModifier(
                isEnabled: isEnabled,
                onHorizontalNavigate: onHorizontalNavigate,
                onHorizontalStream: onHorizontalStream,
                onHorizontalGestureEnded: onHorizontalGestureEnded,
                targetRectInWindow: targetRectInWindow,
                updateWhen: updateWhen,
                isTimeGridViewMode: isTimeGridViewMode
            )
        )
    }
}

// MARK: - Pinch (magnify) to change view density: Day → Week → Month → Year

/// Trackpad pinch: spread to zoom in (finer), pinch to zoom out (wider) — like Apple Calendar.
enum CalendarPinchViewMode {
    fileprivate static let minTotalMagnification: CGFloat = 0.12
    fileprivate static let minDebounce: TimeInterval = 0.25
}

final class CalendarPinchViewModeCoordinator {
    /// `-1` = zoom in toward Day; `+1` = zoom out toward Year
    var onViewModeStep: ((Int) -> Void)?
    var targetRectInWindow: CGRect = .null
    var isEnabled: Bool = true
    var accum: CGFloat = 0
    var lastFired: TimeInterval = 0
    var monitor: Any?
}

extension CalendarPinchViewModeCoordinator {
    func install() {
        guard monitor == nil else { return }
        let c = self
        monitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { event in
            guard event.type == .magnify, c.isEnabled, c.onViewModeStep != nil else { return event }
            guard let win = event.window else { return event }
            guard MainActor.assumeIsolated({ win.isKeyWindow }) else { return event }
            if !c.targetRectInWindow.isNull, !c.targetRectInWindow.contains(event.locationInWindow) {
                return event
            }
            if event.phase == .cancelled {
                c.accum = 0
                return event
            }
            if event.phase == .began { c.accum = 0 }
            c.accum += event.magnification
            // Trackpad: .began / .changed / .ended. Some devices send a single event with an empty phase.
            let noPhase = event.phase.isEmpty && event.momentumPhase.isEmpty
            let phaseEnded = event.phase == .ended || event.phase == .cancelled
            let momentumEnded = event.momentumPhase == .ended
            let gestureComplete = noPhase || phaseEnded || momentumEnded
            if !gestureComplete { return event }
            guard abs(c.accum) >= CalendarPinchViewMode.minTotalMagnification else {
                if phaseEnded || momentumEnded || noPhase { c.accum = 0 }
                return event
            }
            let now = Date.timeIntervalSinceReferenceDate
            guard now - c.lastFired > CalendarPinchViewMode.minDebounce else {
                c.accum = 0
                return event
            }
            // positive magnification = spread = zoom in = finer granularity = step toward Day (-1)
            // negative = pinch = zoom out = step toward Year (+1)
            let step = c.accum > 0 ? -1 : 1
            c.onViewModeStep?(step)
            c.lastFired = now
            c.accum = 0
            return event
        }
    }

    func remove() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }
}

struct CalendarPinchViewModeModifier<Sync: Equatable>: ViewModifier {
    let isEnabled: Bool
    let onViewModeStep: (Int) -> Void
    @Binding var targetRectInWindow: CGRect
    let updateWhen: Sync
    @State private var coordinator = CalendarPinchViewModeCoordinator()

    func body(content: Content) -> some View {
        content
            .onAppear {
                coordinator.onViewModeStep = onViewModeStep
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
                coordinator.onViewModeStep = onViewModeStep
                if e, coordinator.monitor == nil { coordinator.install() }
                if !e { coordinator.remove() }
            }
            .onChange(of: updateWhen) { _, _ in
                coordinator.onViewModeStep = onViewModeStep
            }
            .onChange(of: targetRectInWindow) { _, r in
                coordinator.targetRectInWindow = r
            }
    }
}

extension View {
    /// Pinch on trackpad: spread → show more time detail (Day), pinch → see more span (Year).
    func calendarPinchViewMode<Sync: Equatable>(
        isEnabled: Bool,
        targetRectInWindow: Binding<CGRect>,
        updateWhen: Sync,
        onViewModeStep: @escaping (Int) -> Void
    ) -> some View {
        modifier(
            CalendarPinchViewModeModifier(
                isEnabled: isEnabled,
                onViewModeStep: onViewModeStep,
                targetRectInWindow: targetRectInWindow,
                updateWhen: updateWhen
            )
        )
    }
}
