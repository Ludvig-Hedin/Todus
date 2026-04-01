import SwiftUI

/// Custom floating tab bar — two glass pills side by side.
///
/// Layout (from Figma node 13-188):
///   [  home | tasks | email | calendar  ]  [ AI | + ]
///   ←──── nav tabs pill (fill) ──────────→  ←action→
///
/// Features:
/// • Sliding background plate that animates between active tabs
/// • Subtle scale press effect on tab buttons
/// • Glass/translucent material (iOS 26 Liquid Glass, fallback ultraThinMaterial)
/// • Drag gesture across tab bar to preview/swap tabs
struct CustomTabBar: View {
    @Binding var selectedTab: AppTab
    var hasUpcomingCalendarEvent: Bool = false
    var onAI: () -> Void
    var onCreate: () -> Void
    /// Called when the user taps the overflow (ellipsis) button to open the More sheet.
    var onMore: (() -> Void)? = nil

    /// Namespace for the matched geometry sliding indicator
    @Namespace private var tabIndicator

    // Icons: slightly smaller than Figma's 20px so the bigger button frame has breathing room.
    private let iconFont: Font = .system(size: 17, weight: .semibold)

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
        // Drag gesture across the tab bar to swipe between tabs
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    let tabs = AppTab.allCases
                    guard let currentIndex = tabs.firstIndex(of: selectedTab) else { return }
                    if value.translation.width < -30, currentIndex < tabs.count - 1 {
                        // Swipe left → next tab
                        withAnimation(.snappy(duration: 0.25)) {
                            selectedTab = tabs[currentIndex + 1]
                        }
                    } else if value.translation.width > 30, currentIndex > 0 {
                        // Swipe right → previous tab
                        withAnimation(.snappy(duration: 0.25)) {
                            selectedTab = tabs[currentIndex - 1]
                        }
                    }
                }
        )
        .glassTabPill()
    }

    @ViewBuilder
    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selectedTab == tab
        Button {
            withAnimation(.snappy(duration: 0.25)) { selectedTab = tab }
        } label: {
            Image(
                systemName: isSelected
                    ? tab.activeIcon
                    : tab.inactiveIcon(hasEvent: tab == .calendar && hasUpcomingCalendarEvent)
            )
            .font(iconFont)
            // Figma: active #0081FF, inactive rgba(60,60,67,0.65) = UIColor.secondaryLabel
            .foregroundStyle(isSelected ? Color(red: 0, green: 0x81/255.0, blue: 1) : Color(UIColor.secondaryLabel))
            // Bigger button frame (62×46) gives a more generous touch target.
            .frame(width: 62, height: 46)
            // Sliding indicator: matchedGeometryEffect moves this capsule between tabs
            .background {
                if isSelected {
                    activeIndicatorColor
                        .clipShape(Capsule())
                        .matchedGeometryEffect(id: "activeTab", in: tabIndicator)
                }
            }
            // Extra touch area — extends the tappable region 4pt beyond the visual frame
            .contentShape(Rectangle().inset(by: -4))
        }
        .buttonStyle(TabButtonStyle())
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Action Buttons Pill
    // ─────────────────────────────────────────────────────────────────────────

    private var actionButtonsPill: some View {
        HStack(spacing: 0) {
            // AI button — "sparkles" is the standard Apple AI icon
            Button { onAI() } label: {
                Image(systemName: "sparkles")
                    .font(iconFont)
                    .foregroundStyle(aiGradient)
                    .frame(width: 54, height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TabButtonStyle())

            // Create button — "+" in primary text color
            Button { onCreate() } label: {
                Image(systemName: "plus")
                    .font(iconFont)
                    .foregroundStyle(.primary)
                    .frame(width: 54, height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TabButtonStyle())

            // More button — overflow entry point (Docs, future items)
            Button { onMore?() } label: {
                Image(systemName: "ellipsis")
                    .font(iconFont)
                    .foregroundStyle(Color(UIColor.secondaryLabel))
                    .frame(width: 44, height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TabButtonStyle())
        }
        .padding(4) // Figma: 4px padding around action buttons
        .glassTabPill()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Colors
    // ─────────────────────────────────────────────────────────────────────────

    /// Active tab selection indicator.
    /// Figma: light #F0F0F4 with mix-blend plus-darker, dark #121212 with plus-lighter.
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
            startPoint: UnitPoint(x: 0.25, y: 0),
            endPoint: UnitPoint(x: 0.75, y: 1)
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Tab Button Style (subtle scale on press)
// ─────────────────────────────────────────────────────────────────────────────

/// Provides a delicate press animation: slight scale-down + opacity reduction.
private struct TabButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Glass pill modifier
// ─────────────────────────────────────────────────────────────────────────────

private extension View {
    /// Applies the correct glass material per OS version:
    /// • iOS 26+ → Liquid Glass capsule (system material, blur, specular highlights).
    /// • iOS 17/18 → ultraThinMaterial capsule + subtle drop shadow, more translucent.
    @ViewBuilder
    func glassTabPill() -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        }
    }
}
