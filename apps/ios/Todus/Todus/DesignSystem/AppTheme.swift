import SwiftUI

enum AppTheme {
    // Custom dynamic colors to prefer off-white and off-black
    static let backgroundTop = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.04, alpha: 1) : UIColor(white: 0.98, alpha: 1)
    })
    static let backgroundBottom = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.04, alpha: 1) : UIColor(white: 0.98, alpha: 1)
    })
    static let surfacePrimary = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.08, alpha: 1) : UIColor(white: 1.0, alpha: 1)
    })
    static let surfaceSecondary = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.11, alpha: 1) : UIColor(white: 0.95, alpha: 1)
    })
    // Restrained completely minimal accent
    static let accent = Color.primary
    static let secondaryAccent = Color.secondary
    
    // Borders & dividers: very subtle
    static let cardBorder = Color(uiColor: .separator).opacity(0.24)
    static let strongBorder = Color(uiColor: .separator).opacity(0.5)
    static let divider = Color(uiColor: .separator).opacity(0.16)
    
    // Typography
    static let subtleText = Color.secondary.opacity(0.9)
    static let mutedText = Color.secondary.opacity(0.7)
    static let danger = Color(red: 0.88, green: 0.27, blue: 0.25)
    
    // Row specifics
    static let rowFill = surfacePrimary
    static let rowStroke = Color(uiColor: .separator).opacity(0.12)
    static let shadowColor = Color.black.opacity(0.08)
}

struct SurfaceCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var fill: Color = AppTheme.surfacePrimary
    var stroke: Color = AppTheme.cardBorder

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
            .shadow(color: AppTheme.shadowColor, radius: 8, x: 0, y: 2)
    }
}

struct AppPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.white.opacity(configuration.isPressed ? 0.9 : 1))
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.blue.opacity(configuration.isPressed ? 0.82 : 0.96))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct AppSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.primary.opacity(configuration.isPressed ? 0.7 : 0.9))
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.surfaceSecondary.opacity(configuration.isPressed ? 0.9 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct AppIconButtonModifier: ViewModifier {
    var size: CGFloat = 36

    func body(content: Content) -> some View {
        content
            .frame(width: size, height: size)
            .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 16, fill: Color = AppTheme.surfacePrimary, stroke: Color = AppTheme.cardBorder) -> some View {
        modifier(SurfaceCardModifier(cornerRadius: cornerRadius, fill: fill, stroke: stroke))
    }

    func appIconButton(size: CGFloat = 36) -> some View {
        modifier(AppIconButtonModifier(size: size))
    }

    func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
