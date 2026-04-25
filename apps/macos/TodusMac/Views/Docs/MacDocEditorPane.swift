import SwiftUI
import WebKit

struct MacDocEditorPane: View {
    @Environment(MacAppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    let docId: String
    var onBack: () -> Void

    @State private var doc: DocRecordDTO?
    @State private var titleDraft: String = ""
    @State private var lastSavedJSON: DocJSONValue?
    @State private var lastText: String = ""
    @State private var wk: WKWebView?
    @State private var saveTask: Task<Void, Never>?
    @State private var isSaving = false
    @State private var showInspector = false

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
        .onDisappear {
            saveTask?.cancel()
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
            }
            Spacer()
            if isSaving { ProgressView().controlSize(.small) }
            Button {
                Task { await toggleStar() }
            } label: {
                Image(systemName: (doc?.isStarred ?? false) ? "star.fill" : "star")
            }
            .buttonStyle(.borderless)
            .help("Star")
            Button { showInspector.toggle() } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.borderless)
            .help("Info (coming soon)")
            .popover(isPresented: $showInspector) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Info")
                        .font(.headline)
                    Text("Version, word count, and more in a follow-up.")
                        .font(.caption)
                        .foregroundStyle(MacTheme.textSecondary)
                }
                .frame(width: 220)
                .padding()
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

    @ViewBuilder
    private var docFormatStrip: some View {
        HStack(spacing: MacTheme.spacing6) {
            tiptapButton("bold", .bold)
            tiptapButton("italic", .italic)
            tiptapButton("textformat.size", .heading1)
            tiptapButton("textformat", .heading2)
            tiptapButton("list.bullet", .bulletList)
            tiptapButton("list.number", .orderedList)
            tiptapButton("checklist", .taskList)
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
    private func tiptapButton(_ system: String, _ cmd: TiptapRunCommand) -> some View {
        Button {
            if let w = wk { tiptapRun(cmd, in: w) }
        } label: {
            Image(systemName: system)
        }
        .buttonStyle(.borderless)
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
        do {
            let u = try await services.docsService.updateDoc(DocUpdateInput(id: d.id, title: titleDraft))
            doc = u
        } catch {
            AppLogger.shared.log("[DocEditor] title save: \(error)")
        }
    }

    @MainActor
    private func debouncedSave(json: DocJSONValue?, text: String) {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            guard let d = doc else { return }
            isSaving = true
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
            } catch {
                AppLogger.shared.log("[DocEditor] autosave: \(error)")
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
