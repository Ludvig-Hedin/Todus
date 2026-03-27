import SwiftUI
import UIKit

enum AppTheme {
    // Custom dynamic colors — off-white / off-black, never pure
    // Light: 0.94 matches iOS systemGroupedBackground, giving List cells (white) visible contrast.
    // Dark: 0.05 is near-black; surfacePrimary at 0.11 provides subtle but clear card lift.
    static let backgroundTop = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.05, alpha: 1) : UIColor(white: 0.94, alpha: 1)
    })
    static let backgroundBottom = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.05, alpha: 1) : UIColor(white: 0.94, alpha: 1)
    })
    static let surfacePrimary = Color(UIColor { trait in
        // Dark: 0.11 (up from 0.09) — slightly less stark against near-black background
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.11, alpha: 1) : UIColor(white: 1.0, alpha: 1)
    })
    static let surfaceSecondary = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.14, alpha: 1) : UIColor(white: 0.96, alpha: 1)
    })
    // Restrained completely minimal accent
    static let accent = Color.primary
    static let secondaryAccent = Color.secondary

    // Tab bar colors — system blue matches our button color (AppPrimaryButtonStyle)
    static let accentBlue = Color.blue
    static let mutedGray = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 0.55, alpha: 1)
            : UIColor(white: 0.50, alpha: 1)
    })
    
    // Borders & dividers: very subtle, consistent with web tokens
    static let cardBorder = Color(uiColor: .separator).opacity(0.20)
    static let strongBorder = Color(uiColor: .separator).opacity(0.40)
    static let divider = Color(uiColor: .separator).opacity(0.14)

    // Typography
    static let subtleText = Color.secondary.opacity(0.85)
    static let mutedText = Color.secondary.opacity(0.65)
    static let danger = Color(red: 0.85, green: 0.24, blue: 0.22)

    // Row specifics
    static let rowFill = surfacePrimary
    static let rowStroke = Color(uiColor: .separator).opacity(0.10)
    static let shadowColor = Color.black.opacity(0.06)
}

/// Shared tab-page header:
/// - Top row: user avatar (left) + dual action pill (right)
/// - Second row: large page title
struct AppTopHeader: View {
    @Environment(AppServices.self) private var services

    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                avatarButton
                Spacer()
                actionsPill
            }

            Text(title)
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(.primary)
        }
    }

    private var avatarButton: some View {
        Button {
            services.showsSettings = true
        } label: {
            avatarContent
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open settings")
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let imageURLString = services.authService.userImage,
           let imageURL = URL(string: imageURLString) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    initialsAvatar
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
        } else {
            initialsAvatar
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                )
        }
    }

    private var initialsAvatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.surfacePrimary)
            Text(userInitial)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }

    private var userInitial: String {
        let source = services.authService.userName
            ?? services.authService.userEmail
            ?? services.authStore.accountEmail
            ?? "U"
        return String(source.first(where: { $0.isLetter }) ?? "U").uppercased()
    }

    private var actionsPill: some View {
        HStack(spacing: 0) {
            Button {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Image(systemName: "bell.badge")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 40)
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 20)

            Button {
                services.showsSettings = true
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 40)
            }
            .buttonStyle(.plain)
        }
        .background(AppTheme.surfacePrimary, in: Capsule())
        .overlay(
            Capsule()
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }
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

/// Re-enables the swipe-to-go-back gesture on views that hide the system back button.
/// Use as `.background { SwipeBackEnabler() }` on any view that has
/// `.navigationBarBackButtonHidden(true)` but still needs edge-swipe to pop.
struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }
    func updateUIViewController(_ vc: UIViewController, context: Context) {
        DispatchQueue.main.async {
            vc.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
            vc.navigationController?.interactivePopGestureRecognizer?.delegate = nil
        }
    }
}

/// Button style that uses iOS 26 Liquid Glass on supported devices,
/// falling back to a surface+border card look on older iOS.
struct LiquidGlassButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 14
    func makeBody(configuration: Configuration) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                configuration.label
                    .glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                configuration.label
                    .background(
                        AppTheme.surfacePrimary,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    )
            }
        }
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .animation(.snappy(duration: 0.15), value: configuration.isPressed)
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
