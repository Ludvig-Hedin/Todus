---
id: 0260
title: "DONE Generative-UI catalog: 9 new card types across web, iOS, macOS (2026-04): TaskListCard, EmailLi"
status: done
tags: [task-md, sprint]
files: []
created: unknown
source: TASK.md
---

> Source context: TASK.md → Current Native Fix Batch

- `DONE` **Generative-UI catalog: 9 new card types across web, iOS, macOS (2026-04):** `TaskListCard`, `EmailListCard`, `CalendarEventListCard`, `ContactListCard`, `CopyableTextCard`, `InlineComposeCard`, `SuggestionsCard`, `ActionConfirmationCard`, `QuoteCard`. Backend contract + `drafts.update` mutation landed; web has full Zod schemas + React components + tRPC-wired `update_draft`/`send_draft` actions; iOS extended its existing ChatUISpec system + `DraftService`; **macOS gained the entire ChatUISpec system for the first time** (data model copied verbatim; renderer/views adapted to `MacTheme`; `MacChatMessage.parseUISpec()` + `MacAssistantPanel` render seam; `MacDraftService` parallels iOS). InlineComposeCard locks its seed by `draftId` so AI re-emissions don't clobber unsent edits.
