---
id: 0264
title: "Fix — targeted web CodeRabbit follow-up"
status: archived
category: Fixed
release_date: 2026-04-26
source: CHANGELOG.md
---

## [2026-04-26] Fix — targeted web CodeRabbit follow-up

- [Fix] **Unified inbox infinite queries no longer create duplicate cache entries.** `useThreads()` now calls `trpcClient.mail.listThreadsMulti.query()` directly inside the outer `useInfiniteQuery` instead of nesting `queryClient.fetchQuery(...)`, so the multi-connection feed uses a single query lifecycle and cache entry.
- [Fix] **Settings navigation titles now follow the app i18n path.** The AI settings item now uses the existing `navigation.settings.ai` key, and billing uses the new `navigation.settings.billing` key instead of hardcoded strings.
- [Fix] **Attachment card press events no longer allow download param collisions.** Download-specific params are emitted under `downloadParams` so they cannot overwrite top-level event fields like `action`, `name`, or `mimeType`.
- [Fix] **Compose and AI settings polish:** compose-sheet close fallback now uses React Router state instead of `window.history.length`, and the Ollama URL success toast now only fires after the save mutation succeeds.
- [Fix] **Rendering, accessibility, and locale cleanup:** `WeeklyAgendaCard` now guards `parseISO()` output with `isValid()`, source rows suppress invalid timestamps, source favicon URLs encode `iconHint`, the full `ModelSelector` labels are programmatically tied to their Radix triggers, `CopyableTextCard` only shows copied state after successful local clipboard writes, the `open_attachment` catalog now uses nullable `previewUrl`, Hungarian danger-zone copy is translated, Hindi `cancel` labels are standardized, the French default-email copy is provider-agnostic, Czech `meetings` navigation labels are translated to `Schůzky`, and Catalan spam-delete confirmation stays in the file’s formal register.
- [Fix] **Stream handling, session i18n, and compose resilience:** Ollama pull streams now process the final buffered chunk and surface streamed `error` objects, the security sessions page now uses i18n keys instead of hardcoded English, inline draft autosave returns to `saved` after optimistic sync dispatch, draft update payloads are runtime-validated before use, AI chat markdown normalization uses a non-printable sentinel, and failed `append()` calls now restore the composer and pending attachments before showing an error toast.
- [Files] `apps/web/hooks/use-threads.ts`, `apps/web/config/navigation.ts`, `apps/web/components/ui/model-selector.tsx`, `apps/web/components/generative-ui/components/{AttachmentCard,WeeklyAgendaCard,CopyableTextCard}.tsx`, `apps/web/components/create/ai-sources.tsx`, `apps/web/components/generative-ui/catalog.ts`, `apps/web/app/(routes)/mail/{compose/search}/page.tsx`, `apps/web/app/(routes)/settings/ai/page.tsx`, `apps/web/messages/{en,cs,ca,fr,hi,hu}.json`, `CHANGELOG.md`, `TASK.md`
