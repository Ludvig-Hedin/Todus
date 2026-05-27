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
    /// True when the doc was just created via the `+` button. Autofocuses the
    /// title so the user can rename immediately — without hijacking keyboard
    /// focus when navigating to an existing doc that happens to be titled "Untitled".
    let isNewDoc: Bool

    @State private var titleDraft: String
    @State private var lastSavedTitle: String
    @State private var isStarred: Bool
    @State private var saveState: SaveState = .idle
    @State private var saveTask: Task<Void, Never>?
    @State private var autofocusTask: Task<Void, Never>?
    @State private var showShare = false
    @State private var showInfo = false
    @State private var errorMessage: String?
    @FocusState private var titleFocused: Bool

    init(doc: DocRecordDTO, isNewDoc: Bool = false) {
        self.doc = doc
        self.isNewDoc = isNewDoc
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
        // Show the doc title in the nav bar (drives the back-button label on deeper
        // pushes and confirms to the user which document is open).
        .navigationTitle(titleDraft.isEmpty ? "Untitled" : titleDraft)
        .navigationBarTitleDisplayMode(.inline)
        // Force an opaque nav bar background so iOS 26's glass/transparent nav bar
        // doesn't bleed the dark web-page background through the navigation area.
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar { toolbarContent }
        .onAppear { autofocusIfNew() }
        .onDisappear { flushPendingSave() }
        .sheet(isPresented: $showShare) {
            if let url = shareURL {
                ShareSheet(items: [url])
                    .presentationDetents([.medium])
            } else {
                ContentUnavailableView(
                    "Link unavailable",
                    systemImage: "link.badge.plus",
                    description: Text("Couldn't generate a share link for this document.")
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") { showShare = false }
                    }
                }
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
                .autocorrectionDisabled()
                .textInputAutocapitalization(.sentences)
                .onSubmit {
                    titleFocused = false
                    Task { await saveTitleNow() }
                }
                .onChange(of: titleDraft) { _, _ in
                    scheduleDebouncedTitleSave()
                }
            // Reserve width only when the indicator is visible — avoids a layout
            // shift that would continuously shrink the TextField while typing.
            saveIndicator
                .frame(minWidth: saveState == .idle ? 0 : 70, alignment: .trailing)
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
                    .foregroundStyle(isStarred ? .yellow : .secondary)
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
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Label("Copy title", systemImage: "doc.on.doc")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Behaviors

    /// Autofocus the title only when the doc was *just created* via the `+` button
    /// (`isNewDoc == true`). Avoids hijacking keyboard focus when the user navigates
    /// to an existing doc that happens to be titled "Untitled".
    /// Apple-Notes / Google-Docs feel — user lands and can immediately rename.
    /// Cancellable so a fast push/pop doesn't fire focus on a torn-down view.
    private func autofocusIfNew() {
        guard isNewDoc else { return }
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty || trimmed == "Untitled" else { return }
        autofocusTask?.cancel()
        autofocusTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            titleFocused = true
        }
    }

    private func scheduleDebouncedTitleSave() {
        saveTask?.cancel()
        // Snapshot the draft inside the task so a teardown-time `flushPendingSave`
        // can't race against this scheduled task reading a mutated `titleDraft`.
        let draft = titleDraft
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            // Bail if the draft moved on while we slept — the next keystroke
            // already scheduled a fresh save with the newer value.
            if titleDraft != draft { return }
            await saveTitleNow()
        }
    }

    private func saveTitleNow() async {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmed.isEmpty ? "Untitled" : trimmed
        // Skip when nothing changed vs last persisted value — and clear any
        // stale .failed badge so Retry doesn't no-op after the user reverts.
        if finalTitle == lastSavedTitle {
            if case .failed = saveState { saveState = .saved }
            return
        }
        saveState = .saving
        do {
            _ = try await services.docsService.renameDoc(id: doc.id, title: finalTitle)
            lastSavedTitle = finalTitle
            markSaved()
        } catch is CancellationError {
            // Debounce cancellation is normal — don't flash 'Save failed'.
            return
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            AppLogger.shared.log("[DocEditor] title save: \(error)")
            saveState = .failed(error.localizedDescription)
        }
    }

    /// Fire-and-forget final save when the view goes away — captures the title
    /// snapshot so it survives the View being torn down. Also cancels timers
    /// that would otherwise fire on a torn-down @State.
    private func flushPendingSave() {
        saveTask?.cancel()
        autofocusTask?.cancel()
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == lastSavedTitle { return }
        let svc = services.docsService
        let id = doc.id
        let finalTitle = trimmed.isEmpty ? "Untitled" : trimmed
        Task { @MainActor in
            _ = try? await svc.renameDoc(id: id, title: finalTitle)
        }
    }

    /// Persistent — Google Docs / Apple Notes keep "Saved" visible until the
    /// next edit triggers .saving. Auto-reverting to .idle made users wonder
    /// whether their work was actually safe.
    @MainActor
    private func markSaved() {
        saveState = .saved
    }

    private func toggleStar() async {
        let newValue = !isStarred
        isStarred = newValue
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        do {
            _ = try await services.docsService.setStarred(id: doc.id, isStarred: newValue)
        } catch {
            isStarred = !newValue
            UINotificationFeedbackGenerator().notificationOccurred(.error)
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
    @Environment(\.dismiss) private var dismiss

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
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
