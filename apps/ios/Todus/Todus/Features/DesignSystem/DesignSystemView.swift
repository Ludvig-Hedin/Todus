import SwiftUI

/// Hidden design-system viewer.
///
/// Gated behind `TodusDeveloperAccess.isAllowlisted(email:)` in the Settings
/// developer section so it's a dogfood-only surface. Renders every token the
/// app uses (colors, typography, radius, spacing, motion, components) plus
/// "How to change" callouts pointing at `AppTheme.swift` line ranges.
///
/// Sister surfaces:
/// - macOS: `MacDesignSystemView`
/// - web:   `/settings/design-system`
struct DesignSystemView: View {
    @Environment(AppServices.self) private var services

    /// Local state for the motion demo block — taps animate a swatch sliding
    /// across the row so the user can feel the difference between `.fast`,
    /// `.base`, and `.slow`.
    @State private var motionDemoState: Int = 0

    var body: some View {
        Form {
            surfaceHierarchySection
            colorsSection
            accentSection
            typographySection
            radiusSection
            spacingSection
            buttonsSection
            cardsSection
            toastSection
            brandIconsSection
            motionSection
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.sheetBackground)
        .navigationTitle("Design System")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Surface hierarchy

    /// Nested rounded rectangles previewing the surface ladder. Each child
    /// surface uses the next-up token so the lift is visible without needing
    /// to open every screen.
    private var surfaceHierarchySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Background")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                        .fill(AppTheme.backgroundTop)
                    VStack(spacing: 12) {
                        surfaceCard(label: "sheetBackground", fill: AppTheme.sheetBackground) {
                            VStack(spacing: 8) {
                                surfaceCard(label: "surfacePrimary", fill: AppTheme.surfacePrimary) {
                                    surfaceCard(label: "surfaceSecondary", fill: AppTheme.surfaceSecondary) {
                                        EmptyView()
                                    }
                                }
                            }
                        }
                    }
                    .padding(14)
                }
                .frame(height: 280)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                )
            }
            DSHowToChangeNote(
                path: "DesignSystem/AppTheme.swift",
                lineRange: "L114–L155",
                detail: "Dark mode floor is 0.109 = Apple system dark (#1c1c1e). Surfaces step in ~0.04–0.06 increments."
            )
        } header: {
            Text("Surface hierarchy")
        }
    }

    @ViewBuilder
    private func surfaceCard<Content: View>(
        label: String,
        fill: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Colors

    private var colorsSection: some View {
        Section {
            DSTokenRow(
                name: "backgroundTop",
                value: "dark 0.109 / light 0.94",
                codeSnippet: "AppTheme.backgroundTop"
            ) { swatch(AppTheme.backgroundTop) }
            DSTokenRow(
                name: "sheetBackground",
                value: "dark 0.135 / light 0.978",
                codeSnippet: "AppTheme.sheetBackground"
            ) { swatch(AppTheme.sheetBackground) }
            DSTokenRow(
                name: "surfacePrimary",
                value: "dark 0.165 / light 1.00",
                codeSnippet: "AppTheme.surfacePrimary"
            ) { swatch(AppTheme.surfacePrimary) }
            DSTokenRow(
                name: "surfaceSecondary",
                value: "dark 0.205 / light 0.96",
                codeSnippet: "AppTheme.surfaceSecondary"
            ) { swatch(AppTheme.surfaceSecondary) }
            DSTokenRow(
                name: "chatUserBubbleFill",
                value: "dark 0.23 / light 0.92",
                codeSnippet: "AppTheme.chatUserBubbleFill"
            ) { swatch(AppTheme.chatUserBubbleFill) }
            DSTokenRow(
                name: "segmentedTrack",
                value: "dark 0.185 / light 0.88",
                codeSnippet: "AppTheme.segmentedTrack"
            ) { swatch(AppTheme.segmentedTrack) }
            DSTokenRow(
                name: "segmentedSelectedPill",
                value: "dark 0.30 / light 1.00",
                codeSnippet: "AppTheme.segmentedSelectedPill"
            ) { swatch(AppTheme.segmentedSelectedPill) }
            DSTokenRow(
                name: "sheetCardFill",
                value: "dark 0.185 / light 0.88",
                codeSnippet: "AppTheme.sheetCardFill"
            ) { swatch(AppTheme.sheetCardFill) }
            DSTokenRow(
                name: "cardBorder",
                value: "separator @ 20% opacity",
                codeSnippet: "AppTheme.cardBorder"
            ) { swatch(AppTheme.cardBorder) }
            DSTokenRow(
                name: "danger",
                value: "RGB 0.85, 0.24, 0.22",
                codeSnippet: "AppTheme.danger"
            ) { swatch(AppTheme.danger) }
            DSHowToChangeNote(
                path: "DesignSystem/AppTheme.swift",
                lineRange: "L114–L195",
                detail: "Every surface is a UITraitCollection-aware dynamic color. Edit the dark / light value pair on the listed line."
            )
        } header: {
            Text("Colors")
        }
    }

    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.chip, style: .continuous)
            .fill(color)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.chip, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 0.5)
            )
            .frame(width: 44, height: 28)
    }

    // MARK: - Accent palette

    private var accentSection: some View {
        Section {
            ForEach(AccentPreference.allCases, id: \.rawValue) { preference in
                DSTokenRow(
                    name: "Accents.\(preference.rawValue)",
                    value: rgbDescription(for: preference),
                    codeSnippet: "AppTheme.Accents.\(preference.rawValue)"
                ) {
                    Circle()
                        .fill(preference.color)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                        )
                }
            }
            HStack(spacing: 8) {
                Text("Active accent")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(services.accentPreference.rawValue)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            DSHowToChangeNote(
                path: "DesignSystem/AppTheme.swift",
                lineRange: "L197–L219",
                detail: "Edit the RGB triples in `enum Accents`. Mirror the change to `MacTheme` and web `ACCENT_COLORS`."
            )
        } header: {
            Text("Accent palette")
        }
    }

    private func rgbDescription(for preference: AccentPreference) -> String {
        switch preference {
        case .blue:   return "0.25, 0.48, 1.00"
        case .indigo: return "0.35, 0.34, 0.84"
        case .teal:   return "0.20, 0.68, 0.78"
        case .green:  return "0.20, 0.72, 0.40"
        case .orange: return "0.98, 0.55, 0.20"
        case .rose:   return "0.93, 0.32, 0.46"
        }
    }

    // MARK: - Typography

    /// SF Pro samples at every size we use, with weights 400/500/600. Kept
    /// short ("Aa Bg Mm") so the row fits without truncating on narrow phones.
    private var typographySection: some View {
        Section {
            ForEach(typographySamples, id: \.size) { sample in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Int(sample.size))pt · \(sample.label)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        Text("Aa Bg")
                            .font(.system(size: sample.size, weight: .regular))
                        Text("Aa Bg")
                            .font(.system(size: sample.size, weight: .medium))
                        Text("Aa Bg")
                            .font(.system(size: sample.size, weight: .semibold))
                    }
                }
                .padding(.vertical, 4)
            }
            DSHowToChangeNote(
                path: "DesignSystem/AppTheme.swift",
                lineRange: "(callsites)",
                detail: "Typography is not centralised in tokens yet — set explicit `.font(.system(size:weight:))` per callsite."
            )
        } header: {
            Text("Typography")
        }
    }

    private struct TypographySample {
        let size: CGFloat
        let label: String
    }

    private var typographySamples: [TypographySample] {
        [
            .init(size: 11, label: "footnote / caption"),
            .init(size: 13, label: "body small"),
            .init(size: 15, label: "body"),
            .init(size: 17, label: "control"),
            .init(size: 18, label: "header"),
            .init(size: 22, label: "title"),
        ]
    }

    // MARK: - Radius

    private var radiusSection: some View {
        Section {
            radiusRow(name: "chip",     value: AppTheme.Radius.chip)
            radiusRow(name: "inline",   value: AppTheme.Radius.inline)
            radiusRow(name: "compact",  value: AppTheme.Radius.compact)
            radiusRow(name: "control",  value: AppTheme.Radius.control)
            radiusRow(name: "row",      value: AppTheme.Radius.row)
            radiusRow(name: "card",     value: AppTheme.Radius.card)
            radiusRow(name: "composer", value: AppTheme.Radius.composer)
            DSHowToChangeNote(
                path: "DesignSystem/AppTheme.swift",
                lineRange: "L223–L238",
                detail: "Continuous rounded-rect scale. Mirror with macOS `MacTheme` and the web `--radius-*` custom properties."
            )
        } header: {
            Text("Radius scale")
        }
    }

    private func radiusRow(name: String, value: CGFloat) -> some View {
        DSTokenRow(
            name: "Radius.\(name)",
            value: "\(Int(value))pt",
            codeSnippet: "AppTheme.Radius.\(name)"
        ) {
            RoundedRectangle(cornerRadius: value, style: .continuous)
                .fill(AppTheme.surfacePrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: value, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                )
                .frame(width: 44, height: 28)
        }
    }

    // MARK: - Spacing

    /// The app doesn't carry tokenised spacing yet — these are the values we
    /// reach for again and again at callsite (4/8/12/14/16/20/24/28).
    private var spacingSection: some View {
        Section {
            ForEach([4, 8, 12, 14, 16, 20, 24, 28], id: \.self) { value in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.chip, style: .continuous)
                        .fill(AppTheme.surfacePrimary)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.chip, style: .continuous)
                                .stroke(AppTheme.cardBorder, lineWidth: 1)
                        )
                        .frame(width: CGFloat(value), height: 20)
                    Text("\(value)pt")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.primary)
                    Spacer()
                }
            }
            DSHowToChangeNote(
                path: "DesignSystem/AppTheme.swift",
                lineRange: "(callsites)",
                detail: "Spacing is not tokenised — pick from the visible scale (4 / 8 / 12 / 14 / 16 / 20 / 24 / 28) and stay on the 4pt grid."
            )
        } header: {
            Text("Spacing")
        }
    }

    // MARK: - Buttons

    private var buttonsSection: some View {
        Section {
            VStack(spacing: 12) {
                Button("Primary button") {}
                    .buttonStyle(AppPrimaryButtonStyle())
                    .frame(maxWidth: .infinity)
                Button("Secondary button") {}
                    .buttonStyle(AppSecondaryButtonStyle())
                    .frame(maxWidth: .infinity)
                Button("Liquid glass button") {}
                    .buttonStyle(LiquidGlassButtonStyle())
                    .frame(maxWidth: .infinity)
                Button("Loading…") {}
                    .buttonStyle(AppPrimaryButtonStyle())
                    .inFlight(true)
                    .frame(maxWidth: .infinity)
                Button("Disabled") {}
                    .buttonStyle(AppPrimaryButtonStyle())
                    .disabled(true)
                    .frame(maxWidth: .infinity)
            }
            DSHowToChangeNote(
                path: "DesignSystem/AppTheme.swift",
                lineRange: "L596–L693",
                detail: "Three styles: `AppPrimaryButtonStyle`, `AppSecondaryButtonStyle`, `LiquidGlassButtonStyle`. iOS 26 uses `glassEffect`, older falls back to material."
            )
        } header: {
            Text("Buttons")
        }
    }

    // MARK: - Cards

    private var cardsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Card title")
                    .font(.system(size: 15, weight: .semibold))
                Text("Body text inside `glassCard` modifier — fills with `surfacePrimary` and rounds at `Radius.card`.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()

            VStack(alignment: .leading, spacing: 8) {
                Text("Sheet list row")
                    .font(.system(size: 15, weight: .semibold))
                Text("Composed from `SheetListRowBackground` — the standard look on edit / settings sheets.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SheetListRowBackground())

            DSHowToChangeNote(
                path: "DesignSystem/AppTheme.swift",
                lineRange: "L576–L706",
                detail: "Card surfaces come from `SurfaceCardModifier` (via `.glassCard()`) and `SheetListRowBackground`."
            )
        } header: {
            Text("Cards")
        }
    }

    // MARK: - Toast preview

    private var toastSection: some View {
        Section {
            ToastOverlay(message: .success("Task created."))
                .padding(.vertical, 4)
            ToastOverlay(message: .failure("Could not generate a reply draft."))
                .padding(.vertical, 4)
            ToastOverlay(message: .info("Sync complete."))
                .padding(.vertical, 4)
            DSHowToChangeNote(
                path: "DesignSystem/ToastOverlay.swift",
                lineRange: "full file",
                detail: "Three styles: `.success`, `.failure`, `.info`. Apply via `.toast(_:)` modifier."
            )
        } header: {
            Text("Toast")
        }
    }

    // MARK: - Brand icons

    private var brandIconsSection: some View {
        Section {
            HStack(spacing: 16) {
                AppIconContainer(size: 44, background: .white) { GmailLogo() }
                Spacer()
            }
            DSHowToChangeNote(
                path: "DesignSystem/BrandIcons.swift",
                lineRange: "full file",
                detail: "Wraps brand artwork in `AppIconContainer` so icon radius and shadow stay consistent with Apple app icons."
            )
        } header: {
            Text("Brand icons")
        }
    }

    // MARK: - Motion

    private var motionSection: some View {
        Section {
            motionDemoRow(
                token: "Motion.fast",
                duration: "0.15s snappy",
                animation: AppTheme.Motion.fast
            )
            motionDemoRow(
                token: "Motion.base",
                duration: "0.25s snappy",
                animation: AppTheme.Motion.base
            )
            motionDemoRow(
                token: "Motion.slow",
                duration: "spring(0.35, 0.85)",
                animation: AppTheme.Motion.slow
            )
            motionDemoRow(
                token: "Motion.interactive",
                duration: "0.18s easeOut",
                animation: AppTheme.Motion.interactive
            )
            DSHowToChangeNote(
                path: "DesignSystem/AppTheme.swift",
                lineRange: "L256–L261",
                detail: "Map ad-hoc durations: `<= 0.18s` → `.fast`, `0.19–0.30s` → `.base`, `> 0.30s` → `.slow`."
            )
        } header: {
            Text("Motion")
        } footer: {
            Text("Tap a row to play the animation.")
        }
    }

    private func motionDemoRow(token: String, duration: String, animation: Animation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(token)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                Spacer()
                Text(duration)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                let isShifted = motionDemoState != 0
                let travel = max(proxy.size.width - 28, 0)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.segmentedTrack)
                        .frame(height: 6)
                    Circle()
                        .fill(services.accentPreference.color)
                        .frame(width: 18, height: 18)
                        .offset(x: isShifted ? travel : 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(animation) {
                        motionDemoState = (motionDemoState + 1) % 2
                    }
                }
            }
            .frame(height: 24)
        }
        .padding(.vertical, 2)
    }
}
