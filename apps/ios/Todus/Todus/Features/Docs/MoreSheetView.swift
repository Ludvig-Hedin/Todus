import SwiftUI

/// Sheet presented from the "More" (ellipsis) button in the custom tab bar.
/// Currently houses Docs; designed as an extension point for future overflow items.
struct MoreSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services

    var body: some View {
        NavigationStack {
            List {
                // Docs — opens the web Docs page in a WKWebView
                NavigationLink {
                    DocsWebView()
                        .navigationTitle("Docs")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label("Docs", systemImage: "doc.text")
                }
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Explicit Done button — sheet can also be dismissed by swipe
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
