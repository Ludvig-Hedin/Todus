import SwiftUI
import WebKit

struct MacDocEditorPane: View {
    @Environment(MacAppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    /// 3-state UI signal for autosave. `.failed(msg)` exposes a retry affordance.
    enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    let docId: String
    var onBack: () -> Void

    @State private var doc: DocRecordDTO?
    @State private var titleDraft: String = ""
    @State private var lastSavedJSON: DocJSONValue?
    @State private var lastText: String = ""
    @State private var wk: WKWebView?
    @State private var saveTask: Task<Void, Never>?
    @State private var titleSaveTask: Task<Void, Never>?
    @State private var savedRevertTask: Task<Void, Never>?
    @State private var isSaving = false
    @State private var saveState: SaveState = .idle
    @State private var showInspector = false
    @State private var revertTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            editorChrome
            Divider()
                .background(MacTheme.cardBorder)
            if doc != nil {
                TiptapDocEditorWebView(
                    documentId: docId,
                    initialContent: doc?.content,
                    isDark: colorScheme == .dark,
                    onContentChange: { json, text in
                        lastSavedJSON = json
                        lastText = text
                        debouncedSave(json: json, text: text)
                    },
                    onWebViewReady: { wk = $0 }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if doc != nil { docFormatStrip }
        }
        .background(MacTheme.contentBackground)
        .task(id: docId) { await load() }
        .onChange(of: docId) { oldId, _ in
            // Flush in-memory state for the doc we're leaving before the new one loads.
            flushPendingSave(forDocId: oldId)
        }
        .onAppear {
            services.docsService.currentOpenDocId = docId
        }
        .onDisappear {
            // Cancel debounce, then synchronously enqueue a final save of in-memory
            // state so the last keystroke isn't lost when the view goes away.
            flushPendingSave(forDocId: docId)
            if services.docsService.currentOpenDocId == docId {
                services.docsService.currentOpenDocId = nil
            }
            revertTask?.cancel()
        }
        .onChange(of: services.docsService.pendingDocInsert) { _, text in
            guard let text, let wk else { return }
            let b64 = Data(text.utf8).base64EncodedString()
            let js = """
            (function(){
              var b64='\(b64)';
              var bin=atob(b64);
              var bytes=new Uint8Array(bin.length);
              for(var i=0;i<bin.length;i++)bytes[i]=bin.charCodeAt(i);
              var decoded=new TextDecoder('utf-8').decode(bytes);
              window.todusEditor && window.todusEditor.insertAtCursor(decoded);
            })();
            """
            wk.evaluateJavaScript(js, completionHandler: nil)
            services.docsService.pendingDocInsert = nil
        }
        .onChange(of: services.docsService.hasUnrevertedAIEdit) { _, isActive in
            revertTask?.cancel()
            guard isActive else { return }
            revertTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                guard !Task.isCancelled else { return }
                services.docsService.hasUnrevertedAIEdit = false
            }
        }
    }

    /// Cancel any in-flight debounced save and fire a final detached save of the
    /// current in-memory state. Detached so it survives the View being torn down.
    private func flushPendingSave(forDocId id: String) {
        saveTask?.cancel()
        titleSaveTask?.cancel()
        guard let snapshotDoc = doc, snapshotDoc.id == id else { return }
        let json = lastSavedJSON
        let text = lastText
        let titleSnapshot = titleDraft
        let titleChanged = titleSnapshot != snapshotDoc.title
        // Fire-and-forget: do not capture `self` state for the result; tolerate failure.
        let docsService = services.docsService
        Task { @MainActor in
            do {
                _ = try await docsService.updateDoc(
                    DocUpdateInput(
                        id: id,
                        title: titleChanged ? titleSnapshot : nil,
                        content: json,
                        contentText: (text.isEmpty ? " " : text),
                        emoji: nil,
                        order: nil,
                        parentId: nil,
                        workspaceId: nil,
                        isStarred: nil,
                        linkedThreadId: nil,
                        linkedEventId: nil,
                        linkedTaskId: nil
                    )
                )
            } catch {
                AppLogger.shared.log("[DocEditor] flush save: \(error)")
            }
        }
    }

    @ViewBuilder
    private var editorChrome: some View {
        HStack(alignment: .center, spacing: MacTheme.spacing12) {
            Button(action: onBack) {
                Label("All docs", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12, weight: .medium))
            VStack(alignment: .leading, spacing: 2) {
                Text(breadcrumb)
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.mutedText)
                TextField("Title", text: $titleDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .semibold))
                    .onSubmit { Task { await saveTitle() } }
                    .onChange(of: titleDraft) { _, _ in
                        // Debounce title autosave so users don't have to press Enter.
                        titleSaveTask?.cancel()
                        titleSaveTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 600_000_000)
                            guard !Task.isCancelled else { return }
                            await saveTitle()
                        }
                    }
            }
            Spacer()
            saveIndicator
            if services.docsService.hasUnrevertedAIEdit {
                Button {
                    guard let snap = services.docsService.preAIEditSnapshot,
                          let wk else { return }
                    guard let data = try? JSONEncoder().encode(snap) else { return }
                    let b64 = data.base64EncodedString()
                    let script = """
                    (function(){
                      var b64='\(b64)';
                      var bin=atob(b64);
                      var bytes=new Uint8Array(bin.length);
                      for(var i=0;i<bin.length;i++)bytes[i]=bin.charCodeAt(i);
                      var raw=new TextDecoder('utf-8').decode(bytes);
                      window.todusEditor && window.todusEditor.setContent(JSON.parse(raw));
                    })();
                    """
                    wk.evaluateJavaScript(script, completionHandler: nil)
                    services.docsService.hasUnrevertedAIEdit = false
                    services.docsService.preAIEditSnapshot = nil
                    revertTask?.cancel()
                } label: {
                    Label("Revert AI edit", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.borderless)
                .help("Revert to the document state before the AI edited it")
                .transition(.opacity)
            }
            Button {
                Task { await toggleStar() }
            } label: {
                Image(systemName: (doc?.isStarred ?? false) ? "star.fill" : "star")
            }
            .buttonStyle(.borderless)
            .help("Star")
            Button { showInspector.toggle() } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help("Document info")
            .accessibilityLabel("Document info")
            .popover(isPresented: $showInspector) {
                docInfoPopover
            }
        }
        .padding(.horizontal, MacTheme.spacing16)
        .padding(.vertical, MacTheme.spacing12)
    }

    private var breadcrumb: String {
        guard let d = doc, let w = services.docsService.workspaces.first(where: { $0.id == d.workspaceId }) else {
            return "Docs"
        }
        return "\(w.name) / \(d.parentId == nil ? "Unsorted" : "Nested")"
    }

    /// 3-state save badge (saving → saved → idle, or failed with retry).
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
                    .foregroundStyle(MacTheme.mutedText)
            }
        case .saved:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                Text("Saved")
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.mutedText)
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
                    // Re-run autosave with the last known content snapshot.
                    debouncedSave(json: lastSavedJSON, text: lastText, immediate: true)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .medium))
                .help(message)
            }
        }
    }

    /// Document info popover: word count, character count, last-updated, and a
    /// copyable monospace id. Falls back gracefully when the doc hasn't loaded.
    @ViewBuilder
    private var docInfoPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Info")
                .font(.headline)

            HStack {
                Text("Words")
                    .foregroundStyle(MacTheme.textSecondary)
                Spacer()
                Text("\(wordCount)")
                    .monospacedDigit()
            }
            .font(.system(size: 12))

            HStack {
                Text("Characters")
                    .foregroundStyle(MacTheme.textSecondary)
                Spacer()
                Text("\(characterCount)")
                    .monospacedDigit()
            }
            .font(.system(size: 12))

            if let updatedAt = doc?.updatedAt {
                HStack {
                    Text("Updated")
                        .foregroundStyle(MacTheme.textSecondary)
                    Spacer()
                    Text(updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.system(size: 12))
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("ID")
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.textSecondary)
                Text(docId)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(width: 240)
        .padding(12)
    }

    /// Word count from the current editor text — splits on any whitespace
    /// (spaces, newlines, tabs) and drops empties so blank lines don't inflate.
    private var wordCount: Int {
        lastText
            .split(whereSeparator: { $0.isWhitespace })
            .count
    }

    /// Character count uses Swift's grapheme-cluster `count` so emoji and
    /// combined glyphs count as one user-visible character.
    private var characterCount: Int {
        lastText.count
    }

    /// Sets `.saved` and leaves it visible — Google Docs / Apple Notes both
    /// keep the trust signal persistent until the next edit clears it via
    /// `.saving`. Auto-revert to `.idle` after 2s was a confidence regression.
    @MainActor
    private func markSaved() {
        savedRevertTask?.cancel()
        saveState = .saved
    }

    @ViewBuilder
    private var docFormatStrip: some View {
        HStack(spacing: MacTheme.spacing6) {
            tiptapButton("bold", .bold, help: "Bold", shortcut: "b")
            tiptapButton("italic", .italic, help: "Italic", shortcut: "i")
            tiptapButton("textformat.size", .heading1, help: "Heading 1")
            tiptapButton("textformat", .heading2, help: "Heading 2")
            tiptapButton("list.bullet", .bulletList, help: "Bulleted list")
            tiptapButton("list.number", .orderedList, help: "Numbered list")
            tiptapButton("checklist", .taskList, help: "Task list")
        }
        .padding(MacTheme.spacing8)
        .background(MacTheme.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func tiptapButton(
        _ system: String,
        _ cmd: TiptapRunCommand,
        help: String,
        shortcut: KeyEquivalent? = nil
    ) -> some View {
        let button = Button {
            if let w = wk { tiptapRun(cmd, in: w) }
        } label: {
            Image(systemName: system)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)

        if let shortcut {
            button.keyboardShortcut(shortcut, modifiers: .command)
        } else {
            button
        }
    }

    private func load() async {
        if let d = await services.docsService.getDoc(id: docId) {
            doc = d
            titleDraft = d.title
            lastSavedJSON = d.content
        }
    }

    private func saveTitle() async {
        guard let d = doc else { return }
        if titleDraft == d.title { return }
        saveState = .saving
        isSaving = true
        defer { isSaving = false }
        do {
            let u = try await services.docsService.updateDoc(DocUpdateInput(id: d.id, title: titleDraft))
            doc = u
            markSaved()
        } catch {
            AppLogger.shared.log("[DocEditor] title save: \(error)")
            saveState = .failed(error.localizedDescription)
        }
    }

    @MainActor
    private func debouncedSave(json: DocJSONValue?, text: String, immediate: Bool = false) {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            if !immediate {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            guard !Task.isCancelled else { return }
            guard let d = doc else { return }
            isSaving = true
            saveState = .saving
            defer { isSaving = false }
            do {
                _ = try await services.docsService.updateDoc(
                    DocUpdateInput(
                        id: d.id,
                        title: nil,
                        content: json,
                        contentText: text.isEmpty ? " " : text,
                        emoji: nil,
                        order: nil,
                        parentId: nil,
                        workspaceId: nil,
                        isStarred: nil,
                        linkedThreadId: nil,
                        linkedEventId: nil,
                        linkedTaskId: nil
                    )
                )
                markSaved()
            } catch {
                AppLogger.shared.log("[DocEditor] autosave: \(error)")
                saveState = .failed(error.localizedDescription)
            }
        }
    }

    private func toggleStar() async {
        guard let d = doc else { return }
        do {
            let u = try await services.docsService.updateDoc(
                DocUpdateInput(
                    id: d.id,
                    title: nil,
                    content: nil,
                    contentText: nil,
                    emoji: nil,
                    order: nil,
                    parentId: nil,
                    workspaceId: nil,
                    isStarred: !d.isStarred,
                    linkedThreadId: nil,
                    linkedEventId: nil,
                    linkedTaskId: nil
                )
            )
            doc = u
        } catch {
            AppLogger.shared.log("[DocEditor] star: \(error)")
        }
    }
}
