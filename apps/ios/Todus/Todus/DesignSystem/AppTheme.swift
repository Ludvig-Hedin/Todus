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
    // Sheets sit slightly above the app background in dark mode so they read as a distinct layer.
    static let sheetBackground = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.09, alpha: 1) : UIColor(white: 0.94, alpha: 1)
    })
    static let surfacePrimary = Color(UIColor { trait in
        // Dark: 0.11 (up from 0.09) — slightly less stark against near-black background
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.11, alpha: 1) : UIColor(white: 1.0, alpha: 1)
    })
    static let surfaceSecondary = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.14, alpha: 1) : UIColor(white: 0.96, alpha: 1)
    })
    static let sheetCardFill = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.13, alpha: 1) : UIColor(white: 0.92, alpha: 1)
    })
    // Restrained completely minimal accent
    static let accent = Color.primary
    static let secondaryAccent = Color.secondary

    /// Tint for tab bar, badges, and chrome that should read as primary content — not system blue.
    static let accentBlue = Color.primary

    /// `Toggle` / `UISwitch` on-state — system blue so the track is visible in light and dark mode.
    /// Never use `.tint(.primary)` on switches; it can render as white-on-white in dark mode.
    static let switchTint = Color(UIColor.systemBlue)
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

    // MARK: - Corner radii (aligned with MacTheme — continuous rounded rects app-wide)

    enum Radius {
        /// Primary cards, sheets, prominent surfaces (`MacTheme.cardRadius`)
        static let card: CGFloat = 18
        /// List rows, medium tiles (`MacTheme` large content)
        static let row: CGFloat = 16
        /// Inputs, search fields, secondary panels (`MacTheme.buttonRadius`)
        static let control: CGFloat = 14
        /// Nested cards, columns, compact blocks (`MacTheme.compactRadius`)
        static let compact: CGFloat = 12
        /// Small clips, tight panels
        static let inline: CGFloat = 10
        /// Status / tag / badge chips (`MacTheme.pillRadius`)
        static let chip: CGFloat = 7
        /// Chat composer / large floating chrome
        static let composer: CGFloat = 24
    }
}

/// Shared tab-page header — single row: avatar + page title (left) + action pill (right).
/// Positioned consistently at the top of every tab with uniform padding.
struct AppTopHeader<CustomTitle: View>: View {
    @Environment(AppServices.self) private var services

    let title: String
    let customTitleContent: CustomTitle?

    /// Standard init with a text title
    init(title: String) where CustomTitle == Never {
        self.title = title
        self.customTitleContent = nil
    }

    /// Init with custom content replacing the title (e.g. CalendarViewModePicker)
    init(title: String, @ViewBuilder customTitle: () -> CustomTitle) {
        self.title = title
        self.customTitleContent = customTitle()
    }

    @State private var showNotifications = false
    @State private var showsGlobalSearch = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Keep the profile image + actions from shrinking on narrow devices when the
            // custom title (e.g. Tasks + sync badge) and the action pill are both wide.
            avatarButton
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)

            Group {
                if let customTitleContent {
                    customTitleContent
                } else {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(.primary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .frame(minWidth: 0, alignment: .leading)
            .layoutPriority(0)

            Spacer(minLength: 4)

            actionsPill
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .sheet(isPresented: $showNotifications) {
            NotificationCenterView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .appSheetBackground()
                .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        .sheet(isPresented: $showsGlobalSearch) {
            GlobalSearchView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .appSheetBackground()
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
        .interactiveHitTarget(expansion: 4)
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 40)
                    .interactiveHitTarget(expansion: 4)
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 20)

            Button {
                showNotifications = true
            } label: {
                Image(systemName: "bell.badge")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 40)
                    .interactiveHitTarget(expansion: 4)
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 20)

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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 40)
                    .interactiveHitTarget(expansion: 4)
            }
            .menuStyle(.borderlessButton)
            .tint(.primary)
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
    /// Ensures a minimum visible 44x44 frame and then expands the hit target beyond that frame.
    /// Safe for isolated icon buttons and pill controls; use `interactiveHitTarget` directly in dense rows.
    func minTouchTarget() -> some View {
        self
            .frame(minWidth: 44, minHeight: 44)
            .interactiveHitTarget(expansion: 8)
    }

    /// Expands the interactive region without affecting layout. Use a smaller expansion for
    /// grouped controls and a larger one for isolated icons.
    func interactiveHitTarget(expansion: CGFloat = 6) -> some View {
        contentShape(Rectangle().inset(by: -expansion))
    }
}

struct SurfaceCardModifier: ViewModifier {
    var cornerRadius: CGFloat = AppTheme.Radius.card
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
                    .interactiveHitTarget(expansion: 6)
                    .foregroundStyle(Color.white.opacity(configuration.isPressed ? 0.85 : 1))
                    .glassEffect(
                        .regular.tint(Color.blue.opacity(configuration.isPressed ? 0.72 : 0.88)),
                        in: Capsule()
                    )
            } else {
                // Older iOS: flat blue pill
                configuration.label
                    .interactiveHitTarget(expansion: 6)
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
                    .interactiveHitTarget(expansion: 6)
                    .foregroundStyle(Color.primary.opacity(configuration.isPressed ? 0.7 : 0.9))
                    .glassEffect(.regular, in: Capsule())
            } else {
                configuration.label
                    .interactiveHitTarget(expansion: 6)
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
            .contentShape(Circle().inset(by: -6))
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
    var cornerRadius: CGFloat = AppTheme.Radius.control

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                configuration.label
                    .interactiveHitTarget(expansion: 6)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                configuration.label
                    .interactiveHitTarget(expansion: 6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(AppTheme.cardBorder, lineWidth: 1))
            }
        }
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = AppTheme.Radius.card, fill: Color = AppTheme.surfacePrimary, stroke: Color = AppTheme.cardBorder) -> some View {
        modifier(SurfaceCardModifier(cornerRadius: cornerRadius, fill: fill, stroke: stroke))
    }

    /// Sets the sheet's presentationBackground to `AppTheme.sheetBackground` with a
    /// hairline top border so sheets lift slightly above the app background in dark mode.
    func appSheetBackground() -> some View {
        self.presentationBackground {
            ZStack(alignment: .top) {
                AppTheme.sheetBackground.ignoresSafeArea()
                Color(UIColor.separator).opacity(0.20)
                    .frame(height: 0.5)
            }
        }
    }

    func appIconButton(size: CGFloat = 36) -> some View {
        modifier(AppIconButtonModifier(size: size))
    }

    func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct AttachmentThumbnailView<Placeholder: View>: View {
    let filename: String
    let size: CGFloat
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(AppTheme.Radius.chip, size * 0.2), style: .continuous))
        .task(id: [filename, String(format: "%.2f", size)].joined(separator: "-")) {
            let thumbnailName = filename
            let thumbnailSize = size
            image = nil
            guard !Task.isCancelled else { return }
            let thumbnail = await Task(priority: .utility) {
                let t = AttachmentService.shared.loadThumbnail(
                    for: thumbnailName,
                    maxPixelSize: thumbnailSize * 3
                )
                if t == nil, AttachmentService.shared.isImageFile(thumbnailName) {
                    return AttachmentService.shared.loadImage(for: thumbnailName)
                }
                return t
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                image = thumbnail
            }
        }
    }
}
