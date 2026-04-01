/**
 * Meetings hub — list of all meetings with calendar sync, status filters,
 * and time-based grouping (Today, This Week, Earlier).
 */
import {
  Video,
  RefreshCw,
  Calendar as CalendarIcon,
  Clock,
  AlertCircle,
  CheckCircle2,
  Loader2,
  Search,
  Plus,
} from 'lucide-react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useState, useMemo } from 'react';
import { useTRPC } from '@/providers/query-provider';
import type { Outputs } from '@zero/server/trpc';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { authProxy } from '@/lib/auth-proxy';
import type { Route } from './+types/page';
import { Link } from 'react-router';
import { cn } from '@/lib/utils';
import {
  format,
  isToday,
  isThisWeek,
  parseISO,
  formatDistanceToNow,
} from 'date-fns';

type Meeting = Outputs['meet']['listMeetings']['meetings'][number];
type MeetingStatus = Meeting['status'];

// Auth guard
export async function clientLoader({ request }: Route.ClientLoaderArgs) {
  const session = await authProxy.api.getSession({ headers: request.headers });
  if (!session) return Response.redirect(`${import.meta.env.VITE_PUBLIC_APP_URL}/login`);
  return {};
}

const STATUS_CONFIG: Record<
  MeetingStatus,
  { label: string; className: string; icon: typeof Video }
> = {
  scheduled: {
    label: 'Scheduled',
    className: 'text-blue-600 bg-blue-50 dark:bg-blue-950/30 dark:text-blue-400',
    icon: CalendarIcon,
  },
  bot_joining: {
    label: 'Joining',
    className: 'text-yellow-600 bg-yellow-50 dark:bg-yellow-950/30 dark:text-yellow-400',
    icon: Loader2,
  },
  recording: {
    label: 'Recording',
    className: 'text-red-600 bg-red-50 dark:bg-red-950/30 dark:text-red-400',
    icon: Video,
  },
  processing: {
    label: 'Processing',
    className: 'text-orange-600 bg-orange-50 dark:bg-orange-950/30 dark:text-orange-400',
    icon: Loader2,
  },
  ready: {
    label: 'Ready',
    className: 'text-green-600 bg-green-50 dark:bg-green-950/30 dark:text-green-400',
    icon: CheckCircle2,
  },
  failed: {
    label: 'Failed',
    className: 'text-red-600 bg-red-50 dark:bg-red-950/30 dark:text-red-400',
    icon: AlertCircle,
  },
  cancelled: {
    label: 'Cancelled',
    className: 'text-muted-foreground bg-muted/50',
    icon: AlertCircle,
  },
};

const FILTER_OPTIONS: { value: MeetingStatus | 'all'; label: string }[] = [
  { value: 'all', label: 'All' },
  { value: 'scheduled', label: 'Scheduled' },
  { value: 'recording', label: 'Recording' },
  { value: 'ready', label: 'Ready' },
  { value: 'failed', label: 'Failed' },
];

export default function MeetingsPage() {
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const [statusFilter, setStatusFilter] = useState<MeetingStatus | 'all'>('all');
  const [searchQuery, setSearchQuery] = useState('');

  // Fetch meetings
  const { data, isLoading } = useQuery(
    trpc.meet.listMeetings.queryOptions({
      status: statusFilter === 'all' ? undefined : statusFilter,
      search: searchQuery || undefined,
      limit: 100,
    }),
  );
  const meetings = useMemo(() => data?.meetings ?? [], [data]);

  // Sync from calendar
  const syncMutation = useMutation(trpc.meet.syncFromCalendar.mutationOptions());

  const handleSync = () => {
    syncMutation.mutate(
      undefined,
      {
        onSuccess: () => {
          queryClient.invalidateQueries({ queryKey: trpc.meet.listMeetings.queryKey() });
        },
      },
    );
  };

  // Group meetings by time period
  const grouped = useMemo(() => {
    const today: Meeting[] = [];
    const thisWeek: Meeting[] = [];
    const earlier: Meeting[] = [];

    for (const m of meetings) {
      const date = new Date(m.startsAt);
      if (isToday(date)) today.push(m);
      else if (isThisWeek(date)) thisWeek.push(m);
      else earlier.push(m);
    }
    return { today, thisWeek, earlier };
  }, [meetings]);

  return (
    <div className="flex h-full flex-col">
      {/* Header */}
      <div className="flex items-center justify-between border-b px-6 py-4">
        <div className="flex items-center gap-3">
          <Video className="text-muted-foreground h-5 w-5" />
          <h1 className="text-lg font-semibold">Meetings</h1>
        </div>
        <div className="flex items-center gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={handleSync}
            disabled={syncMutation.isPending}
          >
            <RefreshCw
              className={cn('mr-1.5 h-3.5 w-3.5', syncMutation.isPending && 'animate-spin')}
            />
            {syncMutation.isPending ? 'Syncing...' : 'Sync Calendar'}
          </Button>
        </div>
      </div>

      {/* Filters + search */}
      <div className="flex items-center gap-3 border-b px-6 py-3">
        <div className="relative flex-1">
          <Search className="text-muted-foreground absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2" />
          <Input
            placeholder="Search meetings..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="h-8 pl-8"
          />
        </div>
        <div className="flex gap-1">
          {FILTER_OPTIONS.map((opt) => (
            <Button
              key={opt.value}
              variant={statusFilter === opt.value ? 'default' : 'ghost'}
              size="sm"
              className="h-7 px-2.5 text-xs"
              onClick={() => setStatusFilter(opt.value)}
            >
              {opt.label}
            </Button>
          ))}
        </div>
      </div>

      {/* Meeting list */}
      <div className="flex-1 overflow-y-auto px-6 py-4">
        {isLoading ? (
          <div className="flex items-center justify-center py-20">
            <Loader2 className="text-muted-foreground h-6 w-6 animate-spin" />
          </div>
        ) : meetings.length === 0 ? (
          <EmptyState onSync={handleSync} isSyncing={syncMutation.isPending} />
        ) : (
          <div className="space-y-6">
            {grouped.today.length > 0 && (
              <MeetingSection title="Today" meetings={grouped.today} />
            )}
            {grouped.thisWeek.length > 0 && (
              <MeetingSection title="This Week" meetings={grouped.thisWeek} />
            )}
            {grouped.earlier.length > 0 && (
              <MeetingSection title="Earlier" meetings={grouped.earlier} />
            )}
          </div>
        )}
      </div>
    </div>
  );
}

function MeetingSection({ title, meetings }: { title: string; meetings: Meeting[] }) {
  return (
    <div>
      <h2 className="text-muted-foreground mb-2 text-xs font-medium uppercase tracking-wider">
        {title}
      </h2>
      <div className="space-y-1">
        {meetings.map((m) => (
          <MeetingRow key={m.id} meeting={m} />
        ))}
      </div>
    </div>
  );
}

function MeetingRow({ meeting }: { meeting: Meeting }) {
  const status = STATUS_CONFIG[meeting.status] ?? STATUS_CONFIG.scheduled;
  const StatusIcon = status.icon;
  const startsAt = new Date(meeting.startsAt);

  return (
    <Link
      to={`/mail/meetings/${meeting.id}`}
      className="hover:bg-accent/50 flex items-center gap-3 rounded-lg px-3 py-2.5 transition-colors"
    >
      {/* Status icon */}
      <div className={cn('flex h-8 w-8 items-center justify-center rounded-full', status.className)}>
        <StatusIcon className="h-4 w-4" />
      </div>

      {/* Title + time */}
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-medium">{meeting.title}</p>
        <p className="text-muted-foreground text-xs">
          {format(startsAt, 'MMM d · h:mm a')}
          {meeting.endsAt && ` – ${format(new Date(meeting.endsAt), 'h:mm a')}`}
        </p>
      </div>

      {/* Status badge */}
      <Badge variant="secondary" className={cn('text-xs', status.className)}>
        {status.label}
      </Badge>

      {/* Summary indicator */}
      {meeting.aiSummary && (
        <Badge variant="outline" className="text-xs">
          Recap
        </Badge>
      )}
    </Link>
  );
}

function EmptyState({
  onSync,
  isSyncing,
}: {
  onSync: () => void;
  isSyncing: boolean;
}) {
  return (
    <div className="flex flex-col items-center justify-center py-20 text-center">
      <div className="bg-muted mb-4 flex h-12 w-12 items-center justify-center rounded-full">
        <Video className="text-muted-foreground h-6 w-6" />
      </div>
      <h3 className="mb-1 text-sm font-medium">No meetings yet</h3>
      <p className="text-muted-foreground mb-4 max-w-sm text-sm">
        Sync your Google Calendar to import meetings with Google Meet links. We&apos;ll
        automatically record and summarize them.
      </p>
      <Button onClick={onSync} disabled={isSyncing}>
        <RefreshCw className={cn('mr-1.5 h-4 w-4', isSyncing && 'animate-spin')} />
        Sync from Calendar
      </Button>
    </div>
  );
}
