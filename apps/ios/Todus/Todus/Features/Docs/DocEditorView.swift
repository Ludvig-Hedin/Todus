import SwiftUI

/// Thin wrapper around `DocsBrowserView` that adds a native nav bar (title,
/// star toggle, share). The actual editor stays web-backed for now — the goal
/// here is to make the native shell feel native while the rich-text surface
/// catches up with the macOS one.
struct DocEditorView: View {
    @Environment(AppServices.self) private var services

    let doc: DocRecordDTO

    @State private var isStarred: Bool
    @State private var showShare = false
    @State private var errorMessage: String?

    init(doc: DocRecordDTO) {
        self.doc = doc
        _isStarred = State(initialValue: doc.isStarred)
    }

    var body: some View {
        DocsBrowserView(docId: doc.id)
            .navigationTitle(doc.title.isEmpty ? "Untitled" : doc.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            Task { await toggleStar() }
                        } label: {
                            Label(
                                isStarred ? "Unstar" : "Star",
                                systemImage: isStarred ? "star.slash" : "star"
                            )
                        }
                        Button {
                            showShare = true
                        } label: {
                            Label("Share link", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showShare) {
                if let url = shareURL {
                    ShareSheet(items: [url])
                        .presentationDetents([.medium])
                }
            }
            .alert(
                "Couldn't update doc",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                ),
                actions: {
                    Button("OK", role: .cancel) { errorMessage = nil }
                },
                message: {
                    Text(errorMessage ?? "")
                }
            )
    }

    private var shareURL: URL? {
        services.configuration.effectiveAppURL
            .appendingPathComponent("mail/docs")
            .appendingPathComponent(doc.id)
    }

    private func toggleStar() async {
        let newValue = !isStarred
        isStarred = newValue
        do {
            _ = try await services.docsService.setStarred(id: doc.id, isStarred: newValue)
        } catch {
            // Roll the optimistic UI back if the server rejects the mutation.
            isStarred = !newValue
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Minimal UIActivityViewController wrapper for sharing a doc URL.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
