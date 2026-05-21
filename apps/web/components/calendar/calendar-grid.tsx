/**
 * CalendarGrid — macOS-parity calendar surface for the web client.
 *
 * Supports four modes:
 *   - day:   24-hour vertical timeline (60min slots), event blocks positioned by start/end
 *   - week:  7-column timeline (Mon-Sun), same 60min rows
 *   - month: 6-row grid with up to 3 events per cell + "+N more" affordance
 *   - year:  12 mini-month grids in a 4×3 layout
 *
 * Design tokens only — bg-card, text-muted-foreground, border, accent, --mainBlue.
 * No external dependencies beyond `date-fns` (already in apps/web).
 *
 * Event positioning mirrors `apps/macos/.../CalendarTimeGridView.swift`:
 *   - Hour slot height = HOUR_HEIGHT (px)
 *   - All-day events render in a strip above the timeline
 *   - All-day startTime is YYYY-MM-DD; parsed in local time to avoid UTC drift
 *
 * Tasks (optional) render on their `dueDate` cell in month mode.
 */
import {
  addDays,
  addMonths,
  endOfMonth,
  endOfWeek,
  format,
  isSameDay,
  isSameMonth,
  isToday,
  setHours,
  setMinutes,
  startOfDay,
  startOfMonth,
  startOfWeek,
  startOfYear,
} from 'date-fns';
import { useCallback, useEffect, useMemo, useRef } from 'react';
import { cn } from '@/lib/utils';
import { parseEventStart as parseEventStartShared } from '@/lib/calendar-utils';

// ─── Types ────────────────────────────────────────────────────────────────────

export type CalendarGridMode = 'day' | 'week' | 'month' | 'year';

export interface CalendarGridEvent {
  id: string;
  title: string;
  startTime: string;
  endTime?: string;
  allDay?: boolean;
  color?: string;
}

export interface CalendarGridTask {
  id: string;
  title: string;
  dueDate?: string | Date | null;
  status?: string;
}

export interface CalendarGridProps {
  mode: CalendarGridMode;
  events: CalendarGridEvent[];
  tasks?: CalendarGridTask[];
  selectedDate: Date;
  onSelectDate: (date: Date) => void;
  onModeChange?: (mode: CalendarGridMode) => void;
  onCreateAt?: (start: Date, end: Date) => void;
  onTaskClick?: (taskId: string) => void;
  onEventClick?: (eventId: string) => void;
}

// ─── Constants ────────────────────────────────────────────────────────────────

const HOUR_HEIGHT = 48; // px per hour row — matches macOS visual density
const DAY_HEIGHT = HOUR_HEIGHT * 24;
const TIME_GUTTER = 56; // px reserved for "9 AM" labels on the left
const DEFAULT_EVENT_COLOR = 'var(--mainBlue)';
const MAX_EVENTS_PER_MONTH_CELL = 3;

// ─── Date helpers ─────────────────────────────────────────────────────────────

// Local-timezone safe parser for event start times. Shared with the Calendar
// page so all-day YYYY-MM-DD inputs render under the right local day in
// every timezone west of UTC. Single source of truth: `@/lib/calendar-utils`.
const parseEventStart = parseEventStartShared;

function parseEventEnd(event: CalendarGridEvent): Date {
  if (event.endTime) {
    if (event.allDay) {
      const [y, m, d] = event.endTime.split('-').map((p) => Number(p));
      if (Number.isFinite(y) && Number.isFinite(m) && Number.isFinite(d)) {
        return new Date(y, (m as number) - 1, d as number);
      }
    }
    return new Date(event.endTime);
  }
  // Default to 1h duration when not provided
  const start = parseEventStart(event);
  return new Date(start.getTime() + 60 * 60 * 1000);
}

/** Mon..Sun array of 7 dates starting at the Monday of the week containing date. */
function weekDays(date: Date): Date[] {
  const start = startOfWeek(date, { weekStartsOn: 1 });
  return Array.from({ length: 7 }, (_, i) => addDays(start, i));
}

/**
 * 6-week month grid (always 42 cells). Starts on the Monday on/before the 1st
 * of the month, padding into the previous/next month so each row is full.
 */
function monthGridDays(date: Date): Date[] {
  const first = startOfMonth(date);
  const last = endOfMonth(date);
  const start = startOfWeek(first, { weekStartsOn: 1 });
  const end = endOfWeek(last, { weekStartsOn: 1 });
  const result: Date[] = [];
  let cursor = start;
  while (cursor <= end) {
    result.push(cursor);
    cursor = addDays(cursor, 1);
  }
  // Always 6 rows × 7 cols for stable layout. If shorter month happens to fit
  // in 5 rows (rare), pad another week.
  while (result.length < 42) {
    cursor = addDays(cursor, 1);
    result.push(cursor);
  }
  return result.slice(0, 42);
}

function dateKey(date: Date): string {
  return format(date, 'yyyy-MM-dd');
}

// ─── Main Component ───────────────────────────────────────────────────────────

export function CalendarGrid(props: CalendarGridProps) {
  const { mode, selectedDate, onSelectDate } = props;
  const containerRef = useRef<HTMLDivElement>(null);

  // Keyboard nav: arrows move selection, `t` jumps to today.
  // Scoped to focus on the grid container to avoid stealing keys from inputs.
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const onKey = (e: KeyboardEvent) => {
      // Don't hijack typing
      const target = e.target as HTMLElement | null;
      if (
        target &&
        (target.tagName === 'INPUT' ||
          target.tagName === 'TEXTAREA' ||
          target.isContentEditable)
      ) {
        return;
      }
      if (!el.contains(document.activeElement) && document.activeElement !== document.body) {
        return;
      }
      if (e.key === 'ArrowLeft') {
        e.preventDefault();
        onSelectDate(addDays(selectedDate, mode === 'month' ? -1 : mode === 'week' ? -1 : -1));
      } else if (e.key === 'ArrowRight') {
        e.preventDefault();
        onSelectDate(addDays(selectedDate, 1));
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        onSelectDate(addDays(selectedDate, mode === 'month' ? -7 : -7));
      } else if (e.key === 'ArrowDown') {
        e.preventDefault();
        onSelectDate(addDays(selectedDate, 7));
      } else if (e.key === 't' || e.key === 'T') {
        e.preventDefault();
        onSelectDate(new Date());
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [selectedDate, mode, onSelectDate]);

  return (
    <div
      ref={containerRef}
      tabIndex={0}
      className="focus-visible:outline-none flex h-full w-full flex-col bg-background"
      aria-label={`Calendar (${mode} view)`}
    >
      {mode === 'day' && <DayView {...props} />}
      {mode === 'week' && <WeekView {...props} />}
      {mode === 'month' && <MonthView {...props} />}
      {mode === 'year' && <YearView {...props} />}
    </div>
  );
}

// ─── Day View ────────────────────────────────────────────────────────────────

function DayView({
  events,
  selectedDate,
  onCreateAt,
  onEventClick,
}: CalendarGridProps) {
  const day = startOfDay(selectedDate);

  const { timed, allDay } = useMemo(() => splitEventsForDay(events, day), [events, day]);

  return (
    <div className="flex h-full flex-col overflow-hidden">
      <DayHeader date={selectedDate} />
      <AllDayStrip
        events={allDay}
        gutter={TIME_GUTTER}
        onEventClick={onEventClick}
      />
      <div className="flex-1 overflow-y-auto">
        <TimeGrid
          days={[day]}
          events={timed}
          onCreateAt={onCreateAt}
          onEventClick={onEventClick}
        />
      </div>
    </div>
  );
}

function DayHeader({ date }: { date: Date }) {
  const today = isToday(date);
  return (
    <div className="flex shrink-0 items-center gap-3 border-b px-4 py-2.5">
      <div
        className={cn(
          'flex h-9 w-9 items-center justify-center rounded-full text-[14px] font-semibold',
          today ? 'bg-[var(--mainBlue)] text-white' : 'bg-muted text-foreground',
        )}
      >
        {format(date, 'd')}
      </div>
      <div className="flex flex-col">
        <span className="text-muted-foreground text-[11px] font-medium uppercase tracking-wide">
          {format(date, 'EEEE')}
        </span>
        <span className="text-[13px] font-medium">{format(date, 'MMMM yyyy')}</span>
      </div>
    </div>
  );
}

// ─── Week View ───────────────────────────────────────────────────────────────

function WeekView({
  events,
  selectedDate,
  onSelectDate,
  onCreateAt,
  onEventClick,
}: CalendarGridProps) {
  const days = useMemo(() => weekDays(selectedDate), [selectedDate]);

  // Per-day buckets for the timed events; all-day strips together
  const { timed, allDay } = useMemo(() => splitEventsForRange(events, days), [events, days]);

  return (
    <div className="flex h-full flex-col overflow-hidden">
      {/* Week header — day-of-week + date pill per column */}
      <div
        className="grid shrink-0 border-b"
        style={{ gridTemplateColumns: `${TIME_GUTTER}px repeat(7, minmax(0, 1fr))` }}
      >
        <div />
        {days.map((d) => {
          const selected = isSameDay(d, selectedDate);
          const today = isToday(d);
          return (
            <button
              key={d.toISOString()}
              type="button"
              onClick={() => onSelectDate(d)}
              className={cn(
                'flex flex-col items-center gap-1 border-l py-2 transition-colors',
                'hover:bg-accent/40',
                selected && 'bg-accent/30',
              )}
            >
              <span className="text-muted-foreground text-[10px] font-medium uppercase tracking-wide">
                {format(d, 'EEE')}
              </span>
              <span
                className={cn(
                  'flex h-7 w-7 items-center justify-center rounded-full text-[13px] font-semibold',
                  today ? 'bg-[var(--mainBlue)] text-white' : 'text-foreground',
                )}
              >
                {format(d, 'd')}
              </span>
            </button>
          );
        })}
      </div>

      <AllDayStrip
        events={allDay}
        gutter={TIME_GUTTER}
        days={days}
        onEventClick={onEventClick}
      />

      <div className="flex-1 overflow-y-auto">
        <TimeGrid
          days={days}
          events={timed}
          onCreateAt={onCreateAt}
          onEventClick={onEventClick}
        />
      </div>
    </div>
  );
}

// ─── Time Grid (shared by Day + Week) ────────────────────────────────────────

interface TimeGridProps {
  days: Date[];
  events: CalendarGridEvent[];
  onCreateAt?: (start: Date, end: Date) => void;
  onEventClick?: (eventId: string) => void;
}

function TimeGrid({ days, events, onCreateAt, onEventClick }: TimeGridProps) {
  const handleSlotClick = useCallback(
    (day: Date, hour: number) => {
      if (!onCreateAt) return;
      const start = setMinutes(setHours(startOfDay(day), hour), 0);
      const end = new Date(start.getTime() + 60 * 60 * 1000);
      onCreateAt(start, end);
    },
    [onCreateAt],
  );

  return (
    <div
      className="relative grid"
      style={{
        gridTemplateColumns: `${TIME_GUTTER}px repeat(${days.length}, minmax(0, 1fr))`,
        height: DAY_HEIGHT,
      }}
    >
      {/* Time gutter */}
      <div className="border-r">
        {Array.from({ length: 24 }, (_, hour) => (
          <div
            key={hour}
            className="text-muted-foreground relative text-[10px] font-medium"
            style={{ height: HOUR_HEIGHT }}
          >
            {hour > 0 && (
              <span className="absolute -top-1.5 right-2">
                {formatHourLabel(hour)}
              </span>
            )}
          </div>
        ))}
      </div>

      {/* Day columns */}
      {days.map((day) => {
        const dayEvents = events.filter((e) => isSameDay(parseEventStart(e), day));
        const positioned = positionDayEvents(dayEvents, day);
        return (
          <div key={day.toISOString()} className="relative border-l">
            {/* Hour slots — each is a click target for create */}
            {Array.from({ length: 24 }, (_, hour) => (
              <button
                key={hour}
                type="button"
                onClick={() => handleSlotClick(day, hour)}
                aria-label={`Create event at ${formatHourLabel(hour)} on ${format(day, 'MMM d')}`}
                className={cn(
                  'block w-full border-b border-border/40 transition-colors',
                  'hover:bg-accent/30 focus-visible:bg-accent/40 focus-visible:outline-none',
                  onCreateAt ? 'cursor-pointer' : 'cursor-default',
                )}
                style={{ height: HOUR_HEIGHT }}
                tabIndex={-1}
              />
            ))}

            {/* Current-time indicator (red line) — only on today's column */}
            {isToday(day) && <NowIndicator />}

            {/* Positioned event blocks */}
            {positioned.map(({ event, top, height, leftPct, widthPct }) => (
              <button
                key={event.id}
                type="button"
                onClick={(e) => {
                  e.stopPropagation();
                  onEventClick?.(event.id);
                }}
                title={event.title}
                className={cn(
                  'absolute overflow-hidden rounded-md border border-white/30 px-1.5 py-1 text-left',
                  'text-[11px] font-medium text-white shadow-sm transition-shadow',
                  'hover:shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                )}
                style={{
                  top,
                  height: Math.max(height, 16),
                  left: `calc(${leftPct}% + 2px)`,
                  width: `calc(${widthPct}% - 4px)`,
                  backgroundColor: event.color ?? DEFAULT_EVENT_COLOR,
                }}
              >
                <div className="line-clamp-1">{event.title}</div>
                {height > 28 && (
                  <div className="line-clamp-1 text-[10px] opacity-90">
                    {format(parseEventStart(event), 'h:mm a')}
                  </div>
                )}
              </button>
            ))}
          </div>
        );
      })}
    </div>
  );
}

function NowIndicator() {
  const now = new Date();
  const minutes = now.getHours() * 60 + now.getMinutes();
  const top = (minutes / 60) * HOUR_HEIGHT;
  return (
    <div
      className="pointer-events-none absolute left-0 right-0 z-10"
      style={{ top }}
      aria-hidden
    >
      <div className="bg-destructive h-px w-full opacity-80" />
      <div className="bg-destructive absolute -left-1 -top-1 h-2 w-2 rounded-full opacity-80" />
    </div>
  );
}

// ─── All-Day Strip ────────────────────────────────────────────────────────────

function AllDayStrip({
  events,
  gutter,
  days,
  onEventClick,
}: {
  events: CalendarGridEvent[];
  gutter: number;
  days?: Date[];
  onEventClick?: (eventId: string) => void;
}) {
  if (events.length === 0) return null;
  const cols = days ?? [];
  return (
    <div
      className="grid shrink-0 border-b bg-muted/20"
      style={{
        gridTemplateColumns: cols.length > 0
          ? `${gutter}px repeat(${cols.length}, minmax(0, 1fr))`
          : `${gutter}px minmax(0, 1fr)`,
      }}
    >
      <div className="text-muted-foreground flex items-center justify-end pr-2 text-[10px] font-medium">
        all-day
      </div>
      {cols.length > 0 ? (
        cols.map((d) => {
          const dayEvents = events.filter((e) => isSameDay(parseEventStart(e), d));
          return (
            <div key={d.toISOString()} className="flex flex-col gap-0.5 border-l px-1 py-1">
              {dayEvents.map((e) => (
                <AllDayPill key={e.id} event={e} onClick={onEventClick} />
              ))}
            </div>
          );
        })
      ) : (
        <div className="flex flex-col gap-0.5 px-1 py-1">
          {events.map((e) => (
            <AllDayPill key={e.id} event={e} onClick={onEventClick} />
          ))}
        </div>
      )}
    </div>
  );
}

function AllDayPill({
  event,
  onClick,
}: {
  event: CalendarGridEvent;
  onClick?: (eventId: string) => void;
}) {
  return (
    <button
      type="button"
      onClick={() => onClick?.(event.id)}
      title={event.title}
      className="line-clamp-1 rounded-sm px-1.5 py-0.5 text-left text-[11px] font-medium text-white"
      style={{ backgroundColor: event.color ?? DEFAULT_EVENT_COLOR }}
    >
      {event.title}
    </button>
  );
}

// ─── Month View ──────────────────────────────────────────────────────────────

function MonthView({
  events,
  tasks,
  selectedDate,
  onSelectDate,
  onModeChange,
  onCreateAt,
  onTaskClick,
  onEventClick,
}: CalendarGridProps) {
  const days = useMemo(() => monthGridDays(selectedDate), [selectedDate]);
  const eventsByDay = useMemo(() => groupEventsByDay(events), [events]);
  const tasksByDay = useMemo(() => groupTasksByDay(tasks ?? []), [tasks]);

  return (
    <div className="flex h-full flex-col overflow-hidden">
      {/* Day-of-week header */}
      <div className="grid shrink-0 grid-cols-7 border-b">
        {['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((d) => (
          <div
            key={d}
            className="text-muted-foreground px-2 py-1.5 text-[10px] font-medium uppercase tracking-wide"
          >
            {d}
          </div>
        ))}
      </div>

      <div className="grid flex-1 grid-cols-7 grid-rows-6">
        {days.map((day) => {
          const key = dateKey(day);
          const dayEvents = eventsByDay.get(key) ?? [];
          const dayTasks = tasksByDay.get(key) ?? [];
          const inMonth = isSameMonth(day, selectedDate);
          const selected = isSameDay(day, selectedDate);
          const today = isToday(day);
          const items: { id: string; title: string; color?: string; kind: 'event' | 'task' }[] = [
            ...dayEvents.map((e) => ({
              id: e.id,
              title: e.title,
              color: e.color,
              kind: 'event' as const,
            })),
            ...dayTasks.map((t) => ({
              id: t.id,
              title: t.title,
              color: undefined,
              kind: 'task' as const,
            })),
          ];
          const shown = items.slice(0, MAX_EVENTS_PER_MONTH_CELL);
          const overflow = items.length - shown.length;

          return (
            <button
              key={key}
              type="button"
              onClick={() => {
                onSelectDate(day);
                if (onCreateAt && !inMonth) {
                  // Clicking an out-of-month day jumps the selection; on
                  // double-tap behavior the parent re-renders into that month.
                }
              }}
              onDoubleClick={() => {
                if (onCreateAt) {
                  const start = startOfDay(day);
                  const end = new Date(start.getTime() + 60 * 60 * 1000);
                  onCreateAt(start, end);
                }
              }}
              className={cn(
                'group relative flex flex-col gap-1 overflow-hidden border-b border-r p-1.5 text-left transition-colors',
                'hover:bg-accent/30 focus-visible:bg-accent/40 focus-visible:outline-none',
                !inMonth && 'bg-muted/10 text-muted-foreground',
                selected && 'ring-2 ring-inset ring-[var(--mainBlue)]/50',
              )}
            >
              <div className="flex items-center justify-between">
                <span
                  className={cn(
                    'flex h-5 w-5 items-center justify-center rounded-full text-[11px] font-semibold',
                    today && 'bg-[var(--mainBlue)] text-white',
                  )}
                >
                  {format(day, 'd')}
                </span>
              </div>
              <div className="flex min-h-0 flex-1 flex-col gap-0.5 overflow-hidden">
                {shown.map((item) => (
                  <button
                    key={`${item.kind}-${item.id}`}
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation();
                      if (item.kind === 'event') onEventClick?.(item.id);
                      else onTaskClick?.(item.id);
                    }}
                    title={item.title}
                    className={cn(
                      'line-clamp-1 rounded px-1 py-0.5 text-left text-[10px] font-medium',
                      item.kind === 'event'
                        ? 'text-white'
                        : 'bg-accent text-accent-foreground',
                    )}
                    style={
                      item.kind === 'event'
                        ? { backgroundColor: item.color ?? DEFAULT_EVENT_COLOR }
                        : undefined
                    }
                  >
                    {item.title}
                  </button>
                ))}
                {overflow > 0 && (
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation();
                      onSelectDate(day);
                      onModeChange?.('day');
                    }}
                    className="text-muted-foreground hover:text-foreground text-left text-[10px] font-medium"
                  >
                    +{overflow} more
                  </button>
                )}
              </div>
            </button>
          );
        })}
      </div>
    </div>
  );
}

// ─── Year View ───────────────────────────────────────────────────────────────

function YearView({
  selectedDate,
  onSelectDate,
  onModeChange,
  events,
  tasks,
}: CalendarGridProps) {
  const yearStart = startOfYear(selectedDate);
  const months = useMemo(
    () => Array.from({ length: 12 }, (_, i) => addMonths(yearStart, i)),
    [yearStart],
  );
  const eventDays = useMemo(() => {
    const set = new Set<string>();
    for (const e of events) {
      set.add(dateKey(parseEventStart(e)));
    }
    return set;
  }, [events]);
  const taskDays = useMemo(() => {
    const set = new Set<string>();
    for (const t of tasks ?? []) {
      if (t.dueDate) set.add(dateKey(new Date(t.dueDate)));
    }
    return set;
  }, [tasks]);

  return (
    <div className="flex h-full flex-col overflow-y-auto">
      <div className="shrink-0 border-b px-4 py-2.5">
        <h3 className="text-[14px] font-semibold">{format(yearStart, 'yyyy')}</h3>
      </div>
      <div className="grid grid-cols-1 gap-4 p-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
        {months.map((m) => (
          <MiniMonth
            key={m.toISOString()}
            month={m}
            selectedDate={selectedDate}
            eventDays={eventDays}
            taskDays={taskDays}
            onSelectMonth={(d) => {
              onSelectDate(d);
              onModeChange?.('month');
            }}
            onSelectDay={(d) => {
              onSelectDate(d);
              onModeChange?.('day');
            }}
          />
        ))}
      </div>
    </div>
  );
}

function MiniMonth({
  month,
  selectedDate,
  eventDays,
  taskDays,
  onSelectMonth,
  onSelectDay,
}: {
  month: Date;
  selectedDate: Date;
  eventDays: Set<string>;
  taskDays: Set<string>;
  onSelectMonth: (d: Date) => void;
  onSelectDay: (d: Date) => void;
}) {
  const days = useMemo(() => monthGridDays(month), [month]);
  return (
    <div className="bg-card flex flex-col gap-2 rounded-xl border p-3">
      <button
        type="button"
        onClick={() => onSelectMonth(startOfMonth(month))}
        className="hover:text-[var(--mainBlue)] text-left text-[12px] font-semibold transition-colors"
      >
        {format(month, 'MMMM')}
      </button>
      <div className="grid grid-cols-7 gap-0.5 text-center text-[9px]">
        {['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((d, i) => (
          <div key={`${d}-${i}`} className="text-muted-foreground/60 font-medium">
            {d}
          </div>
        ))}
        {days.map((d) => {
          const key = dateKey(d);
          const inMonth = isSameMonth(d, month);
          const selected = isSameDay(d, selectedDate);
          const today = isToday(d);
          const hasMark = eventDays.has(key) || taskDays.has(key);
          return (
            <button
              key={key}
              type="button"
              onClick={() => onSelectDay(d)}
              className={cn(
                'relative flex h-5 items-center justify-center rounded text-[10px] transition-colors',
                inMonth ? 'text-foreground' : 'text-muted-foreground/40',
                today && 'bg-[var(--mainBlue)] text-white font-semibold',
                selected && !today && 'bg-accent font-semibold',
                !today && !selected && inMonth && 'hover:bg-accent/50',
              )}
            >
              {format(d, 'd')}
              {hasMark && !today && (
                <span className="absolute bottom-0 left-1/2 h-0.5 w-0.5 -translate-x-1/2 rounded-full bg-[var(--mainBlue)]" />
              )}
            </button>
          );
        })}
      </div>
    </div>
  );
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function splitEventsForDay(
  events: CalendarGridEvent[],
  day: Date,
): { timed: CalendarGridEvent[]; allDay: CalendarGridEvent[] } {
  const timed: CalendarGridEvent[] = [];
  const allDay: CalendarGridEvent[] = [];
  for (const e of events) {
    if (!isSameDay(parseEventStart(e), day)) continue;
    if (e.allDay) allDay.push(e);
    else timed.push(e);
  }
  return { timed, allDay };
}

function splitEventsForRange(
  events: CalendarGridEvent[],
  days: Date[],
): { timed: CalendarGridEvent[]; allDay: CalendarGridEvent[] } {
  const timed: CalendarGridEvent[] = [];
  const allDay: CalendarGridEvent[] = [];
  for (const e of events) {
    const start = parseEventStart(e);
    if (!days.some((d) => isSameDay(d, start))) continue;
    if (e.allDay) allDay.push(e);
    else timed.push(e);
  }
  return { timed, allDay };
}

function groupEventsByDay(events: CalendarGridEvent[]): Map<string, CalendarGridEvent[]> {
  const map = new Map<string, CalendarGridEvent[]>();
  for (const e of events) {
    const key = dateKey(parseEventStart(e));
    const list = map.get(key) ?? [];
    list.push(e);
    map.set(key, list);
  }
  return map;
}

function groupTasksByDay(tasks: CalendarGridTask[]): Map<string, CalendarGridTask[]> {
  const map = new Map<string, CalendarGridTask[]>();
  for (const t of tasks) {
    if (!t.dueDate) continue;
    const date = t.dueDate instanceof Date ? t.dueDate : new Date(t.dueDate);
    if (Number.isNaN(date.getTime())) continue;
    const key = dateKey(date);
    const list = map.get(key) ?? [];
    list.push(t);
    map.set(key, list);
  }
  return map;
}

/**
 * Position timed events for a single day column. Returns top/height in px and
 * left/width percentages, splitting overlapping events into side-by-side
 * columns (simple greedy interval-scheduling).
 */
interface PositionedEvent {
  event: CalendarGridEvent;
  top: number;
  height: number;
  leftPct: number;
  widthPct: number;
}

function positionDayEvents(events: CalendarGridEvent[], day: Date): PositionedEvent[] {
  // Sort by start, then longer events first so the longer event takes the
  // leftmost column (matches Google Calendar / macOS behavior).
  const sorted = [...events].sort((a, b) => {
    const aStart = parseEventStart(a).getTime();
    const bStart = parseEventStart(b).getTime();
    if (aStart !== bStart) return aStart - bStart;
    return parseEventEnd(b).getTime() - parseEventEnd(a).getTime();
  });

  type Slot = { event: CalendarGridEvent; start: Date; end: Date; col: number };

  // Build clusters of transitively-overlapping events, then position each
  // event in the lowest-index column with no time conflict in that cluster.
  const clusters: Slot[][] = [];
  let current: Slot[] = [];
  let currentEnd: Date | null = null;

  for (const e of sorted) {
    const start = clampToDay(parseEventStart(e), day);
    const end = clampToDay(parseEventEnd(e), day, true);
    const overlaps = currentEnd !== null && start < currentEnd;
    if (!overlaps) {
      if (current.length > 0) clusters.push(current);
      current = [];
      currentEnd = null;
    }
    const usedCols = new Set<number>();
    for (const s of current) {
      if (s.end > start) usedCols.add(s.col);
    }
    let col = 0;
    while (usedCols.has(col)) col++;
    current.push({ event: e, start, end, col });
    if (currentEnd === null || end > currentEnd) currentEnd = end;
  }
  if (current.length > 0) clusters.push(current);

  const result: PositionedEvent[] = [];
  for (const cl of clusters) {
    const colCount = Math.max(...cl.map((s) => s.col)) + 1;
    const colWidth = 100 / colCount;
    for (const s of cl) {
      const startMin = s.start.getHours() * 60 + s.start.getMinutes();
      const endMin = Math.max(
        startMin + 15,
        s.end.getHours() * 60 + s.end.getMinutes(),
      );
      result.push({
        event: s.event,
        top: (startMin / 60) * HOUR_HEIGHT,
        height: ((endMin - startMin) / 60) * HOUR_HEIGHT - 2,
        leftPct: s.col * colWidth,
        widthPct: colWidth,
      });
    }
  }
  return result;
}

function clampToDay(date: Date, day: Date, isEnd = false): Date {
  const dayStart = startOfDay(day);
  const dayEnd = addDays(dayStart, 1);
  if (date < dayStart) return isEnd ? dayStart : dayStart;
  if (date > dayEnd) return dayEnd;
  return date;
}

function formatHourLabel(hour: number): string {
  if (hour === 0) return '12 AM';
  if (hour === 12) return '12 PM';
  if (hour < 12) return `${hour} AM`;
  return `${hour - 12} PM`;
}
