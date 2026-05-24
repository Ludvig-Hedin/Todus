import SwiftUI

/// Native iOS / iPadOS shell for Docs. On iPhone we use a `NavigationStack` with
/// an explicit `NavigationPath` so both tap-to-open AND programmatic create-then-push
/// work. On iPad we keep `NavigationSplitView` driven by `selection:` so the detail
/// pane stays in sync.
///
/// Tap doc → push doc.id onto path (iPhone) or set selection (iPad).
/// `+` button → create on server, then push/select the new id.
struct DocsListView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// iPhone navigation path. Each entry is a doc id we've pushed.
    @State private var path = NavigationPath()
    /// iPad split-view selection. Drives the right-hand detail pane.
    @State private var selectedDocID: String?

    @State private var pendingCreate = false
    @State private var renamingDoc: DocRecordDTO?
    @State private var renameText: String = ""
    @State private var errorMessage: String?
    @State private var searchText: String = ""

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
                NavigationStack(path: $path) {
                    sidebar
                        .navigationTitle("Docs")
                        .navigationBarTitleDisplayMode(.large)
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
        List {
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
                allDocsSection
                starredSection
                ForEach(svc.workspaces) { workspace in
                    workspaceSection(workspace)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search docs")
        .refreshable { await svc.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await createDoc() }
                } label: {
                    if pendingCreate {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "square.and.pencil")
                    }
                }
                .disabled(pendingCreate)
                .accessibilityLabel("New document")
                .accessibilityIdentifier("docs.list.newDocButton")
            }
        }
    }

    // MARK: - List sections

    private var filteredDocs: [DocRecordDTO] {
        let svc = services.docsService
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return svc.allDocs }
        return svc.allDocs.filter { d in
            d.title.localizedCaseInsensitiveContains(q)
                || (d.contentText?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    @ViewBuilder
    private var allDocsSection: some View {
        let svc = services.docsService
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Section("Results") {
                let results = filteredDocs.sorted { $0.updatedAt > $1.updatedAt }
                if results.isEmpty {
                    Text("No matches")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(results) { doc in
                        flatDocRow(doc)
                    }
                }
            }
        } else if svc.allDocs.count > 1 {
            Section("Recent") {
                let recent = Array(svc.allDocs.sorted { $0.updatedAt > $1.updatedAt }.prefix(5))
                ForEach(recent) { doc in
                    flatDocRow(doc)
                }
            }
        }
    }

    @ViewBuilder
    private var starredSection: some View {
        let svc = services.docsService
        let starred = svc.starredDocs
        if !starred.isEmpty && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Section("Starred") {
                ForEach(starred) { doc in
                    flatDocRow(doc)
                }
            }
        }
    }

    @ViewBuilder
    private func workspaceSection(_ workspace: DocWorkspaceDTO) -> some View {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
    }

    // MARK: - Rows

    private func flatDocRow(_ doc: DocRecordDTO) -> some View {
        Button {
            open(docID: doc.id)
        } label: {
            HStack(spacing: 8) {
                if doc.isStarred {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 12))
                }
                if let emoji = doc.emoji { Text(emoji) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(doc.title.isEmpty ? "Untitled" : doc.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let preview = doc.contentText, !preview.isEmpty {
                        Text(preview)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        .contextMenu { docContextMenu(doc) }
    }

    private func docRow(_ doc: DocRecordDTO, in workspace: DocWorkspaceDTO, depth: Int) -> AnyView {
        let svc = services.docsService
        let children = svc.children(ofParentId: doc.id, workspaceId: workspace.id)

        let row = Button {
            open(docID: doc.id)
        } label: {
            HStack(spacing: 8) {
                if doc.isStarred {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 12))
                }
                if let emoji = doc.emoji { Text(emoji) }
                Text(doc.title.isEmpty ? "Untitled" : doc.title)
                    .font(.system(size: 15))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.leading, CGFloat(depth) * 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        .contextMenu { docContextMenu(doc) }

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
    private func docContextMenu(_ doc: DocRecordDTO) -> some View {
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

    // MARK: - Detail (iPad split-view detail)

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

    /// Opens a doc — pushes onto path on iPhone, sets selection on iPad.
    private func open(docID: String) {
        if sizeClass == .regular {
            selectedDocID = docID
        } else {
            path.append(docID)
        }
    }

    private func createDoc() async {
        guard !pendingCreate else { return }
        pendingCreate = true
        defer { pendingCreate = false }
        do {
            let doc = try await services.docsService.createNewDocument()
            open(docID: doc.id)
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
