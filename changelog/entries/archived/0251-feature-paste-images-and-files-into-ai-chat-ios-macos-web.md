---
id: 0251
title: "Feature — Paste images and files into AI chat (iOS + macOS + web)"
status: archived
category: Added
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Feature — Paste images and files into AI chat (iOS + macOS + web)

- [Feature] **iOS:** Clipboard paste in the AI composer now supports photos (unchanged) plus non-image files via `NSItemProvider` (file URL, images, PDF, generic data) saved through `AttachmentService` and added to the pending-attachment row.
- [Feature] **macOS:** `MacChatNSTextView` intercepts paste to add `NSImage` (written to a temp PNG), file URLs from Finder, or raw PNG/TIFF/PDF data from the pasteboard to `pendingAttachments` (same path as the + attach button).
- [UX] **macOS:** Pending attachment row scrolls horizontally when crowded; each pill shows a 22px image preview (for image types), truncated name, uppercase format label, remove control, and drops paste temp files on remove.
- [Feature] **Web** (`apps/mail` + `apps/web` mail chat): Pasting files or images into the assistant textarea queues them (removable chips), sends with `useChat` `append` + `experimental_attachments` (data URLs), and shows attached filenames on user bubbles when present.
- **Files:** `CaptureComposer.swift`, `AIChatView.swift`, `MacAssistantPanel.swift`, `apps/mail/.../mail/chat/page.tsx`, `apps/web/.../mail/chat/page.tsx`
