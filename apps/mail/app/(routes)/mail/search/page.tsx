import {
  Search,
  CalendarIcon,
  CheckCircle2,
  Circle,
  Mail,
  Loader2,
  Plus,
  Pencil,
} from 'lucide-react';
import { useQuery, useInfiniteQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { useTRPC } from '@/providers/query-provider';
import { useState, useEffect, useRef } from 'react';
import type { Outputs } from '@zero/server/trpc';
import { Link, useNavigate } from 'react-router';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { authProxy } from '@/lib/auth-proxy';
import type { Route } from './+types/page';
import { format, isValid } from 'date-fns';
import { cn } from '@/lib/utils';
import { toast } from 'sonner';

type Task = Outputs['tasks']['list']['tasks'][number];

// Auth guard
export async function clientLoader({ request }: Route.ClientLoaderArgs) {
  const session = await authProxy.api.getSession({ headers: request.headers });
  if (!session) return Response.redirect(`${import.meta.env.VITE_PUBLIC_APP_URL}/login`);
  return {};
}

type Tab = 'all' | 'emails' | 'tasks';

const PRIORITY_CLASS: Record<string, string> = {
  high: 'bg-red-50 text-red-600 dark:bg-red-950/30 dark:text-red-400',
  medium: 'bg-yellow-50 text-yellow-600 dark:bg-yellow-950/30 dark:text-yellow-400',
  low: 'bg-blue-50 text-blue-600 dark:bg-blue-950/30 dark:text-blue-400',
};

// Simple value-based debounce hook
function useDebounceValue(value: string, delay: number) {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const timer = setTimeout(() => setDebounced(value), delay);
    return () => clearTimeout(timer);
  }, [value, delay]);
  return debounced;
}

export default function SearchPage() {
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const [query, setQuery] = useState('');
  const [tab, setTab] = useState<Tab>('all');
  const debouncedQuery = useDebounceValue(query, 300);

  // Quick-add task state
  const [quickTaskTitle, setQuickTaskTitle] = useState('');
  const quickTaskRef = useRef<HTMLInputElement>(null);

  // Create task mutation — used for inline quick-add from search
  const createTask = useMutation({
    ...trpc.tasks.create.mutationOptions(),
    onSuccess: () => {
      void queryClient.invalidateQueries(trpc.tasks.list.queryFilter());
      setQuickTaskTitle('');
      quickTaskRef.current?.focus();
    },
    onError: (err) => {
      // Keep input so user can retry
      console.error('Failed to create task:', err);
      toast.error(err instanceof Error ? err.message : 'Failed to create task. Please try again.');
    },
  });

  const handleQuickTask = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key !== 'Enter') return;
    // Guard against duplicate submissions on rapid Enter presses
    if (createTask.isPending) return;
    const title = quickTaskTitle.trim();
    if (!title) return;
    createTask.mutate({ title, status: 'todo', priority: 'none', dueDate: null, folderId: null });
  };

  // Tasks search
  const { data: tasksData, isLoading: tasksLoading } = useQuery(
    trpc.tasks.list.queryOptions(
      { search: debouncedQuery || undefined, limit: 20 },
      { enabled: debouncedQuery.length > 0 && tab !== 'emails' },
    ),
  );
  const tasks = tasksData?.tasks ?? [];

  // Email thread search via listThreads with q param
  const { data: threadsData, isLoading: threadsLoading } = useInfiniteQuery(
    trpc.mail.listThreads.infiniteQueryOptions(
      { folder: 'inbox', q: debouncedQuery, maxResults: 20 },
      {
        initialCursor: '',
        getNextPageParam: (lastPage) => lastPage?.nextPageToken ?? null,
        enabled: debouncedQuery.length > 0 && tab !== 'tasks',
        staleTime: 30 * 1000,
      },
    ),
  );
  const threads = threadsData?.pages.flatMap((p) => p?.threads ?? []) ?? [];

  const isLoading = (tab !== 'emails' && tasksLoading) || (tab !== 'tasks' && threadsLoading);

  const showEmptyState =
    debouncedQuery.length > 0 && !isLoading && tasks.length === 0 && threads.length === 0;
  const showPlaceholder = debouncedQuery.length === 0;

  const taskCount = tasks.length;
  const emailCount = threads.length;
  const totalCount = taskCount + emailCount;

  return (
    <div className="bg-background flex h-screen flex-col overflow-hidden">
      {/* Header */}
      <div className="border-b px-6 py-4">
        <h1 className="mb-3 text-xl font-semibold tracking-tight">Search</h1>
        <div className="relative">
          <Search className="text-muted-foreground absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2" />
          <Input
            autoFocus
            placeholder="Search emails, tasks..."
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            className="h-10 pl-9"
          />
        </div>
      </div>

      {/* Tabs — only shown when there are results */}
      {debouncedQuery.length > 0 && !showPlaceholder && (
        <div className="border-b px-6 py-2">
          <Tabs value={tab} onValueChange={(v) => setTab(v as Tab)}>
            <TabsList className="h-8">
              <TabsTrigger value="all" className="px-3 text-xs">
                All {totalCount > 0 && `(${totalCount})`}
              </TabsTrigger>
              <TabsTrigger value="emails" className="px-3 text-xs">
                Emails {emailCount > 0 && `(${emailCount})`}
              </TabsTrigger>
              <TabsTrigger value="tasks" className="px-3 text-xs">
                Tasks {taskCount > 0 && `(${taskCount})`}
              </TabsTrigger>
            </TabsList>
          </Tabs>
        </div>
      )}

      {/* Results */}
      <div className="flex-1 overflow-y-auto px-6 py-4">
        {showPlaceholder ? (
          // Initial state — quick-create shortcuts (matches macOS search quick actions)
          <div className="mx-auto w-full max-w-lg pt-6">
            <p className="text-muted-foreground mb-4 text-[11px] font-semibold uppercase tracking-wide">
              Quick Actions
            </p>
            <div className="flex flex-col gap-3">
              {/* Inline quick-add task — type title, press Enter */}
              <div className="bg-card flex items-center gap-3 rounded-xl border px-4 py-3">
                <Plus className="text-muted-foreground h-4 w-4 shrink-0" />
                <Input
                  ref={quickTaskRef}
                  value={quickTaskTitle}
                  onChange={(e) => setQuickTaskTitle(e.target.value)}
                  onKeyDown={handleQuickTask}
                  placeholder="New task… (press Enter to create)"
                  className="h-auto border-0 bg-transparent p-0 text-[13px] shadow-none focus-visible:ring-0"
                  disabled={createTask.isPending}
                />
                {createTask.isPending && (
                  <Loader2 className="text-muted-foreground h-3.5 w-3.5 shrink-0 animate-spin" />
                )}
              </div>

              {/* Compose email — links to compose page */}
              <Button
                variant="outline"
                className="h-auto justify-start gap-3 rounded-xl px-4 py-3 text-left"
                onClick={() => navigate('/mail/compose')}
              >
                <Pencil className="text-muted-foreground h-4 w-4 shrink-0" />
                <span className="text-foreground text-[13px] font-normal">Compose new email…</span>
              </Button>
            </div>

            <p className="text-muted-foreground mt-8 text-center text-[12px]">
              Or type above to search emails and tasks
            </p>
          </div>
        ) : isLoading ? (
          <div className="flex h-32 items-center justify-center">
            <Loader2 className="text-muted-foreground h-5 w-5 animate-spin" />
          </div>
        ) : showEmptyState ? (
          <div className="flex h-32 flex-col items-center justify-center gap-2 text-center">
            <p className="font-medium">No results for &quot;{debouncedQuery}&quot;</p>
            <p className="text-muted-foreground text-sm">Try a different search term</p>
          </div>
        ) : (
          <div className="flex flex-col gap-6">
            {/* Emails section */}
            {tab !== 'tasks' && threads.length > 0 && (
              <section>
                <p className="text-muted-foreground mb-2 text-xs font-semibold uppercase tracking-wide">
                  Emails
                </p>
                <div className="flex flex-col gap-1">
                  {threads.map((thread) => (
                    <EmailResult key={thread.id} thread={thread} />
                  ))}
                </div>
              </section>
            )}

            {/* Tasks section */}
            {tab !== 'emails' && tasks.length > 0 && (
              <section>
                <p className="text-muted-foreground mb-2 text-xs font-semibold uppercase tracking-wide">
                  Tasks
                </p>
                <div className="flex flex-col gap-1">
                  {tasks.map((task) => (
                    <TaskResult key={task.id} task={task} />
                  ))}
                </div>
              </section>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

// ─── EmailResult ────────────────────────────────────────────────────────────

interface EmailResultProps {
  thread: { id: string; subject?: string; snippet?: string; latestMessageSentAt?: string };
}

function EmailResult({ thread }: EmailResultProps) {
  return (
    <Link
      to={`/mail/inbox?threadId=${thread.id}`}
      className="border-border bg-card hover:bg-accent/20 flex items-start gap-3 rounded-xl border p-3.5 transition-colors"
    >
      <Mail className="text-muted-foreground mt-0.5 h-4 w-4 shrink-0" />
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-medium">{thread.subject || '(no subject)'}</p>
        {thread.snippet && (
          <p className="text-muted-foreground mt-0.5 line-clamp-1 text-xs">{thread.snippet}</p>
        )}
      </div>
      {thread.latestMessageSentAt && (() => {
        const d = new Date(thread.latestMessageSentAt);
        return isValid(d) ? (
          <span className="text-muted-foreground shrink-0 text-[11px]">{format(d, 'MMM d')}</span>
        ) : null;
      })()}
    </Link>
  );
}

// ─── TaskResult ─────────────────────────────────────────────────────────────

function TaskResult({ task }: { task: Task }) {
  const isDone = task.status === 'done';

  return (
    <Link
      to="/mail/tasks"
      className={cn(
        'border-border bg-card hover:bg-accent/20 flex items-start gap-3 rounded-xl border p-3.5 transition-colors',
        isDone && 'opacity-60',
      )}
    >
      {isDone ? (
        <CheckCircle2 className="text-primary mt-0.5 h-4 w-4 shrink-0" />
      ) : (
        <Circle className="text-muted-foreground mt-0.5 h-4 w-4 shrink-0" />
      )}
      <div className="min-w-0 flex-1">
        <p
          className={cn(
            'truncate text-sm font-medium',
            isDone && 'text-muted-foreground line-through',
          )}
        >
          {task.title}
        </p>
        {task.description && (
          <p className="text-muted-foreground mt-0.5 line-clamp-1 text-xs">{task.description}</p>
        )}
        <div className="mt-1.5 flex items-center gap-2">
          {task.priority !== 'none' && (
            <Badge
              variant="secondary"
              className={cn(
                'h-4 rounded border-0 px-1.5 text-[10px] font-medium',
                PRIORITY_CLASS[task.priority] ?? '',
              )}
            >
              {task.priority}
            </Badge>
          )}
          {task.dueDate && (() => {
            const d = new Date(task.dueDate);
            return isValid(d) ? (
              <span className="text-muted-foreground flex items-center gap-1 text-[10px]">
                <CalendarIcon className="h-3 w-3" />
                {format(d, 'MMM d')}
              </span>
            ) : null;
          })()}
        </div>
      </div>
    </Link>
  );
}
