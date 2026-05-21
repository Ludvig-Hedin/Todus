/**
 * Home page — iOS/macOS parity redesign.
 * Section headers: icon + title + count badge + "+" action button.
 * Sections: Today's Events (Calendar CTA) → Due Tasks → Recent Emails.
 */
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
  Sparkles,
} from 'lucide-react';
import { useInfiniteQuery, useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { formatDistanceToNow, isToday, format, startOfDay, endOfDay } from 'date-fns';
import { authClient, useSession } from '@/lib/auth-client';
import { useTRPC } from '@/providers/query-provider';
import type { Outputs } from '@zero/server/trpc';
import { Button } from '@/components/ui/button';
import { BackgroundRefreshIndicator } from '@/components/ui/background-refresh-indicator';
import { useThread } from '@/hooks/use-threads';
import { Badge } from '@/components/ui/badge';
import { useSettings } from '@/hooks/use-settings';
import { authProxy } from '@/lib/auth-proxy';
import { upsertTaskInTaskCaches } from '@/lib/task-cache';
import type { Route } from './+types/page';
import { Link, redirect } from 'react-router';
import { cn } from '@/lib/utils';
import { useMemo } from 'react';
import { toast } from 'sonner';

type Task = Outputs['tasks']['list']['tasks'][number];
type CalendarEvent = Outputs['calendar']['events']['events'][number];
type AssistantBriefing = Outputs['assistant']['getBriefing'];

// Auth guard
export async function clientLoader({ request }: Route.ClientLoaderArgs) {
  const session = await authProxy.api.getSession({ headers: request.headers });
  if (!session) throw redirect('/login');
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
  isUpdating = false,
}: {
  icon: React.ComponentType<{ className?: string }>;
  title: string;
  count?: number;
  linkTo?: string;
  onAdd?: () => void;
  isUpdating?: boolean;
}) {
  return (
    <div className="mb-3 flex items-center gap-2">
      <Icon className="text-muted-foreground h-4 w-4 shrink-0" />
      <span className="text-[15px] font-semibold leading-none">{title}</span>
      {typeof count === 'number' && count > 0 && (
        <span className="bg-muted text-muted-foreground rounded-full px-1.5 py-0.5 text-[11px] font-bold">
          {count}
        </span>
      )}
      <div className="ml-auto flex items-center gap-1">
        {isUpdating && <BackgroundRefreshIndicator className="mr-1" />}
        {linkTo && (
          <Button
            asChild
            variant="ghost"
            size="sm"
            className="text-muted-foreground h-7 gap-1 px-2 text-[12px]"
          >
            <Link to={linkTo}>
              See all
              <ArrowRight className="h-3 w-3" />
            </Link>
          </Button>
        )}
        {onAdd && (
          <Button variant="ghost" size="icon" className="h-7 w-7" onClick={onAdd}>
            <Plus className="h-3.5 w-3.5" />
          </Button>
        )}
      </div>
    </div>
  );
}

// ─── Section container with card styling ──────────────────────────────────────

function Section({ children, className }: { children: React.ReactNode; className?: string }) {
  return <div className={cn('bg-card rounded-xl border px-4 py-4', className)}>{children}</div>;
}

export default function HomePage() {
  const { data: session } = useSession();
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const { data: settings } = useSettings();
  const firstName = session?.user?.name?.split(' ')[0] ?? '';
  const assistantPolicy = settings?.settings.assistantAutomationPolicy;
  const showHomeBriefing =
    assistantPolicy?.briefingEnabled !== false && assistantPolicy?.showHomeBriefing !== false;

  const briefingQuery = useQuery(
    trpc.assistant.getBriefing.queryOptions(undefined, {
      enabled: showHomeBriefing,
      staleTime: 60 * 1000,
    }),
  );

  // Tasks — fetch all, filter client-side for "today or pending"
  const { data: tasksData, isLoading: tasksLoading, isFetching: isFetchingTasks } = useQuery(
    trpc.tasks.list.queryOptions(
      { limit: 100 },
      {
        staleTime: 1000 * 60 * 5,
        refetchOnMount: false,
      },
    ),
  );
  const isTasksRefreshing = !!tasksData && !tasksLoading && isFetchingTasks;

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
    onSuccess: ({ task }) => {
      upsertTaskInTaskCaches(queryClient, task);
    },
    onError: (err) => {
      console.error('Failed to update task:', err);
      toast.error('Could not update task. Please try again.');
    },
  });

  // Today's calendar events
  const todayStart = startOfDay(new Date()).toISOString();
  const todayEnd = endOfDay(new Date()).toISOString();
  const { data: eventsData, isLoading: eventsLoading, isFetching: isFetchingEvents } = useQuery(
    trpc.calendar.events.queryOptions(
      { timeMin: todayStart, timeMax: todayEnd },
      {
        staleTime: 1000 * 60 * 3,
        refetchOnMount: false,
      },
    ),
  );
  const todayEvents = eventsData?.events ?? [];
  const calendarScopeMissing = eventsData?.scopeMissing ?? false;
  const isEventsRefreshing = !!eventsData && !eventsLoading && isFetchingEvents;

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
  const isThreadsRefreshing =
    !!threadsQuery.data && !threadsQuery.isLoading && threadsQuery.isFetching;

  return (
    <div className="bg-background flex h-screen flex-col overflow-y-auto">
      <div className="mx-auto w-full max-w-[1280px] px-8 py-8 xl:px-12">
        {/* Greeting — first name only, date subtitle */}
        <div className="mb-8">
          <h1 className="text-[26px] font-bold tracking-tight">
            {getGreeting()}
            {firstName ? `, ${firstName}` : ''}
          </h1>
          <p className="text-muted-foreground mt-0.5 text-[13px]">
            {format(new Date(), 'EEEE, MMMM d')}
          </p>
        </div>

        <div className="flex flex-col gap-4">
          {showHomeBriefing && (
            <Section className="space-y-4">
              <SectionHeader
                icon={Sparkles}
                title="Assistant Briefing"
                isUpdating={!!briefingQuery.data && !briefingQuery.isLoading && briefingQuery.isFetching}
              />
              {briefingQuery.isLoading ? (
                <div className="flex flex-col gap-2">
                  {['briefing-skeleton-1', 'briefing-skeleton-2', 'briefing-skeleton-3'].map(
                    (key) => (
                      <div key={key} className="bg-muted/50 h-12 animate-pulse rounded-lg" />
                    ),
                  )}
                </div>
              ) : briefingQuery.isError ? (
                <div className="flex items-center justify-between gap-3 rounded-lg border border-destructive/30 bg-destructive/5 px-3 py-2.5 text-[13px] text-destructive">
                  <p>Couldn&apos;t load your briefing.</p>
                  <button
                    type="button"
                    onClick={() => void briefingQuery.refetch()}
                    className="rounded-md border border-destructive/40 px-2 py-1 text-[12px] font-medium transition-colors hover:bg-destructive/10"
                  >
                    Retry
                  </button>
                </div>
              ) : briefingQuery.data ? (
                <AssistantBriefingBlock briefing={briefingQuery.data} />
              ) : null}
            </Section>
          )}

          {/* ── Desktop 3-column grid: Events / Tasks / Recent Emails ────── */}
          <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
            {/* Today's Events */}
            <Section>
              <SectionHeader
                icon={CalendarDays}
                title="Today's Events"
                count={todayEvents.length}
                linkTo="/mail/calendar"
                isUpdating={isEventsRefreshing}
              />
              {eventsLoading ? (
                <div className="flex flex-col gap-2">
                  {['event-skeleton-1', 'event-skeleton-2'].map((key) => (
                    <div key={key} className="bg-muted/50 h-10 animate-pulse rounded-lg" />
                  ))}
                </div>
              ) : calendarScopeMissing ? (
                /* User connected Google but hasn't granted calendar scope — prompt re-auth.
                   callbackURL MUST be absolute (origin-qualified). Relative URLs are
                   resolved against the Better Auth backend origin (api.todus.app) and
                   land the user on api.todus.app/mail/home → 404 after consent. */
                <button
                  type="button"
                  onClick={async () => {
                    try {
                      await authClient.linkSocial({
                        provider: 'google',
                        callbackURL: `${window.location.origin}/mail/home`,
                      });
                    } catch (error) {
                      console.error('Failed to start Google reconnect:', error);
                      toast.error('Could not start Google reconnect. Please try again.');
                    }
                  }}
                  className="bg-muted/30 hover:bg-muted/50 flex w-full items-center gap-3 rounded-lg border border-dashed px-4 py-3.5 text-left transition-colors"
                >
                  <CalendarDays className="text-muted-foreground h-5 w-5 shrink-0" />
                  <div className="min-w-0 flex-1">
                    <p className="text-[13px] font-medium">Allow calendar access</p>
                    <p className="text-muted-foreground text-[12px]">
                      Grant the calendar permission to see today&apos;s events.
                    </p>
                  </div>
                  <ExternalLink className="text-muted-foreground h-3.5 w-3.5 shrink-0" />
                </button>
              ) : todayEvents.length === 0 ? (
                <div className="flex flex-col items-center gap-2 py-3 text-center">
                  <CalendarDays className="text-muted-foreground/40 h-7 w-7" />
                  <p className="text-muted-foreground text-[13px]">No events today</p>
                </div>
              ) : (
                <div className="divide-border/60 flex flex-col divide-y">
                  {todayEvents.map((event) => (
                    <CalendarEventRow key={event.id} event={event} />
                  ))}
                </div>
              )}
            </Section>

            {/* Due Tasks */}
            <Section>
              <SectionHeader
                icon={CheckSquare2}
                title="Due Tasks"
                count={todayTasks.length}
                linkTo="/mail/tasks"
                isUpdating={isTasksRefreshing}
              />
              {tasksLoading ? (
                <div className="flex flex-col gap-2">
                  {['task-skeleton-1', 'task-skeleton-2', 'task-skeleton-3'].map((key) => (
                    <div key={key} className="bg-muted/50 h-9 animate-pulse rounded-lg" />
                  ))}
                </div>
              ) : todayTasks.length === 0 ? (
                <div className="flex flex-col items-center gap-2 py-3 text-center">
                  <CheckCircle2 className="text-muted-foreground/40 h-7 w-7" />
                  <p className="text-muted-foreground text-[13px]">All caught up!</p>
                  <Button asChild variant="outline" size="sm" className="h-7 text-xs">
                    <Link to="/mail/tasks">
                      <Plus className="mr-1 h-3 w-3" />
                      New task
                    </Link>
                  </Button>
                </div>
              ) : (
                <div className="divide-border/60 flex flex-col divide-y">
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

            {/* Recent Emails */}
            <Section>
              <SectionHeader
                icon={Mail}
                title="Recent Emails"
                linkTo="/mail/inbox"
                isUpdating={isThreadsRefreshing}
              />
              {threadsQuery.isLoading ? (
                <div className="flex flex-col gap-2">
                  {['mail-skeleton-1', 'mail-skeleton-2', 'mail-skeleton-3'].map((key) => (
                    <div key={key} className="bg-muted/50 h-11 animate-pulse rounded-lg" />
                  ))}
                </div>
              ) : recentThreadIds.length === 0 ? (
                <div className="flex flex-col items-center gap-2 py-3 text-center">
                  <Inbox className="text-muted-foreground/40 h-7 w-7" />
                  <p className="text-muted-foreground text-[13px]">Your inbox is empty</p>
                </div>
              ) : (
                <div className="divide-border/60 flex flex-col divide-y">
                  {recentThreadIds.map((id) => (
                    <EmailThreadRow key={id} threadId={id} />
                  ))}
                </div>
              )}
            </Section>
          </div>
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
        className="text-muted-foreground hover:text-primary shrink-0 transition-colors"
      >
        {task.status === 'done' ? (
          <CheckCircle2 className="text-primary h-4 w-4" />
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
          <p className="text-muted-foreground text-[11px]">Due today</p>
        )}
      </div>
      {task.priority && task.priority !== 'none' && (
        <Badge
          variant="secondary"
          className={cn(
            'h-4 shrink-0 border-0 px-1.5 text-[10px] font-medium',
            task.priority === 'high' &&
              'bg-red-50 text-red-600 dark:bg-red-950/30 dark:text-red-400',
            task.priority === 'medium' &&
              'bg-yellow-50 text-yellow-600 dark:bg-yellow-950/30 dark:text-yellow-400',
            task.priority === 'low' &&
              'bg-blue-50 text-blue-600 dark:bg-blue-950/30 dark:text-blue-400',
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
    return <div className="bg-muted/50 my-1 h-11 animate-pulse rounded-lg" />;
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
      className="hover:bg-accent/40 -mx-1 flex items-start gap-3 rounded-lg px-1 py-3 transition-colors"
    >
      {/* Unread dot */}
      <div className="mt-1.5 shrink-0">
        <div
          className={cn('h-2 w-2 rounded-full', latest.unread ? 'bg-primary' : 'bg-transparent')}
        />
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex items-baseline justify-between gap-2">
          <p
            className={cn('truncate text-[13px]', latest.unread ? 'font-semibold' : 'font-medium')}
          >
            {senderName}
          </p>
          {time && <p className="text-muted-foreground shrink-0 text-[11px]">{time}</p>}
        </div>
        <p className="text-muted-foreground truncate text-[12px]">{subject}</p>
      </div>
    </Link>
  );
}

function CalendarEventRow({ event }: { event: CalendarEvent }) {
  const timeLabel = event.allDay
    ? 'All day'
    : event.startTime && event.endTime
      ? `${format(new Date(event.startTime), 'h:mm a')} - ${format(new Date(event.endTime), 'h:mm a')}`
      : null;

  const content = (
    <div
      className="border-border bg-card hover:bg-accent/20 flex items-start gap-3 rounded-lg border px-3 py-3 transition-colors"
      style={{ borderLeftColor: event.color, borderLeftWidth: 3 }}
    >
      <div className="min-w-0 flex-1">
        <p className="truncate text-[13px] font-medium">{event.title}</p>
        <p className="text-muted-foreground mt-0.5 truncate text-[11px]">{timeLabel}</p>
        {event.location ? (
          <p className="text-muted-foreground mt-1 truncate text-[11px]">{event.location}</p>
        ) : null}
      </div>
    </div>
  );

  if (event.htmlLink) {
    return (
      <a href={event.htmlLink} target="_blank" rel="noopener noreferrer" className="block">
        {content}
      </a>
    );
  }

  return content;
}

function AssistantBriefingBlock({ briefing }: { briefing: AssistantBriefing }) {
  const priorityCards = [
    briefing.today.urgentReply
      ? {
          title: 'Urgent reply',
          detail: briefing.today.urgentReply.title,
          href: briefing.today.urgentReply.threadId
            ? `/mail/inbox?threadId=${briefing.today.urgentReply.threadId}`
            : null,
        }
      : null,
    briefing.today.topTask
      ? {
          title: 'Top task',
          detail: briefing.today.topTask.title,
          href: '/mail/tasks',
        }
      : null,
    briefing.today.nextEvent
      ? {
          title: 'Next event',
          detail: briefing.today.nextEvent.title,
          href: `/mail/meetings/${briefing.today.nextEvent.id}`,
        }
      : null,
  ].filter(Boolean) as Array<{ title: string; detail: string; href: string | null }>;

  const groupedQueues = [
    { title: 'Needs You', items: briefing.needsYou, empty: 'No reply or decision blockers right now.' },
    { title: 'Waiting On', items: briefing.waitingOn, empty: 'Nothing currently tracked as waiting on someone else.' },
    { title: 'Prepared', items: briefing.prepared, empty: 'No prepared drafts or actions waiting for approval.' },
  ];

  return (
    <div className="space-y-4">
      {priorityCards.length > 0 && (
        <div className="grid gap-2 sm:grid-cols-3">
          {priorityCards.map((card) => {
            const content = (
              <div className="rounded-lg border border-border/60 bg-muted/20 px-3 py-3">
                <p className="text-muted-foreground text-[10px] font-semibold uppercase tracking-[0.1em]">
                  {card.title}
                </p>
                <p className="mt-1 text-[13px] font-medium tracking-[-0.01em] text-foreground">
                  {card.detail}
                </p>
              </div>
            );

            return card.href ? (
              <Link key={card.title} to={card.href} className="block">
                {content}
              </Link>
            ) : (
              <div key={card.title}>{content}</div>
            );
          })}
        </div>
      )}

      <div className="grid gap-3 lg:grid-cols-3">
        {groupedQueues.map((section) => (
          <div key={section.title} className="space-y-2">
            <div className="flex items-center justify-between">
              <p className="text-[11px] font-semibold uppercase tracking-[0.1em] text-muted-foreground">
                {section.title}
              </p>
              <Badge variant="outline" className="h-5 rounded-full px-1.5 text-[10px]">
                {section.items.length}
              </Badge>
            </div>
            {section.items.length === 0 ? (
              <div className="rounded-lg border border-dashed border-border/60 bg-muted/10 px-3 py-3 text-[12px] leading-5 text-muted-foreground">
                {section.empty}
              </div>
            ) : (
              <div className="space-y-2">
                {section.items.slice(0, 3).map((item) => {
                  const href =
                    'threadId' in item && item.threadId
                      ? `/mail/inbox?threadId=${item.threadId}`
                      : 'meetingId' in item && item.meetingId
                        ? `/mail/meetings/${item.meetingId}`
                        : null;
                  const content = (
                    <div className="rounded-lg border border-border/60 bg-muted/15 px-3 py-3">
                      <p className="text-[13px] font-medium tracking-[-0.01em] text-foreground">
                        {item.title}
                      </p>
                      <p className="text-muted-foreground mt-1 text-[12px] leading-5">
                        {item.summary}
                      </p>
                    </div>
                  );
                  return href ? (
                    <Link key={item.id} to={href} className="block">
                      {content}
                    </Link>
                  ) : (
                    <div key={item.id}>{content}</div>
                  );
                })}
              </div>
            )}
          </div>
        ))}
      </div>

      {(briefing.upcomingMeetings.length > 0 || briefing.changedSinceLastTime.length > 0) && (
        <div className="grid gap-3 lg:grid-cols-2">
          <div className="space-y-2">
            <p className="text-[11px] font-semibold uppercase tracking-[0.1em] text-muted-foreground">
              Upcoming
            </p>
            <div className="space-y-2">
              {briefing.upcomingMeetings.slice(0, 3).map((meeting) => (
                <Link
                  key={meeting.id}
                  to={`/mail/meetings/${meeting.id}`}
                  className="block rounded-lg border border-border/60 bg-muted/15 px-3 py-3"
                >
                  <p className="text-[13px] font-medium tracking-[-0.01em] text-foreground">
                    {meeting.title}
                  </p>
                  <p className="text-muted-foreground mt-1 text-[12px] leading-5">
                    {format(new Date(meeting.startsAt), 'PPp')}
                  </p>
                </Link>
              ))}
            </div>
          </div>

          <div className="space-y-2">
            <p className="text-[11px] font-semibold uppercase tracking-[0.1em] text-muted-foreground">
              Changed Since Last Time
            </p>
            <div className="space-y-2">
              {briefing.changedSinceLastTime.slice(0, 4).map((item) => (
                <div
                  key={`${item.type}-${item.id}`}
                  className="rounded-lg border border-border/60 bg-muted/15 px-3 py-3"
                >
                  <p className="text-[13px] font-medium tracking-[-0.01em] text-foreground">
                    {item.title}
                  </p>
                  <p className="text-muted-foreground mt-1 text-[12px] leading-5">
                    {item.summary}
                  </p>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
