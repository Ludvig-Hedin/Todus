---
id: 0281
title: "Fix — Generative-UI cards never rendered because the AI never saw the catalog"
status: archived
category: Fixed
release_date: 2026-04-27
source: CHANGELOG.md
---

## [2026-04-27] Fix — Generative-UI cards never rendered because the AI never saw the catalog

- [Fix] **Root cause:** `/api/ai/chat` (the SSE endpoint that web, iOS, and macOS chats all hit) builds the system prompt from `enrichedMessages` plus memory and AI-profile injections — it never appended `GENERATIVE_UI_PROMPT`. `AiChatPrompt()`, which contains the catalog instructions, is only used by the agent and brain routes. As a result the model in chat had zero knowledge of `InlineComposeCard`, `TaskListCard`, `EmailListCard`, etc., so it kept replying in plain markdown and the user never saw a draft card when asking the AI to write an email.
- [Fix] **Server:** [`apps/server/src/routes/ai.ts`](apps/server/src/routes/ai.ts) now imports `GENERATIVE_UI_PROMPT` from [`generative-ui-contract.ts`](apps/server/src/lib/generative-ui-contract.ts) and appends it to the system message right after the AI-profile injection. If no system message exists, one is prepended. The render seam in all three clients (`ChatSpecRenderer` on web, `ChatUISpecView` on iOS / macOS) was already wired — only the AI's awareness was missing.
- [Architectural] **`apps/web` is the active web product**, not `apps/mail` (which is now read-only legacy). Both have a parallel `components/generative-ui/` directory; the catalogs are functionally identical (only diff is `previewUrl: .nullable()` vs `.optional()`). The web rendering for the user lives in [`apps/web/components/create/ai-chat.tsx:601`](apps/web/components/create/ai-chat.tsx) where `<ChatSpecRenderer>` is mounted on every assistant message.
- [Files] `apps/server/src/routes/ai.ts`, `CHANGELOG.md`
