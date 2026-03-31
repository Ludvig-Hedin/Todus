import SwiftUI

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
    static let spacing32: CGFloat = 32

    // MARK: - Corner Radii

    /// Cards, sections, settings panels
    static let cardRadius: CGFloat = 10
    /// Small interactive elements (badges, pills)
    static let pillRadius: CGFloat = 5
    /// Buttons, inputs, search bars — large enough to appear pill-like at typical heights
    static let buttonRadius: CGFloat = 12

    // MARK: - Colors

    /// Main content area background — slightly off-white / deep dark to match iOS
    static let contentBackground = Color(light: Color(white: 0.955), dark: Color(white: 0.08))

    /// Subtle card surface — sits just above the window background
    static let surfaceCard = Color(light: Color(white: 0.945), dark: Color(white: 0.115))

    /// Elevated surface for hover states
    static let surfaceHover = Color(light: Color(white: 0.925), dark: Color(white: 0.15))

    /// Card border — whisper-thin separator
    static let cardBorder = Color(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.10))

    /// Muted text for chevrons, timestamps, tertiary info
    static let mutedText = Color(light: Color(white: 0.55), dark: Color(white: 0.45))

    /// Primary text — slightly softer than pure black for elegance
    static let textPrimary = Color(light: Color(white: 0.12), dark: Color(white: 0.92))

    /// Secondary text
    static let textSecondary = Color(light: Color(white: 0.42), dark: Color(white: 0.55))

    /// Accent — resolves to SwiftUI's `Color.accentColor`, which is set by `.tint()`
    /// on the root view. This ensures ALL accent uses (sidebar icons, buttons, badges)
    /// show the exact same color. The root view calls `.tint(MacTheme.accentColor(for: key))`
    /// so this getter always matches it.
    static var accent: Color { .accentColor }

    /// Badge / count background
    static let badgeSurface = Color(light: Color(white: 0.88), dark: Color(white: 0.18))

    /// Empty state / onboarding card background
    static let emptyStateSurface = Color(light: Color(white: 0.93), dark: Color(white: 0.10))

    // MARK: - Accent Color Palette

    /// Available accent color keys — used by the settings accent picker.
    static let accentColorKeys = ["blue", "indigo", "teal", "green", "orange", "rose"]

    /// Resolves an accent color key to a light/dark adaptive Color.
    /// All colors are intentionally muted — not screaming neon. Fits the refined editorial aesthetic.
    static func accentColor(for key: String) -> Color {
        switch key {
        case "blue":
            return Color(light: Color(red: 0.22, green: 0.45, blue: 0.85),
                         dark: Color(red: 0.30, green: 0.50, blue: 0.88))
        case "indigo":
            return Color(light: Color(red: 0.35, green: 0.32, blue: 0.78),
                         dark: Color(red: 0.5, green: 0.47, blue: 0.9))
        case "teal":
            return Color(light: Color(red: 0.18, green: 0.52, blue: 0.55),
                         dark: Color(red: 0.32, green: 0.68, blue: 0.72))
        case "green":
            return Color(light: Color(red: 0.25, green: 0.55, blue: 0.32),
                         dark: Color(red: 0.38, green: 0.72, blue: 0.45))
        case "orange":
            return Color(light: Color(red: 0.78, green: 0.48, blue: 0.18),
                         dark: Color(red: 0.9, green: 0.6, blue: 0.3))
        case "rose":
            return Color(light: Color(red: 0.72, green: 0.28, blue: 0.35),
                         dark: Color(red: 0.88, green: 0.42, blue: 0.48))
        default:
            return Color(light: Color(red: 0.22, green: 0.45, blue: 0.85),
                         dark: Color(red: 0.38, green: 0.58, blue: 0.95))
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
    static let calendarEventRadius: CGFloat = 3
    /// Grid line color — extremely subtle, almost invisible like Apple Calendar
    static let calendarGridLine = Color(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.07))
    /// Current-time indicator color — Apple's signature red
    static let calendarNowIndicator = Color(light: Color(red: 0.92, green: 0.23, blue: 0.21),
                                            dark: Color(red: 0.95, green: 0.30, blue: 0.28))
    /// All-day bar background — slightly elevated surface
    static let calendarAllDayBg = Color(light: Color(white: 0.965), dark: Color(white: 0.115))

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
