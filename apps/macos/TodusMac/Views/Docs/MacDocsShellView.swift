import SwiftUI

struct MacDocsShellView: View {
    @Environment(MacAppServices.self) private var services

    @State private var selectedDocId: String?
    @State private var isGrid = true
    @State private var searchText = ""
    @State private var createError: String?
    @State private var isCreatingDocument = false

    var body: some View {
        HSplitView {
            MacDocsSidebarView(
                selectedDocId: $selectedDocId,
                searchText: $searchText,
                isCreatingDocument: isCreatingDocument,
                onNewDocument: { Task { await newDocumentTapped() } }
            )
            .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
            rightPane
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MacTheme.contentBackground)
        // Cmd+N triggers "New document" anywhere inside the docs shell.
        // Hidden Button with .keyboardShortcut is the standard SwiftUI pattern
        // for window-scoped shortcuts that don't belong in the menu bar.
        .background(
            Button("") { Task { await newDocumentTapped() } }
                .keyboardShortcut("n", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        )
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

    /// Right pane swaps between the grid/list of all docs and the editor for
    /// the selected doc. Sidebar stays put — this is the Google-Docs layout:
    /// sidebar persistent, content area changes mode.
    @ViewBuilder
    private var rightPane: some View {
        if let id = selectedDocId {
            MacDocEditorPane(docId: id) {
                selectedDocId = nil
            }
        } else {
            MacDocsAllPane(
                selectedDocId: $selectedDocId,
                isGrid: $isGrid,
                searchText: $searchText,
                isCreatingDocument: isCreatingDocument,
                onNewDocument: { Task { await newDocumentTapped() } }
            )
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

/// Sort modes available in the docs grid/list header. Raw values are stable
/// across launches because they're persisted via `@AppStorage`.
enum DocsSortMode: String, CaseIterable, Identifiable {
    case recent
    case alphabetical
    case starredFirst

    var id: String { rawValue }
    var label: String {
        switch self {
        case .recent: return "Most recent"
        case .alphabetical: return "Alphabetical"
        case .starredFirst: return "Starred first"
        }
    }
    var systemImage: String {
        switch self {
        case .recent: return "clock"
        case .alphabetical: return "textformat"
        case .starredFirst: return "star"
        }
    }
}

struct MacDocsAllPane: View {
    @Environment(MacAppServices.self) private var services
    @Binding var selectedDocId: String?
    @Binding var isGrid: Bool
    @Binding var searchText: String
    var isCreatingDocument: Bool
    var onNewDocument: () -> Void

    @AppStorage("docs.allPane.sortMode") private var sortModeRaw: String = DocsSortMode.recent.rawValue
    private var sortMode: DocsSortMode { DocsSortMode(rawValue: sortModeRaw) ?? .recent }

    private var docs: [DocRecordDTO] {
        let s = services.docsService
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [DocRecordDTO]
        if q.isEmpty {
            filtered = s.allDocs
        } else {
            filtered = s.allDocs.filter { d in
                d.title.localizedCaseInsensitiveContains(q)
                    || (d.contentText?.localizedCaseInsensitiveContains(q) ?? false)
            }
        }
        return filtered.sorted { a, b in
            switch sortMode {
            case .recent:
                return a.updatedAt > b.updatedAt
            case .alphabetical:
                let at = (a.title.isEmpty ? "Untitled" : a.title)
                let bt = (b.title.isEmpty ? "Untitled" : b.title)
                return at.localizedCaseInsensitiveCompare(bt) == .orderedAscending
            case .starredFirst:
                if a.isStarred != b.isStarred { return a.isStarred && !b.isStarred }
                return a.updatedAt > b.updatedAt
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("All docs")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                sortMenu
                Button(action: onNewDocument) {
                    Label("New document", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isCreatingDocument)
                .help("Create a new page (⌘N)")
                // Segmented grid/list toggle. Matches the visual language of
                // `viewModePicker` in MacTasksView — selected option gets a pill
                // on a recessed track instead of a bare borderless button.
                gridListPicker
                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
            }
            .padding(.horizontal, MacTheme.spacing20)
            .padding(.vertical, MacTheme.spacing12)
            if services.docsService.isLoading {
                docsLoadingState
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

    /// Sort picker — Menu instead of Picker so each item shows its system
    /// image alongside the label, matching the visual treatment of
    /// `gridListPicker`. The active mode gets a checkmark in the dropdown.
    private var sortMenu: some View {
        Menu {
            ForEach(DocsSortMode.allCases) { mode in
                Button {
                    sortModeRaw = mode.rawValue
                } label: {
                    Label(mode.label, systemImage: mode.systemImage)
                    if mode == sortMode {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            Label(sortMode.label, systemImage: sortMode.systemImage)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Sort documents")
    }

    /// Loading state shows a grid of redacted skeleton cards so users get a
    /// sense of the grid shape before data arrives. Beats a bare spinner.
    private var docsLoadingState: some View {
        let cols = [GridItem(.adaptive(minimum: 200), spacing: 16)]
        return ScrollView {
            LazyVGrid(columns: cols, spacing: 16) {
                ForEach(0..<6, id: \.self) { _ in
                    skeletonCard
                }
            }
            .padding(20)
        }
        .accessibilityLabel("Loading documents")
    }

    private var skeletonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(MacTheme.surfaceHover)
                .frame(width: 140, height: 14)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(MacTheme.surfaceHover.opacity(0.7))
                .frame(height: 10)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(MacTheme.surfaceHover.opacity(0.7))
                .frame(height: 10)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(MacTheme.surfaceHover.opacity(0.7))
                .frame(width: 100, height: 10)
            Spacer()
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(MacTheme.surfaceHover.opacity(0.5))
                .frame(width: 60, height: 9)
        }
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .fill(MacTheme.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
        .redacted(reason: .placeholder)
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

    /// Segmented grid/list picker — same visual treatment as MacTasksView's
    /// `viewModePicker`: selected option gets a filled pill on a recessed track.
    private var gridListPicker: some View {
        HStack(spacing: 2) {
            gridListSegment(isSelected: isGrid, systemImage: "square.grid.2x2", help: "Grid view") {
                withAnimation(MacTheme.Motion.base) { isGrid = true }
            }
            gridListSegment(isSelected: !isGrid, systemImage: "list.bullet", help: "List view") {
                withAnimation(MacTheme.Motion.base) { isGrid = false }
            }
        }
        .padding(3)
        .background(MacTheme.surfaceCard, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(MacTheme.cardBorder, lineWidth: 0.5))
    }

    private func gridListSegment(
        isSelected: Bool,
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? MacTheme.textPrimary : MacTheme.mutedText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(MacTheme.accent.opacity(0.12))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help(help)
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
        DocCardView(
            doc: d,
            isSelected: selectedDocId == d.id
        ) {
            selectedDocId = d.id
        }
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

// MARK: - Card

/// Hover-aware doc card with stronger hierarchy than the inline version.
/// Title is the dominant element; preview is 12pt secondary; timestamp is
/// 10pt muted; star floats top-right. Selected card gets accent border.
private struct DocCardView: View {
    let doc: DocRecordDTO
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 6) {
                    if let emoji = doc.emoji {
                        Text(emoji)
                            .font(.system(size: 16))
                    }
                    Text(doc.title.isEmpty ? "Untitled" : doc.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(MacTheme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if doc.isStarred {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.yellow)
                    }
                }
                Text(previewText)
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.textSecondary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                Text(doc.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 10))
                    .foregroundStyle(MacTheme.mutedText)
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .fill(cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .stroke(cardBorder, lineWidth: isSelected ? 1.5 : 0.5)
            )
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .animation(MacTheme.Motion.fast, value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(action: action) {
                Label("Open", systemImage: "arrow.up.right.square")
            }
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(doc.title.isEmpty ? "Untitled" : doc.title, forType: .string)
            } label: {
                Label("Copy title", systemImage: "doc.on.doc")
            }
        }
    }

    private var previewText: String {
        guard let preview = doc.contentText, !preview.isEmpty else {
            return "Empty document"
        }
        return String(preview.prefix(200))
    }

    private var cardFill: Color {
        if isSelected {
            return MacTheme.accent.opacity(0.06)
        }
        if isHovered {
            return MacTheme.surfaceHover
        }
        return MacTheme.surfaceCard
    }

    private var cardBorder: Color {
        if isSelected {
            return MacTheme.accent
        }
        return MacTheme.cardBorder
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
                            .padding(.vertical, 3)
                            .padding(.horizontal, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(selectedDocId == nil ? MacTheme.accent.opacity(0.16) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)

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
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(selectedDocId == d.id ? MacTheme.accent.opacity(0.16) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func docOutline(_ d: DocRecordDTO, w: DocWorkspaceDTO, depth: Int) -> AnyView {
        let ch = services.docsService.children(ofParentId: d.id, workspaceId: w.id)
        return AnyView(
            VStack(alignment: .leading, spacing: 2) {
                DocsOutlineRow(
                    doc: d,
                    depth: depth,
                    isSelected: selectedDocId == d.id
                ) {
                    selectedDocId = d.id
                }
                ForEach(ch) { c in
                    docOutline(c, w: w, depth: depth + 1)
                }
            }
        )
    }
}

/// Hoverable + selectable outline row. Hover gives a subtle fill; selected
/// gets the accent tint at low opacity so the active doc is unambiguous when
/// the sidebar stays visible alongside the editor.
private struct DocsOutlineRow: View {
    let doc: DocRecordDTO
    let depth: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top) {
                Text(String(repeating: "  ", count: min(depth, 5)))
                Image(systemName: "doc")
                Text((doc.emoji.map { "\($0) " } ?? "") + doc.title)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(rowFill)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button {
                action()
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }
            Button {
                let display = doc.title.isEmpty ? "Untitled" : doc.title
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(display, forType: .string)
            } label: {
                Label("Copy title", systemImage: "doc.on.doc")
            }
        }
    }

    private var rowFill: Color {
        if isSelected {
            return MacTheme.accent.opacity(0.16)
        }
        if isHovered {
            return MacTheme.surfaceHover
        }
        return .clear
    }
}
