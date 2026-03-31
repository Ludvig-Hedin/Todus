/**
 * Calendar page — tasks + real Google Calendar events.
 *
 * Left panel: month calendar picker with task/event count badges on dates.
 * Right panel: Google Calendar events + tasks for the selected date.
 * If the user's Google token lacks the `calendar.readonly` scope (older auth),
 * a "Connect Google Calendar" prompt appears instead of events.
 */
import { useState, useMemo, useRef, useCallback } from 'react';
import { Link } from 'react-router';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  format,
  isSameDay,
  startOfWeek,
  addDays,
  isToday,
  startOfMonth,
  endOfMonth,
  addMonths,
  subMonths,
} from 'date-fns';
import {
  CalendarIcon,
  CheckCircle2,
  Circle,
  Plus,
  Clock,
  MapPin,
  RefreshCw,
} from 'lucide-react';
import { useTRPC } from '@/providers/query-provider';
import { authClient } from '@/lib/auth-client';
import { authProxy } from '@/lib/auth-proxy';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Calendar } from '@/components/ui/calendar';
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import { cn } from '@/lib/utils';
import type { Route } from './+types/page';
import type { Outputs } from '@zero/server/trpc';

type Task = Outputs['tasks']['list']['tasks'][number];
type CalendarEvent = Outputs['calendar']['events']['events'][number];

// Auth guard
export async function clientLoader({ request }: Route.ClientLoaderArgs) {
  const session = await authProxy.api.getSession({ headers: request.headers });
  if (!session) return Response.redirect(`${import.meta.env.VITE_PUBLIC_APP_URL}/login`);
  return {};
}

const PRIORITY_CLASS: Record<string, string> = {
  high: 'bg-red-50 text-red-600 dark:bg-red-950/30 dark:text-red-400',
  medium: 'bg-yellow-50 text-yellow-600 dark:bg-yellow-950/30 dark:text-yellow-400',
  low: 'bg-blue-50 text-blue-600 dark:bg-blue-950/30 dark:text-blue-400',
};

export default function CalendarPage() {
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const [selectedDate, setSelectedDate] = useState<Date>(new Date());
  // The displayed month — controls which range we fetch calendar events for
  const [displayMonth, setDisplayMonth] = useState<Date>(new Date());

  // Inline quick-add state
  const [quickAdd, setQuickAdd] = useState('');
  const quickAddRef = useRef<HTMLInputElement>(null);

  // ── Tasks ──────────────────────────────────────────────────────────────────
  const { data: tasksData, isLoading: tasksLoading } = useQuery(
    trpc.tasks.list.queryOptions({ limit: 500 }),
  );
  const tasks = tasksData?.tasks ?? [];

  // ── Google Calendar events ─────────────────────────────────────────────────
  // Fetch events for the displayed month ±1 day buffer so day-boundary edge
  // cases don't drop events. Refetches automatically when displayMonth changes.
  const eventsTimeMin = startOfMonth(displayMonth).toISOString();
  const eventsTimeMax = endOfMonth(displayMonth).toISOString();

  const { data: eventsData, isLoading: eventsLoading } = useQuery(
    trpc.calendar.events.queryOptions({
      timeMin: eventsTimeMin,
      timeMax: eventsTimeMax,
    }),
  );
  const calendarEvents: CalendarEvent[] = eventsData?.events ?? [];
  // scopeMissing = true means the token lacks calendar.readonly (needs re-auth)
  const scopeMissing = eventsData?.scopeMissing ?? false;

  // ── Mutations ──────────────────────────────────────────────────────────────
  const updateTask = useMutation({
    ...trpc.tasks.update.mutationOptions(),
    onSuccess: () => void queryClient.invalidateQueries(trpc.tasks.list.queryFilter()),
  });

  const createTask = useMutation({
    ...trpc.tasks.create.mutationOptions(),
    onSuccess: () => {
      void queryClient.invalidateQueries(trpc.tasks.list.queryFilter());
      setQuickAdd('');
      quickAddRef.current?.focus();
    },
  });

  // ── Derived data ───────────────────────────────────────────────────────────

  // Dates that have tasks — for calendar underline highlights
  const datesWithTasks = useMemo(() => {
    const set = new Set<string>();
    for (const task of tasks) {
      if (task.dueDate) set.add(format(new Date(task.dueDate), 'yyyy-MM-dd'));
    }
    return set;
  }, [tasks]);

  // Dates that have calendar events
  const datesWithEvents = useMemo(() => {
    const set = new Set<string>();
    for (const event of calendarEvents) {
      if (event.startTime) {
        // All-day events use YYYY-MM-DD; timed events use full ISO
        const dateKey = event.allDay
          ? event.startTime
          : format(new Date(event.startTime), 'yyyy-MM-dd');
        set.add(dateKey);
      }
    }
    return set;
  }, [calendarEvents]);

  // Events for the selected date, sorted by start time
  const selectedDateEvents = useMemo(() => {
    return calendarEvents
      .filter((e) => {
        const d = e.allDay ? new Date(e.startTime) : new Date(e.startTime);
        return isSameDay(d, selectedDate);
      })
      .sort((a, b) => new Date(a.startTime).getTime() - new Date(b.startTime).getTime());
  }, [calendarEvents, selectedDate]);

  // Tasks for the selected date
  const selectedDateTasks = useMemo(() => {
    return tasks.filter((t) => t.dueDate && isSameDay(new Date(t.dueDate), selectedDate));
  }, [tasks, selectedDate]);

  // This week overview (Mon–Sun)
  const weekDays = useMemo(() => {
    const start = startOfWeek(new Date(), { weekStartsOn: 1 });
    return Array.from({ length: 7 }, (_, i) => {
      const day = addDays(start, i);
      const key = format(day, 'yyyy-MM-dd');
      const dayTasks = tasks.filter(
        (t) => t.dueDate && isSameDay(new Date(t.dueDate), day),
      );
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
    await authClient.linkSocial({
      provider: 'google',
      callbackURL: window.location.href,
    });
  }, []);

  const hasContent = selectedDateEvents.length > 0 || selectedDateTasks.length > 0;
  const selectedDateLabel = isToday(selectedDate) ? 'Today' : format(selectedDate, 'EEEE, MMMM d');

  return (
    <div className="flex h-screen flex-col overflow-hidden bg-background">
      {/* Header */}
      <div className="flex items-center justify-between border-b px-6 py-3.5">
        <div className="flex items-center gap-2.5">
          <h1 className="text-[15px] font-semibold">Calendar</h1>
          {scopeMissing && (
            <span className="rounded-full bg-yellow-100 px-2 py-0.5 text-[11px] font-medium text-yellow-700 dark:bg-yellow-950/40 dark:text-yellow-400">
              Events need permission
            </span>
          )}
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

          {/* This week overview */}
          <div>
            <p className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
              This week
            </p>
            <div className="flex flex-col gap-0.5">
              {weekDays.map(({ day, tasks: dayTasks, hasEvent }) => (
                <button
                  key={day.toISOString()}
                  type="button"
                  onClick={() => setSelectedDate(day)}
                  className={cn(
                    'flex items-center justify-between rounded-lg px-2 py-1.5 text-left text-[13px] transition-colors hover:bg-accent',
                    isSameDay(day, selectedDate) && 'bg-accent font-medium',
                    isToday(day) && 'text-primary',
                  )}
                >
                  <span>{format(day, 'EEE, MMM d')}</span>
                  <div className="flex items-center gap-1">
                    {hasEvent && (
                      <span className="h-1.5 w-1.5 rounded-full bg-blue-500" />
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
              <div className="flex flex-col gap-3 rounded-lg border border-dashed bg-muted/20 px-3 py-3">
                <div className="flex items-start gap-2.5">
                  <CalendarIcon className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground/60" />
                  <div className="min-w-0 flex-1">
                    <p className="text-[12px] font-medium leading-tight text-muted-foreground">
                      Google Calendar needs permission
                    </p>
                    <p className="mt-0.5 text-[11px] leading-snug text-muted-foreground/70">
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

        {/* ── Right: Events + Tasks for selected date ────────────────────── */}
        <div className="flex flex-1 flex-col overflow-hidden">
          {/* Day header */}
          <div className="flex items-center gap-2 border-b px-6 py-3.5">
            <CalendarIcon className="h-4 w-4 text-muted-foreground" />
            <h2 className="text-[14px] font-semibold">{selectedDateLabel}</h2>
            {selectedDateEvents.length > 0 && (
              <Badge variant="secondary" className="h-5 text-[11px]">
                {selectedDateEvents.length} {selectedDateEvents.length === 1 ? 'event' : 'events'}
              </Badge>
            )}
            {selectedDateTasks.length > 0 && (
              <Badge variant="outline" className="h-5 text-[11px]">
                {selectedDateTasks.length} {selectedDateTasks.length === 1 ? 'task' : 'tasks'}
              </Badge>
            )}
          </div>

          <div className="flex-1 overflow-y-auto px-6 py-4">
            {/* Quick-add row — always visible, prefills due date to selected day */}
            <div className="mb-4 flex items-center gap-2 rounded-xl border bg-card px-4 py-2.5">
              <Plus className="h-4 w-4 shrink-0 text-muted-foreground" />
              <Input
                ref={quickAddRef}
                value={quickAdd}
                onChange={(e) => setQuickAdd(e.target.value)}
                onKeyDown={handleQuickAdd}
                placeholder={`Add task for ${isToday(selectedDate) ? 'today' : format(selectedDate, 'MMM d')}…`}
                className="h-auto border-0 bg-transparent p-0 text-[13px] shadow-none focus-visible:ring-0"
                disabled={createTask.isPending}
              />
            </div>

            {eventsLoading || tasksLoading ? (
              <div className="flex flex-col gap-2">
                {Array.from({ length: 3 }).map((_, i) => (
                  <div key={i} className="h-16 animate-pulse rounded-xl bg-muted/50" />
                ))}
              </div>
            ) : !hasContent ? (
              <div className="flex flex-col items-center gap-3 py-12 text-center">
                <div className="flex h-11 w-11 items-center justify-center rounded-full bg-muted">
                  <CalendarIcon className="h-5 w-5 text-muted-foreground" />
                </div>
                <div>
                  <p className="text-[13px] font-medium">
                    {scopeMissing ? 'No tasks for this day' : 'Nothing scheduled'}
                  </p>
                  <p className="text-[12px] text-muted-foreground">
                    Type above to quickly add a task, or go to{' '}
                    <Link to="/mail/tasks" className="underline">
                      Tasks
                    </Link>
                    .
                  </p>
                </div>
              </div>
            ) : (
              <div className="flex flex-col gap-4">
                {/* Calendar events section */}
                {selectedDateEvents.length > 0 && (
                  <div>
                    <p className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
                      Events
                    </p>
                    <div className="flex flex-col gap-2">
                      {selectedDateEvents.map((event) => (
                        <CalendarEventRow key={event.id} event={event} />
                      ))}
                    </div>
                  </div>
                )}

                {/* Tasks section */}
                {selectedDateTasks.length > 0 && (
                  <div>
                    <p className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
                      Tasks
                    </p>
                    <div className="flex flex-col gap-2">
                      {selectedDateTasks.map((task) => (
                        <CalendarTaskRow
                          key={task.id}
                          task={task}
                          onToggle={() =>
                            updateTask.mutate({
                              id: task.id,
                              data: { status: task.status === 'done' ? 'todo' : 'done' },
                            })
                          }
                        />
                      ))}
                    </div>
                  </div>
                )}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

// ─── CalendarEventRow ─────────────────────────────────────────────────────────

function CalendarEventRow({ event }: { event: CalendarEvent }) {
  const timeLabel = event.allDay
    ? 'All day'
    : (() => {
        const start = new Date(event.startTime);
        const end = new Date(event.endTime);
        return `${format(start, 'h:mm a')} – ${format(end, 'h:mm a')}`;
      })();

  const content = (
    <div
      className="flex items-start gap-3 rounded-xl border border-border bg-card p-4 transition-colors hover:bg-accent/20"
      style={{ borderLeftColor: event.color, borderLeftWidth: 3 }}
    >
      <div className="min-w-0 flex-1">
        <p className="text-[13px] font-medium">{event.title}</p>
        <div className="mt-1 flex flex-wrap items-center gap-3 text-[12px] text-muted-foreground">
          <span className="flex items-center gap-1">
            <Clock className="h-3 w-3" />
            {timeLabel}
          </span>
          {event.location && (
            <span className="flex items-center gap-1">
              <MapPin className="h-3 w-3" />
              <span className="line-clamp-1">{event.location}</span>
            </span>
          )}
        </div>
        {event.description && (
          <p className="mt-1.5 line-clamp-2 text-[11px] text-muted-foreground">
            {event.description}
          </p>
        )}
      </div>
    </div>
  );

  // If the event has an htmlLink, wrap it in an anchor
  if (event.htmlLink) {
    return (
      <a href={event.htmlLink} target="_blank" rel="noopener noreferrer" className="block">
        {content}
      </a>
    );
  }
  return content;
}

// ─── CalendarTaskRow ───────────────────────────────────────────────────────────

function CalendarTaskRow({ task, onToggle }: { task: Task; onToggle: () => void }) {
  const isDone = task.status === 'done';

  return (
    <div
      className={cn(
        'flex items-start gap-3 rounded-xl border border-border bg-card p-4 transition-colors hover:bg-accent/20',
        isDone && 'opacity-60',
      )}
    >
      <button
        type="button"
        onClick={onToggle}
        className="mt-0.5 shrink-0 text-muted-foreground transition-colors hover:text-primary"
      >
        {isDone ? (
          <CheckCircle2 className="h-5 w-5 text-primary" />
        ) : (
          <Circle className="h-5 w-5" />
        )}
      </button>
      <div className="min-w-0 flex-1">
        <p
          className={cn(
            'text-[13px] font-medium',
            isDone && 'text-muted-foreground line-through',
          )}
        >
          {task.title}
        </p>
        {task.description && (
          <p className="mt-0.5 line-clamp-1 text-[12px] text-muted-foreground">
            {task.description}
          </p>
        )}
        {task.priority && task.priority !== 'none' && (
          <div className="mt-1.5">
            <Badge
              variant="secondary"
              className={cn(
                'h-5 rounded-md border-0 px-1.5 text-[11px] font-medium',
                PRIORITY_CLASS[task.priority] ?? '',
              )}
            >
              {task.priority.charAt(0).toUpperCase() + task.priority.slice(1)}
            </Badge>
          </div>
        )}
      </div>
    </div>
  );
}
