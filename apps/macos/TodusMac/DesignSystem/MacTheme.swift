import SwiftUI
import AppKit

/// Design tokens for the macOS Todus app.
/// "Refined Editorial" aesthetic — monochrome with whisper of accent.
/// Dense but readable. Soft corners. Subtle contrast via background tints.
enum MacTheme {

    // MARK: - Spacing (4/8px grid)

    static let spacing4: CGFloat = 4
    static let spacing6: CGFloat = 6
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing20: CGFloat = 20
    static let spacing24: CGFloat = 24
    static let spacing28: CGFloat = 28
    static let spacing32: CGFloat = 32

    // MARK: - Settings layout tokens
    /// Section gap inside the Settings window — matches the breathing room of iOS insetGrouped lists.
    static let settingsSectionSpacing: CGFloat = 32
    /// Vertical padding inside a Settings row.
    static let settingsRowVerticalPadding: CGFloat = 13
    /// Horizontal padding inside a Settings row.
    static let settingsRowHorizontalPadding: CGFloat = 14
    /// Spacing between visual sub-groups within a section (e.g. AI permission sub-headers).
    static let settingsSubgroupSpacing: CGFloat = 16
    /// Adaptive background for TextField / TextEditor inside Settings — legible in both light and dark mode.
    static let inputBackground = Color(light: Color.black.opacity(0.04), dark: Color.white.opacity(0.05))

    // MARK: - Corner Radii
    /// Kept in sync with `AppTheme.Radius` on iOS — soft, continuous corners everywhere.

    /// Cards, sections, settings panels
    static let cardRadius: CGFloat = 18
    /// List rows, wide tiles (matches `AppTheme.Radius.row`)
    static let rowRadius: CGFloat = 16
    /// Nested panels, tinted callouts, meeting rows (between button and card)
    static let compactRadius: CGFloat = 12
    /// Small interactive elements (badges, pills)
    static let pillRadius: CGFloat = 7
    /// Buttons, inputs, search bars — large enough to appear pill-like at typical heights
    static let buttonRadius: CGFloat = 14

    // MARK: - Colors

    /// Main content area background — slightly off-white / Apple system dark (#1c1c1e) to match iOS
    static let contentBackground = Color(light: Color(white: 0.955), dark: Color(white: 0.109))

    /// Subtle card surface — sits just above the window background
    static let surfaceCard = Color(light: Color(white: 0.945), dark: Color(white: 0.135))

    /// Elevated surface for hover states
    static let surfaceHover = Color(light: Color(white: 0.925), dark: Color(white: 0.17))

    /// Card border — whisper-thin separator
    static let cardBorder = Color(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.10))

    /// Muted text for chevrons, timestamps, tertiary info
    static let mutedText = Color(light: Color(white: 0.55), dark: Color(white: 0.45))

    /// Primary text — slightly softer than pure black for elegance
    static let textPrimary = Color(light: Color(white: 0.12), dark: Color(white: 0.92))

    /// Secondary text
    static let textSecondary = Color(light: Color(white: 0.42), dark: Color(white: 0.55))

    /// `Toggle` / `NSSwitch` on-state. Root uses `.tint(.primary)` for monochrome chrome; switches need explicit blue.
    static let switchTint = Color(nsColor: .systemBlue)

    /// Accent — resolves to SwiftUI's `Color.accentColor`, which is set by `.tint()`
    /// on the root view. This ensures ALL accent uses (sidebar icons, buttons, badges)
    /// show the exact same color. The root view calls `.tint(MacTheme.accentColor(for: key))`
    /// so this getter always matches it.
    static var accent: Color { .accentColor }

    /// Foreground for pill/circle buttons whose background is `MacTheme.accent` / `Color.primary`.
    /// Root uses `.tint(Color.primary)` → dark mode accent = white → white-on-white without this.
    /// `Color(light: .white, dark: Color(white: 0.08))` stays legible on white pill in dark mode.
    static let primaryButtonForeground = Color(light: .white, dark: Color(white: 0.08))

    /// Badge / count background
    static let badgeSurface = Color(light: Color(white: 0.88), dark: Color(white: 0.18))

    /// Neutral fill behind sender-initials avatars (no brand match). Same
    /// muted-gray treatment Notion Mail uses, in both light and dark mode.
    static let mutedAvatarFill = Color(light: Color(white: 0.72), dark: Color(white: 0.35))

    /// Empty state / onboarding card background
    static let emptyStateSurface = Color(light: Color(white: 0.93), dark: Color(white: 0.125))

    /// Sheet / modal surface — lifted between `contentBackground` and `surfaceCard`.
    /// Mirrors iOS `AppTheme.sheetBackground` for cross-platform parity on modal chrome.
    static let sheetBackground = Color(light: Color(white: 0.978), dark: Color(white: 0.135))

    /// Secondary surface — for badges, recessed elements within a surface.
    /// Mirrors iOS `AppTheme.surfaceSecondary`.
    static let surfaceSecondary = Color(light: Color(white: 0.96), dark: Color(white: 0.205))

    // MARK: - Segmented control (Calendar-style glass track + selected pill)

    /// Outer track — matches `CalendarViewModePicker` in `MacCalendarView`.
    static let segmentedTrack = Color(light: Color(white: 0.88), dark: Color(white: 0.15))
    /// Selected segment fill — strong contrast on the track in light and dark mode.
    /// Dark value lifted to 0.30 (0.15 above `segmentedTrack` 0.15) to match iOS canonical contrast.
    static let segmentedSelectedPill = Color(light: Color.white, dark: Color(white: 0.30))

    // MARK: - Accent Color Palette

    /// Available accent color keys — used by the settings accent picker.
    static let accentColorKeys = ["blue", "indigo", "teal", "green", "orange", "rose"]

    /// Resolves an accent color key to a light/dark adaptive Color.
    /// Light values match iOS `AppTheme.accentColor(for:)` exactly (canonical).
    /// Dark variants apply a consistent ~5-8% lift for legibility on the dark surface,
    /// keeping cross-platform parity while remaining muted (not screaming neon).
    static func accentColor(for key: String) -> Color {
        switch key {
        case "blue":
            return Color(light: Color(red: 0.22, green: 0.45, blue: 0.85),
                         dark: Color(red: 0.30, green: 0.50, blue: 0.88))
        case "indigo":
            return Color(light: Color(red: 0.35, green: 0.32, blue: 0.78),
                         dark: Color(red: 0.43, green: 0.40, blue: 0.83))
        case "teal":
            return Color(light: Color(red: 0.18, green: 0.52, blue: 0.55),
                         dark: Color(red: 0.26, green: 0.58, blue: 0.61))
        case "green":
            return Color(light: Color(red: 0.25, green: 0.55, blue: 0.32),
                         dark: Color(red: 0.33, green: 0.61, blue: 0.40))
        case "orange":
            return Color(light: Color(red: 0.78, green: 0.48, blue: 0.18),
                         dark: Color(red: 0.84, green: 0.54, blue: 0.26))
        case "rose":
            return Color(light: Color(red: 0.72, green: 0.28, blue: 0.35),
                         dark: Color(red: 0.79, green: 0.35, blue: 0.42))
        default:
            return Color(light: Color(red: 0.22, green: 0.45, blue: 0.85),
                         dark: Color(red: 0.30, green: 0.50, blue: 0.88))
        }
    }

    // MARK: - Calendar Design Tokens

    /// Height per hour in the time grid — 52pt gives Apple Calendar-like airy spacing
    static let calendarHourHeight: CGFloat = 52
    /// Width of the left gutter containing hour labels
    static let calendarGutterWidth: CGFloat = 50
    /// Minimum rendered height for an event block
    static let calendarMinEventHeight: CGFloat = 20
    /// Left color bar width on event blocks (used only for timed events in month view)
    static let calendarEventBarWidth: CGFloat = 3
    /// Event pill corner radius — matches Apple Calendar's rounded event blocks
    static let calendarEventRadius: CGFloat = 4
    /// Grid line color — extremely subtle, almost invisible like Apple Calendar
    static let calendarGridLine = Color(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.07))
    /// Current-time indicator color — Apple's signature red
    static let calendarNowIndicator = Color(light: Color(red: 0.92, green: 0.23, blue: 0.21),
                                            dark: Color(red: 0.95, green: 0.30, blue: 0.28))
    /// All-day bar background — slightly elevated surface
    static let calendarAllDayBg = Color(light: Color(white: 0.965), dark: Color(white: 0.135))
    /// Time-label column in the day/week grid — same as `contentBackground` so it matches the main calendar surface (labels are painted in this strip in `hourGridLayer` behind the clear foreground spacer)
    static let calendarGutterBackground = contentBackground
    /// Hairline between day columns — keep in sync with layout math in `calendarDayColumnWidth`
    static let calendarColumnSeparatorWidth: CGFloat = 0.5

    /// Returns each day column’s width so header, all-day row, and time grid share the same geometry (avoids `ScrollView` / flexible-width drift).
    static func calendarDayColumnWidth(totalWidth: CGFloat, columnCount: Int) -> CGFloat {
        guard columnCount > 0 else { return 0 }
        let seps = CGFloat(max(0, columnCount - 1)) * calendarColumnSeparatorWidth
        return (totalWidth - calendarGutterWidth - seps) / CGFloat(columnCount)
    }

    /// Hour label font — Apple Calendar uses small, light-weight labels
    static func calendarHourFont() -> Font {
        .system(size: 10, weight: .light, design: .default)
    }

    /// Event title inside a positioned block — white on colored background
    static func calendarEventTitleFont() -> Font {
        .system(size: 11, weight: .medium)
    }

    /// Event time inside a positioned block
    static func calendarEventTimeFont() -> Font {
        .system(size: 10, weight: .regular)
    }

    /// Day number in week/month headers — Apple uses regular weight, today is bold+circled
    static func calendarDayNumberFont(isToday: Bool) -> Font {
        .system(size: 11, weight: isToday ? .bold : .regular, design: .default)
    }

    /// Weekday abbreviation in headers — Apple uses capitalized, not all-caps
    static func calendarWeekdayFont() -> Font {
        .system(size: 11, weight: .regular)
    }

    /// Month title in the calendar header — Apple-style large title
    static func calendarTitleFont() -> Font {
        .system(size: 24, weight: .regular, design: .default)
    }

    /// Month event pill font — compact for month grid
    static func calendarMonthEventFont() -> Font {
        .system(size: 10, weight: .medium)
    }

    // MARK: - Typography Helpers

    /// Greeting — the largest text on the home page
    static func greetingFont() -> Font {
        .system(size: 22, weight: .semibold, design: .default)
    }

    /// Date subtitle under greeting
    static func dateFont() -> Font {
        .system(size: 13, weight: .medium, design: .default)
    }

    /// Section header titles
    static func sectionHeaderFont() -> Font {
        .system(size: 12, weight: .semibold, design: .default)
    }

    /// Section header titles inside the Settings window — bumped to match the visual weight of iOS Settings headers.
    static func settingsSectionHeaderFont() -> Font {
        .system(size: 13, weight: .semibold, design: .default)
    }

    /// Card title text (event name, task title, email sender)
    static func cardTitleFont() -> Font {
        .system(size: 13, weight: .medium)
    }

    /// Card subtitle text (time, snippet)
    static func cardSubtitleFont() -> Font {
        .system(size: 12, weight: .regular)
    }

    /// Small metadata (counts, timestamps)
    static func metaFont() -> Font {
        .system(size: 11, weight: .medium)
    }

    // MARK: - Calendar Hour Formatting

    /// Formats hour as "HH:00" like Apple Calendar (e.g. "01:00", "14:00")
    static func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    // MARK: - Motion
    /// Centralized animation tokens — kept in sync with iOS `AppTheme.Motion`
    /// and web `--motion-duration-*` so transitions feel uniform across platforms.
    /// Use these everywhere instead of inline `.snappy(duration:)` / `.easeOut(duration:)`.
    enum Motion {
        /// Fast (~150ms) — hover, fade, micro-feedback
        static let fast = Animation.snappy(duration: 0.15)
        /// Base (~250ms) — dropdowns, sheets, panel toggles
        static let base = Animation.snappy(duration: 0.25)
        /// Slow (~350ms) — major view transitions, onboarding steps
        static let slow = Animation.spring(response: 0.35, dampingFraction: 0.85)
        /// Spring — toasts, contextual surfaces with bounce
        static let spring = Animation.spring(response: 0.32, dampingFraction: 0.85)
    }

}

// MARK: - Color convenience for light/dark mode

extension Color {
    /// Creates a color that adapts between light and dark mode
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(
            name: nil,
            dynamicProvider: { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return isDark
                    ? NSColor(dark)
                    : NSColor(light)
            }
        ))
    }
}

private struct InteractiveHitTargetModifier: ViewModifier {
    let expansion: CGFloat

    func body(content: Content) -> some View {
        content.contentShape(Rectangle().inset(by: -expansion))
    }
}

extension View {
    func interactiveHitTarget(expansion: CGFloat = 6) -> some View {
        modifier(InteractiveHitTargetModifier(expansion: expansion))
    }

    /// Web-style hand cursor on hover for primary click targets.
    func macClickablePointer() -> some View {
        pointerStyle(.link)
    }
}

struct MacInlineRefreshBadge: View {
    /// No-op visible argument — spinner-only badge. The label is retained for VoiceOver
    /// callers (e.g. `MacInlineRefreshBadge(label: "Syncing")`) without showing on screen.
    var label: String = "Updating"

    var body: some View {
        ProgressView()
            .controlSize(.small)
            .padding(4)
            .background(MacTheme.badgeSurface, in: Circle())
            .overlay(Circle().stroke(MacTheme.cardBorder, lineWidth: 0.5))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
    }
}

// MARK: - Action Patterns
//
// macOS counterpart to the iOS pattern modifiers added to AppTheme.swift. Same
// three primitives adapted for AppKit:
//
//   1. `.inFlight(_:)` — disable + overlay a small ProgressView on async controls
//   2. `.hapticOnChange(_:kind:)` — NSHapticFeedbackManager wrapper, skips initial
//   3. `.confirmDestructive(item:title:...)` — Item? -> confirmationDialog
//
// Same API surface as iOS so cross-platform polish sweeps don't have to think
// about which spelling applies. Lives at the bottom of MacTheme.swift (rather
// than a dedicated file) because the macOS `.xcodeproj` is generated via
// xcodegen, which would only pick up a new file on a project regen — keeping
// these inside an already-tracked file avoids that step.

// MARK: 1. In-flight

extension View {
    /// Marks a control as performing an async action: disables it and overlays
    /// a small ProgressView. Use on `Button`, `Menu`, etc.
    @ViewBuilder
    func inFlight(_ isActive: Bool, showsSpinner: Bool = true) -> some View {
        if showsSpinner {
            self
                .opacity(isActive ? 0.55 : 1)
                .overlay {
                    if isActive {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(MacTheme.mutedText)
                            .transition(.opacity)
                    }
                }
                .disabled(isActive)
                .animation(MacTheme.Motion.fast, value: isActive)
        } else {
            self.disabled(isActive)
        }
    }
}

// MARK: 2. Haptic feedback

/// macOS only exposes a small set of haptic patterns through
/// `NSHapticFeedbackManager`. We map the iOS-style names onto the closest
/// macOS equivalents so call sites can stay symmetric.
///
/// Note: macOS haptics only fire on devices with a Force Touch trackpad — the
/// call is a no-op on a regular mouse, which is the intended behavior.
enum MacHaptic {
    case alignment
    case levelChange
    case generic

    func play() {
        let pattern: NSHapticFeedbackManager.FeedbackPattern
        switch self {
        case .alignment: pattern = .alignment
        case .levelChange: pattern = .levelChange
        case .generic: pattern = .generic
        }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}

extension View {
    /// Plays a haptic when `value` changes after first appearance.
    func hapticOnChange<V: Equatable>(_ value: V, kind: MacHaptic) -> some View {
        self.modifier(MacHapticOnChangeModifier(value: value, kind: kind))
    }
}

private struct MacHapticOnChangeModifier<V: Equatable>: ViewModifier {
    let value: V
    let kind: MacHaptic
    @State private var hasSeenInitial = false

    func body(content: Content) -> some View {
        content.onChange(of: value) { _, _ in
            guard hasSeenInitial else { hasSeenInitial = true; return }
            kind.play()
        }
        .onAppear { hasSeenInitial = true }
    }
}

// MARK: 3. Destructive confirmation

extension View {
    /// Standard destructive `confirmationDialog` keyed off an `Item?` trigger.
    /// Mirrors the iOS API so cross-platform code can adopt the same pattern.
    func confirmDestructive<Item: Identifiable>(
        item: Binding<Item?>,
        title: String,
        message: ((Item) -> String)? = nil,
        confirmLabel: String = "Delete",
        perform: @escaping (Item) -> Void
    ) -> some View {
        self.confirmationDialog(
            title,
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: item.wrappedValue
        ) { presented in
            Button(confirmLabel, role: .destructive) {
                perform(presented)
                item.wrappedValue = nil
            }
            Button("Cancel", role: .cancel) {
                item.wrappedValue = nil
            }
        } message: { presented in
            if let message {
                Text(message(presented))
            }
        }
    }
}
