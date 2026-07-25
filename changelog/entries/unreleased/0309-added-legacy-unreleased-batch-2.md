---
id: 0309
title: "Added — legacy unreleased batch"
status: unreleased
category: Added
release_date: 2026-06-13
source: CHANGELOG.md
---

### Added

#### Web → Native parity (workstream A1) — calendar event editing

- **Web calendar can now create, edit, and delete events** — `/mail/calendar` was previously read-only (it rendered Google Calendar events + task due-dates but had no write UI; the `calendar.createEvent/updateEvent/deleteEvent` mutations existed server-side but nothing called them). Added an `EventEditDialog` (title, all-day toggle, start/end, location, notes — mirrors the native macOS `MacEventEditSheet` field set) wired to those mutations. A header "New event" button and tapping an empty time-grid slot open the create dialog; clicking an event opens edit; delete lives in the dialog. All-day events handle Google's exclusive `end.date` correctly (no off-by-one). Scoped to the primary calendar; multi-calendar visibility toggles are the next workstream (A2). The left-rail quick-add still creates tasks (unchanged). Date/timezone/all-day/payload logic is a pure, unit-tested module (`lib/calendar-event-form.ts`, 13 tests). Also enabled vitest for `apps/web`. See `docs/superpowers/specs/2026-06-13-web-native-parity-MASTER-design.md`. (`apps/web/app/(routes)/mail/calendar/page.tsx`, `apps/web/components/calendar/event-edit-dialog.tsx`, `apps/web/lib/calendar-event-form.ts`)

#### Web → Native parity (workstream A2) — multi-calendar visibility

- **The web calendar now shows all your calendars with per-calendar visibility toggles** — it previously only ever fetched the `primary` calendar (`calendarId` hardcoded). Switched to `calendar.eventsMulti` (spans all connections; each event tagged with its `calendarId`), added a left-rail "Calendars" list with color swatches + visibility toggles (persisted in localStorage, device-local like native), and replaced the `settings/calendars` placeholder with the same real toggles (kept in sync). Event edit/delete now target each event's own calendar instead of always `primary`. (`apps/web/app/(routes)/mail/calendar/page.tsx`, `apps/web/lib/calendar-visibility.ts`, `apps/web/app/(routes)/settings/calendars/page.tsx`)

#### Web → Native parity (workstream B1) — AI can manage tasks

- **The AI assistant can now create, update, complete, and list tasks** — `apps/server/src/routes/agent/tools.ts` previously exposed email tools only, so asking the chat (or voice) assistant to "add a task" silently did nothing. Added `createTask`/`updateTask`/`completeTask`/`listTasks` agent tools (mirroring the `tasks.create` insert, user-scoped via the resolved `userId`). **Also fixed a latent correctness gap:** the `aiCanWriteTasks` permission (Settings → AI → Permissions) was saved by the web settings page but never enforced server-side — write-task tools are now gated behind it (reads stay available). (`apps/server/src/routes/agent/tools.ts`, `apps/server/src/types.ts`)
- **The AI assistant can now create calendar events** (B2) — added a `createEvent` agent tool that writes to the user's primary Google Calendar (reusing the calendar route's Google client, now exported), handling timed (ISO + offset) and all-day (exclusive end) events. Gated behind `aiCanWriteCalendar` (also previously saved-but-unenforced). (`apps/server/src/routes/agent/tools.ts`, `apps/server/src/trpc/routes/calendar.ts`)

#### Web → Native parity (workstream E) — share-conversation UI

- **Web can now create share links for AI conversations** — the `sharing.create` backend existed (password + expiry), and `settings/sharing` could list/revoke, but there was no UI to actually _create_ a share (native has the share sheet). Added `ShareConversationDialog` (title, optional password, expiry: never/1/7/30 days) + a "Share" button in the chat header; shows a copyable `/share/:slug` link. (`apps/web/components/ai/share-conversation-dialog.tsx`, `apps/web/app/(routes)/mail/chat/page.tsx`)

#### Web → Native parity (workstream C) — voice transcript

- **Web voice now shows a live transcript** — the voice call was "blind": nothing displayed what was said. The `onMessage` handler was also attached to `startSession` instead of the `useConversation` hook (where ElevenLabs' `HookCallbacks` live), so it likely never fired. Moved it to the hook, collect the transcript into provider state, and render a compact transcript panel above the voice button. Also added the missing `connectionType: 'webrtc'` (cleared a pre-existing type error). Voice _tool execution_ (create task/event during a call) is still off — it needs the ElevenLabs agent configured in the dashboard; tracked as backlog PAR-C. (`apps/web/providers/voice-provider.tsx`, `apps/web/components/voice-button.tsx`)
