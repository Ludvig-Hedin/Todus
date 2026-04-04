import SwiftUI

/// Onboarding step — lets users choose and order their tab bar before entering the app.
///
/// UX goals:
/// • Framing: "What do you use most?" — personal, not technical.
/// • Drag handles make reordering obvious.
/// • Live tab bar preview shows exactly what the bar will look like as they edit.
/// • "X / 4" count badge is always visible — burger is a fixed extra slot.
struct TabBarOnboardingView: View {
    @Environment(AppServices.self) private var services

    /// Working copy — ordered list of tabs currently in the bar.
    @State private var selectedTabs: [AppTab] = AppTab.defaultNavTabs
    /// Tracks which tab is being dragged (for the drag-to-reorder animation).
    @State private var draggingTab: AppTab? = nil

    /// All tabs that aren't in selectedTabs yet.
    private var availableTabs: [AppTab] {
        AppTab.allCases.filter { !selectedTabs.contains($0) }
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundTop.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header ──────────────────────────────────────────────
                VStack(spacing: 10) {
                    Text("Pick your main pages")
                        .font(.system(size: 30, weight: .bold))
                        .multilineTextAlignment(.center)
                        .padding(.top, 56)

                    Text("Choose the pages you want close by first. You can change this later in Settings.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                .padding(.horizontal, 28)

                Spacer(minLength: 28)

                // ── Tab list ─────────────────────────────────────────────
                VStack(spacing: 0) {
                    // Active tabs — ordered, draggable
                    if !selectedTabs.isEmpty {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Main pages")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .tracking(0.4)
                                Spacer()
                                // Live counter — turns blue at 4 (limit reached)
                                Text("\(selectedTabs.count) / 4")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(selectedTabs.count >= 4 ? .blue : .secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill((selectedTabs.count >= 4 ? Color.blue : Color.secondary).opacity(0.1))
                                    )
                                    .animation(.snappy(duration: 0.2), value: selectedTabs.count)
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 10)

                            ForEach(selectedTabs) { tab in
                                activeRow(tab)
                            }
                        }
                    }

                    // Available tabs — not in bar yet
                    if !availableTabs.isEmpty {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Other pages")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .tracking(0.4)
                                Spacer()
                                if selectedTabs.count >= 4 {
                                    Text("Remove one to add more")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 20)
                            .padding(.bottom, 10)

                            ForEach(availableTabs) { tab in
                                inactiveRow(tab)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 28)

                // ── Live tab bar preview ──────────────────────────────────
                VStack(spacing: 10) {
                    Text("Preview")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.4)

                    tabBarPreview
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        .animation(.snappy(duration: 0.25), value: selectedTabs.map(\.rawValue))

                    Text("Home stays pinned so the app always has a clear starting point.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 28)

                // ── CTA ───────────────────────────────────────────────────
                VStack(spacing: 12) {
                    Button { commit() } label: {
                        Text("Use this setup")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button("Skip for now") {
                        services.hasConfiguredTabBarPrompt = true
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)

                    Text("Choose a simple setup now. You can reorder or swap pages anytime later.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        .onAppear { selectedTabs = services.tabBarTabs }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Active Row (in bar, draggable)
    // ─────────────────────────────────────────────────────────────────────────

    private func activeRow(_ tab: AppTab) -> some View {
        HStack(spacing: 12) {
            // Drag handle — visible cue that this row can be reordered
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 20)

            // Icon
            Image(systemName: tab.activeIcon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 32, height: 32)
                .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            // Label
            VStack(alignment: .leading, spacing: 1) {
                Text(tab.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(tab.description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Remove — locked for required tabs (home)
            if tab.isRequired {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            } else {
                let canRemove = selectedTabs.count > 2
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        guard canRemove else { return }
                        selectedTabs.removeAll { $0 == tab }
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.red.opacity(canRemove ? 0.75 : 0.3))
                }
                .buttonStyle(.plain)
                .disabled(!canRemove)
                .accessibilityLabel(canRemove ? "Remove \(tab.title) from tab bar" : "Keep at least two tabs in the tab bar")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
        .padding(.bottom, 6)
        // Drag-to-reorder: long press then drag vertically
        .onDrag {
            draggingTab = tab
            return NSItemProvider(object: tab.rawValue as NSString)
        }
        .onDrop(of: [.text], delegate: TabDropDelegate(
            tab: tab,
            tabs: $selectedTabs,
            draggingTab: $draggingTab
        ))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Inactive Row (not in bar, can add)
    // ─────────────────────────────────────────────────────────────────────────

    private func inactiveRow(_ tab: AppTab) -> some View {
        let atMax = selectedTabs.count >= 4

        return HStack(spacing: 12) {
            // Spacer to align with drag handle column
            Spacer().frame(width: 20)

            // Icon — muted when at limit
            Image(systemName: tab.inactiveIcon())
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(atMax ? .tertiary : .secondary)
                .frame(width: 32, height: 32)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(tab.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(atMax ? .secondary : .primary)
                Text(tab.description)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Add button
            Button {
                guard !atMax else { return }
                withAnimation(.snappy(duration: 0.22)) {
                    selectedTabs.append(tab)
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(atMax ? Color.secondary.opacity(0.35) : Color.blue)
            }
            .buttonStyle(.plain)
            .disabled(atMax)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppTheme.surfacePrimary.opacity(0.5), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
        .padding(.bottom, 6)
        .opacity(atMax ? 0.6 : 1)
        .animation(.easeInOut(duration: 0.15), value: atMax)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Tab Bar Preview
    // ─────────────────────────────────────────────────────────────────────────

    /// Renders a scaled-down but faithful replica of the actual CustomTabBar glass pill,
    /// so the user sees exactly what they'll get — icons in order.
    /// Mirrors the real CustomTabBar layout:
    /// Left pill = burger + nav tabs (+ ghost slots) | Right pill = AI + create
    private var tabBarPreview: some View {
        HStack(spacing: 8) {
            // Nav tabs pill — burger first, then user tabs, then ghost slots
            HStack(spacing: 0) {
                // Burger button (always present, always first)
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(UIColor.secondaryLabel))
                    .frame(width: 38, height: 38)

                // Thin separator
                Rectangle()
                    .fill(Color(UIColor.separator).opacity(0.25))
                    .frame(width: 1, height: 18)

                ForEach(selectedTabs) { tab in
                    previewTabIcon(tab)
                }
                // Ghost slots: max 4 configurable tabs
                ForEach(0..<max(0, 4 - selectedTabs.count), id: \.self) { _ in
                    previewGhostSlot
                }
            }
            .padding(3)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)

            // Action pill — AI + create (no ellipsis)
            HStack(spacing: 0) {
                previewActionIcon("sparkles", gradient: true)
                previewActionIcon("plus", gradient: false)
            }
            .padding(3)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
        }
        .scaleEffect(0.85, anchor: .bottom)
        .frame(height: 54)
    }

    @ViewBuilder
    private func previewTabIcon(_ tab: AppTab) -> some View {
        // First tab (home) shown as active to make the indicator visible
        let isFirst = selectedTabs.first == tab
        Image(systemName: isFirst ? tab.activeIcon : tab.inactiveIcon())
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isFirst ? Color(red: 0, green: 0x81/255.0, blue: 1) : Color(UIColor.secondaryLabel))
            .frame(width: 52, height: 40)
            .background {
                if isFirst {
                    Color(UIColor { t in
                        t.userInterfaceStyle == .dark
                            ? UIColor(white: 0.12, alpha: 1)
                            : UIColor(white: 0.94, alpha: 1)
                    })
                    .clipShape(Capsule())
                }
            }
    }

    /// Empty slot shown when fewer than 4 tabs selected — dashed outline hint
    private var previewGhostSlot: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
            .foregroundStyle(.secondary.opacity(0.2))
            .frame(width: 52, height: 40)
    }

    private func previewActionIcon(_ icon: String, gradient: Bool) -> some View {
        let size: CGFloat = icon == "ellipsis" ? 36 : 44
        return Group {
            if gradient {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            stops: [
                                .init(color: Color(red: 0, green: 0xAA/255.0, blue: 0xF5/255.0), location: 0.087),
                                .init(color: Color(red: 0xEF/255.0, green: 0, blue: 0xC2/255.0), location: 0.269),
                                .init(color: Color(red: 1, green: 0, blue: 0x38/255.0), location: 0.580),
                                .init(color: Color(red: 0xF9/255.0, green: 0x9F/255.0, blue: 0), location: 0.913),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: 40)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(UIColor.secondaryLabel))
                    .frame(width: size, height: 40)
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Commit
    // ─────────────────────────────────────────────────────────────────────────

    private func commit() {
        // Always ensure home is first; clamp to max 4
        var result = selectedTabs.filter { $0 != .home }
        result.insert(.home, at: 0)
        services.tabBarTabs = Array(result.prefix(4))
        services.hasConfiguredTabBarPrompt = true
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Drag-to-reorder delegate
// ─────────────────────────────────────────────────────────────────────────────

/// Handles the drag-to-reorder gesture for the active tab list.
/// Home is always kept at index 0 regardless of where the user drops it.
private struct TabDropDelegate: DropDelegate {
    let tab: AppTab
    @Binding var tabs: [AppTab]
    @Binding var draggingTab: AppTab?

    func performDrop(info: DropInfo) -> Bool {
        draggingTab = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragging = draggingTab, dragging != tab else { return }
        guard let fromIndex = tabs.firstIndex(of: dragging),
              let toIndex   = tabs.firstIndex(of: tab) else { return }

        withAnimation(.snappy(duration: 0.2)) {
            tabs.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
            // Pin home to index 0 after every move
            if let homeIndex = tabs.firstIndex(of: .home), homeIndex != 0 {
                tabs.move(fromOffsets: IndexSet(integer: homeIndex), toOffset: 0)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
