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
    /// Buttons, inputs
    static let buttonRadius: CGFloat = 6

    // MARK: - Colors

    /// Subtle card surface — sits just above the window background
    static let surfaceCard = Color(light: Color(white: 0.975), dark: Color(white: 0.13))

    /// Elevated surface for hover states
    static let surfaceHover = Color(light: Color(white: 0.955), dark: Color(white: 0.16))

    /// Card border — whisper-thin separator
    static let cardBorder = Color(light: Color.black.opacity(0.06), dark: Color.white.opacity(0.08))

    /// Muted text for chevrons, timestamps, tertiary info
    static let mutedText = Color(light: Color(white: 0.55), dark: Color(white: 0.45))

    /// Primary text — slightly softer than pure black for elegance
    static let textPrimary = Color(light: Color(white: 0.12), dark: Color(white: 0.92))

    /// Secondary text
    static let textSecondary = Color(light: Color(white: 0.42), dark: Color(white: 0.55))

    /// Accent — dynamically resolved from user's chosen accent color preference.
    /// Reads from UserDefaults on each access (cached by the OS, negligible cost).
    static var accent: Color {
        accentColor(for: UserDefaults.standard.string(forKey: "mac_accent_color") ?? "blue")
    }

    /// Badge / count background
    static let badgeSurface = Color(light: Color(white: 0.92), dark: Color(white: 0.2))

    /// Empty state / onboarding card background
    static let emptyStateSurface = Color(light: Color(white: 0.97), dark: Color(white: 0.11))

    // MARK: - Accent Color Palette

    /// Available accent color keys — used by the settings accent picker.
    static let accentColorKeys = ["blue", "indigo", "teal", "green", "orange", "rose"]

    /// Resolves an accent color key to a light/dark adaptive Color.
    /// All colors are intentionally muted — not screaming neon. Fits the refined editorial aesthetic.
    static func accentColor(for key: String) -> Color {
        switch key {
        case "blue":
            return Color(light: Color(red: 0.22, green: 0.45, blue: 0.85),
                         dark: Color(red: 0.38, green: 0.58, blue: 0.95))
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
