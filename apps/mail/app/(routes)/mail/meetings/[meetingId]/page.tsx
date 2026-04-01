/**
 * Meeting detail page — video/audio player, AI recap, action items,
 * transcript with speaker labels, and Q&A chat input.
 */
import {
  ArrowLeft,
  Video,
  Play,
  Clock,
  Users,
  CheckCircle2,
  AlertCircle,
  Loader2,
  Send,
  Sparkles,
  ListChecks,
  MessageSquare,
  Trash2,
  Bot,
} from 'lucide-react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useState, useRef, useEffect, useMemo } from 'react';
import { useTRPC } from '@/providers/query-provider';
import type { Outputs } from '@zero/server/trpc';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { authProxy } from '@/lib/auth-proxy';
import type { Route } from './+types/page';
import { Link, useParams } from 'react-router';
import { cn } from '@/lib/utils';
import { format } from 'date-fns';

type MeetingDetail = Outputs['meet']['getMeeting'];

// Auth guard
export async function clientLoader({ request }: Route.ClientLoaderArgs) {
  const session = await authProxy.api.getSession({ headers: request.headers });
  if (!session) return Response.redirect(`${import.meta.env.VITE_PUBLIC_APP_URL}/login`);
  return {};
}

const STATUS_LABELS: Record<string, { label: string; className: string }> = {
  scheduled: {
    label: 'Scheduled',
    className: 'text-blue-600 bg-blue-50 dark:bg-blue-950/30 dark:text-blue-400',
  },
  bot_joining: {
    label: 'Bot Joining',
    className: 'text-yellow-600 bg-yellow-50 dark:bg-yellow-950/30 dark:text-yellow-400',
  },
  recording: {
    label: 'Recording',
    className: 'text-red-600 bg-red-50 dark:bg-red-950/30 dark:text-red-400',
  },
  processing: {
    label: 'Processing',
    className: 'text-orange-600 bg-orange-50 dark:bg-orange-950/30 dark:text-orange-400',
  },
  ready: {
    label: 'Ready',
    className: 'text-green-600 bg-green-50 dark:bg-green-950/30 dark:text-green-400',
  },
  failed: {
    label: 'Failed',
    className: 'text-red-600 bg-red-50 dark:bg-red-950/30 dark:text-red-400',
  },
  cancelled: {
    label: 'Cancelled',
    className: 'text-muted-foreground bg-muted/50',
  },
};

export default function MeetingDetailPage() {
  const { meetingId } = useParams<{ meetingId: string }>();
  const trpc = useTRPC();
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery(
    trpc.meet.getMeeting.queryOptions({ meetingId: meetingId! }),
  );
  const meeting = data?.meeting;
  const media = data?.media;
  const transcripts = data?.transcripts;

  // Generate AI summary
  const summaryMutation = useMutation(trpc.meet.generateSummary.mutationOptions());

  const handleGenerateSummary = () => {
    summaryMutation.mutate(
      { meetingId: meetingId! },
      {
        onSuccess: () => {
          queryClient.invalidateQueries({ queryKey: trpc.meet.getMeeting.queryKey() });
        },
      },
    );
  };

  // Schedule bot
  const scheduleBotMutation = useMutation(trpc.meet.scheduleBot.mutationOptions());
  const handleScheduleBot = () => {
    scheduleBotMutation.mutate(
      { meetingId: meetingId! },
      {
        onSuccess: () => {
          queryClient.invalidateQueries({ queryKey: trpc.meet.getMeeting.queryKey() });
        },
      },
    );
  };

  // Delete meeting
  const deleteMutation = useMutation(trpc.meet.deleteMeeting.mutationOptions());

  if (isLoading) {
    return (
      <div className="flex h-full items-center justify-center">
        <Loader2 className="text-muted-foreground h-6 w-6 animate-spin" />
      </div>
    );
  }

  if (!meeting) {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-2">
        <AlertCircle className="text-muted-foreground h-8 w-8" />
        <p className="text-muted-foreground text-sm">Meeting not found</p>
        <Link to="/mail/meetings">
          <Button variant="ghost" size="sm">
            <ArrowLeft className="mr-1.5 h-3.5 w-3.5" /> Back to meetings
          </Button>
        </Link>
      </div>
    );
  }

  const statusConfig = STATUS_LABELS[meeting.status] ?? STATUS_LABELS.scheduled;
  const videoMedia = media?.find((m) => m.mediaType === 'video_mixed');
  const hasTranscript = transcripts && transcripts.length > 0;
  const actionItems = meeting.actionItems as Array<{
    task: string;
    owner?: string;
    dueDate?: string;
  }> | null;

  return (
    <div className="flex h-full flex-col overflow-hidden">
      {/* Header */}
      <div className="flex items-center gap-3 border-b px-6 py-4">
        <Link to="/mail/meetings">
          <Button variant="ghost" size="icon" className="h-8 w-8">
            <ArrowLeft className="h-4 w-4" />
          </Button>
        </Link>
        <div className="min-w-0 flex-1">
          <h1 className="truncate text-lg font-semibold">{meeting.title}</h1>
          <div className="text-muted-foreground flex items-center gap-2 text-xs">
            <Clock className="h-3 w-3" />
            <span>
              {format(new Date(meeting.startsAt), 'EEEE, MMM d · h:mm a')}
              {meeting.endsAt && ` – ${format(new Date(meeting.endsAt), 'h:mm a')}`}
            </span>
          </div>
        </div>
        <Badge className={statusConfig.className}>{statusConfig.label}</Badge>

        {/* Schedule bot for scheduled meetings without a bot */}
        {meeting.status === 'scheduled' && !meeting.recallBotId && (
          <Button
            size="sm"
            onClick={handleScheduleBot}
            disabled={scheduleBotMutation.isPending}
          >
            {scheduleBotMutation.isPending ? (
              <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />
            ) : (
              <Bot className="mr-1.5 h-3.5 w-3.5" />
            )}
            Send Note Taker
          </Button>
        )}
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto">
        <div className="mx-auto max-w-4xl space-y-6 px-6 py-6">
          {/* Error state */}
          {meeting.status === 'failed' && meeting.errorMessage && (
            <div className="flex items-start gap-3 rounded-lg border border-red-200 bg-red-50 p-4 dark:border-red-900 dark:bg-red-950/20">
              <AlertCircle className="mt-0.5 h-4 w-4 text-red-600" />
              <div>
                <p className="text-sm font-medium text-red-800 dark:text-red-300">
                  Recording failed
                </p>
                <p className="text-xs text-red-600 dark:text-red-400">{meeting.errorMessage}</p>
              </div>
            </div>
          )}

          {/* Video player */}
          {videoMedia?.url && (
            <div className="overflow-hidden rounded-lg border">
              <video
                src={videoMedia.url}
                controls
                className="aspect-video w-full bg-black"
                preload="metadata"
              />
            </div>
          )}

          {/* Processing placeholder */}
          {(meeting.status === 'recording' || meeting.status === 'processing') && (
            <div className="flex flex-col items-center justify-center rounded-lg border py-16 text-center">
              <Loader2 className="text-muted-foreground mb-3 h-8 w-8 animate-spin" />
              <p className="text-sm font-medium">
                {meeting.status === 'recording'
                  ? 'Meeting is being recorded...'
                  : 'Processing recording...'}
              </p>
              <p className="text-muted-foreground mt-1 text-xs">
                The recap will be available once processing completes.
              </p>
            </div>
          )}

          {/* AI Summary */}
          {meeting.aiSummary ? (
            <div className="rounded-lg border p-4">
              <div className="mb-3 flex items-center gap-2">
                <Sparkles className="h-4 w-4 text-purple-500" />
                <h2 className="text-sm font-semibold">AI Recap</h2>
              </div>
              <p className="text-muted-foreground whitespace-pre-wrap text-sm">
                {meeting.aiSummary}
              </p>
            </div>
          ) : (
            hasTranscript && (
              <div className="flex items-center justify-between rounded-lg border p-4">
                <div className="flex items-center gap-2">
                  <Sparkles className="text-muted-foreground h-4 w-4" />
                  <span className="text-sm">Generate an AI recap from the transcript</span>
                </div>
                <Button
                  size="sm"
                  variant="outline"
                  onClick={handleGenerateSummary}
                  disabled={summaryMutation.isPending}
                >
                  {summaryMutation.isPending ? (
                    <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />
                  ) : (
                    <Sparkles className="mr-1.5 h-3.5 w-3.5" />
                  )}
                  Generate Recap
                </Button>
              </div>
            )
          )}

          {/* Action Items */}
          {actionItems && actionItems.length > 0 && (
            <div className="rounded-lg border p-4">
              <div className="mb-3 flex items-center gap-2">
                <ListChecks className="h-4 w-4 text-blue-500" />
                <h2 className="text-sm font-semibold">Action Items</h2>
              </div>
              <ul className="space-y-2">
                {actionItems.map((item, i) => (
                  <li key={i} className="flex items-start gap-2 text-sm">
                    <CheckCircle2 className="text-muted-foreground mt-0.5 h-4 w-4 shrink-0" />
                    <div>
                      <span>{item.task}</span>
                      {item.owner && (
                        <span className="text-muted-foreground ml-2 text-xs">— {item.owner}</span>
                      )}
                    </div>
                  </li>
                ))}
              </ul>
            </div>
          )}

          {/* Transcript */}
          {hasTranscript && (
            <TranscriptSection segments={transcripts!} />
          )}

          {/* Q&A */}
          {hasTranscript && <QASection meetingId={meetingId!} />}
        </div>
      </div>
    </div>
  );
}

// ── Transcript viewer ────────────────────────────────────────────────────────

function TranscriptSection({
  segments,
}: {
  segments: NonNullable<MeetingDetail['transcripts']>;
}) {
  const [expanded, setExpanded] = useState(false);
  const displaySegments = expanded ? segments : segments.slice(0, 20);

  return (
    <div className="rounded-lg border p-4">
      <div className="mb-3 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <MessageSquare className="h-4 w-4 text-emerald-500" />
          <h2 className="text-sm font-semibold">Transcript</h2>
          <span className="text-muted-foreground text-xs">
            ({segments.length} segment{segments.length !== 1 ? 's' : ''})
          </span>
        </div>
      </div>
      <div className="space-y-3">
        {displaySegments.map((seg) => (
          <div key={seg.id} className="flex gap-3 text-sm">
            <div className="w-20 shrink-0">
              <span className="text-muted-foreground text-xs font-medium">
                {formatMs(seg.startTime)}
              </span>
            </div>
            <div>
              <span className="font-medium text-blue-600 dark:text-blue-400">
                {seg.speakerName}
              </span>
              <p className="text-muted-foreground mt-0.5">{seg.text}</p>
            </div>
          </div>
        ))}
      </div>
      {segments.length > 20 && (
        <Button
          variant="ghost"
          size="sm"
          className="mt-3 w-full"
          onClick={() => setExpanded(!expanded)}
        >
          {expanded ? 'Show less' : `Show all ${segments.length} segments`}
        </Button>
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

// ── Q&A chat ────────────────────────────────────────────────────────────────

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
            { role: 'assistant', content: 'Sorry, I could not answer that question.' },
          ]);
        },
      },
    );
  };

  useEffect(() => {
    scrollRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  return (
    <div className="rounded-lg border p-4">
      <div className="mb-3 flex items-center gap-2">
        <Sparkles className="h-4 w-4 text-purple-500" />
        <h2 className="text-sm font-semibold">Ask about this meeting</h2>
      </div>

      {/* Chat messages */}
      {messages.length > 0 && (
        <div className="mb-3 max-h-64 space-y-3 overflow-y-auto rounded-md bg-muted/30 p-3">
          {messages.map((msg, i) => (
            <div
              key={i}
              className={cn(
                'text-sm',
                msg.role === 'user' ? 'text-right' : 'text-left',
              )}
            >
              <div
                className={cn(
                  'inline-block max-w-[80%] rounded-lg px-3 py-2',
                  msg.role === 'user'
                    ? 'bg-primary text-primary-foreground'
                    : 'bg-muted',
                )}
              >
                {msg.content}
              </div>
            </div>
          ))}
          {askMutation.isPending && (
            <div className="text-left">
              <div className="bg-muted inline-block rounded-lg px-3 py-2">
                <Loader2 className="h-4 w-4 animate-spin" />
              </div>
            </div>
          )}
          <div ref={scrollRef} />
        </div>
      )}

      {/* Input */}
      <div className="flex gap-2">
        <Input
          placeholder="What were the key decisions? Who owns the next steps?"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && !e.shiftKey && handleSend()}
          className="flex-1"
        />
        <Button
          size="icon"
          onClick={handleSend}
          disabled={!input.trim() || askMutation.isPending}
        >
          <Send className="h-4 w-4" />
        </Button>
      </div>
    </div>
  );
}
