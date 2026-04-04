/**
 * Meetings hub — time-grouped list with calendar sync, status filters, and search.
 *
 * Design: Matches the mail list aesthetic — Geist type, tight letter-spacing,
 * neutral hover states, soft borders at 60% opacity, blue accent only for
 * active/unread indicators. Status conveyed through subtle tinted text rather
 * than loud colored badges.
 */
import {
  CalendarIcon,
  Clock,
  AlertCircle,
  CheckCircle2,
  Loader2,
  Search,
  RefreshCw,
} from 'lucide-react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useState, useMemo } from 'react';
import { useTRPC } from '@/providers/query-provider';
import type { Outputs } from '@zero/server/trpc';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { authProxy } from '@/lib/auth-proxy';
import type { Route } from './+types/page';
import { Link } from 'react-router';
import { toast } from 'sonner';
import { cn } from '@/lib/utils';
import {
  format,
  isToday,
  isThisWeek,
} from 'date-fns';

type Meeting = Outputs['meet']['listMeetings']['meetings'][number];
type MeetingStatus = Meeting['status'];

// Auth guard
export async function clientLoader({ request }: Route.ClientLoaderArgs) {
  const session = await authProxy.api.getSession({ headers: request.headers });
  if (!session) return Response.redirect(`${import.meta.env.VITE_PUBLIC_APP_URL}/login`);
  return {};
}

/* ── Status config ─────────────────────────────────────────────────────────
 * Restrained palette: muted tinted text with near-transparent backgrounds.
 * No loud saturated badges — status is secondary information, not primary. */
const STATUS_CONFIG: Record<
  MeetingStatus,
  { label: string; dotClass: string; textClass: string; icon: typeof CalendarIcon }
> = {
  scheduled: {
    label: 'Scheduled',
    dotClass: 'bg-blue-400/70 dark:bg-blue-400/50',
    textClass: 'text-muted-foreground',
    icon: CalendarIcon,
  },
  bot_joining: {
    label: 'Starting',
    dotClass: 'bg-amber-400/80 dark:bg-amber-400/60',
    textClass: 'text-amber-600 dark:text-amber-400',
    icon: Loader2,
  },
  recording: {
    label: 'Recording',
    dotClass: 'bg-red-400/80 dark:bg-red-400/60 animate-pulse',
    textClass: 'text-red-600 dark:text-red-400',
    icon: Clock,
  },
  processing: {
    label: 'Processing',
    dotClass: 'bg-orange-400/70 dark:bg-orange-400/50',
    textClass: 'text-muted-foreground',
    icon: Loader2,
  },
  ready: {
    label: 'Ready',
    dotClass: 'bg-emerald-400/70 dark:bg-emerald-400/50',
    textClass: 'text-muted-foreground',
    icon: CheckCircle2,
  },
  failed: {
    label: 'Failed',
    dotClass: 'bg-red-400/60 dark:bg-red-400/40',
    textClass: 'text-muted-foreground',
    icon: AlertCircle,
  },
  cancelled: {
    label: 'Cancelled',
    dotClass: 'bg-muted-foreground/30',
    textClass: 'text-muted-foreground',
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

  const { data, isLoading } = useQuery(
    trpc.meet.listMeetings.queryOptions({
      status: statusFilter === 'all' ? undefined : statusFilter,
      search: searchQuery || undefined,
      limit: 100,
    }),
  );
  const meetings = useMemo(() => data?.meetings ?? [], [data]);

  const syncMutation = useMutation(trpc.meet.syncFromCalendar.mutationOptions());

  const handleSync = () => {
    syncMutation.mutate(undefined, {
      onSuccess: (data) => {
        queryClient.invalidateQueries({ queryKey: trpc.meet.listMeetings.queryKey() });
        const msg =
          data.synced > 0
            ? `Synced ${data.synced} meeting${data.synced !== 1 ? 's' : ''}${data.autoRecorded ? ` · ${data.autoRecorded} scheduled for recording` : ''}`
            : 'Calendar is up to date';
        toast.success(msg);
      },
      onError: () => {
        toast.error('Failed to sync calendar. Please try again.');
      },
    });
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
      {/* Header — matches settings content header: slim bar, border-border/60 */}
      <div className="flex items-center justify-between border-b border-border/60 px-5 py-3">
        <h1 className="text-[15px] font-semibold tracking-tight">Meetings</h1>
        <Button
          variant="ghost"
          size="sm"
          className="h-7 gap-1.5 text-xs text-muted-foreground"
          onClick={handleSync}
          disabled={syncMutation.isPending}
        >
          <RefreshCw
            className={cn('h-3 w-3', syncMutation.isPending && 'animate-spin')}
          />
          {syncMutation.isPending ? 'Syncing' : 'Sync'}
        </Button>
      </div>

      {/* Search + filters — compact, no heavy dividers */}
      <div className="flex items-center gap-2 border-b border-border/60 px-5 py-2">
        <div className="relative flex-1">
          <Search className="text-muted-foreground/60 absolute left-2 top-1/2 h-3.5 w-3.5 -translate-y-1/2" />
          <Input
            placeholder="Search meetings…"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="h-7 border-none bg-accent/40 pl-7 text-[13px] shadow-none placeholder:text-muted-foreground/50 focus-visible:ring-0"
          />
        </div>
        <div className="flex gap-0.5">
          {FILTER_OPTIONS.map((opt) => (
            <button
              type="button"
              key={opt.value}
              className={cn(
                'rounded-md px-2 py-1 text-[11px] font-medium tracking-tight transition-colors',
                statusFilter === opt.value
                  ? 'bg-accent text-foreground'
                  : 'text-muted-foreground hover:text-foreground',
              )}
              onClick={() => setStatusFilter(opt.value)}
            >
              {opt.label}
            </button>
          ))}
        </div>
      </div>

      {/* Meeting list */}
      <div className="flex-1 overflow-y-auto">
        {isLoading ? (
          <div className="flex items-center justify-center py-20">
            <Loader2 className="text-muted-foreground/50 h-5 w-5 animate-spin" />
          </div>
        ) : meetings.length === 0 ? (
          <EmptyState onSync={handleSync} isSyncing={syncMutation.isPending} />
        ) : (
          <div className="px-2 py-2">
            {grouped.today.length > 0 && (
              <MeetingSection title="Today" meetings={grouped.today} />
            )}
            {grouped.thisWeek.length > 0 && (
              <MeetingSection title="This week" meetings={grouped.thisWeek} />
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

/* ── Section ─────────────────────────────────────────────────────────────── */

function MeetingSection({ title, meetings }: { title: string; meetings: Meeting[] }) {
  return (
    <div className="mb-1">
      {/* Section header — matches mail list section style */}
      <div className="px-3 pb-1 pt-3">
        <span className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground/70">
          {title}
        </span>
      </div>
      <div>
        {meetings.map((m) => (
          <MeetingRow key={m.id} meeting={m} />
        ))}
      </div>
    </div>
  );
}

/* ── Row ─────────────────────────────────────────────────────────────────── */

function MeetingRow({ meeting }: { meeting: Meeting }) {
  const status = STATUS_CONFIG[meeting.status] ?? STATUS_CONFIG.scheduled;
  const startsAt = new Date(meeting.startsAt);

  return (
    <Link
      to={`/mail/meetings/${meeting.id}`}
      className={cn(
        'group mx-1 flex items-center gap-3 rounded-lg px-3 py-2',
        'transition-colors hover:bg-accent/60',
      )}
    >
      {/* Status dot — tiny, like the unread indicator in mail list */}
      <div className={cn('h-1.5 w-1.5 shrink-0 rounded-full', status.dotClass)} />

      {/* Title + time — tight, information-dense */}
      <div className="min-w-0 flex-1">
        <p className="truncate text-[13px] font-medium leading-tight tracking-tight">
          {meeting.title}
        </p>
        <p className="mt-0.5 text-[11px] leading-tight text-muted-foreground">
          {format(startsAt, 'MMM d · h:mm a')}
          {meeting.endsAt && ` – ${format(new Date(meeting.endsAt), 'h:mm a')}`}
        </p>
      </div>

      {/* Status label — quiet, right-aligned */}
      <span className={cn('text-[11px] font-medium tracking-tight', status.textClass)}>
        {status.label}
      </span>

      {/* Recap indicator — subtle dot, like unread indicator */}
      {meeting.aiSummary && (
        <div className="h-1.5 w-1.5 shrink-0 rounded-full bg-[var(--mainBlue)]" title="Recap available" />
      )}
    </Link>
  );
}

/* ── Empty state ─────────────────────────────────────────────────────────── */

function EmptyState({
  onSync,
  isSyncing,
}: {
  onSync: () => void;
  isSyncing: boolean;
}) {
  return (
    <div className="flex flex-col items-center justify-center py-24 text-center">
      <div className="mb-3 flex h-10 w-10 items-center justify-center rounded-full bg-accent/60">
        <CalendarIcon className="h-4 w-4 text-muted-foreground" />
      </div>
      <p className="text-[13px] font-medium tracking-tight">No meetings yet</p>
      <p className="mt-1 max-w-[280px] text-[12px] leading-relaxed text-muted-foreground">
        Sync your calendar to import meetings. They&apos;ll be recorded automatically.
      </p>
      <Button
        variant="outline"
        size="sm"
        className="mt-4 h-7 gap-1.5 text-xs"
        onClick={onSync}
        disabled={isSyncing}
      >
        <RefreshCw className={cn('h-3 w-3', isSyncing && 'animate-spin')} />
        Sync Calendar
      </Button>
    </div>
  );
}
