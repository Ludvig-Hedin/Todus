/**
 * Calendar page — tasks + Google Calendar events with full Day/Week/Month/Year
 * surface powered by `<CalendarGrid>` (matches the macOS calendar parity).
 *
 * Left panel: month picker + week overview + (optional) Google Calendar reconnect CTA.
 * Right panel: segmented Day/Week/Month/Year switcher → `<CalendarGrid>`.
 * If the user's Google token lacks `calendar.readonly`, a "Connect Google Calendar"
 * prompt appears in the left rail; the grid still renders (showing tasks only).
 *
 * View mode persists to localStorage('calendar.viewMode').
 */
import {
  format,
  isSameDay,
  startOfWeek,
  endOfWeek,
  addDays,
  isToday,
  startOfMonth,
  endOfMonth,
  startOfYear,
  endOfYear,
} from 'date-fns';
import {
  CalendarIcon,
  Plus,
  RefreshCw,
  Loader2,
  CalendarDays,
  CalendarRange,
  LayoutGrid,
  Grid3X3,
} from 'lucide-react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useState, useMemo, useRef, useCallback, useEffect } from 'react';
import { Separator } from '@/components/ui/separator';
import { useTRPC } from '@/providers/query-provider';
import { BackgroundRefreshIndicator } from '@/components/ui/background-refresh-indicator';
import { Calendar } from '@/components/ui/calendar';
import type { Outputs } from '@zero/server/trpc';
import { Button } from '@/components/ui/button';
import { authClient } from '@/lib/auth-client';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { authProxy } from '@/lib/auth-proxy';
import type { Route } from './+types/page';
import { redirect } from 'react-router';
import { cn } from '@/lib/utils';
import { upsertTaskInTaskCaches } from '@/lib/task-cache';
import { parseEventStart } from '@/lib/calendar-utils';
import { toast } from 'sonner';
import {
  CalendarGrid,
  type CalendarGridMode,
} from '@/components/calendar/calendar-grid';
import { EventEditDialog, type EventDialogMode } from '@/components/calendar/event-edit-dialog';
import {
  type EventFormValues,
  buildCreatePayload,
  buildUpdatePatch,
  eventToFormValues,
  emptyFormValues,
} from '@/lib/calendar-event-form';

type CalendarEvent = Outputs['calendar']['events']['events'][number];

// Auth guard
export async function clientLoader({ request }: Route.ClientLoaderArgs) {
  const session = await authProxy.api.getSession({ headers: request.headers });
  if (!session) throw redirect('/login');
  return {};
}

const VIEW_MODE_KEY = 'calendar.viewMode';
const VIEW_MODES: readonly CalendarGridMode[] = ['day', 'week', 'month', 'year'] as const;
const VIEW_MODE_ICONS: Record<CalendarGridMode, typeof CalendarDays> = {
  day: CalendarDays,
  week: CalendarRange,
  month: LayoutGrid,
  year: Grid3X3,
};
const VIEW_MODE_LABELS: Record<CalendarGridMode, string> = {
  day: 'Day',
  week: 'Week',
  month: 'Month',
  year: 'Year',
};

function readViewModePref(): CalendarGridMode {
  if (typeof window === 'undefined') return 'week';
  try {
    const raw = localStorage.getItem(VIEW_MODE_KEY);
    if (raw && (VIEW_MODES as readonly string[]).includes(raw)) {
      return raw as CalendarGridMode;
    }
  } catch {
    // ignore (private mode)
  }
  return 'week';
}

export default function CalendarPage() {
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const [selectedDate, setSelectedDate] = useState<Date>(new Date());
  // The displayed month — controls which range we fetch calendar events for
  const [displayMonth, setDisplayMonth] = useState<Date>(new Date());
  const [viewMode, setViewModeState] = useState<CalendarGridMode>(() => readViewModePref());
  const setViewMode = useCallback((mode: CalendarGridMode) => {
    setViewModeState(mode);
    if (typeof window !== 'undefined') {
      try {
        localStorage.setItem(VIEW_MODE_KEY, mode);
      } catch {
        // ignore
      }
    }
  }, []);

  // Inline quick-add state
  const [quickAdd, setQuickAdd] = useState('');
  const quickAddRef = useRef<HTMLInputElement>(null);

  // ── Tasks ──────────────────────────────────────────────────────────────────
  const { data: tasksData, isLoading: tasksLoading, isFetching: isFetchingTasks } = useQuery(
    trpc.tasks.list.queryOptions(
      { limit: 500 },
      {
        staleTime: 1000 * 60 * 5,
        refetchOnMount: false,
      },
    ),
  );
  const tasks = useMemo(() => tasksData?.tasks ?? [], [tasksData]);

  // ── Google Calendar events ─────────────────────────────────────────────────
  // Fetch range is widened in Year mode so the grid can show event markers
  // across every month. For Day/Week/Month we union the displayed month with
  // the visible week to catch adjacent-month days in the left-rail overview.
  const visibleWeekStart = startOfWeek(new Date(), { weekStartsOn: 1 });
  const visibleWeekEnd = endOfWeek(new Date(), { weekStartsOn: 1 });
  const { eventsTimeMin, eventsTimeMax } = useMemo(() => {
    if (viewMode === 'year') {
      return {
        eventsTimeMin: startOfYear(selectedDate).toISOString(),
        eventsTimeMax: endOfYear(selectedDate).toISOString(),
      };
    }
    const monthStart = startOfMonth(displayMonth);
    const monthEnd = endOfMonth(displayMonth);
    return {
      eventsTimeMin:
        (monthStart < visibleWeekStart ? monthStart : visibleWeekStart).toISOString(),
      eventsTimeMax: (monthEnd > visibleWeekEnd ? monthEnd : visibleWeekEnd).toISOString(),
    };
  }, [viewMode, selectedDate, displayMonth, visibleWeekStart, visibleWeekEnd]);

  const { data: eventsData, isLoading: eventsLoading, isFetching: isFetchingEvents } = useQuery(
    trpc.calendar.events.queryOptions(
      {
        timeMin: eventsTimeMin,
        timeMax: eventsTimeMax,
      },
      {
        staleTime: 1000 * 60 * 3,
        refetchOnMount: false,
      },
    ),
  );
  const calendarEvents = useMemo<CalendarEvent[]>(() => eventsData?.events ?? [], [eventsData]);
  // scopeMissing = true means the token lacks calendar.readonly (needs re-auth)
  const scopeMissing = eventsData?.scopeMissing ?? false;

  // Keep displayMonth in sync when selectedDate jumps to a different month
  // (e.g. user clicked an out-of-month day in the grid). Deps intentionally
  // exclude `displayMonth` — including it would re-fire this effect after the
  // user navigates the picker manually (via onMonthChange) and snap the view
  // back to selectedDate's month, breaking month pagination.
  useEffect(() => {
    if (
      selectedDate.getFullYear() !== displayMonth.getFullYear() ||
      selectedDate.getMonth() !== displayMonth.getMonth()
    ) {
      setDisplayMonth(selectedDate);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedDate]);

  // ── Mutations ──────────────────────────────────────────────────────────────
  const createTask = useMutation({
    ...trpc.tasks.create.mutationOptions(),
    onSuccess: ({ task }) => {
      upsertTaskInTaskCaches(queryClient, task);
      setQuickAdd('');
      quickAddRef.current?.focus();
    },
    onError: (err) => {
      console.error('Failed to create task:', err);
      toast.error(err instanceof Error ? err.message : 'Could not add task');
    },
  });

  // ── Event editor (create / edit / delete on the primary calendar) ────────────
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
    setEventDialog({
      open: true,
      mode: 'create',
      eventId: null,
      values: emptyFormValues({ start, end }),
    });
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
        updateEvent.mutate({
          calendarId: 'primary',
          eventId: eventDialog.eventId,
          patch: buildUpdatePatch(values),
        });
      }
    },
    [eventDialog.mode, eventDialog.eventId, createEvent, updateEvent],
  );

  // ── Derived data ───────────────────────────────────────────────────────────

  // Dates that have tasks — for calendar underline highlights
  const datesWithTasks = useMemo(() => {
    const set = new Set<string>();
    for (const task of tasks) {
      if (task.dueDate) set.add(format(new Date(task.dueDate), 'yyyy-MM-dd'));
    }
    return set;
  }, [tasks]);

  // Local-timezone safe event-start parser is now shared with the
  // CalendarGrid component via `@/lib/calendar-utils` — keep one definition
  // so the all-day-UTC-drift fix can't regress in only one place.

  // Dates that have calendar events
  const datesWithEvents = useMemo(() => {
    const set = new Set<string>();
    for (const event of calendarEvents) {
      if (event.startTime) {
        set.add(format(parseEventStart(event), 'yyyy-MM-dd'));
      }
    }
    return set;
  }, [calendarEvents, parseEventStart]);

  // This week overview (Mon–Sun)
  const weekDaysOverview = useMemo(() => {
    const start = startOfWeek(new Date(), { weekStartsOn: 1 });
    return Array.from({ length: 7 }, (_, i) => {
      const day = addDays(start, i);
      const key = format(day, 'yyyy-MM-dd');
      const dayTasks = tasks.filter((t) => t.dueDate && isSameDay(new Date(t.dueDate), day));
      const hasEvent = datesWithEvents.has(key);
      return { day, tasks: dayTasks, hasEvent };
    });
  }, [tasks, datesWithEvents]);

  const handleQuickAdd = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key !== 'Enter') return;
    const title = quickAdd.trim();
    if (!title) return;
    createTask.mutate({
      title,
      status: 'todo',
      priority: 'none',
      dueDate: selectedDate.toISOString(),
      folderId: null,
    });
  };

  const handleConnectGoogleCalendar = useCallback(async () => {
    try {
      await authClient.linkSocial({
        provider: 'google',
        callbackURL: window.location.href,
      });
    } catch (error) {
      console.error('Failed to connect Google Calendar:', error);
      toast.error('Could not connect Google Calendar.');
    }
  }, []);

  // Adapt the tRPC events to CalendarGrid's event shape. CalendarGrid expects
  // optional fields so we just narrow types — the real shape is a strict superset.
  const gridEvents = useMemo(
    () =>
      calendarEvents.map((e) => ({
        id: e.id,
        title: e.title,
        startTime: e.startTime,
        endTime: e.endTime,
        allDay: e.allDay,
        color: e.color,
      })),
    [calendarEvents],
  );

  const selectedDateLabel = isToday(selectedDate) ? 'Today' : format(selectedDate, 'EEEE, MMMM d');
  const isBackgroundRefreshing =
    (!!tasksData && !tasksLoading && isFetchingTasks) ||
    (!!eventsData && !eventsLoading && isFetchingEvents);

  return (
    <div className="bg-background flex h-screen flex-col overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between border-b px-6 py-3.5">
        <div className="flex items-center gap-2.5">
          <h1 className="text-[15px] font-semibold">Calendar</h1>
          {isBackgroundRefreshing ? (
            <BackgroundRefreshIndicator label="Updating calendar" />
          ) : null}
          {scopeMissing && (
            <span className="rounded-full bg-yellow-100 px-2 py-0.5 text-[11px] font-medium text-yellow-700 dark:bg-yellow-950/40 dark:text-yellow-400">
              Events need permission
            </span>
          )}
        </div>

        <div className="flex items-center gap-2">
          <Button
            size="sm"
            variant="outline"
            className="h-7 text-[12px]"
            onClick={() => openCreateEvent()}
          >
            <Plus className="mr-1 h-3.5 w-3.5" /> New event
          </Button>
          {/* Day / Week / Month / Year switcher — mirrors the iOS segmented control */}
          <div
            className="bg-muted/50 flex items-center gap-0.5 rounded-lg border p-0.5"
            role="group"
            aria-label="Calendar view mode"
          >
          {VIEW_MODES.map((mode) => {
            const Icon = VIEW_MODE_ICONS[mode];
            const active = viewMode === mode;
            return (
              <button
                key={mode}
                type="button"
                onClick={() => setViewMode(mode)}
                aria-pressed={active}
                aria-label={`${VIEW_MODE_LABELS[mode]} view`}
                className={cn(
                  'flex items-center gap-1 rounded-md px-2.5 py-1 text-[12px] font-medium transition-colors',
                  'focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring',
                  active
                    ? 'bg-background text-foreground shadow-sm'
                    : 'text-muted-foreground hover:text-foreground',
                )}
              >
                <Icon className="h-3.5 w-3.5" />
                <span className="hidden sm:inline">{VIEW_MODE_LABELS[mode]}</span>
              </button>
            );
          })}
          </div>
        </div>
      </div>

      <div className="flex flex-1 overflow-hidden">
        {/* ── Left: Calendar picker + week overview ─────────────────────── */}
        <div className="flex w-[288px] shrink-0 flex-col overflow-y-auto border-r p-4">
          <Calendar
            mode="single"
            selected={selectedDate}
            onSelect={(d) => d && setSelectedDate(d)}
            month={displayMonth}
            onMonthChange={setDisplayMonth}
            modifiers={{
              hasTasks: (date) => datesWithTasks.has(format(date, 'yyyy-MM-dd')),
              hasEvents: (date) => datesWithEvents.has(format(date, 'yyyy-MM-dd')),
            }}
            modifiersClassNames={{
              hasTasks: 'font-bold underline decoration-primary decoration-2',
              hasEvents: 'ring-1 ring-inset ring-blue-400/60',
            }}
            className="rounded-xl"
          />

          <Separator className="my-3" />

          {/* Quick-add row — always visible, prefills due date to selected day */}
          <div className="bg-card mb-3 flex items-center gap-2 rounded-xl border px-3 py-2">
            {createTask.isPending ? (
              <Loader2 className="text-muted-foreground h-4 w-4 shrink-0 animate-spin" aria-hidden />
            ) : (
              <Plus className="text-muted-foreground h-4 w-4 shrink-0" aria-hidden />
            )}
            <Input
              ref={quickAddRef}
              value={quickAdd}
              onChange={(e) => setQuickAdd(e.target.value)}
              onKeyDown={handleQuickAdd}
              placeholder={`Add for ${isToday(selectedDate) ? 'today' : format(selectedDate, 'MMM d')}…`}
              className="h-auto border-0 bg-transparent p-0 text-[12px] shadow-none focus-visible:ring-0"
              disabled={createTask.isPending}
              aria-label="Add task to selected day"
            />
          </div>

          {/* This week overview */}
          <div>
            <p className="text-muted-foreground mb-2 text-[11px] font-semibold uppercase tracking-wide">
              This week
            </p>
            <div className="flex flex-col gap-0.5">
              {weekDaysOverview.map(({ day, tasks: dayTasks, hasEvent }) => (
                <button
                  key={day.toISOString()}
                  type="button"
                  onClick={() => setSelectedDate(day)}
                  className={cn(
                    'hover:bg-accent flex items-center justify-between rounded-lg px-2 py-1.5 text-left text-[13px] transition-colors',
                    isSameDay(day, selectedDate) && 'bg-accent font-medium',
                    isToday(day) && 'text-[var(--mainBlue)]',
                  )}
                >
                  <span>{format(day, 'EEE, MMM d')}</span>
                  <div className="flex items-center gap-1">
                    {hasEvent && (
                      <span className="h-1.5 w-1.5 rounded-full bg-[var(--mainBlue)]" />
                    )}
                    {dayTasks.length > 0 && (
                      <Badge variant="secondary" className="h-4 min-w-[1rem] px-1 text-[10px]">
                        {dayTasks.length}
                      </Badge>
                    )}
                  </div>
                </button>
              ))}
            </div>
          </div>

          {/* Google Calendar scope notice — shown only when auth re-needed */}
          {scopeMissing && (
            <>
              <Separator className="my-3" />
              <div className="bg-muted/20 flex flex-col gap-3 rounded-lg border border-dashed px-3 py-3">
                <div className="flex items-start gap-2.5">
                  <CalendarIcon className="text-muted-foreground/60 mt-0.5 h-4 w-4 shrink-0" />
                  <div className="min-w-0 flex-1">
                    <p className="text-muted-foreground text-[12px] font-medium leading-tight">
                      Google Calendar needs permission
                    </p>
                    <p className="text-muted-foreground/70 mt-0.5 text-[11px] leading-snug">
                      Re-connect your Google account to grant calendar access.
                    </p>
                  </div>
                </div>
                <Button
                  size="sm"
                  variant="outline"
                  className="w-full text-[12px]"
                  onClick={handleConnectGoogleCalendar}
                >
                  <RefreshCw className="mr-1.5 h-3 w-3" />
                  Connect Google Calendar
                </Button>
              </div>
            </>
          )}
        </div>

        {/* ── Right: Calendar grid (Day / Week / Month / Year) ─────────── */}
        <div className="flex flex-1 flex-col overflow-hidden">
          {/* Selected-day header — kept so users always see what's focused */}
          <div className="flex items-center gap-2 border-b px-6 py-2.5">
            <CalendarIcon className="text-muted-foreground h-4 w-4" />
            <h2 className="text-[14px] font-semibold">{selectedDateLabel}</h2>
          </div>

          <div className="flex-1 overflow-hidden">
            {/* Skeleton while EITHER data set is still loading — previously the
                && gate left an empty grid flicker when events finished first
                but tasks were still in flight. */}
            {eventsLoading || tasksLoading ? (
              <div className="flex flex-col gap-2 p-6">
                {['calendar-skeleton-1', 'calendar-skeleton-2', 'calendar-skeleton-3'].map((key) => (
                  <div key={key} className="bg-muted/50 h-16 animate-pulse rounded-xl" />
                ))}
              </div>
            ) : (
              <CalendarGrid
                mode={viewMode}
                events={gridEvents}
                tasks={tasks.map((t) => ({
                  id: t.id,
                  title: t.title,
                  dueDate: t.dueDate,
                  status: t.status,
                }))}
                selectedDate={selectedDate}
                onSelectDate={setSelectedDate}
                onModeChange={setViewMode}
                onCreateAt={(start, end) => openCreateEvent(start, end)}
                onEventClick={openEditEvent}
              />
            )}
          </div>
        </div>
      </div>

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
    </div>
  );
}
