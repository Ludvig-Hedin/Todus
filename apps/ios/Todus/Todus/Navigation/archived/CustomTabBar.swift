import SwiftUI

/// Custom floating tab bar — two glass pills side by side.
///
/// Layout:
///   [  home | tasks | email | calendar  ]  [ AI | + ]
///   ←──── nav tabs pill (fill) ──────────→  ←action→
///
/// Uses Liquid Glass material on iOS 26, ultraThinMaterial on iOS 17/18.
/// Dimensions and colors sourced from Figma spec (node 11-1402).
struct CustomTabBar: View {
    @Binding var selectedTab: AppTab
    var hasUpcomingCalendarEvent: Bool = false
    var onAI: () -> Void
    var onCreate: () -> Void

    /// Figma spec: font-weight 590 = SF Pro Semibold (closest SwiftUI weight).
    /// 1.25rem = 20pt, letter-spacing -0.1pt.
    private let tabIconFont: Font = .system(size: 20, weight: .semibold)

    var body: some View {
        HStack(spacing: 10) {
            navTabsPill
            actionButtonsPill
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Nav Tabs Pill
    // ─────────────────────────────────────────────────────────────────────────

    /// 4px padding around the tab buttons inside the pill.
    private var navTabsPill: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(4) // 4px padding around all tab buttons
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
            .font(tabIconFont)
            .tracking(-0.1) // letter-spacing: -0.00625rem ≈ -0.1pt
            .foregroundStyle(isSelected ? AppTheme.accentBlue : Color.secondary)
            // Figma spec: each tab button 45×44, padding 0.5rem 0.75rem (8pt vertical, 12pt horizontal)
            .frame(width: 45, height: 44)
            // Active indicator: fully round, platform-adaptive muted background
            // Light: #F0F0F4 with plus-darker blend, Dark: #121212 with plus-lighter blend
            .background(
                isSelected ? activeIndicatorColor : Color.clear,
                in: Circle()
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Figma spec: light #F0F0F4 + plus-darker, dark #121212 + plus-lighter.
    /// SwiftUI doesn't support mix-blend-mode directly, so we use the exact colors
    /// which produce the correct visual result on glass material backgrounds.
    private var activeIndicatorColor: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0x12/255, green: 0x12/255, blue: 0x12/255, alpha: 1)
                : UIColor(red: 0xF0/255, green: 0xF0/255, blue: 0xF4/255, alpha: 1)
        })
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Action Buttons Pill
    // ─────────────────────────────────────────────────────────────────────────

    private var actionButtonsPill: some View {
        HStack(spacing: 0) {
            // AI button — gradient text (matches Figma linear-gradient 151deg)
            // "lasso.badge.sparkles" is valid SF Symbol available from iOS 17+
            Button { onAI() } label: {
                Image(systemName: "lasso.badge.sparkles")
                    .font(tabIconFont)
                    // Figma: gradient text fill — blue → pink → red → orange
                    .foregroundStyle(aiGradient)
                    // Figma: padding 0.5rem 0.5rem 0.5rem 0.75rem (8 8 8 12)
                    .padding(.init(top: 8, leading: 12, bottom: 8, trailing: 8))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("AI Assistant")

            // Create button — "+" in primary text color (not muted)
            Button { onCreate() } label: {
                Image(systemName: "plus")
                    .font(tabIconFont)
                    .foregroundStyle(.primary)
                    // Figma: padding 0.5rem 0.75rem 0.5rem 0.5rem (8 12 8 8)
                    .padding(.init(top: 8, leading: 8, bottom: 8, trailing: 12))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create new item")
        }
        .glassTabPill()
    }

    /// Figma spec: linear-gradient(151deg, #00AAF5 8.66%, #EF00C2 26.94%, #FF0038 57.95%, #F99F00 91.34%)
    private var aiGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0x00/255, green: 0xAA/255, blue: 0xF5/255), // #00AAF5
                Color(red: 0xEF/255, green: 0x00/255, blue: 0xC2/255), // #EF00C2
                Color(red: 0xFF/255, green: 0x00/255, blue: 0x38/255), // #FF0038
                Color(red: 0xF9/255, green: 0x9F/255, blue: 0x00/255), // #F99F00
            ],
            startPoint: UnitPoint(x: 0.3, y: 0),   // ~151deg approximation
            endPoint: UnitPoint(x: 0.7, y: 1)
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Glass pill modifier
// ─────────────────────────────────────────────────────────────────────────────

private extension View {
    /// iOS 26+ → Liquid Glass capsule.
    /// iOS 17/18 → ultraThinMaterial capsule + subtle drop shadow.
    @ViewBuilder
    func glassTabPill() -> some View {
        if #available(iOS 26, *) {
            // .glassEffect requires the material parameter — .regular gives standard system glass
            self.glassEffect(.regular, in: Capsule())
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 3)
        }
    }
}
