import SwiftUI

/// Overflow surface for pages not currently in the tab bar. Used as the
/// content of the fixed "More" tab (pass `showsDone: false`) and reusable as a
/// sheet (default `showsDone: true`).
struct MoreSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    var showsDone: Bool = true
    let onNavigate: (AppTab) -> Void

    /// Content tabs the user hasn't placed in the bar — these are the pages
    /// that need this overflow to stay reachable.
    private var overflowTabs: [AppTab] {
        AppTab.contentTabs.filter { !services.tabBarTabs.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                // Pages not in the tab bar. All navigate by switching the tab
                // selection (some destinations — Docs' split view, Calendar's
                // UIKit container — own their navigation and must not be pushed
                // inside this stack).
                if !overflowTabs.isEmpty {
                    Section("Pages") {
                        ForEach(overflowTabs) { tab in
                            Button {
                                onNavigate(tab)
                                if showsDone { dismiss() }
                            } label: {
                                Label(tab.title, systemImage: tab.inactiveIcon())
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }

                Section {
                    NavigationLink {
                        TabBarCustomizationView()
                    } label: {
                        Label("Customize Tab Bar", systemImage: "square.bottomhalf.filled")
                    }
                } footer: {
                    Text("Pick up to 4 tabs for the bar. Everything else stays here.")
                }

                // Legacy web shim — an internal fallback, not something to show
                // every user next to the native Docs entry. Gate behind the
                // developer allowlist (same mechanism as the Design System viewer).
                if services.isDeveloperModeUIAvailable {
                    Section {
                        NavigationLink {
                            DocsWebView()
                                .navigationTitle("Docs (Web)")
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            Label("Docs (Web)", systemImage: "globe")
                        }
                    }
                }
            }
            // Match the destination pages this surface links to instead of the
            // system grouped background (pure black in dark mode).
            .scrollContentBackground(.hidden)
            .background(AppTheme.backgroundTop)
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsDone {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }
}
