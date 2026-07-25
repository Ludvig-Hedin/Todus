---
id: 0144
title: "Feat — Doc editor page with auto-save (apps/mail/app/(routes)/mail/docs/[docId]/page.tsx)"
status: archived
category: Docs
release_date: 2026-04-01
source: CHANGELOG.md
---

## [2026-04-01] Feat — Doc editor page with auto-save (apps/mail/app/(routes)/mail/docs/[docId]/page.tsx)

Replaced the stub at `/mail/docs/:docId` with a full editor page:

- Two-column `ResizablePanelGroup` matching the docs list page layout; left panel hosts `DocTree` with the current doc highlighted via `selectedDocId`.
- Title: plain `<input>` (`text-2xl font-semibold`, no border) — saves on blur or Enter via `trpc.docs.update`.
- Editor: `<Editor>` (Tiptap/Novel); captures the live editor instance via `onEditorReady` so `getJSON()` / `getText()` provide JSONContent + plaintext for storage (since `onChange` emits HTML only).
- Content auto-save: inline debounce (1 s), calls `trpc.docs.update({ id, content, contentText })`.
- Loading state: shimmer bars (Tailwind `animate-pulse`); error/not-found state: message + Back link.
- Title seeded from server via `useEffect` (TanStack Query v5 — no `onSuccess` on `useQuery`).
