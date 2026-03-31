/**
 * Home page — iOS/macOS parity redesign.
 * Section headers: icon + title + count badge + "+" action button.
 * Sections: Today's Events (Calendar CTA) → Due Tasks → Recent Emails.
 */
import { useMemo } from 'react';
import { useInfiniteQuery, useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { formatDistanceToNow, isToday, format } from 'date-fns';
import { Link } from 'react-router';
import {
  ArrowRight,
  CheckCircle2,
  Circle,
  Inbox,
  Plus,
  CalendarDays,
  CheckSquare2,
  Mail,
  ExternalLink,
} from 'lucide-react';
import { useTRPC } from '@/providers/query-provider';
import { authProxy } from '@/lib/auth-proxy';
import { useSession } from '@/lib/auth-client';
import { useThread } from '@/hooks/use-threads';
import { Button } from '@/components/ui/button';
import { Separator } from '@/components/ui/separator';
import { cn } from '@/lib/utils';
import { Badge } from '@/components/ui/badge';
import type { Route } from './+types/page';
import type { Outputs } from '@zero/server/trpc';

type Task = Outputs['tasks']['list']['tasks'][number];

// Auth guard
export async function clientLoader({ request }: Route.ClientLoaderArgs) {
  const session = await authProxy.api.getSession({ headers: request.headers });
  if (!session) return Response.redirect(`${import.meta.env.VITE_PUBLIC_APP_URL}/login`);
  return {};
}

// Greeting based on time of day
function getGreeting() {
  const hour = new Date().getHours();
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

// ─── SectionHeader ────────────────────────────────────────────────────────────
// iOS-style section header: icon + title + count badge + optional "+" action button

function SectionHeader({
  icon: Icon,
  title,
  count,
  linkTo,
  onAdd,
}: {
  icon: React.ComponentType<{ className?: string }>;
  title: string;
  count?: number;
  linkTo?: string;
  onAdd?: () => void;
}) {
  return (
    <div className="mb-3 flex items-center gap-2">
      <Icon className="h-4 w-4 shrink-0 text-muted-foreground" />
      <span className="text-[15px] font-semibold leading-none">{title}</span>
      {typeof count === 'number' && count > 0 && (
        <span className="rounded-full bg-muted px-1.5 py-0.5 text-[11px] font-bold text-muted-foreground">
          {count}
        </span>
      )}
      <div className="ml-auto flex items-center gap-1">
        {linkTo && (
          <Button
            asChild
            variant="ghost"
            size="sm"
            className="h-7 gap-1 px-2 text-[12px] text-muted-foreground"
          >
            <Link to={linkTo}>
              See all
              <ArrowRight className="h-3 w-3" />
            </Link>
          </Button>
        )}
        {onAdd && (
          <Button
            variant="ghost"
            size="icon"
            className="h-7 w-7"
            onClick={onAdd}
          >
            <Plus className="h-3.5 w-3.5" />
          </Button>
        )}
      </div>
    </div>
  );
}

// ─── Section container with card styling ──────────────────────────────────────

function Section({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <div className={cn('rounded-xl border bg-card px-4 py-4', className)}>
      {children}
    </div>
  );
}

export default function HomePage() {
  const { data: session } = useSession();
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const firstName = session?.user?.name?.split(' ')[0] ?? '';

  // Tasks — fetch all, filter client-side for "today or pending"
  const { data: tasksData, isLoading: tasksLoading } = useQuery(
    trpc.tasks.list.queryOptions({ limit: 100 }),
  );

  const todayTasks = useMemo(() => {
    const tasks = tasksData?.tasks ?? [];
    return tasks
      .filter((t) => {
        if (t.status === 'done') return false;
        if (t.dueDate && isToday(new Date(t.dueDate))) return true;
        if (!t.dueDate && t.status === 'todo') return true;
        return false;
      })
      .slice(0, 5);
  }, [tasksData]);

  // Quick task toggle from home page
  const updateTask = useMutation({
    ...trpc.tasks.update.mutationOptions(),
    onSuccess: () => void queryClient.invalidateQueries(trpc.tasks.list.queryFilter()),
  });

  // Recent inbox threads — first page, 3 items
  const threadsQuery = useInfiniteQuery(
    trpc.mail.listThreads.infiniteQueryOptions(
      { folder: 'inbox', q: '', maxResults: 5 },
      {
        initialCursor: '',
        getNextPageParam: (lastPage) => lastPage?.nextPageToken ?? null,
        staleTime: 60 * 1000 * 2,
      },
    ),
  );
  const recentThreadIds = useMemo(
    () => (threadsQuery.data?.pages[0]?.threads ?? []).slice(0, 3).map((t) => t.id),
    [threadsQuery.data],
  );

  return (
    <div className="flex h-screen flex-col overflow-y-auto bg-background">
      <div className="mx-auto w-full max-w-2xl px-6 py-8">
        {/* Greeting — first name only, date subtitle */}
        <div className="mb-8">
          <h1 className="text-[22px] font-bold tracking-tight">
            {getGreeting()}{firstName ? `, ${firstName}` : ''}
          </h1>
          <p className="mt-0.5 text-[13px] text-muted-foreground">
            {format(new Date(), 'EEEE, MMMM d')}
          </p>
        </div>

        <div className="flex flex-col gap-4">
          {/* ── Today's Events (Calendar CTA) ─────────────────────────────── */}
          <Section>
            <SectionHeader
              icon={CalendarDays}
              title="Today's Events"
              linkTo="/mail/calendar"
            />
            {/* Calendar events require a backend Google Calendar integration — show CTA */}
            <Link
              to="/settings/connections"
              className="flex items-center gap-3 rounded-lg border border-dashed bg-muted/30 px-4 py-3.5 transition-colors hover:bg-muted/50"
            >
              <CalendarDays className="h-5 w-5 shrink-0 text-muted-foreground" />
              <div className="min-w-0 flex-1">
                <p className="text-[13px] font-medium">Connect Google Calendar</p>
                <p className="text-[12px] text-muted-foreground">
                  See today's events here once connected.
                </p>
              </div>
              <ExternalLink className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
            </Link>
          </Section>

          {/* ── Due Tasks ──────────────────────────────────────────────────── */}
          <Section>
            <SectionHeader
              icon={CheckSquare2}
              title="Due Tasks"
              count={todayTasks.length}
              linkTo="/mail/tasks"
            />
            {tasksLoading ? (
              <div className="flex flex-col gap-2">
                {Array.from({ length: 3 }).map((_, i) => (
                  <div key={i} className="h-9 animate-pulse rounded-lg bg-muted/50" />
                ))}
              </div>
            ) : todayTasks.length === 0 ? (
              <div className="flex flex-col items-center gap-2 py-3 text-center">
                <CheckCircle2 className="h-7 w-7 text-muted-foreground/40" />
                <p className="text-[13px] text-muted-foreground">All caught up!</p>
                <Button asChild variant="outline" size="sm" className="h-7 text-xs">
                  <Link to="/mail/tasks">
                    <Plus className="mr-1 h-3 w-3" />
                    New task
                  </Link>
                </Button>
              </div>
            ) : (
              <div className="flex flex-col divide-y divide-border/60">
                {todayTasks.map((task) => (
                  <TaskItem
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
          </Section>

          {/* ── Recent Emails ─────────────────────────────────────────────── */}
          <Section>
            <SectionHeader
              icon={Mail}
              title="Recent Emails"
              linkTo="/mail/inbox"
            />
            {threadsQuery.isLoading ? (
              <div className="flex flex-col gap-2">
                {Array.from({ length: 3 }).map((_, i) => (
                  <div key={i} className="h-11 animate-pulse rounded-lg bg-muted/50" />
                ))}
              </div>
            ) : recentThreadIds.length === 0 ? (
              <div className="flex flex-col items-center gap-2 py-3 text-center">
                <Inbox className="h-7 w-7 text-muted-foreground/40" />
                <p className="text-[13px] text-muted-foreground">Your inbox is empty</p>
              </div>
            ) : (
              <div className="flex flex-col divide-y divide-border/60">
                {recentThreadIds.map((id) => (
                  <EmailThreadRow key={id} threadId={id} />
                ))}
              </div>
            )}
          </Section>
        </div>
      </div>
    </div>
  );
}

// ─── TaskItem ─────────────────────────────────────────────────────────────────
// Compact task row with toggle checkbox + priority badge

function TaskItem({ task, onToggle }: { task: Task; onToggle: () => void }) {
  return (
    <div className="flex items-center gap-3 py-2.5">
      <button
        type="button"
        onClick={onToggle}
        className="shrink-0 text-muted-foreground transition-colors hover:text-primary"
      >
        {task.status === 'done' ? (
          <CheckCircle2 className="h-4 w-4 text-primary" />
        ) : (
          <Circle className="h-4 w-4" />
        )}
      </button>
      <div className="min-w-0 flex-1">
        <p
          className={cn(
            'truncate text-[13px] font-medium',
            task.status === 'done' && 'text-muted-foreground line-through',
          )}
        >
          {task.title}
        </p>
        {task.dueDate && isToday(new Date(task.dueDate)) && (
          <p className="text-[11px] text-muted-foreground">Due today</p>
        )}
      </div>
      {task.priority && task.priority !== 'none' && (
        <Badge
          variant="secondary"
          className={cn(
            'h-4 shrink-0 border-0 px-1.5 text-[10px] font-medium',
            task.priority === 'high' && 'bg-red-50 text-red-600 dark:bg-red-950/30 dark:text-red-400',
            task.priority === 'medium' && 'bg-yellow-50 text-yellow-600 dark:bg-yellow-950/30 dark:text-yellow-400',
            task.priority === 'low' && 'bg-blue-50 text-blue-600 dark:bg-blue-950/30 dark:text-blue-400',
          )}
        >
          {task.priority}
        </Badge>
      )}
    </div>
  );
}

// ─── EmailThreadRow ────────────────────────────────────────────────────────────
// Fetches full thread data per ID to show sender + subject + unread dot

function EmailThreadRow({ threadId }: { threadId: string }) {
  const { data, isLoading } = useThread(threadId);
  const latest = data?.latest;

  if (isLoading) {
    return <div className="h-11 animate-pulse rounded-lg bg-muted/50 my-1" />;
  }

  if (!latest) return null;

  const sender = latest.sender;
  const senderName = sender?.name || sender?.email || 'Unknown';
  const subject = latest.subject || '(no subject)';
  const time = latest.receivedOn
    ? formatDistanceToNow(new Date(latest.receivedOn), { addSuffix: true })
    : '';

  return (
    <Link
      to={`/mail/inbox?threadId=${threadId}`}
      className="-mx-1 flex items-start gap-3 rounded-lg px-1 py-3 transition-colors hover:bg-accent/40"
    >
      {/* Unread dot */}
      <div className="mt-1.5 shrink-0">
        <div
          className={cn(
            'h-2 w-2 rounded-full',
            latest.unread ? 'bg-primary' : 'bg-transparent',
          )}
        />
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex items-baseline justify-between gap-2">
          <p className={cn('truncate text-[13px]', latest.unread ? 'font-semibold' : 'font-medium')}>
            {senderName}
          </p>
          {time && (
            <p className="shrink-0 text-[11px] text-muted-foreground">{time}</p>
          )}
        </div>
        <p className="truncate text-[12px] text-muted-foreground">{subject}</p>
      </div>
    </Link>
  );
}
