import SwiftUI

/// Sheet presented from the burger (☰) button in the custom tab bar.
/// Lists pages not in the floating nav bar so they remain easily reachable.
struct MoreSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    let onNavigate: (AppTab) -> Void

    var body: some View {
        NavigationStack {
            List {
                // Pages section — mirrors what the Home "More" section shows
                Section("Pages") {
                    // Meetings — only shown here when not in the tab bar.
                    // Navigate to the meetings tab directly (same pattern as Calendar/Docs)
                    // to avoid nesting MeetingsListView inside this sheet's NavigationStack.
                    if !services.tabBarTabs.contains(.meetings) {
                        Button {
                            onNavigate(.meetings)
                            dismiss()
                        } label: {
                            Label("Meetings", systemImage: "video")
                                .foregroundStyle(.primary)
                        }
                    }

                    // Calendar — only shown here when not in the tab bar
                    if !services.tabBarTabs.contains(.calendar) {
                        // Calendar uses a custom UIKit container — navigate as a sheet tab instead
                        Button {
                            onNavigate(.calendar)
                            dismiss()
                        } label: {
                            Label("Calendar", systemImage: "calendar")
                                .foregroundStyle(.primary)
                        }
                    }

                    // Docs owns its own NavigationStack/Split view internally —
                    // pushing it inside this sheet's NavigationStack would
                    // double-nest and swallow internal pushes. Jump to the
                    // tab instead, matching how Calendar is handled above.
                    Button {
                        onNavigate(.docs)
                        dismiss()
                    } label: {
                        Label("Docs", systemImage: "doc.text")
                            .foregroundStyle(.primary)
                    }

                    // Legacy web shim — an internal fallback, not something to show
                    // every user next to the native Docs entry. Gate behind the
                    // developer allowlist (same mechanism as the Design System viewer).
                    if services.isDeveloperModeUIAvailable {
                        NavigationLink {
                            DocsWebView()
                                .navigationTitle("Docs (Web)")
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            Label("Docs (Web)", systemImage: "globe")
                        }
                    }
                }

                // Tab bar settings shortcut — Customize Tab Bar is a no-op while
                // MainTabView renders a fixed tab set (see BH-0613-6), so gate the
                // entry behind the developer allowlist until the dynamic bar returns.
                if services.isDeveloperModeUIAvailable {
                    Section {
                        NavigationLink {
                            TabBarCustomizationView()
                        } label: {
                            Label("Customize Tab Bar", systemImage: "square.bottomhalf.filled")
                        }
                    }
                }
            }
            // Match the destination pages this sheet links to (Meetings / Calendar /
            // Docs) instead of the system grouped background (pure black in dark mode).
            .scrollContentBackground(.hidden)
            .background(AppTheme.backgroundTop)
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
