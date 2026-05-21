/**
 * Meeting detail — video player, AI recap, action items, transcript, Q&A.
 *
 * Design: Sections use subtle background tints (bg-accent/30) instead of
 * bordered cards for softer visual grouping. Section headings are small,
 * uppercase, muted — consistent with section headers in the mail list.
 * Actions are quiet ghost buttons; the primary CTA (Record / Generate)
 * uses outline variant to avoid competing with content.
 */
import {
  ArrowLeft,
  Clock,
  CheckCircle2,
  AlertCircle,
  Loader2,
  Send,
  Sparkles,
  ListChecks,
  MessageSquare,
  Mic,
  Trash2,
  ChevronDown,
  ChevronUp,
} from 'lucide-react';
import { toast } from 'sonner';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useState, useRef, useEffect, useMemo } from 'react';
import { useTRPC } from '@/providers/query-provider';
import type { Outputs } from '@zero/server/trpc';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { authProxy } from '@/lib/auth-proxy';
import type { Route } from './+types/page';
import { Link, useNavigate, useParams, redirect } from 'react-router';
import { cn } from '@/lib/utils';
import { format } from 'date-fns';

type MeetingDetail = Outputs['meet']['getMeeting'];

// Auth guard
export async function clientLoader({ request }: Route.ClientLoaderArgs) {
  const session = await authProxy.api.getSession({ headers: request.headers });
  if (!session) throw redirect('/login');
  return {};
}

/* ── Status config ────────────────────────────────────────────────────────── */
const STATUS_CONFIG: Record<string, { label: string; dotClass: string }> = {
  scheduled: { label: 'Scheduled', dotClass: 'bg-blue-400/70 dark:bg-blue-400/50' },
  bot_joining: { label: 'Starting', dotClass: 'bg-amber-400/80 dark:bg-amber-400/60' },
  recording: { label: 'Recording', dotClass: 'bg-red-400/80 dark:bg-red-400/60 animate-pulse' },
  processing: { label: 'Processing', dotClass: 'bg-orange-400/70 dark:bg-orange-400/50' },
  ready: { label: 'Ready', dotClass: 'bg-emerald-400/70 dark:bg-emerald-400/50' },
  failed: { label: 'Failed', dotClass: 'bg-red-400/60 dark:bg-red-400/40' },
  cancelled: { label: 'Cancelled', dotClass: 'bg-muted-foreground/30' },
};

export default function MeetingDetailPage() {
  const { meetingId } = useParams<{ meetingId: string }>();
  const navigate = useNavigate();
  const trpc = useTRPC();
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery(
    trpc.meet.getMeeting.queryOptions({ meetingId: meetingId! }),
  );
  const media = data?.media;
  const transcripts = data?.transcript;
  const meeting = data
    ? (() => {
        const { media: m, transcript: t, ...row } = data;
        void m;
        void t;
        return row;
      })()
    : undefined;

  // Generate AI summary
  const summaryMutation = useMutation(trpc.meet.generateSummary.mutationOptions());
  const handleGenerateSummary = () => {
    summaryMutation.mutate(
      { meetingId: meetingId! },
      {
        onSuccess: () => {
          queryClient.invalidateQueries({ queryKey: trpc.meet.getMeeting.queryKey() });
          toast.success('AI recap generated');
        },
        onError: () => toast.error('Failed to generate recap'),
      },
    );
  };

  // Schedule recording
  const scheduleBotMutation = useMutation(trpc.meet.scheduleBot.mutationOptions());
  const handleScheduleBot = () => {
    scheduleBotMutation.mutate(
      { meetingId: meetingId! },
      {
        onSuccess: () => {
          queryClient.invalidateQueries({ queryKey: trpc.meet.getMeeting.queryKey() });
          toast.success('Recording scheduled');
        },
        onError: () => toast.error('Failed to schedule recording'),
      },
    );
  };

  // Delete meeting
  const deleteMutation = useMutation(trpc.meet.deleteMeeting.mutationOptions());
  const handleDelete = () => {
    if (!confirm('Delete this meeting and all its recordings?')) return;
    deleteMutation.mutate(
      { meetingId: meetingId! },
      {
        onSuccess: () => {
          queryClient.invalidateQueries({ queryKey: trpc.meet.listMeetings.queryKey() });
          toast.success('Meeting deleted');
          navigate('/mail/meetings');
        },
        onError: () => toast.error('Failed to delete meeting'),
      },
    );
  };

  if (isLoading) {
    return (
      <div className="flex h-full items-center justify-center">
        <Loader2 className="text-muted-foreground/50 h-5 w-5 animate-spin" />
      </div>
    );
  }

  if (!meeting) {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-2">
        <p className="text-[13px] text-muted-foreground">Meeting not found</p>
        <Link to="/mail/meetings">
          <Button variant="ghost" size="sm" className="h-7 gap-1.5 text-xs">
            <ArrowLeft className="h-3 w-3" /> Back
          </Button>
        </Link>
      </div>
    );
  }

  const statusConfig = STATUS_CONFIG[meeting.status] ?? STATUS_CONFIG.scheduled;
  const videoMedia = media?.find((m) => m.mediaType === 'video_mixed');
  const hasTranscript = transcripts && transcripts.length > 0;
  const actionItems = meeting.actionItems as Array<{
    task: string;
    owner?: string;
    dueDate?: string;
  }> | null;

  return (
    <div className="flex h-full flex-col overflow-hidden">
      {/* Header — slim, consistent with meetings list header */}
      <div className="flex items-center gap-2 border-b border-border/60 px-4 py-2.5">
        <Link to="/mail/meetings">
          <Button variant="ghost" size="icon" className="h-7 w-7 text-muted-foreground">
            <ArrowLeft className="h-3.5 w-3.5" />
          </Button>
        </Link>

        <div className="min-w-0 flex-1">
          <h1 className="truncate text-[14px] font-semibold leading-tight tracking-tight">
            {meeting.title}
          </h1>
          <div className="mt-0.5 flex items-center gap-1.5 text-[11px] text-muted-foreground">
            <Clock className="h-3 w-3" />
            <span>
              {format(new Date(meeting.startsAt), 'EEE, MMM d · h:mm a')}
              {meeting.endsAt && ` – ${format(new Date(meeting.endsAt), 'h:mm a')}`}
            </span>
          </div>
        </div>

        {/* Status — dot + label, matching list view */}
        <div className="flex items-center gap-1.5">
          <div className={cn('h-1.5 w-1.5 rounded-full', statusConfig.dotClass)} />
          <span className="text-[11px] font-medium text-muted-foreground">
            {statusConfig.label}
          </span>
        </div>

        {/* Record CTA — only for unrecorded scheduled meetings */}
        {meeting.status === 'scheduled' && !meeting.recallBotId && (
          <Button
            variant="outline"
            size="sm"
            className="h-7 gap-1.5 text-xs"
            onClick={handleScheduleBot}
            disabled={scheduleBotMutation.isPending}
          >
            {scheduleBotMutation.isPending ? (
              <Loader2 className="h-3 w-3 animate-spin" />
            ) : (
              <Mic className="h-3 w-3" />
            )}
            Record
          </Button>
        )}

        {/* Delete */}
        <Button
          variant="ghost"
          size="icon"
          className="h-7 w-7 text-muted-foreground/50 hover:text-red-500"
          onClick={handleDelete}
          disabled={deleteMutation.isPending}
        >
          <Trash2 className="h-3.5 w-3.5" />
        </Button>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto">
        <div className="mx-auto max-w-3xl space-y-4 px-5 py-5">
          {/* Error state */}
          {meeting.status === 'failed' && meeting.errorMessage && (
            <div className="flex items-start gap-2.5 rounded-lg bg-red-50/50 p-3 dark:bg-red-950/10">
              <AlertCircle className="mt-0.5 h-3.5 w-3.5 shrink-0 text-red-500/70" />
              <div>
                <p className="text-[13px] font-medium text-red-700 dark:text-red-300">
                  Recording failed
                </p>
                <p className="mt-0.5 text-[12px] text-red-600/80 dark:text-red-400/80">
                  {meeting.errorMessage}
                </p>
              </div>
            </div>
          )}

          {/* Video player */}
          {videoMedia?.url && (
            <div className="overflow-hidden rounded-xl border border-border/60">
              <video
                src={videoMedia.url}
                controls
                className="aspect-video w-full bg-neutral-950"
                preload="metadata"
              />
            </div>
          )}

          {/* Processing placeholder */}
          {(meeting.status === 'recording' || meeting.status === 'processing') && (
            <div className="flex flex-col items-center justify-center rounded-xl bg-accent/30 py-14 text-center">
              <Loader2 className="text-muted-foreground/40 mb-2.5 h-6 w-6 animate-spin" />
              <p className="text-[13px] font-medium tracking-tight">
                {meeting.status === 'recording'
                  ? 'Recording in progress…'
                  : 'Processing recording…'}
              </p>
              <p className="mt-1 text-[11px] text-muted-foreground">
                The recap will be available once processing completes.
              </p>
            </div>
          )}

          {/* AI Summary */}
          {meeting.aiSummary ? (
            <ContentSection icon={Sparkles} title="Recap">
              <p className="whitespace-pre-wrap text-[13px] leading-relaxed text-muted-foreground">
                {meeting.aiSummary}
              </p>
            </ContentSection>
          ) : (
            hasTranscript && (
              <div className="flex items-center justify-between rounded-xl bg-accent/30 px-4 py-3">
                <div className="flex items-center gap-2">
                  <Sparkles className="h-3.5 w-3.5 text-muted-foreground/60" />
                  <span className="text-[13px] text-muted-foreground">
                    Generate an AI recap from the transcript
                  </span>
                </div>
                <Button
                  variant="outline"
                  size="sm"
                  className="h-7 gap-1.5 text-xs"
                  onClick={handleGenerateSummary}
                  disabled={summaryMutation.isPending}
                >
                  {summaryMutation.isPending ? (
                    <Loader2 className="h-3 w-3 animate-spin" />
                  ) : (
                    <Sparkles className="h-3 w-3" />
                  )}
                  Generate
                </Button>
              </div>
            )
          )}

          {/* Action Items */}
          {actionItems && actionItems.length > 0 && (
            <ContentSection icon={ListChecks} title="Action items">
              <ul className="space-y-2">
                {actionItems.map((item, i) => (
                  <li key={i} className="flex items-start gap-2 text-[13px]">
                    <CheckCircle2 className="mt-0.5 h-3.5 w-3.5 shrink-0 text-muted-foreground/40" />
                    <div>
                      <span className="leading-snug">{item.task}</span>
                      {item.owner && (
                        <span className="ml-1.5 text-[11px] text-muted-foreground">
                          — {item.owner}
                        </span>
                      )}
                    </div>
                  </li>
                ))}
              </ul>
            </ContentSection>
          )}

          {/* Transcript */}
          {hasTranscript && <TranscriptSection segments={transcripts!} />}

          {/* Q&A */}
          {hasTranscript && <QASection meetingId={meetingId!} />}
        </div>
      </div>
    </div>
  );
}

/* ── Content section wrapper ─────────────────────────────────────────────── */

function ContentSection({
  icon: Icon,
  title,
  children,
}: {
  icon: typeof Sparkles;
  title: string;
  children: React.ReactNode;
}) {
  return (
    <div className="rounded-xl bg-accent/30 px-4 py-3.5">
      <div className="mb-2.5 flex items-center gap-1.5">
        <Icon className="h-3.5 w-3.5 text-muted-foreground/50" />
        <span className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground/70">
          {title}
        </span>
      </div>
      {children}
    </div>
  );
}

/* ── Transcript ──────────────────────────────────────────────────────────── */

function TranscriptSection({
  segments,
}: {
  segments: NonNullable<MeetingDetail['transcript']>;
}) {
  const [expanded, setExpanded] = useState(false);
  const displaySegments = expanded ? segments : segments.slice(0, 15);

  const durationLabel = useMemo(() => {
    if (segments.length < 2) return '';
    const lastSeg = segments[segments.length - 1];
    const firstSeg = segments[0];
    if (!lastSeg || !firstSeg) return '';
    const lastEnd = lastSeg.endTime ?? lastSeg.startTime;
    const firstStart = firstSeg.startTime;
    const totalMinutes = Math.round(((lastEnd ?? 0) - firstStart) / 60000);
    if (totalMinutes < 1) return '< 1 min';
    return `${totalMinutes} min`;
  }, [segments]);

  return (
    <div className="rounded-xl bg-accent/30 px-4 py-3.5">
      <div className="mb-3 flex items-center gap-1.5">
        <MessageSquare className="h-3.5 w-3.5 text-muted-foreground/50" />
        <span className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground/70">
          Transcript
        </span>
        {durationLabel && (
          <span className="text-[11px] text-muted-foreground/50">· {durationLabel}</span>
        )}
      </div>
      <div className="space-y-2.5">
        {displaySegments.map((seg) => (
          <div key={seg.id} className="flex gap-2.5 text-[13px]">
            <span className="w-12 shrink-0 text-[11px] tabular-nums text-muted-foreground/50">
              {formatMs(seg.startTime)}
            </span>
            <div className="min-w-0">
              <span className="font-medium text-foreground/80">{seg.speakerName}</span>
              <p className="mt-0.5 leading-relaxed text-muted-foreground">{seg.text}</p>
            </div>
          </div>
        ))}
      </div>
      {segments.length > 15 && (
        <button
          className="mt-3 flex w-full items-center justify-center gap-1 text-[11px] font-medium text-muted-foreground/60 transition-colors hover:text-foreground"
          onClick={() => setExpanded(!expanded)}
        >
          {expanded ? (
            <>
              Show less <ChevronUp className="h-3 w-3" />
            </>
          ) : (
            <>
              Show full transcript <ChevronDown className="h-3 w-3" />
            </>
          )}
        </button>
      )}
    </div>
  );
}

function formatMs(ms: number): string {
  const totalSeconds = Math.floor(ms / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${seconds.toString().padStart(2, '0')}`;
}

/* ── Q&A ─────────────────────────────────────────────────────────────────── */

interface QAMessage {
  role: 'user' | 'assistant';
  content: string;
}

function QASection({ meetingId }: { meetingId: string }) {
  const trpc = useTRPC();
  const [messages, setMessages] = useState<QAMessage[]>([]);
  const [input, setInput] = useState('');
  const scrollRef = useRef<HTMLDivElement>(null);

  const askMutation = useMutation(trpc.meet.askQuestion.mutationOptions());

  const handleSend = () => {
    const q = input.trim();
    if (!q) return;
    setInput('');
    setMessages((prev) => [...prev, { role: 'user', content: q }]);
    askMutation.mutate(
      { meetingId, question: q },
      {
        onSuccess: (data) => {
          setMessages((prev) => [...prev, { role: 'assistant', content: data.answer }]);
        },
        onError: () => {
          setMessages((prev) => [
            ...prev,
            { role: 'assistant', content: 'Sorry, I could not answer that.' },
          ]);
        },
      },
    );
  };

  useEffect(() => {
    scrollRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  return (
    <div className="rounded-xl bg-accent/30 px-4 py-3.5">
      <div className="mb-2.5 flex items-center gap-1.5">
        <Sparkles className="h-3.5 w-3.5 text-muted-foreground/50" />
        <span className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground/70">
          Ask about this meeting
        </span>
      </div>

      {/* Chat messages */}
      {messages.length > 0 && (
        <div className="mb-3 max-h-56 space-y-2 overflow-y-auto rounded-lg bg-background/50 p-2.5">
          {messages.map((msg, i) => (
            <div
              key={i}
              className={cn('text-[13px]', msg.role === 'user' ? 'text-right' : 'text-left')}
            >
              <div
                className={cn(
                  'inline-block max-w-[80%] rounded-lg px-3 py-1.5',
                  msg.role === 'user'
                    ? 'bg-foreground/10 text-foreground'
                    : 'bg-accent text-foreground',
                )}
              >
                {msg.content}
              </div>
            </div>
          ))}
          {askMutation.isPending && (
            <div className="text-left">
              <div className="inline-block rounded-lg bg-accent px-3 py-1.5">
                <Loader2 className="h-3.5 w-3.5 animate-spin text-muted-foreground" />
              </div>
            </div>
          )}
          <div ref={scrollRef} />
        </div>
      )}

      {/* Input */}
      <div className="flex gap-1.5">
        <Input
          placeholder="What were the key decisions?"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && !e.shiftKey && handleSend()}
          className="h-8 flex-1 border-border/60 bg-background/50 text-[13px] shadow-none"
        />
        <Button
          variant="ghost"
          size="icon"
          className="h-8 w-8 text-muted-foreground hover:text-foreground"
          onClick={handleSend}
          disabled={!input.trim() || askMutation.isPending}
        >
          <Send className="h-3.5 w-3.5" />
        </Button>
      </div>
    </div>
  );
}
