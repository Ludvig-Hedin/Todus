import SwiftUI

/// Native iOS / iPadOS shell for Docs. Renders workspaces and their nested docs
/// in a sidebar, tapping a doc pushes `DocEditorView` (which wraps the existing
/// `DocsBrowserView` so the actual editor stays web-backed for now).
///
/// iPad: `NavigationSplitView` so the sidebar stays visible alongside the editor.
/// iPhone: `NavigationStack` with a list that pushes the editor.
struct DocsListView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var selectedDocID: String?
    @State private var pendingCreate = false
    @State private var renamingDoc: DocRecordDTO?
    @State private var renameText: String = ""
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    sidebar
                        .navigationTitle("Docs")
                        .navigationDestination(for: String.self) { id in
                            destination(for: id)
                        }
                } detail: {
                    detail
                }
            } else {
                NavigationStack {
                    sidebar
                        .navigationTitle("Docs")
                        .navigationBarTitleDisplayMode(.inline)
                        .navigationDestination(for: String.self) { id in
                            destination(for: id)
                        }
                }
            }
        }
        .task { await services.docsService.refresh() }
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
        .alert("Rename document", isPresented: Binding(
            get: { renamingDoc != nil },
            set: { if !$0 { renamingDoc = nil } }
        )) {
            TextField("Title", text: $renameText)
            Button("Save") { commitRename() }
            Button("Cancel", role: .cancel) { renamingDoc = nil }
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        let svc = services.docsService
        List(selection: $selectedDocID) {
            if svc.isLoading && svc.allDocs.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            } else if let err = svc.lastError, svc.allDocs.isEmpty {
                emptyState(message: err, showCreate: false)
                    .listRowBackground(Color.clear)
            } else if svc.workspaces.isEmpty {
                emptyState(
                    message: "No workspaces yet — pull to refresh to create your Personal workspace.",
                    showCreate: false
                )
                .listRowBackground(Color.clear)
            } else if svc.allDocs.isEmpty {
                emptyState(message: "No documents yet.", showCreate: true)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(svc.workspaces) { workspace in
                    workspaceSection(workspace)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await svc.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await createDoc() }
                } label: {
                    if pendingCreate {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "plus")
                    }
                }
                .disabled(pendingCreate)
                .accessibilityLabel("New document")
                .accessibilityIdentifier("docs.list.newDocButton")
            }
        }
    }

    @ViewBuilder
    private func workspaceSection(_ workspace: DocWorkspaceDTO) -> some View {
        let svc = services.docsService
        let roots = svc.rootDocs(forWorkspaceId: workspace.id)
        Section {
            if roots.isEmpty {
                Text("No documents")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(roots) { doc in
                    docRow(doc, in: workspace, depth: 0)
                }
            }
        } header: {
            HStack(spacing: 6) {
                if let emoji = workspace.emoji { Text(emoji) }
                Text(workspace.name)
            }
        }
    }

    /// Recursive row for a doc + any children. Uses iOS leading indentation rather
    /// than a custom outline view so swipe-to-delete and selection still work.
    /// `AnyView` is required because `@ViewBuilder` cannot infer an opaque
    /// return type for a self-recursive helper.
    private func docRow(_ doc: DocRecordDTO, in workspace: DocWorkspaceDTO, depth: Int) -> AnyView {
        let svc = services.docsService
        let children = svc.children(ofParentId: doc.id, workspaceId: workspace.id)

        let row = NavigationLink(value: doc.id) {
            HStack(spacing: 8) {
                if doc.isStarred {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 12))
                }
                if let emoji = doc.emoji { Text(emoji) }
                Text(doc.title.isEmpty ? "Untitled" : doc.title)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.leading, CGFloat(depth) * 12)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await delete(doc) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                Task { await toggleStar(doc) }
            } label: {
                Label(
                    doc.isStarred ? "Unstar" : "Star",
                    systemImage: doc.isStarred ? "star.slash" : "star"
                )
            }
            .tint(.yellow)
        }
        .contextMenu {
            Button {
                renameText = doc.title
                renamingDoc = doc
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                UIPasteboard.general.string = doc.title.isEmpty ? "Untitled" : doc.title
            } label: {
                Label("Copy title", systemImage: "doc.on.doc")
            }
            Button {
                Task { await toggleStar(doc) }
            } label: {
                Label(doc.isStarred ? "Unstar" : "Star", systemImage: doc.isStarred ? "star.slash" : "star")
            }
            Button(role: .destructive) {
                Task { await delete(doc) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }

        return AnyView(
            Group {
                row
                ForEach(children) { child in
                    docRow(child, in: workspace, depth: depth + 1)
                }
            }
        )
    }

    @ViewBuilder
    private func emptyState(message: String, showCreate: Bool) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if showCreate {
                Button {
                    Task { await createDoc() }
                } label: {
                    Label("New document", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(pendingCreate)
                .accessibilityIdentifier("docs.list.emptyState.newDocButton")
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("docs.list.emptyState")
    }

    // MARK: - Detail (iPad only — iPhone uses navigation push)

    @ViewBuilder
    private func destination(for id: String) -> some View {
        if let doc = services.docsService.allDocs.first(where: { $0.id == id }) {
            DocEditorView(doc: doc)
        } else {
            ProgressView()
                .task { _ = await services.docsService.getDoc(id: id) }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selectedDocID, let doc = services.docsService.allDocs.first(where: { $0.id == id }) {
            DocEditorView(doc: doc)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Select a document")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func createDoc() async {
        guard !pendingCreate else { return }
        pendingCreate = true
        defer { pendingCreate = false }
        do {
            let doc = try await services.docsService.createNewDocument()
            selectedDocID = doc.id
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func delete(_ doc: DocRecordDTO) async {
        do {
            try await services.docsService.deleteDoc(id: doc.id)
            if selectedDocID == doc.id { selectedDocID = nil }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func toggleStar(_ doc: DocRecordDTO) async {
        do {
            _ = try await services.docsService.togglePin(id: doc.id)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func commitRename() {
        guard let doc = renamingDoc else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            renamingDoc = nil
            return
        }
        Task {
            do {
                _ = try await services.docsService.renameDoc(id: doc.id, title: trimmed)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        renamingDoc = nil
    }
}
