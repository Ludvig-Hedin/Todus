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

    /// Tabs the user can add (excludes create/ai — not shown as “pages”; matches native `TabView` + AI FAB).
    private var availableTabs: [AppTab] {
        AppTab.allCases.filter { tab in
            !selectedTabs.contains(tab) && tab != .create && tab != .ai
        }
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundTop.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .center, spacing: 0) {
                    // ── Header ──────────────────────────────────────────────
                    VStack(spacing: 6) {
                        Text("Pick your main pages")
                            .font(.system(size: 22, weight: .bold))
                            .multilineTextAlignment(.center)

                        Text("Choose the pages you want close by first. You can change this later in Settings.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 20)

                    // ── Tab list ─────────────────────────────────────────────
                    VStack(spacing: 0) {
                        if !selectedTabs.isEmpty {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Main pages")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .textCase(.uppercase)
                                        .tracking(0.35)
                                    Spacer()
                                    Text("\(selectedTabs.count) / 4")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(selectedTabs.count >= 4 ? .primary : .secondary)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill((selectedTabs.count >= 4 ? Color.primary : Color.secondary).opacity(0.1))
                                        )
                                        .animation(.snappy(duration: 0.2), value: selectedTabs.count)
                                }
                                .padding(.horizontal, 4)
                                .padding(.top, 16)
                                .padding(.bottom, 6)

                                ForEach(selectedTabs) { tab in
                                    activeRow(tab)
                                }
                            }
                        }

                        if !availableTabs.isEmpty {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Other pages")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .textCase(.uppercase)
                                        .tracking(0.35)
                                    Spacer()
                                    if selectedTabs.count >= 4 {
                                        Text("Remove one to add more")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 4)
                                .padding(.top, 12)
                                .padding(.bottom, 6)

                                ForEach(availableTabs) { tab in
                                    inactiveRow(tab)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                    // ── Live tab bar preview (native order: tab₁ · tab₂ · + · tab₃ · tab₄) ──
                    VStack(spacing: 6) {
                        Text("Preview")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.35)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)

                        tabBarPreview
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                            .animation(.snappy(duration: 0.25), value: selectedTabs.map(\.rawValue))

                        Text("Bottom bar matches the app: Home, two tabs, +, then the rest. AI is the floating sparkles button above, not a tab.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 14)
                    .padding(.horizontal, 16)

                    // ── CTA ───────────────────────────────────────────────────
                    VStack(spacing: 8) {
                        Button { commit() } label: {
                            Text("Use this setup")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                        }
                        .buttonStyle(AppPrimaryButtonStyle())

                        Button("Skip for now") {
                            services.hasConfiguredTabBarPrompt = true
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)

                        Text("Choose a simple setup now. You can reorder or swap pages anytime later.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 16)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
            }
        }
        .onAppear { selectedTabs = services.tabBarTabs }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Active Row (in bar, draggable)
    // ─────────────────────────────────────────────────────────────────────────

    private func activeRow(_ tab: AppTab) -> some View {
        HStack(spacing: 8) {
            // Drag handle — visible cue that this row can be reordered
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 16)

            // Icon
            Image(systemName: tab.activeIcon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous))

            // Label
            VStack(alignment: .leading, spacing: 0) {
                Text(tab.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(tab.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Remove — locked for required tabs (home)
            if tab.isRequired {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
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
                        .font(.system(size: 18))
                        .foregroundStyle(.red.opacity(canRemove ? 0.75 : 0.3))
                }
                .buttonStyle(.plain)
                .disabled(!canRemove)
                .accessibilityLabel(canRemove ? "Remove \(tab.title) from tab bar" : "Keep at least two tabs in the tab bar")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                .stroke(Color.primary.opacity(0.2), lineWidth: 1)
        )
        .padding(.bottom, 4)
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

        return HStack(spacing: 8) {
            // Spacer to align with drag handle column
            Spacer().frame(width: 16)

            // Icon — muted when at limit
            Image(systemName: tab.inactiveIcon())
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(atMax ? .tertiary : .secondary)
                .frame(width: 28, height: 28)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous))

            VStack(alignment: .leading, spacing: 0) {
                Text(tab.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(atMax ? .secondary : .primary)
                Text(tab.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
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
                    .font(.system(size: 18))
                    .foregroundStyle(atMax ? Color.secondary.opacity(0.35) : Color.primary)
            }
            .buttonStyle(.plain)
            .disabled(atMax)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.surfacePrimary.opacity(0.5), in: RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
        .padding(.bottom, 4)
        .opacity(atMax ? 0.6 : 1)
        .animation(.easeInOut(duration: 0.15), value: atMax)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Tab Bar Preview
    // ─────────────────────────────────────────────────────────────────────────

    /// Order matches `MainTabView`’s `TabView`: `tab[0] · tab[1] · + · tab[2] · tab[3]`.
    /// (AI is a floating action button, not a tab; no custom burger bar.)
    private var tabBarPreview: some View {
        HStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { i in
                nativePreviewTabSlot(index: i)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(UIColor.separator).opacity(0.22), lineWidth: 0.5)
        )
    }

    private func tabInPreviewBar(at index: Int) -> AppTab? {
        switch index {
        case 0: return selectedTabs.indices.contains(0) ? selectedTabs[0] : nil
        case 1: return selectedTabs.indices.contains(1) ? selectedTabs[1] : nil
        case 2: return .create
        case 3: return selectedTabs.indices.contains(2) ? selectedTabs[2] : nil
        case 4: return selectedTabs.indices.contains(3) ? selectedTabs[3] : nil
        default: return nil
        }
    }

    @ViewBuilder
    private func nativePreviewTabSlot(index: Int) -> some View {
        let secondary = Color(UIColor.secondaryLabel)
        let accent = Color(UIColor.systemBlue)

        if let tab = tabInPreviewBar(at: index) {
            let isSelected = (index == 0) && (tab == .home)
            if tab == .create {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            } else {
                Image(systemName: isSelected ? tab.activeIcon : tab.inactiveIcon())
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? accent : secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            }
        } else {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 0.5, dash: [3, 2]))
                .foregroundStyle(secondary.opacity(0.2))
                .frame(maxWidth: .infinity)
                .frame(height: 20)
                .padding(.vertical, 6)
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
