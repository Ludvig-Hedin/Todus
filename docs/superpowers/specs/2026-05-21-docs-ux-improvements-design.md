# Docs UX Improvements

**Date:** 2026-05-21  
**Status:** Pending implementation  
**Scope:** macOS app + backend (versioning)

## Context

The docs feature exists but is not intuitive to use. Opening a doc does not focus the editor, clicking empty space below content does nothing, the AI writes responses to chat instead of the doc, suggestions shown when a doc is open are generic (home-tab prompts), the context pill says "Docs" instead of the doc's name, and there is no version history. This spec covers all five problem areas.

---

## Phase 1 — Core Editor UX (no DB changes)

### 1. Auto-focus & click-to-edit

**Problem:** Editor never focuses on open. Clicking blank space below text does nothing.

**Files:**
- `packages/macos-doc-editor/src/index.ts`
- `packages/macos-doc-editor/src/editor.css`
- `packages/macos-doc-editor/dist/index.js` (rebuild artifact)
- `packages/macos-doc-editor/dist/index.html` (no change needed)

**Changes:**

`editor.css` — make editor fill full WebView height so blank space is always clickable:
```css
#editor {
  min-height: 100vh;
  cursor: text;
}
```

`index.ts` — after `setContent`, focus at end; add click-outside handler:
```ts
setContent: (json) => {
  // ... existing setContent logic ...
  editor.commands.setContent(json);
  editor.commands.focus('end');   // ← new: auto-focus at end on doc open
  notifyChange();
},
```
Add inside `mount()` after editor is created:
```ts
// Click on blank space below content → focus at end
document.addEventListener('click', (e) => {
  const target = e.target as HTMLElement;
  if (!target.closest('.ProseMirror')) {
    editor?.commands.focus('end');
  }
});
```

**Rebuild:** `pnpm --filter @zero/macos-doc-editor build` after changes.

---

### 2. AI insert at cursor ("Insert into doc" button)

**Problem:** AI writes to chat. No way to get AI content into the doc.

**JS API extension** (`packages/macos-doc-editor/src/index.ts`):

Add to `TodusEditorApi` type:
```ts
insertAtCursor: (text: string) => void;
```

Add to `api` object in `mount()`:
```ts
insertAtCursor: (text: string) => {
  if (!editor) return;
  editor.chain().focus().insertContent(text).run();
  notifyChange();
},
```
`focus()` restores last cursor position. Content inserts there.

**Swift bridge — `MacDocsService.swift`:**
Add observable property:
```swift
var pendingDocInsert: String? = nil
```

**`MacDocEditorPane.swift`:**
Watch `pendingDocInsert` and call JS:
```swift
.onChange(of: services.docsService.pendingDocInsert) { _, text in
  guard let text, let wk else { return }
  let escaped = text
    .replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "'", with: "\\'")
    .replacingOccurrences(of: "\n", with: "\\n")
  wk.evaluateJavaScript(
    "window.todusEditor && window.todusEditor.insertAtCursor('\(escaped)');",
    completionHandler: nil
  )
  services.docsService.pendingDocInsert = nil
}
```

**`MacAssistantPanel.swift` — "Insert into doc" button:**
In the AI message bubble view, when `currentSelection.category == "docs"` and message is the last AI message with text content, show:
```swift
Button {
  services.docsService.pendingDocInsert = message.content
} label: {
  Label("Insert into doc", systemImage: "arrow.down.doc")
    .font(.system(size: 11, weight: .medium))
}
.buttonStyle(.borderless)
```
Only on the last AI message. Button placed below the message bubble.

---

### 3. Doc-specific suggestions & title in context pill

**Problem:** Suggestions show home-tab prompts when a doc is open. Pill says "Docs" not the doc name.

**`MacAssistantPanel.swift` — add `currentDocTitle: String?` parameter:**
```swift
var currentDocTitle: String? = nil
```

Update `currentSelection.title` display in the pill:
```swift
// In the pill HStack:
let pillTitle: String = {
  if currentSelection.category == "docs", let t = currentDocTitle { return t }
  return currentSelection.title
}()
Text(pillTitle)
```

Update `currentPageContext` in `sendMessage`:
```swift
chatService.currentPageContext = pageContextAttached
  ? (currentDocTitle.map { "Doc: \($0)" } ?? currentSelection.title + " view")
  : nil
```

**`MacDocsShellView.swift` — pass doc title to panel:**
When a doc is open, pass `currentDocTitle: selectedDocId.flatMap { docsService.docs.first(where: { $0.id == $0.id })?.title }` down to `MacAssistantPanel`.

**`contextualSuggestionsPool` — add `"docs"` case:**
```swift
case "docs":
  pinned = [
    ("pencil",           "Continue where I left off"),
    ("wand.and.stars",   "Improve the writing and clarity"),
    ("list.bullet.indent","Add structure with headings and sections"),
  ]
  extended = [
    ("text.alignleft",        "Write an introduction for this document"),
    ("doc.text.magnifyingglass","Summarize this document"),
    ("checkmark.circle",       "Fix grammar and tone"),
    ("arrow.down.right.and.arrow.up.left","Make this more concise"),
    ("plus.bubble",            "Expand the main points with more detail"),
    ("text.badge.checkmark",   "Add a conclusion"),
    ("list.bullet",            "Convert paragraphs into bullet points"),
  ]
```

---

## Phase 2 — AI Direct Edit + Session Revert

### 4. AI direct edit (explicit intent only)

**Trigger:** User says "rewrite this", "edit the doc", "improve this", "fix this" etc. AI detects intent and returns a `replace_doc_content` generative UI card with new content.

**Server side (`apps/server/src/trpc/routes/docs.ts` or AI router):**
Add a new generative UI card type `replace_doc_content: { content: string }` where `content` is markdown. The AI is instructed to return this card only when the user explicitly asks to edit/rewrite.

**macOS (`MacAssistantPanel.swift`):**
Handle `replace_doc_content` card:
1. Before replacing: snapshot current content to `services.docsService.preAIEditSnapshot`
2. Convert markdown to Tiptap JSON via a new JS function `setContentFromMarkdown(md)`
3. Evaluate JS to replace doc content
4. Show revert affordance in `MacDocEditorPane`

**JS addition (`index.ts`):**
```ts
setContentFromMarkdown: (md: string) => {
  if (!editor) return;
  // Use Tiptap's built-in markdown parsing or convert to HTML first
  editor.commands.setContent(`<p>${md.replace(/\n/g, '</p><p>')}</p>`);
  notifyChange();
},
```
(For richer markdown support, add `@tiptap/extension-markdown` package.)

### 5. Session revert after AI edit

**`MacDocsService.swift`:**
```swift
var preAIEditSnapshot: DocJSONValue? = nil
var hasUnrevertedAIEdit: Bool = false
```

**`MacDocEditorPane.swift` — revert button in chrome:**
```swift
if services.docsService.hasUnrevertedAIEdit {
  Button("Revert AI edit") {
    guard let snap = services.docsService.preAIEditSnapshot,
          let wk else { return }
    // Re-inject snapshot content via setContent JS
    services.docsService.hasUnrevertedAIEdit = false
    services.docsService.preAIEditSnapshot = nil
  }
  .buttonStyle(.borderless)
  .font(.system(size: 11, weight: .medium))
  .foregroundStyle(.orange)
}
```
Button disappears on next user save or after 5 minutes (timer in `task`).

---

## Phase 3 — Persistent Version History

### 6. DB schema

New table in `apps/server/src/db/schema.ts`:
```ts
export const docVersion = createTable(
  'doc_version',
  {
    id: text('id').primaryKey(),
    docId: text('doc_id').notNull().references(() => doc.id, { onDelete: 'cascade' }),
    userId: text('user_id').notNull().references(() => user.id, { onDelete: 'cascade' }),
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

Run `pnpm db:generate` then `pnpm db:migrate` after adding this.

### 7. tRPC routes

Add to `docsRouter` in `apps/server/src/trpc/routes/docs.ts`:

```ts
listVersions: privateProcedure
  .input(z.object({ docId: z.string(), limit: z.number().default(50) }))
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
    return ctx.db
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
  }),

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
    return ctx.db
      .update(doc)
      .set({
        title: v.title,
        content: v.content,
        contentText: v.contentText,
        updatedAt: new Date(),
      })
      .where(and(eq(doc.id, input.docId), eq(doc.userId, ctx.user.id)))
      .returning();
  }),
```

### 8. macOS service layer

Add to `MacDocsService.swift`:
```swift
struct DocVersionDTO: Codable, Identifiable {
  let id: String
  let docId: String
  let title: String
  let contentText: String?
  let source: String  // "user" | "ai"
  let createdAt: Date
}

func listVersions(docId: String) async throws -> [DocVersionDTO]
func createVersion(docId: String) async throws -> DocVersionDTO
func restoreVersion(docId: String, versionId: String) async throws -> DocRecordDTO
```

### 9. macOS version history UI

**Trigger logic in `MacDocEditorPane.swift`:**
- 30-second idle debounce: reset timer on each `onContentChange`, fire `createVersion` when timer expires
- Immediately before AI edit: `createVersion` synchronously before replace
- Manual trigger: button in history popover

**History button in editor chrome** (alongside existing star + info buttons):
```swift
Button { showHistory.toggle() } label: {
  Image(systemName: "clock.arrow.circlepath")
}
.buttonStyle(.borderless)
.help("Version history")
.popover(isPresented: $showHistory) {
  DocVersionHistoryView(docId: docId, onRestore: { restoredDoc in
    doc = restoredDoc
    titleDraft = restoredDoc.title
    // Re-inject content via webView
  })
}
```

**`DocVersionHistoryView`:**
- List of `DocVersionDTO` items
- Each row: relative timestamp ("2 hours ago"), source badge ("You" / "AI" in accent color), first line of `contentText` as preview
- "Restore" button with confirmation alert
- Keep last 50 versions (enforced at query level)

---

## Critical Files

| File | Change |
|------|--------|
| `packages/macos-doc-editor/src/index.ts` | focus on setContent, click handler, insertAtCursor, setContentFromMarkdown |
| `packages/macos-doc-editor/src/editor.css` | #editor min-height: 100vh, cursor: text |
| `apps/macos/TodusMac/Views/Docs/MacDocEditorPane.swift` | pendingDocInsert observer, revert button, version snapshot timer, history button |
| `apps/macos/TodusMac/Views/Docs/TiptapDocEditorWebView.swift` | no change needed |
| `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift` | Insert button, docs suggestions, title pill, currentDocTitle param |
| `apps/macos/TodusMac/Services/Docs/MacDocsService.swift` | pendingDocInsert, preAIEditSnapshot, version API methods |
| `apps/macos/TodusMac/Views/Docs/MacDocsShellView.swift` | pass currentDocTitle to MacAssistantPanel |
| `apps/server/src/db/schema.ts` | add docVersion table |
| `apps/server/src/trpc/routes/docs.ts` | listVersions, createVersion, restoreVersion |
| `packages/shared/` | DocVersionDTO type (if shared across platforms) |

---

## Verification

1. **Focus:** Open a doc → cursor should appear at end without clicking. Click blank space below text → cursor moves there.
2. **Insert:** Ask AI "write a summary" → "Insert into doc" button appears on response → click inserts at last cursor position.
3. **Suggestions:** Open AI panel while doc is open → first 3 suggestions are doc-writing prompts. Pill shows doc title not "Docs".
4. **AI edit:** Say "rewrite this doc" → AI replaces content → "Revert AI edit" button appears in chrome → clicking restores previous state.
5. **Versioning:** Edit a doc, wait 30s idle → run `listVersions` query to confirm version created. Open history popover → versions listed → restore one → doc content updates.

---

## Phasing

- **Phase 1** (JS + Swift, no migrations): Sections 1–3. Ship first, standalone, no risk.
- **Phase 2** (AI edit + session revert): Section 4–5. Depends on AI generative UI card extension.
- **Phase 3** (persistent versioning): Sections 6–9. Requires `pnpm db:generate && pnpm db:migrate`.
