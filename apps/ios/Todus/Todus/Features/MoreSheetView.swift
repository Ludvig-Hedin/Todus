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
                    // Meetings — only shown here when not in the tab bar
                    if !services.tabBarTabs.contains(.meetings) {
                        NavigationLink {
                            MeetingsListView()
                        } label: {
                            Label("Meetings", systemImage: "video")
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

                    // Legacy web shim — kept as an opt-in fallback so users who
                    // hit issues with the native shell can still get to docs.
                    NavigationLink {
                        DocsWebView()
                            .navigationTitle("Docs (Web)")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("Docs (Web)", systemImage: "globe")
                    }
                }

                // Tab bar settings shortcut
                Section {
                    NavigationLink {
                        TabBarCustomizationView()
                    } label: {
                        Label("Customize Tab Bar", systemImage: "square.bottomhalf.filled")
                    }
                }
            }
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
