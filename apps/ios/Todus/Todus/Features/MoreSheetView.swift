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

                    NavigationLink {
                        DocsWebView()
                            .navigationTitle("Docs")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("Docs", systemImage: "doc.text")
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
