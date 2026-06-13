# Web Calendar Write Support — Design (Workstream A)

> Date: 2026-06-13 · Status: design for review · Parent: `2026-06-13-web-native-parity-MASTER-design.md`

## Problem

The web calendar (`/mail/calendar`) is **read-only**. It renders Google Calendar
events + task due-dates across Day/Week/Month/Year, but the user cannot create,
edit, or delete events, and cannot choose which calendars are visible. Native iOS
and macOS both have full event CRUD and per-calendar visibility. This is the
single largest visible parity hole.

## Why this is small

The backend and most of the UI plumbing already exist:

- **Server mutations exist** — `apps/server/src/trpc/routes/calendar.ts`:
  - `createEvent` (`:473`) — input `{ calendarId='primary', summary, description?, location?, start:{dateTime?|date?, timeZone?}, end:{...}, attendees?:[{email,displayName?}], colorId?, reminders?:{useDefault?, overrides?} }`
  - `updateEvent` (`:544`) — input `{ calendarId='primary', eventId, patch:{ summary?, description?, location?, start?, end?, attendees?, colorId? } }`
  - `deleteEvent` (`:609`) — input `{ calendarId='primary', eventId }`
- **Multi-calendar already supported** — `calendar.calendars` query (`:252`) lists
  the user's calendars; `calendar.eventsMulti` + `multiConnectionProcedure` (`:289`)
  fetches events across all connections with `connectionIds?` and
  `calendarIds?: Record<connectionId, string[]>`.
- **Grid already exposes the hooks** — `apps/web/components/calendar/calendar-grid.tsx`:
  `onEventClick(eventId)` (`:69`) and `onCreateAt(start, end)` (`:67`) are wired
  through every sub-view (TimeGrid slot click `:378`, event pill click `:398-400`,
  all-day pill `:480`). The page currently passes neither correctly — it ignores
  `onEventClick` and uses `onCreateAt` to focus the **task** quick-add instead of
  creating an event.

So this workstream is: one dialog component + page wiring + a visibility store.
No new server work.

## Parity reference (native field set)

`apps/macos/TodusMac/Views/Calendar/MacEventEditSheet.swift` form:
title, all-day toggle, start/end date pickers (end auto-bumps to start+1h when it
would precede start), calendar picker, location, notes. iOS uses EventKit's native
editor. Web mirrors the macOS field set.

## Design

### 1. `EventEditDialog` (new — `apps/web/components/calendar/event-edit-dialog.tsx`)

shadcn `Dialog`. Two modes: `create | edit`.

Fields (mapped to server input):
| UI field | create input | update patch |
| --- | --- | --- |
| Title | `summary` | `summary` |
| All-day toggle | switches start/end between `date` and `dateTime` | same |
| Start | `start.dateTime`/`start.date` + `timeZone` | `start` |
| End | `end.dateTime`/`end.date` + `timeZone` | `end` |
| Calendar | `calendarId` (+ connectionId) | `calendarId` |
| Location | `location` | `location` |
| Notes | `description` | `description` |

Deferred (not in v1): attendees, colorId, custom reminders. (Server accepts them;
add later if needed.)

Behavior:
- Reuse existing primitives: `Input`, `Textarea`, `Switch`, date/time picker
  components already in `apps/web/components/ui/`. Use `parseEventStart`
  (`@/lib/calendar-utils`) + the user's timezone for local-safe conversion.
- Validation: non-empty title; `end > start` for timed events — auto-bump end to
  start+1h on start change (mirror native), block save otherwise.
- All-day: emit `date` (YYYY-MM-DD), omit `timeZone`; timed: emit `dateTime` ISO +
  `timeZone`.
- Calendar picker sourced from `calendar.calendars`; default = the currently
  "primary"/first writable calendar. Skip calendars whose `accessRole` is
  `reader`/`freeBusyReader` (read-only) — not selectable for create.
- Delete button (edit mode only) → confirm → `deleteEvent`.

### 2. Wire `calendar/page.tsx`

- Add mutations: `createEvent`, `updateEvent`, `deleteEvent` with optimistic
  update of the events cache + `invalidate` on the events query (`eventsMulti`).
  On error: rollback + `toast.error`.
- Dialog state: `{ open, mode, event?, prefill?: {start,end,allDay} }`.
- **New event affordances** (keep task creation intact):
  - Header **"New event"** button (next to view switcher) → open create dialog,
    prefilled with `selectedDate` at the next hour, 1h duration.
  - Grid `onCreateAt(start, end)` → open create dialog prefilled with the tapped
    slot range. (Replaces the current "focus left-rail task quick-add" behavior
    for the grid; the left-rail quick-add **stays** task-only — that's the
    task/event split.)
- `onEventClick(eventId)` → find event in `gridEvents`/`calendarEvents` (it has
  `description`, `location`, `startTime`, `endTime`, `allDay`, `color`,
  `calendarId`/`connectionId`) → open edit dialog.

### 3. Multi-calendar visibility

- New store `apps/web/lib/calendar-visibility.ts` — localStorage-backed set of
  hidden `calendarId`s (per connection), with read/write helpers + a small hook.
- Page: switch from `calendar.events` (primary-only) to **`calendar.eventsMulti`**,
  passing `calendarIds` derived from `calendar.calendars` minus the hidden set.
- Left rail: **"Calendars"** section listing each calendar (grouped by connection)
  with a checkbox + its color dot. Toggling persists to the store and re-filters.
- Wire the existing placeholder toggles in
  `apps/web/app/(routes)/settings/calendars/page.tsx` to the **same** store so the
  two surfaces agree.
- Per-calendar color: use the calendar's color (from `calendar.calendars`) as a
  fallback when an event lacks `colorId`.

### 4. Edge / error states
- `scopeMissing` — reuse the existing "Connect Google Calendar" CTA; disable
  create/edit when scope is missing.
- Read-only calendars — hide from the create picker; for events on a read-only
  calendar, open the dialog in a view-only state (no save/delete).
- Timezone correctness via `parseEventStart` + `Intl` tz; never construct dates
  from raw UTC for all-day events (existing drift fix must not regress).
- Optimistic rollback with toast on any mutation failure.

## Files

- new `apps/web/components/calendar/event-edit-dialog.tsx`
- new `apps/web/lib/calendar-visibility.ts`
- edit `apps/web/app/(routes)/mail/calendar/page.tsx`
- edit `apps/web/components/calendar/calendar-grid.tsx` (pass `onEventClick`
  through from page; minor — props already exist)
- edit `apps/web/app/(routes)/settings/calendars/page.tsx`

## Testing

- Component test: `EventEditDialog` — create payload shape (timed + all-day),
  edit patch shape, `end<=start` validation + auto-bump, read-only view state.
- Page test: `onCreateAt` opens create dialog (not task quick-add); successful
  create optimistically inserts an event; toggling a calendar hides its events.
- Verify: typecheck/build on the touched web files only (no project-wide lint).

## Acceptance criteria

1. User can create a Google Calendar event from web (header button or grid slot
   tap); it appears after refetch on the correct calendar.
2. User can click an event → edit fields → save; changes persist.
3. User can delete an event from the edit dialog (with confirm).
4. All-day vs timed events round-trip correctly (no timezone drift).
5. User can toggle individual calendars' visibility; hidden calendars' events
   disappear; selection persists across reloads; `settings/calendars` reflects the
   same state.
6. Task quick-add and task chips are unchanged (no regression).
7. `scopeMissing` and read-only calendars are handled gracefully.

## Out of scope (this workstream)
Attendees editing, RSVP, recurrence editing, custom reminder overrides, drag-to-
move/resize events. Track as follow-ups if wanted.
