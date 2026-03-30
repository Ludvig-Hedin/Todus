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

/// Shared tab-page header — single row: avatar + page title (left) + action pill (right).
/// Positioned consistently at the top of every tab with uniform padding.
struct AppTopHeader: View {
    @Environment(AppServices.self) private var services

    let title: String

    @State private var showNotifications = false
    @State private var showsGlobalSearch = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            avatarButton

            Text(title)
                .font(.system(size: 18, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(.primary)

            Spacer()

            actionsPill
        }
        .sheet(isPresented: $showNotifications) {
            NotificationCenterView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(AppTheme.backgroundTop)
                .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        .sheet(isPresented: $showsGlobalSearch) {
            GlobalSearchView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(AppTheme.backgroundTop)
                .preferredColorScheme(services.appearancePreference.colorScheme)
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
            .frame(width: 34, height: 34)
            .clipShape(Circle())
            .overlay(Circle().stroke(AppTheme.cardBorder, lineWidth: 1))
        } else {
            initialsAvatar
                .frame(width: 34, height: 34)
                .clipShape(Circle())
                .overlay(Circle().stroke(AppTheme.cardBorder, lineWidth: 1))
        }
    }

    private var initialsAvatar: some View {
        ZStack {
            Circle()
                .fill(AppTheme.surfacePrimary)
            Text(userInitial)
                .font(.system(size: 15, weight: .semibold))
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

    /// Action buttons pill — real Liquid Glass on iOS 26, material fallback on older.
    private var actionsPill: some View {
        HStack(spacing: 0) {
            Button {
                showsGlobalSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 36)
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 18)

            Button {
                showNotifications = true
            } label: {
                Image(systemName: "bell.badge")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 36)
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 18)

            Menu {
                Button("Settings") {
                    services.showsSettings = true
                }

                Divider()

                Button("Refresh Mail") {
                    Task { await services.emailService.loadThreads(refresh: true) }
                }

                Button("New Email") {
                    services.showsComposeEmail = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 36)
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
        }
        .glassActionPill()
    }
}

private extension View {
    /// Liquid Glass pill for the header action buttons.
    /// iOS 26+: real system Liquid Glass. Older: ultraThinMaterial fallback.
    @ViewBuilder
    func glassActionPill() -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(AppTheme.cardBorder, lineWidth: 1))
        }
    }
}

// MARK: - Touch Target Helpers

extension View {
    /// Ensures a minimum 44×44 pt interactive touch area (Apple HIG requirement) without
    /// changing the visual appearance of the view. The visible content stays the same size;
    /// only the hit-testing region is expanded. Safe to use on buttons separated from
    /// neighbours by a Spacer or flexible area — do NOT use in dense equal-width button rows.
    func minTouchTarget() -> some View {
        self
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
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

/// Primary action button — pill-shaped, blue, glass tint on iOS 26.
struct AppPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                // iOS 26: Liquid Glass with a blue tint overlay — pill shape
                configuration.label
                    .foregroundStyle(Color.white.opacity(configuration.isPressed ? 0.85 : 1))
                    .glassEffect(
                        .regular.tint(Color.blue.opacity(configuration.isPressed ? 0.72 : 0.88)),
                        in: Capsule()
                    )
            } else {
                // Older iOS: flat blue pill
                configuration.label
                    .foregroundStyle(Color.white.opacity(configuration.isPressed ? 0.9 : 1))
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(configuration.isPressed ? 0.82 : 0.96))
                    )
            }
        }
        .scaleEffect(configuration.isPressed ? 0.98 : 1)
        .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Secondary action button — pill-shaped, glass material.
struct AppSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                configuration.label
                    .foregroundStyle(Color.primary.opacity(configuration.isPressed ? 0.7 : 0.9))
                    .glassEffect(.regular, in: Capsule())
            } else {
                configuration.label
                    .foregroundStyle(Color.primary.opacity(configuration.isPressed ? 0.7 : 0.9))
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    )
            }
        }
        .scaleEffect(configuration.isPressed ? 0.98 : 1)
        .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct AppIconButtonModifier: ViewModifier {
    var size: CGFloat = 36

    func body(content: Content) -> some View {
        content
            .frame(width: size, height: size)
            .background(AppTheme.surfacePrimary, in: Circle())
            .overlay(Circle().stroke(AppTheme.cardBorder, lineWidth: 1))
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
/// falling back to ultraThinMaterial rounded rectangle on older iOS.
/// `cornerRadius` is used for the fallback path; iOS 26 always uses Capsule glass.
struct LiquidGlassButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                configuration.label
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                configuration.label
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(AppTheme.cardBorder, lineWidth: 1))
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
