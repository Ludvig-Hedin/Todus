import SwiftUI

struct MacDocsShellView: View {
    @Environment(MacAppServices.self) private var services

    @State private var selectedDocId: String?
    @State private var isGrid = true
    @State private var searchText = ""
    @State private var createError: String?
    @State private var isCreatingDocument = false

    var body: some View {
        Group {
            if let id = selectedDocId {
                MacDocEditorPane(docId: id) {
                    selectedDocId = nil
                }
            } else {
                HSplitView {
                    MacDocsSidebarView(
                        selectedDocId: $selectedDocId,
                        searchText: $searchText,
                        isCreatingDocument: isCreatingDocument,
                        onNewDocument: { Task { await newDocumentTapped() } }
                    )
                    .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
                    MacDocsAllPane(
                        selectedDocId: $selectedDocId,
                        isGrid: $isGrid,
                        searchText: $searchText,
                        isCreatingDocument: isCreatingDocument,
                        onNewDocument: { Task { await newDocumentTapped() } }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MacTheme.contentBackground)
        .task {
            await services.docsService.refresh()
        }
        .alert("Couldn’t create page", isPresented: Binding(
            get: { createError != nil },
            set: { if !$0 { createError = nil } }
        )) {
            Button("OK", role: .cancel) { createError = nil }
        } message: {
            Text(createError ?? "")
        }
    }

    @MainActor
    private func newDocumentTapped() async {
        guard !isCreatingDocument else { return }
        isCreatingDocument = true
        defer { isCreatingDocument = false }
        do {
            let d = try await services.docsService.createNewDocument()
            selectedDocId = d.id
        } catch {
            createError = error.localizedDescription
        }
    }
}

// MARK: - All docs (grid / list)

struct MacDocsAllPane: View {
    @Environment(MacAppServices.self) private var services
    @Binding var selectedDocId: String?
    @Binding var isGrid: Bool
    @Binding var searchText: String
    var isCreatingDocument: Bool
    var onNewDocument: () -> Void

    private var docs: [DocRecordDTO] {
        let s = services.docsService
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            return s.allDocs.sorted { $0.updatedAt > $1.updatedAt }
        }
        return s.allDocs
            .filter { d in
                d.title.localizedCaseInsensitiveContains(q)
                    || (d.contentText?.localizedCaseInsensitiveContains(q) ?? false)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("All docs")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(action: onNewDocument) {
                    Label("New document", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isCreatingDocument)
                .help("Create a new page")
                Button { isGrid = true } label: { Image(systemName: "square.grid.2x2") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(isGrid ? MacTheme.accent : MacTheme.mutedText)
                Button { isGrid = false } label: { Image(systemName: "list.bullet") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(!isGrid ? MacTheme.accent : MacTheme.mutedText)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
            }
            .padding(.horizontal, MacTheme.spacing20)
            .padding(.vertical, MacTheme.spacing12)
            if services.docsService.isLoading {
                ProgressView().padding(24)
            } else if let err = services.docsService.lastError, docs.isEmpty {
                docsLoadErrorState(message: err)
            } else if docs.isEmpty {
                emptyState
            } else if isGrid {
                grid
            } else {
                list
            }
        }
    }

    private func docsLoadErrorState(message: String) -> some View {
        VStack(spacing: 16) {
            Text("Couldn’t load docs")
                .font(.system(size: 16, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(MacTheme.mutedText)
                .frame(maxWidth: 420)
            Button("Retry") {
                Task { await services.docsService.refresh() }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("No pages yet")
                .font(.system(size: 16, weight: .semibold))
            Text("Start with a new document, or add one from the Docs sidebar when your workspace is ready.")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(MacTheme.mutedText)
                .frame(maxWidth: 360)
            Button(action: onNewDocument) {
                Label("New document", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isCreatingDocument)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var grid: some View {
        let cols = [GridItem(.adaptive(minimum: 200), spacing: 16)]
        return ScrollView {
            LazyVGrid(columns: cols, spacing: 16) {
                ForEach(docs) { d in
                    docCard(d)
                }
            }
            .padding(20)
        }
    }

    private func docCard(_ d: DocRecordDTO) -> some View {
        Button {
            selectedDocId = d.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if d.isStarred { Image(systemName: "star.fill").font(.caption2).foregroundStyle(MacTheme.accent) }
                    Spacer()
                }
                Text((d.emoji.map { "\($0) " } ?? "") + d.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(MacTheme.textPrimary)
                Text(d.contentText.map { String($0.prefix(120)) } ?? "…")
                    .font(.system(size: 12))
                    .lineLimit(4)
                    .foregroundStyle(MacTheme.textSecondary)
                Text(d.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 10))
                    .foregroundStyle(MacTheme.mutedText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(MacTheme.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var list: some View {
        Table(docs) {
            TableColumn("Title") { d in
                Button {
                    selectedDocId = d.id
                } label: {
                    HStack {
                        if d.isStarred { Image(systemName: "star.fill") }
                        Text((d.emoji.map { "\($0) " } ?? "") + d.title)
                    }
                }
                .buttonStyle(.plain)
            }
            TableColumn("Updated") { d in
                Text(d.updatedAt.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }
}

// MARK: - Sidebar

struct MacDocsSidebarView: View {
    @Environment(MacAppServices.self) private var services
    @Binding var selectedDocId: String?
    @Binding var searchText: String
    var isCreatingDocument: Bool
    var onNewDocument: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("My space")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(action: onNewDocument) {
                    Label("New", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isCreatingDocument)
                .help("Create a new document")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        selectedDocId = nil
                    } label: {
                        Label("All documents", systemImage: "rectangle.grid.2x2")
                    }
                    .buttonStyle(.borderless)

                    if !services.docsService.starredDocs.isEmpty {
                        Text("Starred")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MacTheme.mutedText)
                        ForEach(services.docsService.starredDocs) { d in
                            sidebarRow(d)
                        }
                    }
                    ForEach(services.docsService.workspaces) { w in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(w.emoji.map { "\($0) \(w.name)" } ?? w.name)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(MacTheme.mutedText)
                            ForEach(roots(w.id), id: \.id) { d in
                                docOutline(d, w: w, depth: 0)
                            }
                            Button {
                                Task {
                                    if let c = try? await services.docsService.createDoc(
                                        workspaceId: w.id,
                                        parentId: nil,
                                        title: "Untitled"
                                    ) {
                                        selectedDocId = c.id
                                    }
                                }
                            } label: {
                                Label("New page", systemImage: "plus.circle")
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 12))
                        }
                    }
                }
                .padding(12)
            }
            if let err = services.docsService.lastError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MacTheme.emptyStateSurface)
    }

    private func roots(_ id: String) -> [DocRecordDTO] {
        services.docsService.rootDocs(forWorkspaceId: id)
    }

    private func sidebarRow(_ d: DocRecordDTO) -> some View {
        Button {
            selectedDocId = d.id
        } label: {
            HStack {
                Image(systemName: "doc")
                Text((d.emoji.map { "\($0) " } ?? "") + d.title)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func docOutline(_ d: DocRecordDTO, w: DocWorkspaceDTO, depth: Int) -> AnyView {
        let ch = services.docsService.children(ofParentId: d.id, workspaceId: w.id)
        return AnyView(
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    Text(String(repeating: "  ", count: min(depth, 5)))
                    Image(systemName: "doc")
                    Text((d.emoji.map { "\($0) " } ?? "") + d.title)
                }
                .padding(.vertical, 1)
                .contentShape(Rectangle())
                .onTapGesture { selectedDocId = d.id }
                ForEach(ch) { c in
                    docOutline(c, w: w, depth: depth + 1)
                }
            }
        )
    }
}
