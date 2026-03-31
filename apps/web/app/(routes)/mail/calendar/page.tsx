/**
 * Calendar page — improved parity.
 * - Left panel: month calendar picker with task count badges on dates
 * - Right panel: tasks for selected date + inline quick-add row
 * - "Connect Google Calendar" notice (no backend Calendar API yet)
 */
import { useState, useMemo, useRef } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  format,
  isSameDay,
  startOfWeek,
  addDays,
  isToday,
} from 'date-fns';
import {
  CalendarIcon,
  CheckCircle2,
  Circle,
  Plus,
} from 'lucide-react';
import { useTRPC } from '@/providers/query-provider';
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

  // Inline quick-add state
  const [quickAdd, setQuickAdd] = useState('');
  const quickAddRef = useRef<HTMLInputElement>(null);

  // Fetch all tasks (we filter client-side)
  const { data, isLoading } = useQuery(trpc.tasks.list.queryOptions({ limit: 500 }));
  const tasks = data?.tasks ?? [];

  const updateTask = useMutation({
    ...trpc.tasks.update.mutationOptions(),
    onSuccess: () => void queryClient.invalidateQueries(trpc.tasks.list.queryFilter()),
  });

  // Create task mutation — used for inline quick-add
  const createTask = useMutation({
    ...trpc.tasks.create.mutationOptions(),
    onSuccess: () => {
      void queryClient.invalidateQueries(trpc.tasks.list.queryFilter());
      setQuickAdd('');
      quickAddRef.current?.focus();
    },
  });

  // Compute dates that have tasks for calendar highlights
  const datesWithTasks = useMemo(() => {
    const set = new Set<string>();
    for (const task of tasks) {
      if (task.dueDate) {
        set.add(format(new Date(task.dueDate), 'yyyy-MM-dd'));
      }
    }
    return set;
  }, [tasks]);

  // Tasks for the selected date
  const selectedDateTasks = useMemo(() => {
    return tasks.filter((t) => t.dueDate && isSameDay(new Date(t.dueDate), selectedDate));
  }, [tasks, selectedDate]);

  // This week overview (Mon–Sun)
  const weekDays = useMemo(() => {
    const start = startOfWeek(new Date(), { weekStartsOn: 1 });
    return Array.from({ length: 7 }, (_, i) => {
      const day = addDays(start, i);
      const dayTasks = tasks.filter(
        (t) => t.dueDate && isSameDay(new Date(t.dueDate), day),
      );
      return { day, tasks: dayTasks };
    });
  }, [tasks]);

  // Handle quick-add: create task with the selected date as due date
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

  const hasSelectedDateTasks = selectedDateTasks.length > 0;
  const selectedDateLabel = isToday(selectedDate)
    ? 'Today'
    : format(selectedDate, 'EEEE, MMMM d');

  return (
    <div className="flex h-screen flex-col overflow-hidden bg-background">
      {/* Header — honest about this being task-date view, not a full calendar */}
      <div className="flex items-center justify-between border-b px-6 py-3.5">
        <div className="flex items-center gap-2.5">
          <h1 className="text-[15px] font-semibold">Tasks by Date</h1>
          <span className="rounded-full bg-muted px-2 py-0.5 text-[11px] font-medium text-muted-foreground">
            Calendar events coming soon
          </span>
        </div>
      </div>

      <div className="flex flex-1 overflow-hidden">
        {/* ── Left: Calendar picker + week overview ─────────────────────── */}
        <div className="flex w-[288px] shrink-0 flex-col overflow-y-auto border-r p-4">
          <Calendar
            mode="single"
            selected={selectedDate}
            onSelect={(d) => d && setSelectedDate(d)}
            modifiers={{
              // Underline dates that have tasks
              hasTasks: (date) => datesWithTasks.has(format(date, 'yyyy-MM-dd')),
            }}
            modifiersClassNames={{
              hasTasks: 'font-bold underline decoration-primary decoration-2',
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
              {weekDays.map(({ day, tasks: dayTasks }) => (
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
                  {dayTasks.length > 0 && (
                    <Badge variant="secondary" className="h-4 min-w-[1rem] px-1 text-[10px]">
                      {dayTasks.length}
                    </Badge>
                  )}
                </button>
              ))}
            </div>
          </div>

          <Separator className="my-3" />

          {/* Calendar events notice — Google Calendar integration not yet available */}
          <div className="flex items-start gap-2.5 rounded-lg border border-dashed bg-muted/20 px-3 py-3">
            <CalendarIcon className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground/60" />
            <div className="min-w-0 flex-1">
              <p className="text-[12px] font-medium leading-tight text-muted-foreground">
                Google Calendar coming soon
              </p>
              <p className="text-[11px] leading-snug text-muted-foreground/70">
                Events from your connected calendar will appear here
              </p>
            </div>
          </div>
        </div>

        {/* ── Right: Tasks for selected date ────────────────────────────── */}
        <div className="flex flex-1 flex-col overflow-hidden">
          {/* Day header */}
          <div className="flex items-center gap-2 border-b px-6 py-3.5">
            <CalendarIcon className="h-4 w-4 text-muted-foreground" />
            <h2 className="text-[14px] font-semibold">{selectedDateLabel}</h2>
            {hasSelectedDateTasks && (
              <Badge variant="secondary" className="h-5 text-[11px]">
                {selectedDateTasks.length} {selectedDateTasks.length === 1 ? 'task' : 'tasks'}
              </Badge>
            )}
          </div>

          <div className="flex-1 overflow-y-auto px-6 py-4">
            {/* Quick-add row — always visible at top, prefills due date to selected day */}
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

            {isLoading ? (
              <div className="flex flex-col gap-2">
                {Array.from({ length: 3 }).map((_, i) => (
                  <div key={i} className="h-16 animate-pulse rounded-xl bg-muted/50" />
                ))}
              </div>
            ) : !hasSelectedDateTasks ? (
              <div className="flex flex-col items-center gap-3 py-12 text-center">
                <div className="flex h-11 w-11 items-center justify-center rounded-full bg-muted">
                  <CalendarIcon className="h-5 w-5 text-muted-foreground" />
                </div>
                <div>
                  <p className="text-[13px] font-medium">No tasks for this day</p>
                  <p className="text-[12px] text-muted-foreground">
                    Type above to quickly add one, or go to{' '}
                    <Link to="/mail/tasks" className="underline">
                      Tasks
                    </Link>
                    .
                  </p>
                </div>
              </div>
            ) : (
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
            )}
          </div>
        </div>
      </div>
    </div>
  );
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
