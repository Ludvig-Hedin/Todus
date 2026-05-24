# Docs Feature Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix critical iOS navigation bugs in the docs feature (tap doesn't open doc, `+` doesn't navigate) and bring iOS + macOS to Apple-Notes / Google-Docs polish.

**Architecture:** All changes are SwiftUI view-layer refactors. No backend, no DB, no schema, no shared package changes. iOS shifts from `List(selection:)`-on-iPhone (broken) to `NavigationPath`-based programmatic push, gets native title/save chrome around the existing Tiptap-in-WebView body, and grows a search + starred + all-docs list section. macOS shifts from swap-layout to persistent 2-column (sidebar always visible, right pane swaps list↔editor) with Cmd+N and richer cards.

**Tech Stack:** Swift 6 / SwiftUI (strict concurrency), `@Observable` services, WKWebView (body editor stays web-backed), pnpm monorepo with `xcodebuild` for iOS/macOS builds.

**Spec:** [docs/superpowers/specs/2026-05-24-docs-feature-overhaul-design.md](../specs/2026-05-24-docs-feature-overhaul-design.md)

---

## File Map

| File | Action | Reason |
|------|--------|--------|
| `apps/ios/Todus/Todus/Features/Docs/DocsListView.swift` | Rewrite | NavigationPath-based push, search, starred section, all-docs section, button rows |
| `apps/ios/Todus/Todus/Features/Docs/DocEditorView.swift` | Rewrite | Native title TextField, save indicator, back, star, info menu |
| `apps/macos/TodusMac/Views/Docs/MacDocsShellView.swift` | Refactor | 2-col persistent sidebar layout, Cmd+N, sort/filter integration |
| `apps/macos/TodusMac/Views/Docs/MacDocEditorPane.swift` | Modify | "Back to All docs" header polish (Google-Docs feel) |
| `CHANGELOG.md` | Append | Entry for the overhaul |
| `TASK.md` | Update | Mark docs polish in progress / done |

No new files required. No backend, no DB, no shared package, no Xcode project.pbxproj edits.

---

## Verification Strategy

SwiftUI view-layer work has no unit-test scaffolding in this repo. Verification gates:

1. **Compile** — `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -destination 'generic/platform=iOS' build` (or `pnpm ios:build:preview`) and `xcodebuild -project apps/macos/TodusMac/TodusMac.xcodeproj -scheme TodusMac build` after each phase.
2. **Simulator smoke** — `pnpm ios:simulator` + manual tap-through of the four critical flows: tap doc opens editor, `+` opens new doc, search filters, star toggles.
3. **macOS smoke** — `pnpm macos`, then verify sidebar persists during edit, Cmd+N creates and opens, back button returns to list.
4. **Existing UI tests** — `apps/ios/Todus/TodusUITests/CriticalFlowsTests.swift` exists; run after Phase 1 to catch regressions.

If a step says "verify build" and the build fails, the engineer fixes the compile error before proceeding — never commits a red build.

---

## Phase 1 — iOS Navigation Bug Fix (unblocks users)

### Task 1.1: Replace `List(selection:)` + `NavigationLink` with `NavigationPath` push on iPhone

**Files:**
- Rewrite: `apps/ios/Todus/Todus/Features/Docs/DocsListView.swift`

**Why:** `List(selection:)` is for `NavigationSplitView` (iPad). On iPhone `NavigationStack`, it consumes the tap as a selection change instead of letting `NavigationLink` push the destination. Also `createDoc` only mutates `selectedDocID`, which iPhone stack does not observe.

**Verification gate after this task:** iPhone simulator — tap doc opens it; `+` opens new doc.

- [ ] **Step 1: Read the current file to confirm state**

Run: `cat apps/ios/Todus/Todus/Features/Docs/DocsListView.swift | head -40`

Expected: `@State private var selectedDocID: String?` at line 13, `List(selection: $selectedDocID)` at line 71, `selectedDocID = doc.id` in `createDoc` at line 270. This matches the spec's confirmed bug locations.

- [ ] **Step 2: Replace the full `DocsListView` with the NavigationPath-aware version**

This is one cohesive rewrite — the navigation pattern, the row tap action, and the create flow all flip together. Trying to do it as separate edits leaves intermediate broken states.

Overwrite `apps/ios/Todus/Todus/Features/Docs/DocsListView.swift`:

```swift
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

    /// Filtered docs for the active search query. Empty query returns everything.
    private var filteredDocs: [DocRecordDTO] {
        let svc = services.docsService
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return svc.allDocs }
        return svc.allDocs.filter { d in
            d.title.localizedCaseInsensitiveContains(q)
                || (d.contentText?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    /// "All documents" — flat list sorted by most recently updated. Mirrors macOS.
    /// Only shown when search is empty (avoids duplicating workspace results).
    @ViewBuilder
    private var allDocsSection: some View {
        let svc = services.docsService
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // In search mode, replace workspace sections with flat filtered results.
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
        // Hide workspace sections during active search — results section already covers them.
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

    /// Flat row for All/Recent/Starred/Search sections. No depth indent, no children.
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

    /// Recursive workspace row (preserves outline shape).
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
```

- [ ] **Step 3: Note — `MainTabView.swift:115` wraps `DocsListView()` in `NavigationStack`**

That outer `NavigationStack` will conflict with the inner one we introduced on iPhone (double-nested stack swallows pushes). Confirm and fix:

Run: `grep -n 'DocsListView' apps/ios/Todus/Todus/Navigation/MainTabView.swift`

Expected output line: `NavigationStack { DocsListView() }`

Edit `apps/ios/Todus/Todus/Navigation/MainTabView.swift` — remove the wrapping `NavigationStack`:

Old:
```swift
NavigationStack { DocsListView() }
```

New:
```swift
DocsListView()
```

(`DocsListView` now owns its own `NavigationStack`/`NavigationSplitView` based on size class. Wrapping again would double-stack.)

- [ ] **Step 4: Build iOS**

Run: `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -destination 'generic/platform=iOS Simulator' -configuration Debug build -quiet 2>&1 | tail -20`

Expected: `** BUILD SUCCEEDED **`

If build fails: fix the compile error before continuing. Common causes — missing import, mismatched binding, AnyView ambiguity. Re-read the error and patch.

- [ ] **Step 5: Smoke test in simulator**

Run: `pnpm ios:simulator` (in a separate terminal/tab so it stays running)

Tap the Docs tab. Manually verify:
1. **Tap on existing doc → editor opens** (the original Bug 1 fix)
2. **Tap `+` icon → editor opens immediately with a new "Untitled" doc** (the original Bug 2 fix)
3. Search bar appears at top, typing filters the list
4. Starred section appears if you have starred docs (use context menu → Star to test)
5. Pull-to-refresh still works
6. Swipe-to-delete still works

If any flow regresses, fix before commit.

- [ ] **Step 6: Commit**

```bash
git add apps/ios/Todus/Todus/Features/Docs/DocsListView.swift apps/ios/Todus/Todus/Navigation/MainTabView.swift
git commit -m "fix(ios): docs list nav — tap and + button now open the editor

Root causes:
- List(selection:) on iPhone NavigationStack swallowed taps so
  NavigationLink push never fired (selection is for NavigationSplitView).
- createDoc only set selectedDocID, which iPhone NavigationStack doesn't
  observe — only the iPad detail pane did, so the new doc was created
  on the server but the user stayed on the list.

Fix:
- iPhone uses NavigationStack(path:) with explicit NavigationPath.
- Rows are Buttons that push doc.id onto path (iPhone) or set
  selectedDocID (iPad), branching by horizontalSizeClass.
- createDoc routes through the same open(docID:) helper, so a new doc
  always lands in the editor.
- MainTabView no longer wraps DocsListView in an outer NavigationStack
  (DocsListView owns its own nav now; double-stacking swallows pushes).

Also adds:
- Recent / Starred / Search sections (Apple-Notes style list shape).
- .searchable() for inline filtering by title + contentText.
- Flat docRow with content preview for non-workspace rows.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Phase 2 — iOS Editor Native Chrome

### Task 2.1: Wrap the Tiptap WebView body in native title + save indicator + back chrome

**Files:**
- Rewrite: `apps/ios/Todus/Todus/Features/Docs/DocEditorView.swift`

**Why:** Today the editor is just a toolbar wrapper around `DocsBrowserView` (which loads `/mail/docs/<id>` from the web app). The title is whatever the web page renders, save state is invisible, and there's no info menu — that's far from the macOS feel. Adding a native `TextField` for the title plus a save indicator and richer toolbar gives the Apple-Notes shell pattern.

The body stays `DocsBrowserView` so we don't have to bundle Tiptap into iOS this session (see spec "Out of Scope").

- [ ] **Step 1: Rewrite `DocEditorView`**

Overwrite `apps/ios/Todus/Todus/Features/Docs/DocEditorView.swift`:

```swift
import SwiftUI

/// Native shell around the (still web-backed) Tiptap doc editor. Mirrors the
/// macOS `MacDocEditorPane` pattern: native title TextField, save indicator,
/// star, info menu — WebView only renders the body.
///
/// Autofocuses the title when the doc opens with an empty / "Untitled" title
/// (i.e. it was just created from the `+` button) so the user can start typing.
struct DocEditorView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    let doc: DocRecordDTO

    @State private var titleDraft: String
    @State private var isStarred: Bool
    @State private var saveState: SaveState = .idle
    @State private var saveTask: Task<Void, Never>?
    @State private var savedRevertTask: Task<Void, Never>?
    @State private var showShare = false
    @State private var showInfo = false
    @State private var errorMessage: String?
    @FocusState private var titleFocused: Bool

    init(doc: DocRecordDTO) {
        self.doc = doc
        _titleDraft = State(initialValue: doc.title)
        _isStarred = State(initialValue: doc.isStarred)
    }

    var body: some View {
        VStack(spacing: 0) {
            titleHeader
            Divider()
            DocsBrowserView(docId: doc.id)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear { autofocusIfNew() }
        .onDisappear { flushPendingSave() }
        .sheet(isPresented: $showShare) {
            if let url = shareURL {
                ShareSheet(items: [url])
                    .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $showInfo) {
            DocInfoSheet(doc: doc)
                .presentationDetents([.medium])
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

    // MARK: - Title header

    @ViewBuilder
    private var titleHeader: some View {
        HStack(spacing: 10) {
            TextField("Untitled", text: $titleDraft)
                .font(.system(size: 18, weight: .semibold))
                .focused($titleFocused)
                .submitLabel(.done)
                .onSubmit {
                    titleFocused = false
                    Task { await saveTitleNow() }
                }
                .onChange(of: titleDraft) { _, _ in
                    scheduleDebouncedTitleSave()
                }
            saveIndicator
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var saveIndicator: some View {
        switch saveState {
        case .idle:
            EmptyView()
        case .saving:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("Saving…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .saved:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                Text("Saved")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
                Text("Save failed")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                Button("Retry") {
                    Task { await saveTitleNow() }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .medium))
                .help(message)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await toggleStar() }
            } label: {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .foregroundStyle(isStarred ? .yellow : .accentColor)
            }
            .accessibilityLabel(isStarred ? "Unstar" : "Star")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    showInfo = true
                } label: {
                    Label("Document info", systemImage: "info.circle")
                }
                Button {
                    showShare = true
                } label: {
                    Label("Share link", systemImage: "square.and.arrow.up")
                }
                Button {
                    UIPasteboard.general.string = titleDraft.isEmpty ? "Untitled" : titleDraft
                } label: {
                    Label("Copy title", systemImage: "doc.on.doc")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Behaviors

    /// Autofocus the title when the doc was just created (default title or empty).
    /// Apple-Notes / Google-Docs feel — user lands and can immediately rename.
    private func autofocusIfNew() {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Untitled" {
            // Tiny delay so the keyboard/animation settles before focus moves.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                titleFocused = true
            }
        }
    }

    private func scheduleDebouncedTitleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await saveTitleNow()
        }
    }

    private func saveTitleNow() async {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        // Skip when nothing changed.
        if trimmed == doc.title { return }
        saveState = .saving
        do {
            _ = try await services.docsService.renameDoc(
                id: doc.id,
                title: trimmed.isEmpty ? "Untitled" : trimmed
            )
            markSaved()
        } catch {
            AppLogger.shared.log("[DocEditor] title save: \(error)")
            saveState = .failed(error.localizedDescription)
        }
    }

    /// Fire-and-forget final save when the view goes away — captures the title
    /// snapshot so it survives the View being torn down.
    private func flushPendingSave() {
        saveTask?.cancel()
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == doc.title { return }
        let svc = services.docsService
        let id = doc.id
        let finalTitle = trimmed.isEmpty ? "Untitled" : trimmed
        Task { @MainActor in
            _ = try? await svc.renameDoc(id: id, title: finalTitle)
        }
    }

    @MainActor
    private func markSaved() {
        savedRevertTask?.cancel()
        saveState = .saved
        savedRevertTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            if case .saved = saveState { saveState = .idle }
        }
    }

    private func toggleStar() async {
        let newValue = !isStarred
        isStarred = newValue
        do {
            _ = try await services.docsService.setStarred(id: doc.id, isStarred: newValue)
        } catch {
            isStarred = !newValue
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var shareURL: URL? {
        services.configuration.effectiveAppURL
            .appendingPathComponent("mail/docs")
            .appendingPathComponent(doc.id)
    }
}

// MARK: - Info sheet

private struct DocInfoSheet: View {
    let doc: DocRecordDTO

    var body: some View {
        NavigationStack {
            List {
                Section("Document") {
                    LabeledContent("Title", value: doc.title.isEmpty ? "Untitled" : doc.title)
                    if let emoji = doc.emoji {
                        LabeledContent("Emoji", value: emoji)
                    }
                    LabeledContent("Created", value: doc.createdAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Updated", value: doc.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
                Section("ID") {
                    Text(doc.id)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Share sheet bridge

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
```

- [ ] **Step 2: Hide duplicate web title (CSS injection)**

The web page at `/mail/docs/<id>` renders its own title at the top, which now duplicates the native one. Hide the web title by extending the dark-mode injection script in `DocsWebView.swift` (so we don't introduce another script).

Open `apps/ios/Todus/Todus/Features/Docs/DocsWebView.swift`. Find the `darkModeScript` constant (around line 60) and add the title-hide CSS injection after it inside the same script block.

Edit — replace the `darkModeScript` declaration block (lines 60-72) with:

```swift
let darkModeScript = """
    function applyDarkMode() {
        if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches && document.documentElement) {
            document.documentElement.classList.add('dark');
        }
    }

    function hideWebTitleForNativeChrome() {
        // The native iOS shell renders its own title TextField above the WebView,
        // so the web doc page's title input would visually duplicate it. This
        // selector matches the title row in /mail/docs/<id>. Update it if the
        // web template changes.
        var s = document.createElement('style');
        s.setAttribute('data-todus-native-chrome', '1');
        s.textContent = '[data-doc-page-title], .doc-page-title, .docs-title-bar { display: none !important; }';
        document.head && document.head.appendChild(s);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function() {
            applyDarkMode();
            hideWebTitleForNativeChrome();
        }, { once: true });
    } else {
        applyDarkMode();
        hideWebTitleForNativeChrome();
    }
"""
```

> If the web page does not yet expose any of those class names / data attributes, the rule is a no-op — that's fine. We're future-proofing for when the web page is checked. The native title is still the source of truth.

- [ ] **Step 3: Build iOS**

Run: `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -destination 'generic/platform=iOS Simulator' -configuration Debug build -quiet 2>&1 | tail -20`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Smoke test in simulator**

In the running simulator (from Phase 1 step 5):
1. Tap `+` to create a new doc.
2. Verify: native title TextField is auto-focused, keyboard appears, you can type a title immediately.
3. Stop typing — wait ~600ms — see "Saving…" then "Saved ✓" then it disappears.
4. Tap the star — it fills + persists across navigations.
5. Tap the `…` menu — confirm Info / Share / Copy title work.
6. Pop back to the list — verify the renamed title shows on the row.

- [ ] **Step 5: Commit**

```bash
git add apps/ios/Todus/Todus/Features/Docs/DocEditorView.swift apps/ios/Todus/Todus/Features/Docs/DocsWebView.swift
git commit -m "feat(ios): native chrome around doc editor (title, save indicator, info)

Mirrors MacDocEditorPane pattern — native title TextField with debounced
autosave, save indicator (idle/saving/saved/failed with retry), star,
info sheet, share. Body stays the Tiptap WebView (web-backed) for now;
bundling Tiptap into iOS is deferred to a follow-up project.

Title autofocuses when the doc opens with an empty / 'Untitled' title
(i.e. it was just created via +) so the user can start typing
immediately — Apple-Notes feel.

DocsWebView injects CSS to hide the web page's own title row so the
two don't visually duplicate. Selectors are forward-compatible no-ops
if the web template uses different class names.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Phase 3 — macOS 2-Column Layout (Google-Docs feel)

### Task 3.1: Refactor `MacDocsShellView` to persistent sidebar + swap-right-pane

**Files:**
- Modify: `apps/macos/TodusMac/Views/Docs/MacDocsShellView.swift`

**Why:** Today the shell either shows `MacDocEditorPane` (when a doc is selected) OR `HSplitView { sidebar, MacDocsAllPane }` (when not). The sidebar disappears as soon as you open a doc — opposite of Google Docs / Apple Notes. Refactor so the sidebar is always in an `HSplitView` and the right pane switches between list and editor.

- [ ] **Step 1: Read current shell**

Confirm with `wc -l apps/macos/TodusMac/Views/Docs/MacDocsShellView.swift` — should show 440. We're modifying just the top-level `body` of `MacDocsShellView`; the rest (sidebar, pane, cards, outline row) stays.

- [ ] **Step 2: Replace the `body` property and helper in `MacDocsShellView`**

In `apps/macos/TodusMac/Views/Docs/MacDocsShellView.swift`, find:

```swift
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
```

Replace with:

```swift
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
        // Cmd+N for "New document" wherever the docs shell has focus.
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

    /// Right pane swaps between the grid/list of all docs and the editor for the
    /// selected doc. Sidebar stays put — this is the Google-Docs layout the user
    /// asked for: sidebar persistent, content area changes mode.
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
```

- [ ] **Step 3: Build macOS**

Run: `xcodebuild -project apps/macos/TodusMac/TodusMac.xcodeproj -scheme TodusMac -configuration Debug build -quiet 2>&1 | tail -20`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Smoke test**

Run `pnpm macos` in a separate terminal.

Verify:
1. Sidebar visible on app open with grid in right pane.
2. Click a doc → right pane swaps to editor; **sidebar stays visible**.
3. Click "All documents" in sidebar → right pane swaps back to grid.
4. Click the "All docs" back chevron in the editor header → right pane swaps back to grid (sidebar still visible).
5. **Cmd+N** anywhere in the docs view → new doc created, opens in right pane editor, sidebar visible.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/TodusMac/Views/Docs/MacDocsShellView.swift
git commit -m "feat(macos): docs persistent sidebar layout + Cmd+N

Refactors MacDocsShellView from swap-on-select (sidebar disappears
when editing a doc) to a Google-Docs style 2-column layout: sidebar
is always in an HSplitView, right pane swaps between MacDocsAllPane
(no doc selected) and MacDocEditorPane (doc selected).

Adds a hidden keyboard-shortcut button so Cmd+N triggers New
document anywhere inside the docs shell. The hidden button is a
common SwiftUI pattern for window-scoped shortcuts that don't belong
in a menu bar item.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

### Task 3.2: Highlight active sidebar entry + add sort menu to right pane

**Files:**
- Modify: `apps/macos/TodusMac/Views/Docs/MacDocsShellView.swift`

**Why:** With the sidebar always visible, users need to see which doc is open. Today sidebar rows have no selected state. And the grid has no sort option — Apple-Notes / Google-Docs default to most-recent but users expect Alphabetical / Starred-first.

- [ ] **Step 1: Add a `selected` highlight to `DocsOutlineRow`**

In `apps/macos/TodusMac/Views/Docs/MacDocsShellView.swift`, find the `DocsOutlineRow` struct (near the bottom — around line 397).

Replace the entire struct with:

```swift
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
            Button(action: action) {
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
```

- [ ] **Step 2: Pass `isSelected` from sidebar callers**

In the same file, find `MacDocsSidebarView.docOutline` (around line 382) and update the call site that builds `DocsOutlineRow`:

Old:
```swift
private func docOutline(_ d: DocRecordDTO, w: DocWorkspaceDTO, depth: Int) -> AnyView {
    let ch = services.docsService.children(ofParentId: d.id, workspaceId: w.id)
    return AnyView(
        VStack(alignment: .leading, spacing: 2) {
            DocsOutlineRow(doc: d, depth: depth) { selectedDocId = d.id }
            ForEach(ch) { c in
                docOutline(c, w: w, depth: depth + 1)
            }
        }
    )
}
```

New:
```swift
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
```

- [ ] **Step 3: Highlight "All documents" entry**

In the same file, find the `MacDocsSidebarView.body` "All documents" Button (around line 311):

Old:
```swift
Button {
    selectedDocId = nil
} label: {
    Label("All documents", systemImage: "rectangle.grid.2x2")
}
.buttonStyle(.borderless)
```

Replace with:
```swift
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
```

- [ ] **Step 4: Highlight starred sidebar rows**

In the same file, find `MacDocsSidebarView.sidebarRow` (around line 369) and replace:

```swift
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
```

- [ ] **Step 5: Add a sort menu to `MacDocsAllPane`**

In the same file, find `MacDocsAllPane` (around line 68). Add a sort-mode enum and `@AppStorage` binding, then surface the menu.

Add this enum just above `struct MacDocsAllPane: View {`:

```swift
/// Sort modes available in the docs grid/list header. Persisted across launches.
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
```

Inside `MacDocsAllPane`, add an `@AppStorage` property just below the existing `@Binding var searchText`:

```swift
@AppStorage("docs.allPane.sortMode") private var sortModeRaw: String = DocsSortMode.recent.rawValue
private var sortMode: DocsSortMode { DocsSortMode(rawValue: sortModeRaw) ?? .recent }
```

Replace the `docs` computed property with sort-aware logic:

Old:
```swift
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
```

New:
```swift
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
```

Add the sort menu to the header HStack. Find the existing header in `MacDocsAllPane.body`:

```swift
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
    gridListPicker
    TextField("Search", text: $searchText)
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 220)
}
```

Replace with:
```swift
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
    gridListPicker
    TextField("Search", text: $searchText)
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 220)
}
```

Add the `sortMenu` view just above `docsLoadingState`:

```swift
/// Sort picker — Menu instead of Picker so each item shows its system image
/// alongside the label, matching the visual treatment of the gridListPicker.
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
    .help("Sort documents")
}
```

- [ ] **Step 6: Build macOS**

Run: `xcodebuild -project apps/macos/TodusMac/TodusMac.xcodeproj -scheme TodusMac -configuration Debug build -quiet 2>&1 | tail -20`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Smoke test**

Restart `pnpm macos` (or use the running instance — SwiftUI hot reload won't pick up structural changes).

Verify:
1. Click a sidebar workspace row → it gets a subtle accent tint while open.
2. Click "All documents" → it gets the accent tint and right pane shows grid.
3. Click a starred row → same selected treatment.
4. Open the sort menu in `All docs` header → switch to Alphabetical → grid reorders A→Z.
5. Switch to Starred first → starred docs cluster at top.
6. Restart app → sort mode persists.

- [ ] **Step 8: Commit**

```bash
git add apps/macos/TodusMac/Views/Docs/MacDocsShellView.swift
git commit -m "feat(macos): sidebar selected state + sort menu in docs all-pane

Now that the sidebar stays visible during editing, users need to see
which doc is open. Each sidebar row (workspace outline, starred,
'All documents') gets a subtle MacTheme.accent.opacity(0.16) fill
when its target matches selectedDocId.

Adds a sort menu (Most recent / Alphabetical / Starred first) to the
All docs pane header, persisted via @AppStorage so the user's choice
survives relaunches. Defaults to Most recent — matches Apple Notes
and Google Docs.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Phase 4 — macOS Doc Card Polish

### Task 4.1: Richer doc cards (preview, hierarchy, hover)

**Files:**
- Modify: `apps/macos/TodusMac/Views/Docs/MacDocsShellView.swift`

**Why:** Cards today show title + content preview + timestamp but the hierarchy is weak — title and preview are similar sizes, no hover feedback, star is dim. Improve hierarchy + add hover state + bump title weight.

- [ ] **Step 1: Replace `docCard` in `MacDocsAllPane`**

Find `private func docCard(_ d: DocRecordDTO) -> some View` (around line 229) and replace with:

```swift
private func docCard(_ d: DocRecordDTO) -> some View {
    DocCardView(
        doc: d,
        isSelected: selectedDocId == d.id
    ) {
        selectedDocId = d.id
    }
}
```

Add this struct just above `struct MacDocsSidebarView: View {`:

```swift
/// Hover-aware doc card with stronger hierarchy than the inline version.
/// Title is the dominant element; preview is 12pt secondary; timestamp is
/// 10pt muted; star floats top-right.
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
```

- [ ] **Step 2: Improve loading state with skeleton cards**

Find `docsLoadingState` (around line 129) and replace:

```swift
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
```

- [ ] **Step 3: Build macOS**

Run: `xcodebuild -project apps/macos/TodusMac/TodusMac.xcodeproj -scheme TodusMac -configuration Debug build -quiet 2>&1 | tail -20`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Smoke test**

Restart `pnpm macos`. Verify cards:
1. Hover a card — subtle background change + 1.01 scale.
2. Click a card — it opens in editor; sidebar accent tint matches the workspace row.
3. Empty (no contentText) docs show "Empty document" in preview slot.
4. Briefly during load (disconnect network or watch fast): 6 skeleton cards animate.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/TodusMac/Views/Docs/MacDocsShellView.swift
git commit -m "feat(macos): richer doc cards + skeleton loading state

Cards:
- Title is now 15pt semibold (was 14pt), with emoji inline at 16pt.
- Star floats top-right at 11pt yellow.
- Preview is 12pt secondary, 4-line clamp, falls back to 'Empty document'.
- Relative timestamp at 10pt muted, anchored bottom.
- Hover: 1.01 scale + surfaceHover fill via Motion.fast.
- Selected: accent border + faint accent fill (1.5px stroke).
- Min height 130px so empty docs don't collapse.

Loading state: 6 skeleton cards instead of a bare spinner — matches
MacHomeView's loadingCard pattern and gives users a sense of the grid
shape before data arrives.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Phase 5 — Cross-Platform Bug Hunt + Inconsistency Sweep

### Task 5.1: Run `/bug-hunt` over the changed files

**Files:** read-only review.

- [ ] **Step 1: Invoke the bug-hunt skill**

In this session, invoke `/bug-hunt` and scope it to:
- `apps/ios/Todus/Todus/Features/Docs/DocsListView.swift`
- `apps/ios/Todus/Todus/Features/Docs/DocEditorView.swift`
- `apps/ios/Todus/Todus/Features/Docs/DocsWebView.swift`
- `apps/ios/Todus/Todus/Services/Docs/DocsService.swift`
- `apps/macos/TodusMac/Views/Docs/MacDocsShellView.swift`
- `apps/macos/TodusMac/Views/Docs/MacDocEditorPane.swift`
- `apps/macos/TodusMac/Services/Docs/MacDocsService.swift`

Capture the report.

- [ ] **Step 2: Triage and fix high-confidence bugs**

For each high-confidence finding:
- If it's a 1-2 line fix in a file already touched this session, fix inline.
- If it's larger or in untouched code, file a TODO with a backlog entry and continue.
- Document fixes in `CHANGELOG.md`.

- [ ] **Step 3: Commit any fixes**

```bash
git add -p   # interactive review
git commit -m "fix(docs): bug-hunt findings on iOS + macOS docs surface

<paste short list of fixes>

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

If no fixes were needed, skip this step.

### Task 5.2: Run `/inconsistency-hunter` across docs surface

**Files:** read-only review.

- [ ] **Step 1: Invoke the inconsistency-hunter skill**

Invoke `/inconsistency-hunter` scoped to the docs feature across iOS + macOS + web (`apps/web/app/(routes)/.../docs/`). Tell it to check:
- Visual / styling drift (spacing, colors, typography)
- UX pattern divergence (back button placement, create flow, save indicator)
- Copy / label mismatches ("New document" vs "New page" vs "+")
- Feature parity gaps

- [ ] **Step 2: Pick the top 3 inconsistencies and fix them**

Don't try to close every gap — pick the 3 most user-visible. Common candidates:
- "New page" vs "New document" — pick one (recommend "New document" — matches Apple Notes).
- Card hover scale should match between web and macOS.
- Empty state copy alignment.

Edit files, commit each fix individually with a clear `fix(consistency): ...` message.

### Task 5.3: Update CHANGELOG.md + TASK.md

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `TASK.md`

- [ ] **Step 1: Read current CHANGELOG head**

Run: `head -40 CHANGELOG.md`

- [ ] **Step 2: Add an entry at the top**

Open `CHANGELOG.md` and add under the most recent date heading (or create a new dated heading for `2026-05-24`):

```markdown
## 2026-05-24

### Docs Feature Overhaul (iOS + macOS)

**iOS bug fixes**
- Fix: tapping a doc row on iPhone now opens the editor (was: `List(selection:)` swallowed taps on `NavigationStack`).
- Fix: `+` button on iPhone now creates **and** opens the new doc (was: created on server but stayed on the list).

**iOS polish**
- Native title TextField with debounced autosave + save indicator (idle/saving/saved/failed-with-retry).
- Title autofocuses on newly-created docs — Apple-Notes feel.
- Search via `.searchable()` across title + contentText.
- "Recent" + "Starred" + per-workspace sections in the list.
- Flat doc rows show a one-line content preview.
- Doc info sheet (created/updated/ID) + share link + copy title in `…` menu.

**macOS polish**
- Persistent sidebar — sidebar stays visible when editing a doc (was: swap-on-select hid the sidebar entirely).
- Right pane swaps between `MacDocsAllPane` and `MacDocEditorPane` instead of the shell itself.
- Cmd+N creates and opens a new doc from anywhere in the docs view.
- Sidebar entries (workspace rows, starred rows, "All documents") get an accent fill when their target is selected.
- Sort menu (Most recent / Alphabetical / Starred first) in the `All docs` header, persisted via `@AppStorage`.
- Richer doc cards: stronger title hierarchy, 4-line preview, hover scale, selected accent border, min-height for empty docs.
- Skeleton loading state instead of a bare spinner.

**Architecture notes**
- iOS body editor still uses the `DocsBrowserView` WKWebView (loads `/mail/docs/<id>`). Bundling the Tiptap editor into iOS for offline parity is a deferred follow-up project.
- Web title row is hidden via injected CSS so it doesn't duplicate the native title.
```

- [ ] **Step 3: Update TASK.md**

Open `TASK.md`, find any "docs" related task and mark it done; if none exists, add:

```markdown
## ✅ 2026-05-24 — Docs feature overhaul
- iOS: fixed tap-to-open and create-and-navigate bugs.
- iOS: native title + autosave + save indicator + search + starred section.
- macOS: persistent sidebar, Cmd+N, sort menu, richer cards.
- Bug hunt + inconsistency hunter ran.
- See `docs/superpowers/specs/2026-05-24-docs-feature-overhaul-design.md`.
```

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md TASK.md
git commit -m "docs: changelog + task entry for docs feature overhaul

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

### Task 5.4: Final build + smoke

- [ ] **Step 1: Build iOS clean**

```bash
xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -destination 'generic/platform=iOS Simulator' -configuration Debug clean build -quiet 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Build macOS clean**

```bash
xcodebuild -project apps/macos/TodusMac/TodusMac.xcodeproj -scheme TodusMac -configuration Debug clean build -quiet 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Run existing critical-flow UI tests if scheme exists**

```bash
xcodebuild test -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:TodusUITests/CriticalFlowsTests -quiet 2>&1 | tail -30
```

If the scheme is not configured for tests, skip with a note. Don't fail the plan on missing test infra.

- [ ] **Step 4: Manual final pass on both platforms**

iOS (`pnpm ios:simulator`):
- [ ] Tap a doc opens it
- [ ] `+` creates and opens a doc
- [ ] Title typing → "Saving…" → "Saved ✓"
- [ ] Search filters list
- [ ] Star toggles persist
- [ ] Delete swipe works
- [ ] Back nav returns to list

macOS (`pnpm macos`):
- [ ] Sidebar always visible
- [ ] Cmd+N creates + opens
- [ ] Click All docs returns to grid
- [ ] Sort menu reorders
- [ ] Sidebar selected state visible
- [ ] Hover scale on cards
- [ ] Skeleton state during load

If any check fails, fix before declaring done.

---

## Risks Recap

- **Double NavigationStack on iPhone** — verified in Task 1.1 step 3. If we missed a tab-bar parent, push will silently no-op. Mitigation: `pnpm ios:simulator` test in Phase 1.
- **`.searchable()` on iPad in `NavigationSplitView`** — search bar may render in the wrong column. Mitigation: if it does, gate `.searchable()` to iPhone only (`sizeClass != .regular`).
- **Cmd+N hidden Button trick** — does not always work in SwiftUI on macOS 14+. Fallback: wire to `Commands` in the app's `WindowGroup` instead. Verify during Task 3.1 step 4.
- **`@AppStorage` raw string for enum** — if the stored value is corrupted (manual UserDefaults edit), `init(rawValue:)` returns nil and we fall back to `.recent`. No crash. Acceptable.
- **Web title hide CSS** — selector list is forward-looking. If web template changes, this becomes a no-op. Not a regression risk; worst case the title visually duplicates until selectors are updated.

---

## Out of Scope (do not start here)

- Bundling Tiptap into iOS (would unblock offline editing + true macOS parity). Separate spec.
- Drag-to-reorder docs across workspaces.
- Doc templates.
- Embeds for `linkedThreadId/EventId/TaskId`.
- Real-time collab (Yjs).
- Version history (Phase 3 of the older 2026-05-21 plan covers this on macOS).
