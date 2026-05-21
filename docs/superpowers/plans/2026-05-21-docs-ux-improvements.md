# Docs UX Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the macOS docs feature intuitive — auto-focus on open, click-to-edit, AI insert-into-doc button, doc-specific suggestions, doc title in context pill, and persistent version history.

**Architecture:** Phase 1 is pure JS + Swift with no backend changes. Phase 2 adds session-only revert state. Phase 3 adds a `doc_version` DB table, tRPC routes, and a macOS version history UI — it requires running migrations and is intentionally separated.

**Tech Stack:** Swift 6 / SwiftUI (macOS), Tiptap (TypeScript, bundled as local HTML/JS), tRPC + Drizzle ORM (backend), pnpm monorepo.

> ⚠️ **Phase boundary:** Tasks 1–8 require no DB changes and can ship immediately. Tasks 9–14 require `pnpm db:generate && pnpm db:migrate` — coordinate separately.

---

## File Map

| File | Action | Reason |
|------|--------|--------|
| `packages/macos-doc-editor/src/index.ts` | Modify | focus on load, click handler, insertAtCursor |
| `packages/macos-doc-editor/src/editor.css` | Modify | full-height click target |
| `packages/macos-doc-editor/dist/index.js` | Rebuild | artifact from build step |
| `apps/macos/TodusMac/Services/Docs/MacDocsService.swift` | Modify | bridge properties (insert, currentDocId, snapshot, versions) |
| `apps/macos/TodusMac/Views/Docs/MacDocEditorPane.swift` | Modify | insert observer, doc tracking, revert button, history button, snapshot timer |
| `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift` | Modify | insert button on messages, docs suggestions, doc title in pill |
| `apps/macos/TodusMac/Views/Docs/DocVersionHistoryView.swift` | Create | version history list UI |
| `apps/server/src/db/schema.ts` | Modify | add docVersion table (Phase 3) |
| `apps/server/src/trpc/routes/docs.ts` | Modify | listVersions, createVersion, restoreVersion (Phase 3) |

---

## Phase 1 — Core Editor UX

### Task 1: JS editor — auto-focus, click-to-edit, insertAtCursor

**Files:**
- Modify: `packages/macos-doc-editor/src/index.ts`
- Modify: `packages/macos-doc-editor/src/editor.css`

- [ ] **Step 1: Update `editor.css` — full-height click target**

Replace the `#editor` / `.todus-prose` block (lines 1–6):
```css
#editor,
.todus-prose {
  min-height: 100vh;
  outline: none;
  cursor: text;
}
```

- [ ] **Step 2: Update `TodusEditorApi` type in `index.ts` — add `insertAtCursor`**

Replace the existing `TodusEditorApi` type (lines 19–25):
```typescript
export type TodusEditorApi = {
  setContent: (json: unknown) => void;
  getJSON: () => unknown;
  getText: () => string;
  setTheme: (mode: 'light' | 'dark') => void;
  run: (command: string) => void;
  insertAtCursor: (text: string) => void;
};
```

- [ ] **Step 3: Update `setContent` in `api` object — auto-focus after inject**

Find the `setContent` implementation in `mount()` (around line 75) and replace:
```typescript
setContent: (json: unknown) => {
  if (!editor) return;
  try {
    editor.commands.setContent(json as Parameters<Editor['commands']['setContent']>[0]);
    editor.commands.focus('end');
    notifyChange();
  } catch {
    editor.commands.setContent('<p></p>');
    editor.commands.focus('end');
  }
},
```

- [ ] **Step 4: Add `insertAtCursor` to `api` object**

Add after the `run` property in the `api` object (before `window.todusEditor = api;`):
```typescript
insertAtCursor: (text: string) => {
  if (!editor) return;
  editor.chain().focus().insertContent(text).run();
  notifyChange();
},
```

- [ ] **Step 5: Add click-outside handler in `mount()` — clicking blank space focuses editor**

Add after `window.todusEditor = api;` (line ~130) and before the closing brace of `mount()`:
```typescript
// Clicking blank space below content focuses editor at end
document.addEventListener('click', (e) => {
  const target = e.target as HTMLElement;
  if (!target.closest('.ProseMirror')) {
    editor?.commands.focus('end');
  }
});
```

---

### Task 2: Rebuild the editor bundle

**Files:**
- Regenerate: `packages/macos-doc-editor/dist/index.js`

- [ ] **Step 1: Build**

```bash
pnpm --filter @zero/macos-doc-editor build
```
Expected: `dist/index.js` updated, no errors.

- [ ] **Step 2: Verify dist updated**

```bash
ls -la packages/macos-doc-editor/dist/
```
Expected: `index.js` has a recent modification timestamp.

---

### Task 3: MacDocsService — bridge properties

**Files:**
- Modify: `apps/macos/TodusMac/Services/Docs/MacDocsService.swift`

- [ ] **Step 1: Add bridge properties after `didLogDocsUnavailable` declaration (around line 15)**

```swift
// MARK: - UI Bridge Properties

/// Set by MacDocEditorPane when a doc is open; cleared on disappear.
/// Allows MacAssistantPanel to show the doc title in the context pill.
var currentOpenDocId: String? = nil

/// Set by MacAssistantPanel when user taps "Insert into doc".
/// MacDocEditorPane observes this via onChange and inserts via JS, then clears it.
var pendingDocInsert: String? = nil

/// Snapshot of doc content taken before an AI edit.
/// Used by the session-level revert button in MacDocEditorPane.
var preAIEditSnapshot: DocJSONValue? = nil

/// True while the revert button should be visible in the editor chrome.
var hasUnrevertedAIEdit: Bool = false
```

---

### Task 4: MacDocEditorPane — track open doc + insert observer

**Files:**
- Modify: `apps/macos/TodusMac/Views/Docs/MacDocEditorPane.swift`

- [ ] **Step 1: Set `currentOpenDocId` when doc opens, clear on disappear**

In the `body` `VStack`, after the existing `.task(id: docId)` modifier, add:
```swift
.onAppear {
    services.docsService.currentOpenDocId = docId
}
.onDisappear {
    if services.docsService.currentOpenDocId == docId {
        services.docsService.currentOpenDocId = nil
    }
}
```

- [ ] **Step 2: Observe `pendingDocInsert` and call JS**

Add this modifier to the `VStack` body (after the existing `.onDisappear`):
```swift
.onChange(of: services.docsService.pendingDocInsert) { _, text in
    guard let text, let wk else { return }
    // Use base64 to avoid any escaping issues with arbitrary text content
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
```

---

### Task 5: MacAssistantPanel — docs suggestions + title pill + insert button

**Files:**
- Modify: `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift`

- [ ] **Step 1: Add `"docs"` case to `contextualSuggestionsPool`**

In `contextualSuggestionsPool`, find `default: // home` and insert the `"docs"` case **before** it (around line 1626):
```swift
case "docs":
    pinned = [
        ("pencil",            "Continue where I left off"),
        ("wand.and.stars",    "Improve the writing and clarity"),
        ("list.bullet.indent","Add structure with headings and sections"),
    ]
    extended = [
        ("text.alignleft",                    "Write an introduction for this document"),
        ("doc.text.magnifyingglass",           "Summarize this document"),
        ("checkmark.circle",                   "Fix grammar and tone throughout"),
        ("arrow.down.right.and.arrow.up.left", "Make this more concise"),
        ("plus.bubble",                        "Expand the main points with more detail"),
        ("text.badge.checkmark",               "Add a conclusion"),
        ("list.bullet",                        "Convert paragraphs into bullet points"),
    ]
```

- [ ] **Step 2: Add `pillTitle` computed property to `MacAssistantPanel` — drives the context pill label**

Add as a private computed property near the other computed properties (after `contextualSuggestionsPool` or near `selectionIcon`):
```swift
private var pillTitle: String {
    if currentSelection.category == "docs",
       let id = services.docsService.currentOpenDocId,
       let title = services.docsService.allDocs.first(where: { $0.id == id })?.title {
        return title
    }
    return currentSelection.title
}
```

Then find `Text(currentSelection.title)` inside the pill HStack (around line 1191) and replace with:
```swift
Text(pillTitle)
    .font(.system(size: 11, weight: .medium))
```

The `Image(systemName: selectionIcon(currentSelection))` line above it stays unchanged.

- [ ] **Step 3: Update `currentPageContext` to include doc title**

In `sendMessage` (search for `chatService.currentPageContext = pageContextAttached`), there are two identical assignments. Replace both with:
```swift
chatService.currentPageContext = pageContextAttached ? {
    if currentSelection.category == "docs",
       let id = services.docsService.currentOpenDocId,
       let title = services.docsService.allDocs.first(where: { $0.id == id })?.title {
        return "Doc: \(title)"
    }
    return currentSelection.title + " view"
}() : nil
```

- [ ] **Step 4: Add `onInsertIntoDoc` callback to `MacMessageBubble` struct**

Find `private struct MacMessageBubble: View` (around line 1900). Add a new optional callback property after `onUpgrade`:
```swift
/// Called when user taps "Insert into doc" — only provided when docs context is active.
var onInsertIntoDoc: ((String) -> Void)?
```

- [ ] **Step 5: Render "Insert into doc" button in `MacMessageBubble.body`**

In `MacMessageBubble.body`, after the `actionRow` block (which ends around line 1962), add:
```swift
// "Insert into doc" button — shown when parent is in docs context
if let onInsert = onInsertIntoDoc,
   message.role == .assistant,
   !message.isStreaming,
   !message.content.isEmpty {
    HStack {
        Button {
            onInsert(message.content)
        } label: {
            Label("Insert into doc", systemImage: "arrow.down.doc")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MacTheme.mutedText)
        }
        .buttonStyle(.borderless)
        .macClickablePointer()
        .help("Insert AI response at cursor position in the open document")
        Spacer()
    }
    .padding(.top, 2)
}
```

- [ ] **Step 6: Pass `onInsertIntoDoc` in the `ForEach` that renders messages**

Find `ForEach(chatService.messages) { message in` (around line 1088). Inside the `MacMessageBubble(...)` initializer, add after `onUpgrade`.

Note: `chatService` is referenced the same way as in the `canRetry` call on the nearby line — match that access pattern exactly.

```swift
onInsertIntoDoc: {
    // Only the last assistant message while in docs context gets this callback
    guard currentSelection.category == "docs",
          !message.isStreaming,
          message.role == .assistant,
          chatService.messages.last(where: { $0.role == .assistant })?.id == message.id
    else { return nil }
    return { text in services.docsService.pendingDocInsert = text }
}(),
```

- [ ] **Step 7: Verify build compiles**

Open Xcode and build the macOS target, or run:
```bash
pnpm macos
```
Expected: No compile errors.

---

## Phase 2 — Session Revert After AI Edit

### Task 6: MacDocEditorPane — revert button + snapshot state

**Files:**
- Modify: `apps/macos/TodusMac/Views/Docs/MacDocEditorPane.swift`

- [ ] **Step 1: Add `@State` for revert timer**

In the `@State` declarations block (after line ~30), add:
```swift
@State private var revertTask: Task<Void, Never>?
```

- [ ] **Step 2: Add revert button to `editorChrome`**

In `editorChrome`, find the `HStack` that contains the star and info buttons. Add before the star button:
```swift
if services.docsService.hasUnrevertedAIEdit {
    Button {
        guard let snap = services.docsService.preAIEditSnapshot,
              let wk else { return }
        // Re-inject the pre-AI snapshot
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
}
```

- [ ] **Step 3: Auto-dismiss revert button after 5 minutes**

In `body`, after the existing modifiers, add:
```swift
.onChange(of: services.docsService.hasUnrevertedAIEdit) { _, isActive in
    revertTask?.cancel()
    guard isActive else { return }
    revertTask = Task { @MainActor in
        try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
        guard !Task.isCancelled else { return }
        services.docsService.hasUnrevertedAIEdit = false
    }
}
```

> **Note:** The `preAIEditSnapshot` is set and `hasUnrevertedAIEdit = true` by the AI card handler in `MacAssistantPanel` when the AI replaces doc content. That handler will be wired in a follow-up task once the AI `replace_doc_content` card type is implemented on the backend.

---

## Phase 3 — Persistent Version History

> ⚠️ **Requires DB migration.** Complete Tasks 1–8 first and ship. Run `pnpm db:generate && pnpm db:migrate` before starting Phase 3.

### Task 7: DB schema — `doc_version` table

**Files:**
- Modify: `apps/server/src/db/schema.ts`

- [ ] **Step 1: Add `docVersion` table after the `doc` table (after line ~1026)**

```typescript
export const docVersion = createTable(
  'doc_version',
  {
    id: text('id').primaryKey(),
    docId: text('doc_id')
      .notNull()
      .references(() => doc.id, { onDelete: 'cascade' }),
    userId: text('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    title: text('title').notNull().default('Untitled'),
    content: jsonb('content'),
    contentText: text('content_text'),
    source: text('source').$type<'user' | 'ai'>().notNull().default('user'),
    createdAt: timestamp('created_at').notNull().defaultNow(),
  },
  (t) => [
    index('doc_version_doc_id_idx').on(t.docId),
    index('doc_version_user_id_idx').on(t.userId),
    index('doc_version_created_at_idx').on(t.createdAt),
  ],
);
```

- [ ] **Step 2: Generate migration**

```bash
pnpm db:generate
```
Expected: A new migration file created in `apps/server/drizzle/`.

- [ ] **Step 3: Apply migration**

```bash
pnpm db:migrate
```
Expected: Migration applied successfully, `doc_version` table exists.

---

### Task 8: tRPC — versioning routes

**Files:**
- Modify: `apps/server/src/trpc/routes/docs.ts`

- [ ] **Step 1: Import `docVersion` in the docs router**

At the top of `apps/server/src/trpc/routes/docs.ts`, add `docVersion` to the existing schema imports:
```typescript
import { doc, docVersion, docWorkspace } from '../../db/schema';
```

- [ ] **Step 2: Add `listVersions` procedure to `docsRouter`**

Inside `docsRouter`, after the `search` procedure (end of file), add:
```typescript
listVersions: privateProcedure
  .input(z.object({ docId: z.string(), limit: z.number().int().min(1).max(100).default(50) }))
  .query(async ({ ctx, input }) => {
    return ctx.db
      .select()
      .from(docVersion)
      .where(
        and(
          eq(docVersion.docId, input.docId),
          eq(docVersion.userId, ctx.user.id),
        ),
      )
      .orderBy(desc(docVersion.createdAt))
      .limit(input.limit);
  }),
```

- [ ] **Step 3: Add `createVersion` procedure**

```typescript
createVersion: privateProcedure
  .input(z.object({ docId: z.string() }))
  .mutation(async ({ ctx, input }) => {
    const existing = await ctx.db
      .select()
      .from(doc)
      .where(and(eq(doc.id, input.docId), eq(doc.userId, ctx.user.id)))
      .limit(1);
    if (!existing[0]) throw new TRPCError({ code: 'NOT_FOUND' });
    const d = existing[0];
    const [created] = await ctx.db
      .insert(docVersion)
      .values({
        id: createId(),
        docId: d.id,
        userId: ctx.user.id,
        title: d.title,
        content: d.content,
        contentText: d.contentText,
        source: 'user',
      })
      .returning();
    return created;
  }),
```

- [ ] **Step 4: Add `restoreVersion` procedure**

```typescript
restoreVersion: privateProcedure
  .input(z.object({ docId: z.string(), versionId: z.string() }))
  .mutation(async ({ ctx, input }) => {
    const version = await ctx.db
      .select()
      .from(docVersion)
      .where(
        and(
          eq(docVersion.id, input.versionId),
          eq(docVersion.docId, input.docId),
          eq(docVersion.userId, ctx.user.id),
        ),
      )
      .limit(1);
    if (!version[0]) throw new TRPCError({ code: 'NOT_FOUND' });
    const v = version[0];
    const [updated] = await ctx.db
      .update(doc)
      .set({
        title: v.title,
        content: v.content as typeof doc.$inferInsert['content'],
        contentText: v.contentText,
        updatedAt: new Date(),
      })
      .where(and(eq(doc.id, input.docId), eq(doc.userId, ctx.user.id)))
      .returning();
    if (!updated) throw new TRPCError({ code: 'NOT_FOUND' });
    return updated;
  }),
```

- [ ] **Step 5: Verify required imports are present at top of file**

Ensure `createId`, `TRPCError`, `and`, `eq`, `desc` are all imported. They should already exist — grep to confirm:
```bash
grep -n "createId\|TRPCError\|and,\| and \|desc," apps/server/src/trpc/routes/docs.ts | head -10
```

---

### Task 9: MacDocsService — version API + DTO

**Files:**
- Modify: `apps/macos/TodusMac/Services/Docs/MacDocsService.swift`

- [ ] **Step 1: Add `DocVersionDTO` struct**

Add after the existing DTO structs (search for `DocRecordDTO` to find the area), or at the top of the file's extension section:
```swift
struct DocVersionDTO: Codable, Identifiable, Sendable {
    let id: String
    let docId: String
    let userId: String
    let title: String
    let contentText: String?
    let source: String  // "user" | "ai"
    let createdAt: Date
}

struct DocVersionListResponse: Codable {
    // tRPC query returns an array directly
}
```

Actually tRPC query for `listVersions` returns `[DocVersionDTO]` directly. Check `TodosAPIClient.trpcQuery` signature to confirm how to decode arrays — if it wraps in `result.data` or returns array directly.

Run:
```bash
grep -n "trpcQuery\|trpcMutation\|func trpc" apps/ios/Todus/Todus/Services/API/TodosAPIClient.swift | head -10
```

Adjust the response wrapper accordingly. If the existing pattern wraps in a struct:
```swift
struct DocVersionListResponse: Codable {
    let result: DocVersionListResult
    struct DocVersionListResult: Codable {
        let data: [DocVersionDTO]
    }
}
```

- [ ] **Step 2: Add `listVersions` method**

```swift
func listVersions(docId: String, limit: Int = 50) async throws -> [DocVersionDTO] {
    guard let client = apiClient else { throw URLError(.userAuthenticationRequired) }
    struct Input: Encodable { let docId: String; let limit: Int }
    // Adjust response type based on tRPC wrapper pattern used by other methods
    let response: [DocVersionDTO] = try await client.trpcQuery(
        "docs.listVersions",
        input: Input(docId: docId, limit: limit)
    )
    return response
}
```

- [ ] **Step 3: Add `createVersion` method**

```swift
func createVersion(docId: String) async throws -> DocVersionDTO {
    guard let client = apiClient else { throw URLError(.userAuthenticationRequired) }
    struct Input: Encodable { let docId: String }
    struct Response: Decodable { let result: Result; struct Result: Decodable { let data: DocVersionDTO } }
    let response: Response = try await client.trpcMutation("docs.createVersion", input: Input(docId: docId))
    return response.result.data
}
```

- [ ] **Step 4: Add `restoreVersion` method**

```swift
func restoreVersion(docId: String, versionId: String) async throws -> DocRecordDTO {
    guard let client = apiClient else { throw URLError(.userAuthenticationRequired) }
    struct Input: Encodable { let docId: String; let versionId: String }
    struct Response: Decodable { let result: Result; struct Result: Decodable { let data: DocRecordDTO } }
    let response: Response = try await client.trpcMutation(
        "docs.restoreVersion",
        input: Input(docId: docId, versionId: versionId)
    )
    return response.result.data
}
```

> **Note:** The exact `trpcQuery` / `trpcMutation` response wrapping pattern must match `TodosAPIClient`. Inspect `getDoc` in `MacDocsService` for the exact pattern and replicate it.

---

### Task 10: MacDocEditorPane — version snapshot timer + history button

**Files:**
- Modify: `apps/macos/TodusMac/Views/Docs/MacDocEditorPane.swift`

- [ ] **Step 1: Add state for version snapshot timer and history sheet**

In `@State` block:
```swift
@State private var versionSnapshotTask: Task<Void, Never>?
@State private var showHistory = false
```

- [ ] **Step 2: Debounce version snapshot on content change**

In `onContentChange` closure (inside `TiptapDocEditorWebView` call), after the existing `debouncedSave` call, add:
```swift
scheduleVersionSnapshot()
```

Add the private method:
```swift
@MainActor
private func scheduleVersionSnapshot() {
    versionSnapshotTask?.cancel()
    versionSnapshotTask = Task { @MainActor in
        // 30-second idle window — same principle as Google Docs revision batching
        try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
        guard !Task.isCancelled, let d = doc else { return }
        do {
            _ = try await services.docsService.createVersion(docId: d.id)
        } catch {
            AppLogger.shared.log("[DocEditor] version snapshot: \(error)")
        }
    }
}
```

Cancel in `onDisappear` / `flushPendingSave`:
```swift
versionSnapshotTask?.cancel()
```

- [ ] **Step 3: Add history button to `editorChrome`**

In `editorChrome`, add after the info button (`.popover(isPresented: $showInspector)`):
```swift
Button { showHistory.toggle() } label: {
    Image(systemName: "clock.arrow.circlepath")
}
.buttonStyle(.borderless)
.help("Version history")
.accessibilityLabel("Version history")
.popover(isPresented: $showHistory, arrowEdge: .bottom) {
    DocVersionHistoryView(docId: docId) { restoredDoc in
        doc = restoredDoc
        titleDraft = restoredDoc.title
        lastSavedJSON = restoredDoc.content
        // Re-inject restored content into the WebView
        guard let data = try? JSONEncoder().encode(restoredDoc.content),
              let wk else { return }
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
        showHistory = false
    }
}
```

---

### Task 11: DocVersionHistoryView — new file

**Files:**
- Create: `apps/macos/TodusMac/Views/Docs/DocVersionHistoryView.swift`

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

struct DocVersionHistoryView: View {
    @Environment(MacAppServices.self) private var services

    let docId: String
    var onRestore: (DocRecordDTO) -> Void

    @State private var versions: [DocVersionDTO] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var confirmingVersion: DocVersionDTO?
    @State private var isRestoring = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Version History")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else if versions.isEmpty {
                Text("No saved versions yet.\nVersions are created automatically as you edit.")
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.mutedText)
                    .multilineTextAlignment(.center)
                    .padding(20)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(versions) { version in
                            versionRow(version)
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }

            if let error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .frame(width: 320, height: 400)
        .task { await loadVersions() }
        .alert("Restore this version?", isPresented: Binding(
            get: { confirmingVersion != nil },
            set: { if !$0 { confirmingVersion = nil } }
        )) {
            Button("Restore", role: .destructive) {
                guard let v = confirmingVersion else { return }
                Task { await restore(v) }
            }
            Button("Cancel", role: .cancel) { confirmingVersion = nil }
        } message: {
            Text("This will replace the current document content with the selected version.")
        }
    }

    @ViewBuilder
    private func versionRow(_ version: DocVersionDTO) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(version.createdAt, style: .relative)
                        .font(.system(size: 12, weight: .medium))
                    Text("ago")
                        .font(.system(size: 12))
                        .foregroundStyle(MacTheme.mutedText)
                    Spacer()
                    // Source badge
                    Text(version.source == "ai" ? "AI" : "You")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(version.source == "ai" ? .blue : MacTheme.mutedText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            (version.source == "ai" ? Color.blue : Color.primary).opacity(0.1),
                            in: Capsule()
                        )
                }
                if let preview = version.contentText?.split(separator: "\n").first.map(String.init),
                   !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: 11))
                        .foregroundStyle(MacTheme.mutedText)
                        .lineLimit(1)
                }
            }

            Button("Restore") {
                confirmingVersion = version
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11, weight: .medium))
            .disabled(isRestoring)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func loadVersions() async {
        isLoading = true
        defer { isLoading = false }
        do {
            versions = try await services.docsService.listVersions(docId: docId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func restore(_ version: DocVersionDTO) async {
        isRestoring = true
        confirmingVersion = nil
        defer { isRestoring = false }
        do {
            let restored = try await services.docsService.restoreVersion(
                docId: docId,
                versionId: version.id
            )
            onRestore(restored)
        } catch {
            self.error = "Restore failed: \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 2: Add `DocVersionHistoryView.swift` to the Xcode project**

In Xcode: right-click `Views/Docs` group → Add Files → select `DocVersionHistoryView.swift`. Or if using file-system-only build, no action needed.

- [ ] **Step 3: Build and verify no compile errors**

```bash
pnpm macos
```
Expected: Clean build.

---

## Verification Checklist

### Phase 1
- [ ] Open a doc → cursor appears at end automatically (no click needed)
- [ ] Click blank space below text → cursor moves there, editor is active
- [ ] AI panel open with doc context: suggestions are doc-writing prompts (not home prompts)
- [ ] Context pill shows doc title (e.g. "Meeting Notes"), not "Docs"
- [ ] Ask AI to "write a paragraph about X" → "Insert into doc" button appears on the response
- [ ] Click "Insert into doc" → text appears at cursor position in the doc
- [ ] AI context sends "Doc: {title}" to the backend (check via AI response referencing doc by name)

### Phase 2
- [ ] After AI edits doc content, "Revert AI edit" button appears in orange in the editor chrome
- [ ] Clicking it restores the pre-AI content
- [ ] Button disappears after 5 minutes if not clicked

### Phase 3
- [ ] Edit a doc, wait 30 seconds idle → clock icon in chrome is available
- [ ] Open history popover → version created ~30s ago is listed
- [ ] Click "Restore" on a version → confirmation alert → doc content is replaced
- [ ] AI edits are labeled "AI" in the history list
