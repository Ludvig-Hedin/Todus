import CryptoKit
import SwiftUI
import UIKit

// MARK: - Cached Avatar Image

/// Filesystem-backed avatar cache. Lives under `Caches/avatars/` so iOS can evict it
/// on disk pressure without us shipping multi-MB blobs in UserDefaults (the previous
/// implementation cratered cold-launch perf on accounts with dozens of senders).
enum AvatarDiskCache {
    /// Lazily-created directory used for cached avatar JPEGs. Resolved once and
    /// reused — `FileManager.default.urls(for:in:)` is cheap, but we still avoid
    /// hitting it on every read.
    static let directory: URL = {
        let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("avatars", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }()

    /// Stable, filename-safe key derived from the source URL.
    static func key(for urlString: String) -> String {
        let hash = SHA256.hash(data: Data(urlString.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    static func url(for key: String) -> URL {
        directory.appendingPathComponent(key, isDirectory: false)
    }

    static func read(key: String) -> Data? {
        try? Data(contentsOf: url(for: key))
    }

    static func write(_ data: Data, key: String) {
        try? data.write(to: url(for: key), options: .atomic)
    }
}

/// Avatar view that fetches from the network and persists the image data locally so
/// it renders correctly when the device is offline. Cache updates on each successful
/// fetch; passing nil for urlString shows the fallback immediately.
struct CachedAvatarImage<Fallback: View>: View {
    let urlString: String?
    let size: CGFloat
    @ViewBuilder let fallback: () -> Fallback

    /// Stable filesystem key — SHA-256 of the URL string. Replaces the previous
    /// `String.hashValue` key which was per-launch random (Swift seeds its String
    /// hasher with a fresh value each process), causing every relaunch to refetch
    /// the same avatars and then orphan the prior cache entry.
    private var diskCacheKey: String? {
        guard let urlString, !urlString.isEmpty else { return nil }
        return AvatarDiskCache.key(for: urlString)
    }

    /// Legacy UserDefaults key — read once on first appear so existing cached blobs
    /// migrate to the new on-disk store and the UserDefaults bloat can be cleared.
    private var legacyDefaultsKey: String? {
        guard let urlString else { return nil }
        return "com.todus.avatar.imageData.\(urlString.hashValue)"
    }

    @State private var loadedImage: Image? = nil

    var body: some View {
        Group {
            if let img = loadedImage {
                img.resizable().scaledToFill()
            } else {
                fallback()
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: urlString) {
            await loadFromCache()
            await fetchAndCache()
        }
    }

    /// Disk read + JPEG decode happen on a background task. The previous
    /// `.onAppear`-driven sync `Data(contentsOf:)` ran on the main thread for
    /// every row scrolling into view — a steady source of inbox scroll hitching.
    private func loadFromCache() async {
        guard loadedImage == nil, let diskCacheKey else { return }
        let legacyKey = legacyDefaultsKey
        let uiImage: UIImage? = await Task.detached(priority: .userInitiated) {
            if let data = AvatarDiskCache.read(key: diskCacheKey),
               let image = UIImage(data: data) {
                return image
            }
            // One-shot migration: surface a stale UserDefaults blob, copy it to disk,
            // then drop the defaults entry so we stop carrying it across launches.
            if let legacyKey,
               let legacyData = UserDefaults.standard.data(forKey: legacyKey),
               let image = UIImage(data: legacyData) {
                AvatarDiskCache.write(legacyData, key: diskCacheKey)
                UserDefaults.standard.removeObject(forKey: legacyKey)
                return image
            }
            return nil
        }.value
        if let uiImage, loadedImage == nil {
            loadedImage = Image(uiImage: uiImage)
        }
    }

    @MainActor
    private func fetchAndCache() async {
        guard let urlString, let url = URL(string: urlString), let diskCacheKey else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let uiImage = UIImage(data: data) else { return }
        // Persist off-main — `.atomic` writes a temp file + rename, which is real
        // disk I/O that doesn't belong on the main thread.
        Task.detached(priority: .utility) {
            AvatarDiskCache.write(data, key: diskCacheKey)
        }
        loadedImage = Image(uiImage: uiImage)
    }
}

enum AppTheme {
    // Custom dynamic colors — off-white / off-black, never pure
    // Light: 0.94 matches iOS systemGroupedBackground, giving List cells (white) visible contrast.
    // Dark: 0.109 = Apple system dark (#1c1c1e); surfaces step in ~0.04–0.06 increments.
    static let backgroundTop = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.109, alpha: 1) : UIColor(white: 0.94, alpha: 1)
    })
    static let backgroundBottom = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.109, alpha: 1) : UIColor(white: 0.94, alpha: 1)
    })
    // Sheets use a distinct surface: lighter “paper” in light mode vs gray app chrome; lifted gray in dark.
    static let sheetBackground = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.135, alpha: 1) : UIColor(white: 0.978, alpha: 1)
    })
    static let surfacePrimary = Color(UIColor { trait in
        // Dark: 0.165 — clear lift above the lifted #1c1c1e background while staying restrained.
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.165, alpha: 1) : UIColor(white: 1.0, alpha: 1)
    })
    static let surfaceSecondary = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.205, alpha: 1) : UIColor(white: 0.96, alpha: 1)
    })
    /// User chat bubble fill inside the AI sheet.
    /// Tuned to keep roughly the same perceived separation in both appearances:
    /// restrained light gray on light mode, restrained dark gray on dark mode.
    static let chatUserBubbleFill = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.23, alpha: 1) : UIColor(white: 0.92, alpha: 1)
    })
    // MARK: Segmented control (same recipe as macOS `MacTheme.segmentedTrack` / Calendar picker)
    /// Recessed track behind segments — visible in light and dark mode.
    static let segmentedTrack = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.185, alpha: 1) : UIColor(white: 0.88, alpha: 1)
    })
    /// Selected tab pill — high contrast on `segmentedTrack`.
    static let segmentedSelectedPill = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.30, alpha: 1) : UIColor(white: 1.0, alpha: 1)
    })
    /// Inset list rows on sheets — light mode uses a slightly darker fill + stroke so fields read as real cards.
    static let sheetCardFill = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.185, alpha: 1) : UIColor(white: 0.88, alpha: 1)
    })
    static let sheetListRowStroke = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.separator.withAlphaComponent(0.22)
            : UIColor.separator.withAlphaComponent(0.40)
    })
    // Restrained completely minimal accent
    static let accent = Color.primary
    static let secondaryAccent = Color.secondary

    /// Tint for tab bar, badges, and chrome that should read as primary content — not system blue.
    static let accentBlue = Color.primary

    /// Foreground for pill/circle buttons whose background is `AppTheme.accent` / `Color.primary`.
    /// Inverts with appearance: light mode → accent is near-black → white foreground;
    /// dark mode → accent resolves to white → dark foreground (prevents white-on-white).
    static let primaryButtonForeground = Color(UIColor.systemBackground)

    /// `Toggle` / `UISwitch` on-state — system blue so the track is visible in light and dark mode.
    /// Never use `.tint(.primary)` on switches; it can render as white-on-white in dark mode.
    static let switchTint = Color(UIColor.systemBlue)

    /// Cross-device accent color palette. Keys match macOS `MacTheme.accentColorKeys` so
    /// the synced `accentColor` field round-trips identically between iOS / macOS / web.
    /// Use `AccentPreference(rawValue: key)?.color` (or `AppTheme.Accents.<name>`) to
    /// resolve a key to a `Color` — the previous `accentColor(for:)` shim has been
    /// removed so there is a single source of truth for the RGB triples.
    static let accentColorKeys: [String] = ["blue", "indigo", "teal", "green", "orange", "rose"]
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

    /// Single source of truth for the "now" marker color on calendar grids. Centralised
    /// here so the various calendar surfaces (week, day, multi-day) match without each
    /// hand-rolling an RGB literal. Match the calendar agent's deferred polish item.
    static let calendarNow = Color(red: 0.92, green: 0.23, blue: 0.21)

    // Row specifics
    static let rowFill = surfacePrimary
    static let rowStroke = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.separator.withAlphaComponent(0.12)
            : UIColor.separator.withAlphaComponent(0.24)
    })
    static let shadowColor = Color.black.opacity(0.06)

    // MARK: - Accent palette (shared with macOS + web)
    //
    // Six restrained accents. Used for the optional user-selectable accent
    // (Settings → Appearance) and the future cross-platform branding tint.
    // Keep the RGB triples in lockstep with `MacTheme` / web `ACCENT_COLORS`.

    enum Accents {
        static let blue   = Color(red: 0.22, green: 0.45, blue: 0.85)
        static let indigo = Color(red: 0.35, green: 0.32, blue: 0.78)
        static let teal   = Color(red: 0.18, green: 0.52, blue: 0.55)
        static let green  = Color(red: 0.25, green: 0.55, blue: 0.32)
        static let orange = Color(red: 0.78, green: 0.48, blue: 0.18)
        static let rose   = Color(red: 0.72, green: 0.28, blue: 0.35)
        /// Ordered list for swatch pickers and previews.
        static let all: [(String, Color)] = [
            ("blue", blue),
            ("indigo", indigo),
            ("teal", teal),
            ("green", green),
            ("orange", orange),
            ("rose", rose),
        ]
    }

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

    /// Layout metrics for inline `ProgressView` in buttons and rows (prevents spinners from dictating height).
    enum Metrics {
        /// Primary pill buttons with ~20pt icons (Gmail, calendar, notifications, etc.).
        static let buttonInlineSpinner: CGFloat = 20
        /// Navigation bar and toolbar items (~16pt SF Symbol / bar title).
        static let toolbarInlineSpinner: CGFloat = 16
        /// Compact chips and secondary actions with 12–13pt type.
        static let compactInlineSpinner: CGFloat = 14
    }

    // MARK: - Motion tokens (shared with macOS + web duration scale)
    //
    // Centralised animation tokens so per-callsite durations stay in lockstep.
    // Map ad-hoc literals as: <= 0.18s → `.fast`, 0.19–0.30s → `.base`, > 0.30s → `.slow`.
    // `.interactive` is reserved for press / tap feedback where snap-back matters.

    enum Motion {
        static let fast: Animation = .snappy(duration: 0.15)
        static let base: Animation = .snappy(duration: 0.25)
        static let slow: Animation = .spring(response: 0.35, dampingFraction: 0.85)
        static let interactive: Animation = .easeOut(duration: 0.18)
    }
}

/// User-selectable brand accent. Mirrors macOS `MacAccentPreference` and the web
/// `ACCENT_COLORS` array so all three platforms share the same six names + RGB.
enum AccentPreference: String, CaseIterable, Sendable {
    case blue, indigo, teal, green, orange, rose

    var color: Color {
        switch self {
        case .blue:   return AppTheme.Accents.blue
        case .indigo: return AppTheme.Accents.indigo
        case .teal:   return AppTheme.Accents.teal
        case .green:  return AppTheme.Accents.green
        case .orange: return AppTheme.Accents.orange
        case .rose:   return AppTheme.Accents.rose
        }
    }
}

/// Circular progress sized like an inline icon so loading state does not enlarge the button or row.
struct ButtonInlineProgressView: View {
    var tint: Color
    /// Square edge length; prefer `AppTheme.Metrics` presets to match neighboring icons or type.
    var side: CGFloat

    init(tint: Color = .white, side: CGFloat = AppTheme.Metrics.buttonInlineSpinner) {
        self.tint = tint
        self.side = side
    }

    var body: some View {
        ProgressView()
            .controlSize(.mini)
            .tint(tint)
            .frame(width: side, height: side)
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

    private var avatarContent: some View {
        CachedAvatarImage(urlString: services.authService.userImage, size: 34) {
            initialsAvatar
        }
        .overlay(Circle().stroke(AppTheme.cardBorder, lineWidth: 1))
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
                // Always render the plain `bell` glyph for now — the previous
                // `bell.badge` variant made VoiceOver announce "Notifications, with badge"
                // even when there were zero unread items, which read as a phantom alert.
                // When we wire a real unread-count signal here, switch back to
                // `bell.badge` only when the count is > 0.
                Image(systemName: "bell")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 40)
                    .interactiveHitTarget(expansion: 4)
                    .accessibilityLabel("Notifications")
            }
            .buttonStyle(.plain)

            if hasContextMenuItems {
                Divider()
                    .frame(height: 20)

                Menu {
                    contextMenuContent
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 40)
                        .interactiveHitTarget(expansion: 4)
                }
                .menuStyle(.button)
                .tint(.primary)
                .buttonStyle(.plain)
            }
        }
        .glassActionPill()
    }

    /// Whether the current tab exposes any contextual actions. When false, the entire
    /// ellipsis button (and its leading divider) is omitted so the action pill
    /// shrinks gracefully to just search + notifications.
    private var hasContextMenuItems: Bool {
        switch services.currentTab {
        case .home, .tasks, .email, .calendar:
            return true
        case .meetings, .docs, .create, .ai:
            return false
        }
    }

    /// Contextual menu items for the active tab.
    @ViewBuilder
    private var contextMenuContent: some View {
        switch services.currentTab {
        case .home:
            Button {
                services.homeRefreshTick &+= 1
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            Divider()
            Button {
                services.requestCreateSheet = .task
            } label: {
                Label("New Task", systemImage: "checklist")
            }
            Button {
                services.showsComposeEmail = true
            } label: {
                Label("New Email", systemImage: "square.and.pencil")
            }

        case .tasks:
            Button {
                services.tasksSyncRemindersTick &+= 1
            } label: {
                Label("Sync with Apple Reminders", systemImage: "arrow.triangle.2.circlepath")
            }
            Divider()
            Button(role: .destructive) {
                services.tasksClearCompletedTick &+= 1
            } label: {
                Label("Clear Completed", systemImage: "trash")
            }
            Divider()
            Button {
                services.requestCreateSheet = .task
            } label: {
                Label("New Task", systemImage: "checklist")
            }

        case .email:
            Button {
                services.emailRefreshTick &+= 1
            } label: {
                Label("Refresh Mail", systemImage: "arrow.clockwise")
            }
            Button {
                services.emailMarkAllReadTick &+= 1
            } label: {
                Label("Mark All as Read", systemImage: "envelope.open")
            }
            Button {
                services.threadGroupingEnabled.toggle()
            } label: {
                Label(
                    services.threadGroupingEnabled ? "View as People" : "View as Threads",
                    systemImage: services.threadGroupingEnabled ? "person.2" : "tray.2"
                )
            }
            Divider()
            Button {
                services.showsComposeEmail = true
            } label: {
                Label("New Email", systemImage: "square.and.pencil")
            }

        case .calendar:
            Button {
                services.calendarGoToTodayTick &+= 1
            } label: {
                Label("Go to Today", systemImage: "calendar.circle")
            }
            Button {
                services.calendarRefreshTick &+= 1
            } label: {
                Label("Refresh Events", systemImage: "arrow.clockwise")
            }
            Menu {
                ForEach(CalendarViewMode.allCases) { mode in
                    Button {
                        services.calendarRequestedViewMode = mode
                    } label: {
                        Text(mode.menuLabel(multiDayCount: 3))
                    }
                }
            } label: {
                Label("View", systemImage: "rectangle.3.group")
            }
            Divider()
            Button {
                services.requestCreateSheet = .event
            } label: {
                Label("New Event", systemImage: "calendar.badge.plus")
            }

        case .meetings, .docs, .create, .ai:
            EmptyView()
        }
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

// MARK: - Page Header Scrim

extension View {
    /// Floating page header background — opaque at the top (blending with the status bar),
    /// fading to clear `scrimHeight` points below the header's top edge.
    /// Apply to the header overlay VStack; pair with `.safeAreaInset(edge: .top)` on the
    /// scroll view so content starts where the gradient becomes transparent.
    func pageHeaderScrim(color: Color = AppTheme.backgroundTop, scrimHeight: CGFloat) -> some View {
        background(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: color, location: 0.0),
                    .init(color: color, location: 0.72),
                    .init(color: color.opacity(0), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
            .frame(height: max(scrimHeight, 60))
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

/// Primary action button — pill-shaped, accent-tinted, glass on iOS 26.
/// Uses `Color.accentColor` (which the asset catalog maps to the brand neutral) so
/// rebranding or dark-mode tweaks flow through automatically instead of being
/// pinned to the system blue.
struct AppPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                configuration.label
                    .interactiveHitTarget(expansion: 6)
                    // White, not `primaryButtonForeground` (= systemBackground, which
                    // is BLACK in dark mode): the background is the saturated
                    // `Color.accentColor` (the asset AccentColor / blue), not
                    // `Color.primary`, so the inverting foreground rendered black
                    // text on a blue pill in dark mode. White reads on the accent
                    // in both light and dark.
                    .foregroundStyle(Color.white.opacity(configuration.isPressed ? 0.85 : 1))
                    .glassEffect(
                        .regular.tint(Color.accentColor.opacity(configuration.isPressed ? 0.72 : 0.88)),
                        in: Capsule()
                    )
            } else {
                configuration.label
                    .interactiveHitTarget(expansion: 6)
                    .foregroundStyle(Color.white.opacity(configuration.isPressed ? 0.9 : 1))
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(configuration.isPressed ? 0.82 : 1.0))
                    )
            }
        }
        .scaleEffect(configuration.isPressed ? 0.98 : 1)
        .animation(AppTheme.Motion.fast, value: configuration.isPressed)
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
        .animation(AppTheme.Motion.fast, value: configuration.isPressed)
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
        .animation(AppTheme.Motion.fast, value: configuration.isPressed)
    }
}

/// Background for `List` rows on task edit / form sheets — readable lift in light mode.
struct SheetListRowBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
            .fill(AppTheme.sheetCardFill)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                    .stroke(AppTheme.sheetListRowStroke, lineWidth: 0.5)
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = AppTheme.Radius.card, fill: Color = AppTheme.surfacePrimary, stroke: Color = AppTheme.cardBorder) -> some View {
        modifier(SurfaceCardModifier(cornerRadius: cornerRadius, fill: fill, stroke: stroke))
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

// MARK: - Action Patterns
//
// Shared SwiftUI modifiers that standardize the three most common UX gaps we
// keep re-inventing per-view:
//
//   1. In-flight async buttons (disable + spinner)
//   2. Haptic feedback on a toggling value
//   3. Destructive confirmation dialogs from an `Item?` trigger
//
// New code (and audit fixes) should adopt these instead of re-implementing the
// same `@State var isSaving` / `UIImpactFeedbackGenerator(...)` / inline
// `confirmationDialog` boilerplate. Apply with `.inFlight(_:)`,
// `.hapticOnChange(_:kind:)`, `.confirmDestructive(item:title:...)`.
//
// These live in AppTheme.swift (rather than a dedicated file) because the iOS
// `.xcodeproj` lists source files explicitly — keeping the patterns inside an
// already-tracked file avoids an Xcode project edit per addition.

// MARK: 1. In-flight

extension View {
    /// Marks a control as performing an async action: disables it and overlays
    /// an inline spinner. Use on `Button`, `Menu`, etc.
    ///
    /// Replaces the recurring `@State var isSaving = false` + manual
    /// `.disabled` + manual ProgressView swap pattern.
    ///
    /// - Parameters:
    ///   - isActive: True while the action is running.
    ///   - showsSpinner: When true, fades the label and overlays a centered
    ///     spinner. When false, only the disabled state applies (use for
    ///     controls that already render their own progress badge).
    @ViewBuilder
    func inFlight(_ isActive: Bool, showsSpinner: Bool = true) -> some View {
        if showsSpinner {
            self
                .opacity(isActive ? 0.55 : 1)
                .overlay {
                    if isActive {
                        ButtonInlineProgressView(
                            tint: AppTheme.mutedText,
                            side: AppTheme.Metrics.compactInlineSpinner
                        )
                        .transition(.opacity)
                    }
                }
                .disabled(isActive)
                .animation(AppTheme.Motion.fast, value: isActive)
        } else {
            self.disabled(isActive)
        }
    }
}

// MARK: 2. Haptic feedback

/// Discrete haptic kinds. Wraps UIKit's generators so callers don't have to
/// import UIKit or pick a generator type each time.
enum AppHaptic {
    case light
    case medium
    case heavy
    case selection
    case success
    case warning
    case error

    /// Fire immediately. Prefer `.hapticOnChange` modifier when feedback is
    /// tied to a state change — that variant skips the haptic on first appear.
    func play() {
        // UIKit feedback generators are main-actor-isolated. Every caller fires
        // from a synchronous SwiftUI main-thread context (button taps, onChange),
        // so assume isolation instead of hopping actors and delaying the buzz.
        MainActor.assumeIsolated {
            switch self {
            case .light:
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            case .medium:
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case .heavy:
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            case .selection:
                UISelectionFeedbackGenerator().selectionChanged()
            case .success:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .warning:
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            case .error:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}

extension View {
    /// Plays a haptic when `value` changes after first appearance. Skips the
    /// initial `onAppear` value so views don't buzz on every render.
    func hapticOnChange<V: Equatable>(_ value: V, kind: AppHaptic) -> some View {
        self.modifier(HapticOnChangeModifier(value: value, kind: kind))
    }
}

private struct HapticOnChangeModifier<V: Equatable>: ViewModifier {
    let value: V
    let kind: AppHaptic
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
    /// Setting the binding to non-nil presents the dialog; the Confirm button
    /// calls `perform(item)` and the dialog auto-clears the binding on dismiss.
    ///
    /// Use for one-shot destructive actions (Delete thread, Clear completed,
    /// Remove account). For inline swipe-deletes prefer `allowsFullSwipe:
    /// false` first — confirmations are cheap, but every dialog tax is a tax.
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
