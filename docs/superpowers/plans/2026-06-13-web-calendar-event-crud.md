# Web Calendar Event CRUD (A1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let web users create, edit, and delete Google Calendar events on their primary calendar from `/mail/calendar`, matching native iOS/macOS event editing.

**Architecture:** All date/timezone/all-day/payload logic lives in a pure module (`apps/web/lib/calendar-event-form.ts`) that is unit-tested with vitest. A new `EventEditDialog` React component renders the form using that module. The calendar page wires existing-but-unused grid hooks (`onEventClick`, `onCreateAt`) and the existing server mutations (`calendar.createEvent/updateEvent/deleteEvent`, all `activeConnectionProcedure`, `calendarId='primary'`) with optimistic cache updates.

**Tech Stack:** React Router v7, TanStack Query + tRPC, shadcn/ui (`Dialog`, `Input`, `Textarea`, `Switch`, `Button`), date-fns, vitest.

**Scope:** Primary calendar only (the calendar the page already displays). Multi-calendar visibility + non-primary/multi-connection editing is a separate plan (A2) — it needs new server shape (a multi-connection calendars query and `connectionId` on the write mutations).

**Server contracts (already exist — do not change):**
- `calendar.createEvent` input: `{ calendarId='primary', summary, description?, location?, start:{dateTime?|date?, timeZone?}, end:{dateTime?|date?, timeZone?}, attendees?, colorId?, reminders? }`
- `calendar.updateEvent` input: `{ calendarId='primary', eventId, patch:{ summary?, description?, location?, start?, end?, attendees?, colorId? } }`
- `calendar.deleteEvent` input: `{ calendarId='primary', eventId }`
- `calendar.events` output item: `{ id, title, description, location, startTime, endTime, allDay, color, htmlLink, organizer, isOrganizer }` (no `calendarId` → implicitly `primary`). All-day items use `date` (`startTime`/`endTime` are `YYYY-MM-DD`); Google all-day `end.date` is **exclusive**.

---

## File Structure

- Create `apps/web/lib/calendar-event-form.ts` — pure form↔payload logic (no React).
- Create `apps/web/lib/calendar-event-form.test.ts` — vitest unit tests.
- Create `apps/web/vite.config.test.ts` additions OR a `test` block in `apps/web/vite.config.ts` — enable vitest (node env).
- Create `apps/web/components/calendar/event-edit-dialog.tsx` — the dialog.
- Modify `apps/web/app/(routes)/mail/calendar/page.tsx` — mutations + dialog state + wire grid hooks + header "New event" button.
- Modify `apps/web/app/(routes)/mail/calendar/page.tsx` already passes most grid props; add `onEventClick`.

---

## Task 0: Enable vitest in apps/web

**Files:**
- Modify: `apps/web/package.json` (add devDep + `test` script)
- Modify: `apps/web/vite.config.ts` (add `test` block)

- [ ] **Step 1: Add vitest devDependency**

Run:
```bash
pnpm --filter=@zero/web add -D vitest@3.2.4
```
Expected: `package.json` gains `"vitest": "3.2.4"` under devDependencies; lockfile updates.

- [ ] **Step 2: Add a `test` script**

In `apps/web/package.json`, inside `"scripts"`, add:
```json
"test": "vitest run",
```

- [ ] **Step 3: Add a vitest `test` block to the vite config**

In `apps/web/vite.config.ts`, add a `test` property to the config object (mirror `apps/server/vite.config.ts`). The helpers are pure → node environment, no jsdom:
```ts
  test: {
    environment: 'node',
    include: ['lib/**/*.test.ts'],
  },
```

- [ ] **Step 4: Verify the runner starts (no tests yet)**

Run:
```bash
pnpm --filter=@zero/web test
```
Expected: vitest runs, reports "No test files found" (exit 0) — confirms config is valid.

- [ ] **Step 5: Commit**
```bash
git add apps/web/package.json apps/web/vite.config.ts pnpm-lock.yaml
git commit -m "chore(web): enable vitest for unit tests"
```

---

## Task 1: Pure form↔payload module (TDD)

**Files:**
- Create: `apps/web/lib/calendar-event-form.ts`
- Test: `apps/web/lib/calendar-event-form.test.ts`

- [ ] **Step 1: Write the failing tests**

Create `apps/web/lib/calendar-event-form.test.ts`:
```ts
import { describe, expect, it } from 'vitest';
import {
  type EventFormValues,
  buildCreatePayload,
  buildUpdatePatch,
  eventToFormValues,
  validateForm,
  bumpEndAfterStart,
} from './calendar-event-form';

const timed: EventFormValues = {
  title: 'Standup',
  allDay: false,
  startDate: '2026-06-15',
  startTime: '09:00',
  endDate: '2026-06-15',
  endTime: '09:30',
  location: 'Room 1',
  description: 'Daily',
};

const allDay: EventFormValues = {
  title: 'Conf',
  allDay: true,
  startDate: '2026-06-15',
  startTime: '00:00',
  endDate: '2026-06-15', // inclusive in the UI
  endTime: '00:00',
  location: '',
  description: '',
};

describe('validateForm', () => {
  it('rejects empty title', () => {
    expect(validateForm({ ...timed, title: '  ' })).toMatch(/title/i);
  });
  it('rejects timed end <= start', () => {
    expect(validateForm({ ...timed, endTime: '09:00' })).toMatch(/after/i);
  });
  it('accepts a valid timed event', () => {
    expect(validateForm(timed)).toBeNull();
  });
  it('rejects all-day end before start', () => {
    expect(validateForm({ ...allDay, endDate: '2026-06-14' })).toMatch(/on or after/i);
  });
  it('accepts a valid all-day event', () => {
    expect(validateForm(allDay)).toBeNull();
  });
});

describe('buildCreatePayload', () => {
  it('builds a timed payload with dateTime + timeZone', () => {
    const p = buildCreatePayload(timed, 'primary');
    expect(p.calendarId).toBe('primary');
    expect(p.summary).toBe('Standup');
    expect(p.location).toBe('Room 1');
    expect(p.start.dateTime).toBe(new Date('2026-06-15T09:00').toISOString());
    expect(p.start.date).toBeUndefined();
    expect(typeof p.start.timeZone).toBe('string');
  });
  it('builds an all-day payload with EXCLUSIVE end date (+1 day)', () => {
    const p = buildCreatePayload(allDay, 'primary');
    expect(p.start.date).toBe('2026-06-15');
    expect(p.start.dateTime).toBeUndefined();
    expect(p.end.date).toBe('2026-06-16'); // Google end.date is exclusive
  });
  it('omits empty optional fields', () => {
    const p = buildCreatePayload({ ...timed, location: '', description: '' });
    expect(p.location).toBeUndefined();
    expect(p.description).toBeUndefined();
  });
});

describe('eventToFormValues (edit mode)', () => {
  it('parses a timed event', () => {
    const v = eventToFormValues({
      title: 'Sync',
      description: 'x',
      location: 'y',
      startTime: '2026-06-15T14:00:00.000Z',
      endTime: '2026-06-15T15:00:00.000Z',
      allDay: false,
    });
    expect(v.allDay).toBe(false);
    expect(v.startDate).toBe('2026-06-15');
    expect(v.title).toBe('Sync');
  });
  it('parses an all-day event back to INCLUSIVE end date (-1 day)', () => {
    const v = eventToFormValues({
      title: 'Conf',
      description: null,
      location: null,
      startTime: '2026-06-15',
      endTime: '2026-06-17', // Google exclusive end
      allDay: true,
    });
    expect(v.allDay).toBe(true);
    expect(v.startDate).toBe('2026-06-15');
    expect(v.endDate).toBe('2026-06-16'); // inclusive
  });
});

describe('buildUpdatePatch', () => {
  it('produces a patch matching the create start/end shape', () => {
    const patch = buildUpdatePatch(timed);
    expect(patch.summary).toBe('Standup');
    expect(patch.start.dateTime).toBe(new Date('2026-06-15T09:00').toISOString());
    expect(patch.end.dateTime).toBe(new Date('2026-06-15T09:30').toISOString());
  });
});

describe('bumpEndAfterStart', () => {
  it('moves end to start+1h when end <= new start (timed)', () => {
    const v = bumpEndAfterStart({ ...timed, startTime: '10:00', endTime: '09:30' });
    expect(v.endDate).toBe('2026-06-15');
    expect(v.endTime).toBe('11:00');
  });
  it('leaves a valid end untouched', () => {
    const v = bumpEndAfterStart(timed);
    expect(v.endTime).toBe('09:30');
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run:
```bash
pnpm --filter=@zero/web test lib/calendar-event-form.test.ts
```
Expected: FAIL — `Cannot find module './calendar-event-form'`.

- [ ] **Step 3: Implement the module**

Create `apps/web/lib/calendar-event-form.ts`:
```ts
/**
 * Pure form <-> Google Calendar payload helpers for the web event editor.
 * No React, no tRPC — fully unit-testable. All-day semantics follow Google:
 * `end.date` is EXCLUSIVE, so the UI's inclusive end date is +1 day on write
 * and -1 day on read.
 */
import { addDays, format, parseISO } from 'date-fns';

export interface EventFormValues {
  title: string;
  allDay: boolean;
  startDate: string; // YYYY-MM-DD
  startTime: string; // HH:mm
  endDate: string; // YYYY-MM-DD (inclusive, as shown to the user)
  endTime: string; // HH:mm
  location: string;
  description: string;
}

export interface EventTimePart {
  dateTime?: string;
  date?: string;
  timeZone?: string;
}

const DATE_FMT = 'yyyy-MM-dd';

export function getLocalTimeZone(): string {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone;
  } catch {
    return 'UTC';
  }
}

function shiftDateStr(date: string, days: number): string {
  return format(addDays(parseISO(date), days), DATE_FMT);
}

function composeDate(date: string, time: string): Date {
  return new Date(`${date}T${time || '00:00'}`);
}

function toStartPart(v: EventFormValues, tz: string): EventTimePart {
  if (v.allDay) return { date: v.startDate };
  return { dateTime: composeDate(v.startDate, v.startTime).toISOString(), timeZone: tz };
}

function toEndPart(v: EventFormValues, tz: string): EventTimePart {
  if (v.allDay) return { date: shiftDateStr(v.endDate, 1) }; // exclusive
  return { dateTime: composeDate(v.endDate, v.endTime).toISOString(), timeZone: tz };
}

export function validateForm(v: EventFormValues): string | null {
  if (!v.title.trim()) return 'Title is required';
  if (v.allDay) {
    if (composeDate(v.endDate, '00:00') < composeDate(v.startDate, '00:00')) {
      return 'End date must be on or after the start date';
    }
    return null;
  }
  if (composeDate(v.endDate, v.endTime).getTime() <= composeDate(v.startDate, v.startTime).getTime()) {
    return 'End must be after start';
  }
  return null;
}

export function buildCreatePayload(v: EventFormValues, calendarId = 'primary') {
  const tz = getLocalTimeZone();
  return {
    calendarId,
    summary: v.title.trim(),
    description: v.description.trim() || undefined,
    location: v.location.trim() || undefined,
    start: toStartPart(v, tz),
    end: toEndPart(v, tz),
  };
}

export function buildUpdatePatch(v: EventFormValues) {
  const tz = getLocalTimeZone();
  return {
    summary: v.title.trim(),
    description: v.description.trim() || undefined,
    location: v.location.trim() || undefined,
    start: toStartPart(v, tz),
    end: toEndPart(v, tz),
  };
}

export interface EventLike {
  title: string;
  description: string | null;
  location: string | null;
  startTime: string; // ISO datetime OR YYYY-MM-DD (all-day)
  endTime: string;
  allDay: boolean;
}

export function eventToFormValues(e: EventLike): EventFormValues {
  if (e.allDay) {
    return {
      title: e.title === '(No title)' ? '' : e.title,
      allDay: true,
      startDate: e.startTime.slice(0, 10),
      startTime: '00:00',
      endDate: shiftDateStr(e.endTime.slice(0, 10), -1), // exclusive -> inclusive
      endTime: '00:00',
      location: e.location ?? '',
      description: e.description ?? '',
    };
  }
  const start = parseISO(e.startTime);
  const end = parseISO(e.endTime);
  return {
    title: e.title === '(No title)' ? '' : e.title,
    allDay: false,
    startDate: format(start, DATE_FMT),
    startTime: format(start, 'HH:mm'),
    endDate: format(end, DATE_FMT),
    endTime: format(end, 'HH:mm'),
    location: e.location ?? '',
    description: e.description ?? '',
  };
}

export function bumpEndAfterStart(v: EventFormValues): EventFormValues {
  if (v.allDay) {
    if (composeDate(v.endDate, '00:00') < composeDate(v.startDate, '00:00')) {
      return { ...v, endDate: v.startDate };
    }
    return v;
  }
  const start = composeDate(v.startDate, v.startTime);
  const end = composeDate(v.endDate, v.endTime);
  if (end.getTime() <= start.getTime()) {
    const bumped = new Date(start.getTime() + 60 * 60 * 1000);
    return { ...v, endDate: format(bumped, DATE_FMT), endTime: format(bumped, 'HH:mm') };
  }
  return v;
}

export function emptyFormValues(prefill?: { start?: Date; end?: Date; allDay?: boolean }): EventFormValues {
  const start = prefill?.start ?? new Date();
  const end = prefill?.end ?? new Date(start.getTime() + 60 * 60 * 1000);
  return {
    title: '',
    allDay: prefill?.allDay ?? false,
    startDate: format(start, DATE_FMT),
    startTime: format(start, 'HH:mm'),
    endDate: format(end, DATE_FMT),
    endTime: format(end, 'HH:mm'),
    location: '',
    description: '',
  };
}
```

- [ ] **Step 4: Run to verify it passes**

Run:
```bash
pnpm --filter=@zero/web test lib/calendar-event-form.test.ts
```
Expected: PASS (all describe blocks green).

- [ ] **Step 5: Commit**
```bash
git add apps/web/lib/calendar-event-form.ts apps/web/lib/calendar-event-form.test.ts
git commit -m "feat(web/calendar): pure event form<->payload helpers with tests"
```

---

## Task 2: EventEditDialog component

**Files:**
- Create: `apps/web/components/calendar/event-edit-dialog.tsx`

- [ ] **Step 1: Implement the dialog**

Create `apps/web/components/calendar/event-edit-dialog.tsx`:
```tsx
/**
 * Create/edit a calendar event. Pure logic lives in
 * `@/lib/calendar-event-form`; this is the form shell. Primary calendar only
 * (workstream A1) — calendar picker arrives with multi-calendar visibility (A2).
 */
import { useEffect, useState } from 'react';
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { Trash2, Loader2 } from 'lucide-react';
import { toast } from 'sonner';
import {
  type EventFormValues,
  bumpEndAfterStart,
  validateForm,
} from '@/lib/calendar-event-form';

export type EventDialogMode = 'create' | 'edit';

interface EventEditDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  mode: EventDialogMode;
  initialValues: EventFormValues;
  readOnly?: boolean;
  saving?: boolean;
  deleting?: boolean;
  onSave: (values: EventFormValues) => void;
  onDelete?: () => void;
}

export function EventEditDialog({
  open,
  onOpenChange,
  mode,
  initialValues,
  readOnly = false,
  saving = false,
  deleting = false,
  onSave,
  onDelete,
}: EventEditDialogProps) {
  const [values, setValues] = useState<EventFormValues>(initialValues);

  // Reset the form whenever the dialog (re)opens with new initial values.
  useEffect(() => {
    if (open) setValues(initialValues);
  }, [open, initialValues]);

  const set = <K extends keyof EventFormValues>(key: K, value: EventFormValues[K]) =>
    setValues((prev) => ({ ...prev, [key]: value }));

  const handleStartChange = (key: 'startDate' | 'startTime', value: string) => {
    setValues((prev) => bumpEndAfterStart({ ...prev, [key]: value }));
  };

  const handleSave = () => {
    const error = validateForm(values);
    if (error) {
      toast.error(error);
      return;
    }
    onSave(values);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[440px]">
        <DialogHeader>
          <DialogTitle className="text-[15px]">
            {mode === 'create' ? 'New event' : readOnly ? 'Event' : 'Edit event'}
          </DialogTitle>
        </DialogHeader>

        <div className="flex flex-col gap-3 py-1">
          <Input
            autoFocus={!readOnly}
            disabled={readOnly}
            value={values.title}
            onChange={(e) => set('title', e.target.value)}
            placeholder="Add a title"
            aria-label="Event title"
          />

          <div className="flex items-center justify-between">
            <Label htmlFor="all-day" className="text-[13px]">
              All day
            </Label>
            <Switch
              id="all-day"
              disabled={readOnly}
              checked={values.allDay}
              onCheckedChange={(checked) => setValues((prev) => bumpEndAfterStart({ ...prev, allDay: checked }))}
            />
          </div>

          <div className="grid grid-cols-2 gap-2">
            <div className="flex flex-col gap-1">
              <Label className="text-muted-foreground text-[11px]">Starts</Label>
              <Input
                type="date"
                disabled={readOnly}
                value={values.startDate}
                onChange={(e) => handleStartChange('startDate', e.target.value)}
                aria-label="Start date"
              />
              {!values.allDay && (
                <Input
                  type="time"
                  disabled={readOnly}
                  value={values.startTime}
                  onChange={(e) => handleStartChange('startTime', e.target.value)}
                  aria-label="Start time"
                />
              )}
            </div>
            <div className="flex flex-col gap-1">
              <Label className="text-muted-foreground text-[11px]">Ends</Label>
              <Input
                type="date"
                disabled={readOnly}
                value={values.endDate}
                onChange={(e) => set('endDate', e.target.value)}
                aria-label="End date"
              />
              {!values.allDay && (
                <Input
                  type="time"
                  disabled={readOnly}
                  value={values.endTime}
                  onChange={(e) => set('endTime', e.target.value)}
                  aria-label="End time"
                />
              )}
            </div>
          </div>

          <Input
            disabled={readOnly}
            value={values.location}
            onChange={(e) => set('location', e.target.value)}
            placeholder="Location (optional)"
            aria-label="Location"
          />
          <Textarea
            disabled={readOnly}
            value={values.description}
            onChange={(e) => set('description', e.target.value)}
            placeholder="Notes (optional)"
            rows={3}
            aria-label="Notes"
          />
        </div>

        <DialogFooter className="flex items-center justify-between gap-2 sm:justify-between">
          {mode === 'edit' && onDelete && !readOnly ? (
            <Button
              variant="ghost"
              size="sm"
              className="text-destructive hover:text-destructive"
              onClick={onDelete}
              disabled={deleting || saving}
            >
              {deleting ? <Loader2 className="h-4 w-4 animate-spin" /> : <Trash2 className="h-4 w-4" />}
            </Button>
          ) : (
            <span />
          )}
          <div className="flex items-center gap-2">
            <Button variant="outline" size="sm" onClick={() => onOpenChange(false)}>
              {readOnly ? 'Close' : 'Cancel'}
            </Button>
            {!readOnly && (
              <Button size="sm" onClick={handleSave} disabled={saving || deleting}>
                {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : mode === 'create' ? 'Create' : 'Save'}
              </Button>
            )}
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
```

- [ ] **Step 2: Verify it typechecks**

Run:
```bash
pnpm --filter=@zero/web exec tsc --noEmit
```
Expected: no errors referencing `event-edit-dialog.tsx`. (If `Textarea`/`Switch`/`Label` import paths differ, fix to match the actual files in `apps/web/components/ui/`.)

- [ ] **Step 3: Commit**
```bash
git add apps/web/components/calendar/event-edit-dialog.tsx
git commit -m "feat(web/calendar): EventEditDialog (create/edit/delete/read-only)"
```

---

## Task 3: Wire mutations + dialog into the calendar page

**Files:**
- Modify: `apps/web/app/(routes)/mail/calendar/page.tsx`

- [ ] **Step 1: Add imports**

At the top of `page.tsx`, add:
```tsx
import { EventEditDialog, type EventDialogMode } from '@/components/calendar/event-edit-dialog';
import {
  type EventFormValues,
  buildCreatePayload,
  buildUpdatePatch,
  eventToFormValues,
  emptyFormValues,
} from '@/lib/calendar-event-form';
```

- [ ] **Step 2: Add dialog state + mutations inside `CalendarPage`**

After the existing `createTask` mutation block, add:
```tsx
  // ── Event editor state ──────────────────────────────────────────────────────
  const [eventDialog, setEventDialog] = useState<{
    open: boolean;
    mode: EventDialogMode;
    eventId: string | null;
    values: EventFormValues;
  }>({ open: false, mode: 'create', eventId: null, values: emptyFormValues() });

  const invalidateEvents = useCallback(() => {
    queryClient.invalidateQueries({ queryKey: trpc.calendar.events.queryKey() });
  }, [queryClient, trpc]);

  const createEvent = useMutation({
    ...trpc.calendar.createEvent.mutationOptions(),
    onSuccess: () => {
      invalidateEvents();
      setEventDialog((p) => ({ ...p, open: false }));
      toast.success('Event created');
    },
    onError: (err) => toast.error(err instanceof Error ? err.message : 'Could not create event'),
  });

  const updateEvent = useMutation({
    ...trpc.calendar.updateEvent.mutationOptions(),
    onSuccess: () => {
      invalidateEvents();
      setEventDialog((p) => ({ ...p, open: false }));
      toast.success('Event updated');
    },
    onError: (err) => toast.error(err instanceof Error ? err.message : 'Could not update event'),
  });

  const deleteEvent = useMutation({
    ...trpc.calendar.deleteEvent.mutationOptions(),
    onSuccess: () => {
      invalidateEvents();
      setEventDialog((p) => ({ ...p, open: false }));
      toast.success('Event deleted');
    },
    onError: (err) => toast.error(err instanceof Error ? err.message : 'Could not delete event'),
  });

  const openCreateEvent = useCallback((start?: Date, end?: Date) => {
    setEventDialog({ open: true, mode: 'create', eventId: null, values: emptyFormValues({ start, end }) });
  }, []);

  const openEditEvent = useCallback(
    (eventId: string) => {
      const ev = calendarEvents.find((e) => e.id === eventId);
      if (!ev) return;
      setEventDialog({
        open: true,
        mode: 'edit',
        eventId,
        values: eventToFormValues({
          title: ev.title,
          description: ev.description,
          location: ev.location,
          startTime: ev.startTime,
          endTime: ev.endTime,
          allDay: ev.allDay,
        }),
      });
    },
    [calendarEvents],
  );

  const handleSaveEvent = useCallback(
    (values: EventFormValues) => {
      if (eventDialog.mode === 'create') {
        createEvent.mutate(buildCreatePayload(values, 'primary'));
      } else if (eventDialog.eventId) {
        updateEvent.mutate({ calendarId: 'primary', eventId: eventDialog.eventId, patch: buildUpdatePatch(values) });
      }
    },
    [eventDialog.mode, eventDialog.eventId, createEvent, updateEvent],
  );
```

> Note: `CalendarEvent` (the page's `Outputs['calendar']['events']['events'][number]`) includes `description` and `location` — confirm by hovering the type; they are part of the server output object. If TypeScript complains, the fields are present in `apps/server/src/trpc/routes/calendar.ts` event mapping.

- [ ] **Step 3: Replace `onCreateAt` to open the event dialog**

The grid's `onCreateAt(start, end)` currently focuses the task quick-add. Change the prop passed to `<CalendarGrid>` from `onCreateAt={handleCreateAt}` to:
```tsx
                onCreateAt={(start, end) => openCreateEvent(start, end)}
                onEventClick={openEditEvent}
```
(Keep `handleCreateAt` removed only if now unused — if the left-rail still references it, leave it; otherwise delete the now-dead `handleCreateAt`/`quickAddPulse` only if nothing else uses them. The left-rail task quick-add input stays as-is for task creation.)

- [ ] **Step 4: Add a "New event" button in the header**

In the header `div` next to the view-mode switcher (around the `role="group"` switcher), add before it:
```tsx
        <Button size="sm" variant="outline" className="h-7 text-[12px]" onClick={() => openCreateEvent()}>
          <Plus className="mr-1 h-3.5 w-3.5" /> New event
        </Button>
```
(`Plus` and `Button` are already imported.)

- [ ] **Step 5: Render the dialog before the closing root `</div>`**

Just before the final `</div>` of the component's return, add:
```tsx
      <EventEditDialog
        open={eventDialog.open}
        onOpenChange={(open) => setEventDialog((p) => ({ ...p, open }))}
        mode={eventDialog.mode}
        initialValues={eventDialog.values}
        readOnly={scopeMissing}
        saving={createEvent.isPending || updateEvent.isPending}
        deleting={deleteEvent.isPending}
        onSave={handleSaveEvent}
        onDelete={
          eventDialog.eventId
            ? () => deleteEvent.mutate({ calendarId: 'primary', eventId: eventDialog.eventId! })
            : undefined
        }
      />
```

- [ ] **Step 6: Typecheck**

Run:
```bash
pnpm --filter=@zero/web exec tsc --noEmit
```
Expected: no errors. Fix any type mismatches (e.g., `trpc.calendar.events.queryKey()` — if the helper differs, use the project's standard invalidation: `queryClient.invalidateQueries({ queryKey: trpc.calendar.events.queryKey({ timeMin: eventsTimeMin, timeMax: eventsTimeMax }) })` or the partial-key form the codebase already uses elsewhere).

- [ ] **Step 7: Commit**
```bash
git add "apps/web/app/(routes)/mail/calendar/page.tsx"
git commit -m "feat(web/calendar): wire event create/edit/delete dialog into calendar page"
```

---

## Task 4: Manual verification + build

**Files:** none (verification only)

- [ ] **Step 1: Build the web app**

Run:
```bash
pnpm --filter=@zero/web build
```
Expected: build succeeds.

- [ ] **Step 2: Run the unit tests once more**

Run:
```bash
pnpm --filter=@zero/web test
```
Expected: PASS.

- [ ] **Step 3: Manual smoke (document results)**

Start the stack (`pnpm dev`), open `/mail/calendar`, and verify against the acceptance criteria in the spec:
1. "New event" button → dialog → Create → event appears after refetch.
2. Tap an empty grid slot → create dialog prefilled with that time.
3. Click an existing event → edit → Save → change persists.
4. Delete from the edit dialog (trash) → event disappears.
5. Toggle "All day" → date-only fields; created all-day event spans the correct day (no off-by-one).
6. Task quick-add (left rail) still creates tasks — unchanged.
7. With `scopeMissing`, the dialog opens read-only and the connect CTA still shows.

Record pass/fail for each in the PR description. (No automated DOM test — `apps/web` has no jsdom harness; logic is covered by Task 1 unit tests.)

---

## Task 5: Docs

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `FEATURES.md`
- Modify: `docs/superpowers/specs/2026-06-13-web-native-parity-MASTER-design.md` (mark A1 done)

- [ ] **Step 1: Update CHANGELOG `[Unreleased]`**
Add: `- web(calendar): create/edit/delete Google Calendar events from /mail/calendar (primary calendar). Closes parity workstream A1.`

- [ ] **Step 2: Update FEATURES.md** calendar row to note event CRUD on web.

- [ ] **Step 3: Mark A1 done** in the master spec table (Calendar row → status: A1 shipped; A2 multi-calendar visibility pending).

- [ ] **Step 4: Commit**
```bash
git add CHANGELOG.md FEATURES.md docs/superpowers/specs/2026-06-13-web-native-parity-MASTER-design.md
git commit -m "docs: record web calendar event CRUD (parity A1)"
```

---

## Self-Review notes

- **Spec coverage:** event create ✅ (T2/T3), edit ✅, delete ✅, all-day correctness ✅ (T1 tests), scopeMissing read-only ✅ (T3 step 5), task-quick-add regression guard ✅ (T4 step 3.6). Multi-calendar visibility + read-only-calendar picker + non-primary/multi-connection editing are **explicitly deferred to plan A2** (server-shape change required) — noted in spec "Out of scope" + master table.
- **Placeholders:** none — all steps contain runnable commands and complete code.
- **Type consistency:** `EventFormValues`, `buildCreatePayload`, `buildUpdatePatch`, `eventToFormValues`, `emptyFormValues`, `bumpEndAfterStart`, `validateForm` are defined in Task 1 and used identically in Tasks 2–3. `EventDialogMode` defined in Task 2, used in Task 3.
- **Known verification caveats to resolve during execution:** exact tRPC query-key invalidation helper (`trpc.calendar.events.queryKey(...)`) and shadcn import paths for `Textarea`/`Switch`/`Label` — adjust to match the repo if tsc flags them (Task 2 Step 2 / Task 3 Step 6 call this out).
