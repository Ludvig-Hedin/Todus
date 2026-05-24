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
    @State private var lastSavedTitle: String
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
        _lastSavedTitle = State(initialValue: doc.title)
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
                .accessibilityHint(message)
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
        // Snapshot the draft inside the task so a teardown-time `flushPendingSave`
        // can't race against this scheduled task reading a mutated `titleDraft`.
        let draft = titleDraft
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            // Bail if the draft moved on while we slept — the next keystroke
            // already scheduled a fresh save with the newer value.
            if titleDraft != draft { return }
            await saveTitleNow()
        }
    }

    private func saveTitleNow() async {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        // Skip when nothing changed vs last persisted value.
        if trimmed == lastSavedTitle { return }
        saveState = .saving
        let finalTitle = trimmed.isEmpty ? "Untitled" : trimmed
        do {
            _ = try await services.docsService.renameDoc(id: doc.id, title: finalTitle)
            lastSavedTitle = finalTitle
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
        if trimmed == lastSavedTitle { return }
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
            // Only revert to idle if still .saved — if the user kept typing,
            // saveState may already be .saving and we shouldn't blow it away.
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
