---
id: 0214
title: "Fix — Native AI chat file attachments (iOS, macOS, server)"
status: archived
category: Fixed
release_date: 2026-04-24
source: CHANGELOG.md
---

## [2026-04-24] Fix — Native AI chat file attachments (iOS, macOS, server)

- [Fix] Chat attachments are now serialized (base64 + MIME) in the `POST /api/ai/chat` body and merged into the last user turn on the server: images use OpenAI-style `image_url` parts; text-like files are inlined; other binaries get a short description so the model can still reason from filename and context.
- [Fix] iOS: pending files are read from `AttachmentService` storage, `send` accepts `attachmentFileNames`, and user bubbles show attachment pills next to the message. Saved conversations persist attachment filenames (re-open shows labels; re-sending from disk works when files still exist).
- [Fix] macOS: file picker URLs are read with security-scoped access, payloads cached by user message id for the stream/ retry round, the send button enables for attachment-only sends, and user bubbles list attached file names.
- **Files:** `apps/server/src/routes/ai.ts`, `apps/ios/.../AIChatView.swift`, `AIChatService.swift`, `AIChatMessage.swift`, `AIChatConversation.swift`, `AttachmentService.swift`, `EmailAIDraftSheet.swift`, `apps/macos/.../MacAIChatService.swift`, `MacAssistantPanel.swift`
