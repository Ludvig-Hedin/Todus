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
    /// Doc the user requested to delete via swipe. Drives the confirmation
    /// dialog so a fat-finger swipe doesn't immediately destroy data.
    @State private var deletingDoc: DocRecordDTO?

    var body: some View {
        Group {
            if sizeClass == .regular {
                // iPad: `selectedDocID` drives the detail pane directly; no
                // push happens on the sidebar column, so the
                // `navigationDestination` modifier is intentionally absent.
                NavigationSplitView {
                    sidebar
                        .navigationTitle("Docs")
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
            set: { if !$0 { renamingDoc = nil; renameText = "" } }
        )) {
            TextField("Title", text: $renameText)
                .submitLabel(.done)
                .onSubmit {
                    if !renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        commitRename()
                    }
                }
            Button("Save") { commitRename() }
                .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {
                renamingDoc = nil
                renameText = ""
            }
        }
        .confirmationDialog(
            deletingDoc.map { "Delete “\($0.title.isEmpty ? "Untitled" : $0.title)”?" } ?? "Delete document?",
            isPresented: Binding(
                get: { deletingDoc != nil },
                set: { if !$0 { deletingDoc = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let d = deletingDoc { Task { await delete(d) } }
                deletingDoc = nil
            }
            Button("Cancel", role: .cancel) { deletingDoc = nil }
        } message: {
            Text("This can't be undone.")
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
            // Recent skips docs that are already in the Starred section to avoid
            // showing the same row twice in the same list. Workspace section
            // duplication is intentional (it's the home view of the doc) but
            // top-of-list redundancy is noise.
            let starredIDs = Set(svc.starredDocs.map(\.id))
            let recent = Array(
                svc.allDocs
                    .filter { !starredIDs.contains($0.id) }
                    .sorted { $0.updatedAt > $1.updatedAt }
                    .prefix(5)
            )
            if !recent.isEmpty {
                Section("Recent") {
                    ForEach(recent, id: \.id) { doc in
                        flatDocRow(doc)
                            // Compound id keeps SwiftUI from merging swipe / hover
                            // state with this doc's other appearance in a workspace.
                            .id("recent-\(doc.id)")
                    }
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
                ForEach(starred, id: \.id) { doc in
                    flatDocRow(doc)
                        .id("starred-\(doc.id)")
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

    /// True when the row's doc is the active doc in the iPad detail pane.
    /// iPhone NavigationStack pushes don't need a sticky highlight (the editor
    /// is full-screen anyway), so we gate on size class.
    private func isActive(_ docID: String) -> Bool {
        sizeClass == .regular && selectedDocID == docID
    }

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
        .listRowBackground(isActive(doc.id) ? Color.accentColor.opacity(0.12) : nil)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deletingDoc = doc
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
        .listRowBackground(isActive(doc.id) ? Color.accentColor.opacity(0.12) : nil)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deletingDoc = doc
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
            // Route through the same confirmation dialog as swipe-delete.
            // Long-press → Delete is just as fat-fingerable as a swipe.
            deletingDoc = doc
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
            // .id(doc.id) so SwiftUI rebuilds state when navigating between docs
            // — without it the previous doc's title can briefly show.
            DocEditorView(doc: doc)
                .id(doc.id)
        } else {
            ProgressView()
                .task { _ = await services.docsService.getDoc(id: id) }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selectedDocID, let doc = services.docsService.allDocs.first(where: { $0.id == id }) {
            DocEditorView(doc: doc)
                .id(doc.id)
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
    /// Triggers a soft impact only when the open actually navigates somewhere
    /// (skip re-tap on the already-selected iPad row).
    private func open(docID: String) {
        let willChange: Bool
        if sizeClass == .regular {
            willChange = selectedDocID != docID
            selectedDocID = docID
        } else {
            // iPhone always pushes a fresh editor view — even if the user taps
            // the same doc twice from different sections, push counts.
            willChange = true
            path.append(docID)
        }
        if willChange {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
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
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func delete(_ doc: DocRecordDTO) async {
        do {
            try await services.docsService.deleteDoc(id: doc.id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if selectedDocID == doc.id { selectedDocID = nil }
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func toggleStar(_ doc: DocRecordDTO) async {
        do {
            _ = try await services.docsService.togglePin(id: doc.id)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func commitRename() {
        guard let doc = renamingDoc else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Save-disabled keeps this unreachable through the alert button, but
        // guard anyway in case rename is triggered programmatically later.
        guard !trimmed.isEmpty else {
            renamingDoc = nil
            renameText = ""
            return
        }
        Task {
            do {
                _ = try await services.docsService.renameDoc(id: doc.id, title: trimmed)
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        renamingDoc = nil
        renameText = ""
    }
}
