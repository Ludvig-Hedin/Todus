import SwiftUI

/// Tab bar customization — lets users pick which tabs appear in the floating bar
/// and reorder them via drag handles.
///
/// Rules:
/// • Home is always first and cannot be removed (it surfaces non-tab pages).
/// • Min 2 tabs total, max 4 — the burger (☰) button is a fixed extra slot.
/// • Changes are saved to AppServices / UserDefaults on "Save".
struct TabBarCustomizationView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    // Local mutable copy — committed on "Save" (or on appear if opened from onboarding)
    @State private var activeTabs: [AppTab] = []
    @State private var editMode: EditMode = .active

    private var availableTabs: [AppTab] { AppTab.allCases.filter { $0 != .create && $0 != .ai } }

    var body: some View {
        List {
            activeSection
            availableSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.backgroundTop)
        .environment(\.editMode, $editMode)
        .navigationTitle("Tab Bar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
            }
        }
        .onAppear { activeTabs = services.tabBarTabs }
    }

    // MARK: - Active Tabs Section

    private var activeSection: some View {
        Section {
            ForEach(activeTabs) { tab in
                HStack(spacing: 14) {
                    tabIcon(tab, active: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tab.title)
                            .font(.system(size: 15, weight: .semibold))
                        Text(tab.description)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if tab.isRequired {
                        Text("Required")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.secondary.opacity(0.12), in: Capsule())
                    }
                }
                // Disable swipe-to-delete for required tabs
                .deleteDisabled(tab.isRequired)
            }
            .onDelete { indices in
                // Guard: don't delete required tabs; keep min 2
                let filtered = indices.filter { !activeTabs[$0].isRequired }
                let toRemove = IndexSet(filtered)
                guard activeTabs.count - toRemove.count >= 2 else { return }
                activeTabs.remove(atOffsets: toRemove)
            }
            .onMove { from, to in
                activeTabs.move(fromOffsets: from, toOffset: to)
                // Always keep home first after any move
                if let homeIndex = activeTabs.firstIndex(of: .home), homeIndex != 0 {
                    activeTabs.move(fromOffsets: IndexSet(integer: homeIndex), toOffset: 0)
                }
            }
        } header: {
            Text("In Tab Bar (\(activeTabs.count)/4)")
        } footer: {
            Text("Drag to reorder. Swipe left to remove. Home is always first.")
        }
    }

    // MARK: - Available (inactive) Tabs Section

    private var availableSection: some View {
        let inactive = availableTabs.filter { !activeTabs.contains($0) }
        return Group {
            if !inactive.isEmpty {
                Section("More Pages") {
                    ForEach(inactive) { tab in
                        HStack(spacing: 14) {
                            tabIcon(tab, active: false)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tab.title)
                                    .font(.system(size: 15, weight: .semibold))
                                Text(tab.description)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            // Add button — disabled when already at max 4 tabs
                            Button {
                                guard activeTabs.count < 4 else { return }
                                withAnimation(AppTheme.Motion.base) { activeTabs.append(tab) }
                            } label: {
                                Image(systemName: activeTabs.count < 4 ? "plus.circle.fill" : "plus.circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(activeTabs.count < 4 ? .primary : .secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(activeTabs.count >= 4)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func tabIcon(_ tab: AppTab, active: Bool) -> some View {
        Image(systemName: active ? tab.activeIcon : tab.inactiveIcon())
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(active ? .primary : .secondary)
            .frame(width: 32, height: 32)
            .background(
                (active ? Color.primary : Color.secondary).opacity(0.1),
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.inline, style: .continuous)
            )
    }

    private func save() {
        // Always guarantee home is first; clamp to max 4
        var result = activeTabs.filter { $0 != .home }
        result.insert(.home, at: 0)
        services.tabBarTabs = Array(result.prefix(4))
        dismiss()
    }
}

