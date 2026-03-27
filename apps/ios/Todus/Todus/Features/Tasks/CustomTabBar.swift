import SwiftUI

/// Custom floating tab bar — two glass pills side by side.
///
/// Layout (from Figma node 13-188):
///   [  home | tasks | email | calendar  ]  [ AI | + ]
///   ←──── nav tabs pill (fill) ──────────→  ←action→
///
/// • iOS 26: Liquid Glass via `.glassEffect(.regular, in: Capsule())`.
/// • iOS 17/18: `.ultraThinMaterial` capsule + drop shadow.
/// • Dimensions, colors, and font specs sourced from Figma design system.
struct CustomTabBar: View {
    @Binding var selectedTab: AppTab
    var hasUpcomingCalendarEvent: Bool = false
    var onAI: () -> Void
    var onCreate: () -> Void

    // Figma spec: SF Pro Semibold (weight 590), 20px
    // Note: .tracking() only works on Text views, not Image, so it's not applied to icons.
    private let iconFont: Font = .system(size: 20, weight: .semibold)

    var body: some View {
        HStack(spacing: 10) {
            navTabsPill
            actionButtonsPill
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Nav Tabs Pill
    // ─────────────────────────────────────────────────────────────────────────

    private var navTabsPill: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(4) // Figma: 4px padding around the tab buttons
        .glassTabPill()
    }

    @ViewBuilder
    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selectedTab == tab
        Button {
            withAnimation(.snappy(duration: 0.18)) { selectedTab = tab }
        } label: {
            Image(
                systemName: isSelected
                    ? tab.activeIcon
                    : tab.inactiveIcon(hasEvent: tab == .calendar && hasUpcomingCalendarEvent)
            )
            .font(iconFont)
            // Figma: active #0081FF, inactive rgba(60,60,67,0.65) = UIColor.secondaryLabel
            .foregroundStyle(isSelected ? Color(red: 0, green: 0x81/255.0, blue: 1) : Color(UIColor.secondaryLabel))
            // Figma: each button 54×40 (px=12 py=8, icon area 30×24)
            .frame(width: 54, height: 40)
            // Active indicator: fully round capsule, Figma light #F0F0F4 / dark #121212
            .background(
                isSelected ? activeIndicatorColor : Color.clear,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Action Buttons Pill
    // ─────────────────────────────────────────────────────────────────────────

    private var actionButtonsPill: some View {
        HStack(spacing: 0) {
            // AI button — "sparkles" is the standard Apple AI icon (used in Apple Intelligence,
            // Siri suggestions, etc.) — more recognizable than the previous "lasso.badge.sparkles".
            Button { onAI() } label: {
                Image(systemName: "sparkles")
                    .font(iconFont)

                    .foregroundStyle(aiGradient)
                    // Figma: w=50, pl=12 pr=8 py=8
                    .frame(width: 50, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Create button — "+" in primary text color (user requested: not muted gray)
            Button { onCreate() } label: {
                Image(systemName: "plus")
                    .font(iconFont)

                    .foregroundStyle(.primary)
                    // Figma: w=50, pl=8 pr=12 py=8
                    .frame(width: 50, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(4) // Figma: 4px padding around action buttons
        .glassTabPill()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Colors
    // ─────────────────────────────────────────────────────────────────────────

    /// Active tab selection indicator.
    /// Figma: light #F0F0F4 with mix-blend plus-darker, dark #121212 with plus-lighter.
    /// SwiftUI doesn't support mix-blend-mode, so we use the exact colors directly
    /// which produce the correct visual result on the glass material.
    private var activeIndicatorColor: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0x12/255.0, green: 0x12/255.0, blue: 0x12/255.0, alpha: 1)
                : UIColor(red: 0xF0/255.0, green: 0xF0/255.0, blue: 0xF4/255.0, alpha: 1)
        })
    }

    /// Figma: linear-gradient(151deg, #00AAF5 8.66%, #EF00C2 26.94%, #FF0038 57.95%, #F99F00 91.34%)
    private var aiGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0, green: 0xAA/255.0, blue: 0xF5/255.0), location: 0.087),
                .init(color: Color(red: 0xEF/255.0, green: 0, blue: 0xC2/255.0), location: 0.269),
                .init(color: Color(red: 1, green: 0, blue: 0x38/255.0), location: 0.580),
                .init(color: Color(red: 0xF9/255.0, green: 0x9F/255.0, blue: 0), location: 0.913),
            ],
            // 151° → approx top-left to bottom-right, offset
            startPoint: UnitPoint(x: 0.25, y: 0),
            endPoint: UnitPoint(x: 0.75, y: 1)
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Glass pill modifier
// ─────────────────────────────────────────────────────────────────────────────

private extension View {
    /// Applies the correct glass material per OS version:
    /// • iOS 26+ → Liquid Glass capsule (system material, blur, specular highlights).
    /// • iOS 17/18 → ultraThinMaterial capsule + subtle drop shadow.
    @ViewBuilder
    func glassTabPill() -> some View {
        if #available(iOS 26, *) {
            // .regular gives the standard system glass — same material as the system tab bar.
            // Capsule shape matches Figma rounded-[345px] ≈ fully rounded.
            self.glassEffect(.regular, in: Capsule())
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 3)
        }
    }
}
