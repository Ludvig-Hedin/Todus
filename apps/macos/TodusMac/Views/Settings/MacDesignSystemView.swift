import SwiftUI

/// macOS Design System viewer — gated to developer-mode/allowlisted users.
/// Renders every token in `MacTheme.swift` with a "How to change" callout
/// citing the exact source line range so engineers can locate + edit values fast.
///
/// Mirrors the cross-platform contract documented in repo-root `DESIGN_SYSTEM.md`:
/// keeping this viewer in lockstep with iOS `DesignSystemView` and the web
/// `/settings/design-system` page is the dogfood loop that keeps the tokens honest.
///
/// Eats its own dogfood: every swatch container uses `MacTheme.surfaceCard`,
/// `MacTheme.cardBorder`, and `MacTheme.cardRadius` rather than ad-hoc values.
struct MacDesignSystemView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: DSSection = .colors

    enum DSSection: String, CaseIterable, Hashable, Identifiable {
        case colors
        case typography
        case radius
        case spacing
        case accent
        case components
        case motion

        var id: String { rawValue }

        var title: String {
            switch self {
            case .colors: return "Colors"
            case .typography: return "Typography"
            case .radius: return "Radius"
            case .spacing: return "Spacing"
            case .accent: return "Accent palette"
            case .components: return "Components"
            case .motion: return "Motion"
            }
        }

        var systemImage: String {
            switch self {
            case .colors: return "paintpalette"
            case .typography: return "textformat"
            case .radius: return "rectangle.roundedtop"
            case .spacing: return "ruler"
            case .accent: return "circle.hexagongrid"
            case .components: return "square.on.square"
            case .motion: return "waveform.path"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(DSSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .font(.system(size: 12.5))
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: MacTheme.spacing24) {
                    sectionHeader
                    sectionBody
                }
                .padding(.horizontal, MacTheme.spacing24)
                .padding(.vertical, MacTheme.spacing24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(MacTheme.contentBackground)
        }
        .navigationTitle("Design System")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .frame(minWidth: 820, minHeight: 600)
    }

    // MARK: - Header

    @ViewBuilder
    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(selection.title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(MacTheme.textPrimary)
            Text("Live values from MacTheme.swift — every token below is the actual computed value.")
                .font(MacTheme.cardSubtitleFont())
                .foregroundStyle(MacTheme.textSecondary)
        }
    }

    @ViewBuilder
    private var sectionBody: some View {
        switch selection {
        case .colors: colorsSection
        case .typography: typographySection
        case .radius: radiusSection
        case .spacing: spacingSection
        case .accent: accentSection
        case .components: componentsSection
        case .motion: motionSection
        }
    }

    // MARK: - Colors

    @ViewBuilder
    private var colorsSection: some View {
        let columns = [GridItem(.adaptive(minimum: 220), spacing: MacTheme.spacing12)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: MacTheme.spacing12) {
            colorSwatch(name: "contentBackground", value: "Color(white: 0.109) dark", source: "MacTheme.swift:48", color: MacTheme.contentBackground)
            colorSwatch(name: "surfaceCard", value: "Color(white: 0.135) dark", source: "MacTheme.swift:51", color: MacTheme.surfaceCard)
            colorSwatch(name: "surfaceHover", value: "Color(white: 0.17) dark", source: "MacTheme.swift:54", color: MacTheme.surfaceHover)
            colorSwatch(name: "cardBorder", value: "white opacity 0.10 dark", source: "MacTheme.swift:57", color: MacTheme.cardBorder)
            colorSwatch(name: "mutedText", value: "Color(white: 0.45) dark", source: "MacTheme.swift:60", color: MacTheme.mutedText)
            colorSwatch(name: "textPrimary", value: "Color(white: 0.92) dark", source: "MacTheme.swift:63", color: MacTheme.textPrimary)
            colorSwatch(name: "textSecondary", value: "Color(white: 0.55) dark", source: "MacTheme.swift:66", color: MacTheme.textSecondary)
            colorSwatch(name: "badgeSurface", value: "Color(white: 0.18) dark", source: "MacTheme.swift:78", color: MacTheme.badgeSurface)
            colorSwatch(name: "mutedAvatarFill", value: "Color(white: 0.35) dark", source: "MacTheme.swift:82", color: MacTheme.mutedAvatarFill)
            colorSwatch(name: "emptyStateSurface", value: "Color(white: 0.125) dark", source: "MacTheme.swift:85", color: MacTheme.emptyStateSurface)
            colorSwatch(name: "segmentedTrack", value: "Color(white: 0.15) dark", source: "MacTheme.swift:90", color: MacTheme.segmentedTrack)
            colorSwatch(name: "segmentedSelectedPill", value: "Color(white: 0.22) dark", source: "MacTheme.swift:92", color: MacTheme.segmentedSelectedPill)
            colorSwatch(name: "calendarAllDayBg", value: "Color(white: 0.135) dark", source: "MacTheme.swift:145", color: MacTheme.calendarAllDayBg)
            colorSwatch(name: "inputBackground", value: "white opacity 0.05 dark", source: "MacTheme.swift:29", color: MacTheme.inputBackground)
        }
        howToChange(text: "Edit `MacTheme.swift:45-94`. Each swatch uses `Color(light:dark:)` — change the dark variant to lift; iOS counterpart is `AppTheme.swift:114-160`.")
    }

    private func colorSwatch(name: String, value: String, source: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous)
                .fill(color)
                .frame(height: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous)
                        .stroke(MacTheme.cardBorder, lineWidth: 0.5)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(MacTheme.textPrimary)
                Text(value)
                    .font(MacTheme.metaFont())
                    .foregroundStyle(MacTheme.textSecondary)
                Text(source)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(MacTheme.mutedText)
            }
        }
        .padding(MacTheme.spacing12)
        .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Typography

    @ViewBuilder
    private var typographySection: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing12) {
            typeRow(name: "greetingFont", description: "22pt semibold — page-level greeting", source: "MacTheme.swift:196", sample: "Good morning, Ludvig") {
                MacTheme.greetingFont()
            }
            typeRow(name: "dateFont", description: "13pt medium — date subtitle", source: "MacTheme.swift:201", sample: "Wednesday, May 21") {
                MacTheme.dateFont()
            }
            typeRow(name: "sectionHeaderFont", description: "12pt semibold — section labels", source: "MacTheme.swift:206", sample: "INBOX") {
                MacTheme.sectionHeaderFont()
            }
            typeRow(name: "settingsSectionHeaderFont", description: "13pt semibold — Settings section labels", source: "MacTheme.swift:211", sample: "Connected Services") {
                MacTheme.settingsSectionHeaderFont()
            }
            typeRow(name: "cardTitleFont", description: "13pt medium — primary card title", source: "MacTheme.swift:216", sample: "Quarterly Review with Sam") {
                MacTheme.cardTitleFont()
            }
            typeRow(name: "cardSubtitleFont", description: "12pt regular — secondary content", source: "MacTheme.swift:221", sample: "2:00 PM · 30 min") {
                MacTheme.cardSubtitleFont()
            }
            typeRow(name: "metaFont", description: "11pt medium — counts + timestamps", source: "MacTheme.swift:226", sample: "12m ago") {
                MacTheme.metaFont()
            }
        }
        howToChange(text: "Edit `MacTheme.swift:194-228`. Functions return `Font.system(...)` — change weight/size in place. Avoid `.title`/`.body` shortcuts so values stay explicit.")
    }

    private func typeRow(name: String, description: String, source: String, sample: String, font: () -> Font) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sample)
                .font(font())
                .foregroundStyle(MacTheme.textPrimary)
            HStack(spacing: 10) {
                Text(name)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(MacTheme.textSecondary)
                Text(description)
                    .font(MacTheme.metaFont())
                    .foregroundStyle(MacTheme.mutedText)
                Spacer()
                Text(source)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(MacTheme.mutedText)
            }
        }
        .padding(MacTheme.spacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Radius

    @ViewBuilder
    private var radiusSection: some View {
        let chips: [(String, CGFloat, String)] = [
            ("pillRadius", MacTheme.pillRadius, "MacTheme.swift:41"),
            ("compactRadius", MacTheme.compactRadius, "MacTheme.swift:39"),
            ("buttonRadius", MacTheme.buttonRadius, "MacTheme.swift:43"),
            ("rowRadius", MacTheme.rowRadius, "MacTheme.swift:37"),
            ("cardRadius", MacTheme.cardRadius, "MacTheme.swift:35"),
            ("calendarEventRadius", MacTheme.calendarEventRadius, "MacTheme.swift:138")
        ]
        VStack(alignment: .leading, spacing: MacTheme.spacing12) {
            ForEach(chips, id: \.0) { item in
                HStack(spacing: MacTheme.spacing16) {
                    RoundedRectangle(cornerRadius: item.1, style: .continuous)
                        .fill(MacTheme.surfaceHover)
                        .frame(width: 90, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: item.1, style: .continuous)
                                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.0)
                            .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(MacTheme.textPrimary)
                        Text("\(Int(item.1))pt")
                            .font(MacTheme.metaFont())
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                    Spacer()
                    Text(item.2)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(MacTheme.mutedText)
                }
                .padding(MacTheme.spacing12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                        .stroke(MacTheme.cardBorder, lineWidth: 0.5)
                )
            }
        }
        howToChange(text: "Edit `MacTheme.swift:32-43`. Six-tier scale aligned with iOS `AppTheme.Radius` and web `--radius-*`. New radius? Add a `static let` and use it from your view.")
    }

    // MARK: - Spacing

    @ViewBuilder
    private var spacingSection: some View {
        let stops: [(String, CGFloat)] = [
            ("spacing4", MacTheme.spacing4),
            ("spacing6", MacTheme.spacing6),
            ("spacing8", MacTheme.spacing8),
            ("spacing12", MacTheme.spacing12),
            ("spacing16", MacTheme.spacing16),
            ("spacing20", MacTheme.spacing20),
            ("spacing24", MacTheme.spacing24),
            ("spacing28", MacTheme.spacing28),
            ("spacing32", MacTheme.spacing32)
        ]
        VStack(alignment: .leading, spacing: 10) {
            ForEach(stops, id: \.0) { stop in
                HStack(spacing: MacTheme.spacing16) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(MacTheme.surfaceHover)
                        .frame(width: stop.1, height: 18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
                        )
                    Text(stop.0)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(MacTheme.textPrimary)
                    Text("\(Int(stop.1))pt")
                        .font(MacTheme.metaFont())
                        .foregroundStyle(MacTheme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, MacTheme.spacing12)
                .padding(.vertical, MacTheme.spacing8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                        .stroke(MacTheme.cardBorder, lineWidth: 0.5)
                )
            }
        }
        howToChange(text: "Edit `MacTheme.swift:11-19`. 4/8pt grid — new value? Add a `static let spacingN: CGFloat = N` constant. iOS uses identical values in `AppTheme.Metrics`.")
    }

    // MARK: - Accent palette

    @ViewBuilder
    private var accentSection: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing16) {
            HStack(spacing: MacTheme.spacing16) {
                ForEach(MacTheme.accentColorKeys, id: \.self) { key in
                    VStack(spacing: 6) {
                        Circle()
                            .fill(MacTheme.accentColor(for: key))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Circle().stroke(MacTheme.cardBorder, lineWidth: 0.5)
                            )
                        Text(key.capitalized)
                            .font(MacTheme.metaFont())
                            .foregroundStyle(MacTheme.textPrimary)
                    }
                }
                Spacer()
            }
            .padding(MacTheme.spacing16)
            .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
        }
        howToChange(text: "Edit `MacTheme.swift:97-125`. Six-color palette mirrored on iOS (`AppTheme.Accents`) and web (`ACCENT_COLORS`). Adding a key? Update `accentColorKeys` + `accentColor(for:)` + the iOS + web counterparts.")
    }

    // MARK: - Components

    @ViewBuilder
    private var componentsSection: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing16) {
            componentRow(title: "MacInlineRefreshBadge", description: "Spinner-only badge with `badgeSurface` background.") {
                MacInlineRefreshBadge(label: "Syncing")
            }
            componentRow(title: "Button with .inFlight(true)", description: "Async control modifier — fades + overlays mini spinner.") {
                Button("Refreshing…") {}
                    .buttonStyle(.bordered)
                    .inFlight(true)
            }
            componentRow(title: "Sample card", description: "Uses `surfaceCard` + `cardBorder` + `cardRadius`.") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quarterly Review")
                        .font(MacTheme.cardTitleFont())
                        .foregroundStyle(MacTheme.textPrimary)
                    Text("Wednesday · 2:00 PM with Sam, Mira, and 3 others")
                        .font(MacTheme.cardSubtitleFont())
                        .foregroundStyle(MacTheme.textSecondary)
                }
                .padding(MacTheme.spacing16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.rowRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MacTheme.rowRadius, style: .continuous)
                        .stroke(MacTheme.cardBorder, lineWidth: 0.5)
                )
            }
            componentRow(title: "Sample row with hover state", description: "Hover this row to see `surfaceHover` apply.") {
                HoverableRowSample()
            }
        }
        howToChange(text: "Components are composed from tokens — there is no central component file. Search a component name (e.g. `MacInlineRefreshBadge`) to find its implementation. Add new shared atoms here when you spot the third copy.")
    }

    private func componentRow<Content: View>(title: String, description: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(MacTheme.textPrimary)
                Text(description)
                    .font(MacTheme.metaFont())
                    .foregroundStyle(MacTheme.textSecondary)
            }
            content()
                .padding(.top, 4)
        }
        .padding(MacTheme.spacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Motion

    @ViewBuilder
    private var motionSection: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing16) {
            MotionDemoBlock(
                title: "Motion.fast",
                description: "150ms easeOut — hover, fades, micro-feedback.",
                source: "MacTheme.swift:243",
                animation: MacTheme.Motion.fast
            )
            MotionDemoBlock(
                title: "Motion.base",
                description: "250ms snappy — dropdowns, sheets, panel toggles.",
                source: "MacTheme.swift:245",
                animation: MacTheme.Motion.base
            )
            MotionDemoBlock(
                title: "Motion.slow",
                description: "350ms snappy — onboarding steps, major transitions.",
                source: "MacTheme.swift:247",
                animation: MacTheme.Motion.slow
            )
        }
        howToChange(text: "Edit `MacTheme.swift:238-251`. Cross-platform parity with iOS `AppTheme.Motion` and web `--motion-duration-*`. Inline `.snappy(duration:)` / `.easeOut(duration:)` in components is a smell — always prefer `MacTheme.Motion.X`.")
    }

    // MARK: - "How to change" callout

    private func howToChange(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MacTheme.mutedText)
            Text(text)
                .font(MacTheme.metaFont())
                .foregroundStyle(MacTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MacTheme.spacing12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacTheme.contentBackground, in: RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - Motion demo block

private struct MotionDemoBlock: View {
    let title: String
    let description: String
    let source: String
    let animation: Animation

    @State private var shifted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(MacTheme.textPrimary)
                Text(description)
                    .font(MacTheme.metaFont())
                    .foregroundStyle(MacTheme.textSecondary)
                Spacer()
                Text(source)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(MacTheme.mutedText)
            }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous)
                    .fill(MacTheme.surfaceHover)
                    .frame(height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous)
                            .stroke(MacTheme.cardBorder, lineWidth: 0.5)
                    )
                Circle()
                    .fill(MacTheme.accent)
                    .frame(width: 28, height: 28)
                    .padding(.leading, 4)
                    .offset(x: shifted ? 240 : 0)
            }
            Button(shifted ? "Slide back" : "Slide right") {
                withAnimation(animation) { shifted.toggle() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(MacTheme.spacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - Hover row sample

private struct HoverableRowSample: View {
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(MacTheme.mutedAvatarFill)
                .frame(width: 28, height: 28)
                .overlay(
                    Text("S")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MacTheme.textPrimary)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Sam Rivera")
                    .font(MacTheme.cardTitleFont())
                    .foregroundStyle(MacTheme.textPrimary)
                Text("Re: invoice — quick clarification")
                    .font(MacTheme.cardSubtitleFont())
                    .foregroundStyle(MacTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("2:14 PM")
                .font(MacTheme.metaFont())
                .foregroundStyle(MacTheme.mutedText)
        }
        .padding(MacTheme.spacing12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (isHovered ? MacTheme.surfaceHover : MacTheme.contentBackground),
            in: RoundedRectangle(cornerRadius: MacTheme.rowRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.rowRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
        .onHover { isHovered = $0 }
        .animation(MacTheme.Motion.fast, value: isHovered)
    }
}

#Preview {
    MacDesignSystemView()
        .frame(width: 940, height: 700)
        .preferredColorScheme(.dark)
}
