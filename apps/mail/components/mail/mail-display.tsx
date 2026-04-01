import {
  Bell,
  Docx,
  Figma,
  Forward,
  ImageFile,
  Lightning,
  PDF,
  Reply,
  ReplyAll,
  ThreeDots,
  Tag,
  User,
  ChevronDown,
  Printer,
} from '../icons/icons';
import {
  Briefcase,
  CalendarClock,
  Star,
  StickyNote,
  Users,
  Lock,
  HardDriveDownload,
  Loader2,
  CopyIcon,
  ListTodo,
  Search,
} from 'lucide-react';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '../ui/dropdown-menu';
import { cn, formatDate, formatTime, shouldShowSeparateTime } from '@/lib/utils';
import { Dialog, DialogTitle, DialogHeader, DialogContent } from '../ui/dialog';
import { memo, useEffect, useMemo, useState, useRef, useCallback } from 'react';
import { Tooltip, TooltipContent, TooltipTrigger } from '../ui/tooltip';
import { Popover, PopoverContent, PopoverTrigger } from '../ui/popover';
import { EmailVerificationBadge } from './email-verification-badge';
import type { Sender, ParsedMessage, Attachment } from '@/types';
import { useActiveConnection } from '@/hooks/use-connections';
import { useAttachments } from '@/hooks/use-attachments';
import { useTRPC } from '@/providers/query-provider';
import { useThreadLabels } from '@/hooks/use-labels';
import { useMutation, useQuery } from '@tanstack/react-query';
import { Markdown } from '@react-email/components';
import { TextShimmer } from '../ui/text-shimmer';
import { useThread } from '@/hooks/use-threads';
import { BimiAvatar } from '../ui/bimi-avatar';
import { RenderLabels } from './render-labels';
import { cleanHtml } from '@/lib/email-utils';
import { MailContent } from './mail-content';
import { APP_NAME } from '@/lib/branding';
import { m } from '@/paraglide/messages';
import { useParams } from 'react-router';
import { FileText } from 'lucide-react';
import { Button } from '../ui/button';
import { useQueryState } from 'nuqs';
import { Badge } from '../ui/badge';
import { format } from 'date-fns';
import { useAISidebar } from '@/components/ui/ai-sidebar';
import { useSettings } from '@/hooks/use-settings';
import posthog from 'posthog-js';
import { toast } from 'sonner';

// Add formatFileSize utility function
const formatFileSize = (size: number) => {
  const sizeInMB = (size / (1024 * 1024)).toFixed(2);
  return sizeInMB === '0.00' ? '' : `${sizeInMB} MB`;
};

// Add getFileIcon utility function
const getFileIcon = (filename: string) => {
  const extension = filename.split('.').pop()?.toLowerCase();

  switch (extension) {
    case 'pdf':
      return <PDF className="fill-[#F43F5E]" />;
    case 'jpg':
      return <ImageFile />;
    case 'jpeg':
      return <ImageFile />;
    case 'png':
      return <ImageFile />;
    case 'gif':
      return <ImageFile />;
    case 'docx':
      return <Docx />;
    case 'fig':
      return <Figma />;
    case 'webp':
      return <ImageFile />;
    default:
      return <FileText className="h-4 w-4 text-[#8B5CF6]" />;
  }
};

const buildSummaryShareText = (subject: string | undefined, summary: string) => {
  const headline = subject?.trim() ? `Thread: ${subject.trim()}` : 'Todus thread summary';

  return [headline, '', summary.trim(), '', `Shared with ${APP_NAME} • https://todus.app`].join(
    '\n',
  );
};

const buildTaskSuggestionFromMessage = (message: ParsedMessage) => {
  const fallbackSubject = message.subject?.trim() || 'Email follow-up';
  const description = cleanHtml(message.decodedBody || message.body || '')
    .replace(/\s+/g, ' ')
    .trim();

  return {
    title: fallbackSubject.startsWith('Re:') ? fallbackSubject : `Follow up: ${fallbackSubject}`,
    description: description.length > 280 ? `${description.slice(0, 277)}...` : description || null,
    priority: 'medium' as const,
    dueDate: null,
  };
};

const StreamingText = ({ text }: { text: string }) => {
  const [displayText, setDisplayText] = useState('');
  const [isComplete, setIsComplete] = useState(false);
  const [isThinking, setIsThinking] = useState(false);

  useEffect(() => {
    let currentIndex = 0;
    setIsComplete(false);
    setIsThinking(true);

    const thinkingTimeout = setTimeout(() => {
      setIsThinking(false);
      setDisplayText('');

      const interval = setInterval(() => {
        if (currentIndex < text.length) {
          const nextChar = text[currentIndex];
          setDisplayText((prev) => prev + nextChar);
          currentIndex++;
        } else {
          setIsComplete(true);
          clearInterval(interval);
        }
      }, 20);

      return () => clearInterval(interval);
    }, 1000);

    return () => {
      clearTimeout(thinkingTimeout);
    };
  }, [text]);

  return (
    <div className="flex items-center gap-2">
      <div
        className={cn(
          'bg-linear-to-r bg-size-[200%_100%] from-neutral-500 via-neutral-300 to-neutral-500 bg-clip-text text-sm leading-relaxed text-transparent',
          isComplete ? 'animate-shine-slow' : '',
        )}
      >
        {isThinking ? (
          <TextShimmer duration={1}>Thinking...</TextShimmer>
        ) : (
          <span>{displayText}</span>
        )}
        {!isComplete && !isThinking && (
          <span className="animate-blink bg-primary ml-0.5 inline-block h-4 w-0.5"></span>
        )}
      </div>
    </div>
  );
};

type Props = {
  emailData: ParsedMessage;
  isFullscreen: boolean;
  isMuted: boolean;
  isLoading: boolean;
  index: number;
  totalEmails?: number;
  demo?: boolean;
  subject?: string;
  onReply?: () => void;
  onReplyAll?: () => void;
  onForward?: () => void;
  threadAttachments?: Attachment[];
};

const MailDisplayLabels = ({ labels }: { labels: string[] }) => {
  const visibleLabels = labels.filter(
    (label) => !['unread', 'inbox'].includes(label.toLowerCase()),
  );

  if (!visibleLabels.length) return null;

  return (
    <div className="flex">
      {visibleLabels.map((label, index) => {
        const normalizedLabel = label.toLowerCase().replace(/^category_/i, '');

        let icon = null;
        let bgColor = '';
        let labelText = '';

        switch (normalizedLabel) {
          case 'important':
            icon = <Lightning className="h-3.5 w-3.5 fill-white" />;
            bgColor = 'bg-[#F59E0D]';
            labelText = m['common.mailCategories.important']();
            break;
          case 'promotions':
            icon = <Tag className="h-3.5 w-3.5 fill-white" />;
            bgColor = 'bg-[#F43F5E]';
            labelText = m['common.mailCategories.promotions']();
            break;
          case 'personal':
            icon = <User className="h-3.5 w-3.5 fill-white" />;
            bgColor = 'bg-[#39AE4A]';
            labelText = m['common.mailCategories.personal']();
            break;
          case 'updates':
            icon = <Bell className="h-3.5 w-3.5 fill-white" />;
            bgColor = 'bg-[#8B5CF6]';
            labelText = m['common.mailCategories.updates']();
            break;
          case 'work':
            icon = <Briefcase className="h-3.5 w-3.5 text-white" />;
            bgColor = '';
            labelText = m['common.mailCategories.work']();
            break;
          case 'forums':
            icon = <Users className="h-3.5 w-3.5 text-white" />;
            bgColor = 'bg-blue-600';
            labelText = m['common.mailCategories.forums']();
            break;
          case 'notes':
            icon = <StickyNote className="h-3.5 w-3.5 text-white" />;
            bgColor = 'bg-amber-500';
            labelText = m['common.mailCategories.notes']();
            break;
          case 'starred':
            icon = <Star className="h-3.5 w-3.5 fill-white text-white" />;
            bgColor = 'bg-yellow-500';
            labelText = m['common.mailCategories.starred']();
            break;
          default:
            return null;
        }

        return (
          <Tooltip key={`${label}-${index}`}>
            <TooltipTrigger>
              <Badge
                key={`${label}-${index}`}
                className={`rounded-md p-1 ${bgColor} dark:border-panelDark -ml-1.5 border-2 border-white transition-transform first:ml-0`}
              >
                {icon}
              </Badge>
            </TooltipTrigger>
            <TooltipContent>
              <p className="text-xs">{labelText}</p>
            </TooltipContent>
          </Tooltip>
        );
      })}
    </div>
  );
};

// Helper function to clean email display
const cleanEmailDisplay = (email?: string) => {
  if (!email) return '';
  const match = email.match(/([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/);
  return match ? match[1] : email;
};

// Helper function to clean name display
const cleanNameDisplay = (name?: string) => {
  if (!name) return '';
  return name.trim();
};

const ThreadAttachments = ({ attachments }: { attachments: Attachment[] }) => {
  if (!attachments || attachments.length === 0) return null;

  const handleDownload = async (attachment: Attachment) => {
    try {
      // Convert base64 to blob
      const byteCharacters = atob(attachment.body);
      const byteNumbers: number[] = Array(byteCharacters.length);
      for (let i = 0; i < byteCharacters.length; i++) {
        byteNumbers[i] = byteCharacters.charCodeAt(i);
      }
      const byteArray = new Uint8Array(byteNumbers);
      const blob = new Blob([byteArray], { type: attachment.mimeType });

      // Create download link
      const url = window.URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = attachment.filename;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      window.URL.revokeObjectURL(url);
    } catch (error) {
      console.error('Error downloading attachment:', error);
    }
  };

  return (
    <div className="mt-2 w-full">
      <div className="flex items-center gap-2">
        <span className="text-sm font-medium">
          Thread Attachments <span className="text-[#8D8D8D]">[{attachments.length}]</span>
        </span>
      </div>
      <div className="mt-2 flex flex-wrap gap-2">
        {attachments.map((attachment) => (
          <button
            key={`${attachment.attachmentId}-${attachment.filename}`}
            onClick={() => handleDownload(attachment)}
            className="flex cursor-pointer items-center gap-2 rounded-md px-2 py-1 text-sm hover:bg-[#F0F0F0] dark:bg-[#262626] dark:hover:bg-[#303030]"
          >
            <span className="text-muted-foreground">{getFileIcon(attachment.filename)}</span>
            <span className="max-w-[200px] truncate" title={attachment.filename}>
              {attachment.filename}
            </span>
            <span className="text-muted-foreground">{formatFileSize(attachment.size)}</span>
          </button>
        ))}
      </div>
    </div>
  );
};

const MailAssistantCard = ({
  subject,
  latestMessage,
  onAskAI,
  onResearch,
}: {
  subject?: string;
  latestMessage: ParsedMessage;
  onAskAI: () => void;
  onResearch: (query: string) => void;
}) => {
  const [threadId] = useQueryState('threadId');
  const [, setMode] = useQueryState('mode');
  const [, setDraftId] = useQueryState('draftId');
  const [isCopied, setIsCopied] = useState(false);
  const copyResetTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const trpc = useTRPC();
  const { data: settings } = useSettings();
  const assistantPolicy = settings?.settings.assistantAutomationPolicy;
  const assistantQuery = useQuery(
    trpc.mailAssistant.getThread.queryOptions(
      { threadId: threadId! },
      {
        enabled: !!threadId && assistantPolicy?.assistantThreadActionsVisible !== false,
      },
    ),
  );
  const { mutateAsync: createTaskSuggestion, isPending: isCreatingTask } = useMutation(
    trpc.mailAssistant.createTaskFromSuggestion.mutationOptions(),
  );
  const { mutateAsync: createEventSuggestion, isPending: isCreatingEvent } = useMutation(
    trpc.mailAssistant.createEventFromSuggestion.mutationOptions(),
  );
  const { mutateAsync: generateDraft, isPending: isGeneratingDraft } = useMutation(
    trpc.mailAssistant.generateDraft.mutationOptions(),
  );
  const { mutateAsync: logActivity } = useMutation(trpc.mailAssistant.logActivity.mutationOptions());

  useEffect(() => {
    return () => {
      if (copyResetTimeoutRef.current) {
        clearTimeout(copyResetTimeoutRef.current);
      }
    };
  }, []);

  const handleCopySummary = useCallback(
    async (e: React.MouseEvent) => {
      e.stopPropagation();

      const summaryText = assistantQuery.data?.summary?.trim();
      if (!summaryText) return;

      try {
        const shareText = buildSummaryShareText(subject, summaryText);
        await navigator.clipboard.writeText(shareText);

        posthog.capture('Thread Summary Shared', {
          threadId: threadId ?? null,
          subject: subject ?? '',
          summaryLength: summaryText.length,
          source: 'mail-thread-summary',
        });

        setIsCopied(true);
        toast.success('Thread summary copied');
        if (threadId) {
          await logActivity({
            threadId,
            type: 'summary_viewed',
            summary: summaryText,
            metadata: { source: 'copy-summary' },
          });
        }

        if (copyResetTimeoutRef.current) {
          clearTimeout(copyResetTimeoutRef.current);
        }

        copyResetTimeoutRef.current = setTimeout(() => {
          setIsCopied(false);
        }, 2000);
      } catch (error) {
        console.error('Failed to copy thread summary:', error);
        toast.error('Failed to copy thread summary');
      }
    },
    [assistantQuery.data?.summary, subject, threadId, logActivity],
  );

  const assistant = assistantQuery.data;
  if (assistantPolicy?.assistantThreadActionsVisible === false) return null;
  if (assistantQuery.isLoading || !assistant) return null;

  const intentBadges = [
    assistant.replyNeeded ? 'Needs reply' : null,
    assistant.meetingRequested ? 'Meeting request' : null,
    assistant.actionItems.length ? 'Action items found' : null,
    assistant.followUpNeeded ? 'Follow up overdue' : null,
  ].filter(Boolean);

  const handleCreateTask = async (task: (typeof assistant.suggestedTasks)[number]) => {
    if (!threadId) return;

    try {
      await createTaskSuggestion({ threadId, task });
      toast.success('Task created from thread');
      await assistantQuery.refetch();
    } catch (error) {
      console.error('Failed to create task from thread', error);
      toast.error('Failed to create task');
    }
  };

  const handleCreateEvent = async () => {
    if (!threadId || !assistant.suggestedEvent?.startAt || !assistant.suggestedEvent.endAt) return;

    try {
      await createEventSuggestion({
        threadId,
        event: {
          ...assistant.suggestedEvent,
          startAt: assistant.suggestedEvent.startAt,
          endAt: assistant.suggestedEvent.endAt,
        },
      });
      toast.success('Calendar event created');
      await assistantQuery.refetch();
    } catch (error) {
      console.error('Failed to create event from thread', error);
      toast.error('Failed to create calendar event');
    }
  };

  const handleGenerateDraft = async () => {
    if (!threadId) return;

    try {
      const result = await generateDraft({ threadId, openInComposer: true });
      if (!result.created || !result.draftId) {
        toast.message(result.reason || 'Draft already exists for this thread');
        return;
      }
      setDraftId(result.draftId);
      setMode('reply');
      toast.success('Assistant draft opened');
      await assistantQuery.refetch();
    } catch (error) {
      console.error('Failed to generate assistant draft', error);
      toast.error('Failed to draft reply');
    }
  };

  return (
    <div
      className="mt-3 flex max-w-4xl flex-col gap-4 rounded-2xl border border-[#D7CCFF] bg-[#FCFAFF] p-4 dark:border-[#4A3D76] dark:bg-[#1E1A28]"
      onClick={(e) => e.stopPropagation()}
    >
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="space-y-2">
          <div className="flex flex-wrap items-center gap-2">
            <TextShimmer className="text-xs font-semibold tracking-[0.16em] text-[#7C63E6] uppercase">
              Mail Assistant
            </TextShimmer>
            <Badge variant="secondary" className="rounded-full px-2.5 py-0.5 text-[11px]">
              {Math.round(assistant.confidence * 100)}% confidence
            </Badge>
            <Badge
              variant="outline"
              className={cn(
                'rounded-full px-2.5 py-0.5 text-[11px]',
                assistant.riskLevel === 'high'
                  ? 'border-[#F43F5E]/30 text-[#F43F5E]'
                  : assistant.riskLevel === 'medium'
                    ? 'border-[#F59E0B]/30 text-[#F59E0B]'
                    : 'border-[#10B981]/30 text-[#10B981]',
              )}
            >
              {assistant.riskLevel} risk
            </Badge>
            {assistant.autoSendCandidate && (
              <Badge variant="outline" className="rounded-full px-2.5 py-0.5 text-[11px]">
                Low-risk auto-send candidate
              </Badge>
            )}
          </div>
          <div className="flex flex-wrap gap-2">
            {intentBadges.map((badge) => (
              <Badge key={badge} variant="secondary" className="rounded-full px-2.5 py-0.5 text-[11px]">
                {badge}
              </Badge>
            ))}
          </div>
        </div>

        <div className="flex items-center gap-2">
          <Button
            type="button"
            size="xs"
            variant="secondary"
            className="h-7 gap-1.5 rounded-full px-2.5 text-[11px]"
            onClick={async (e) => {
              e.stopPropagation();
              try {
                await assistantQuery.refetch();
                if (threadId) {
                  await logActivity({
                    threadId,
                    type: 'summary_viewed',
                    summary: assistant.summary,
                    metadata: { source: 'manual-refresh' },
                  });
                }
                toast.success('Assistant refreshed');
              } catch {
                toast.error('Failed to refresh assistant. Please try again.');
              }
            }}
          >
            <ChevronDown className="h-3.5 w-3.5 -rotate-90" />
            Summarize
          </Button>
          <Button
            type="button"
            size="xs"
            variant="secondary"
            className="h-7 gap-1.5 rounded-full px-2.5 text-[11px]"
            onClick={handleCopySummary}
          >
            <CopyIcon className="h-3.5 w-3.5" />
            {isCopied ? 'Copied' : 'Copy summary'}
          </Button>
        </div>
      </div>

      <div className="flex flex-wrap gap-2">
        <Button
          type="button"
          size="sm"
          className="h-8 rounded-full px-3"
          onClick={() => void (assistant.suggestedTasks[0] && handleCreateTask(assistant.suggestedTasks[0]))}
          disabled={!assistant.suggestedTasks.length || isCreatingTask}
        >
          <ListTodo className="mr-1 h-3.5 w-3.5" />
          Extract tasks
        </Button>
        <Button
          type="button"
          size="sm"
          variant="secondary"
          className="h-8 rounded-full px-3"
          onClick={handleCreateEvent}
          disabled={!assistant.suggestedEvent?.startAt || !assistant.suggestedEvent.endAt || isCreatingEvent}
        >
          <CalendarClock className="mr-1 h-3.5 w-3.5" />
          Create event
        </Button>
        <Button
          type="button"
          size="sm"
          variant="secondary"
          className="h-8 rounded-full px-3"
          onClick={handleGenerateDraft}
          disabled={!assistant.draftEligible || isGeneratingDraft}
        >
          {isGeneratingDraft ? (
            <Loader2 className="mr-1 h-3.5 w-3.5 animate-spin" />
          ) : (
            <Reply className="mr-1 h-3.5 w-3.5 fill-current" />
          )}
          Draft reply
        </Button>
        <Button type="button" size="sm" variant="secondary" className="h-8 rounded-full px-3" onClick={onAskAI}>
          <Lightning className="mr-1 h-3.5 w-3.5 fill-current" />
          Ask AI
        </Button>
        <Button
          type="button"
          size="sm"
          variant="secondary"
          className="h-8 rounded-full px-3"
          onClick={() =>
            onResearch(
              assistant.researchQueries[0] ||
                `${latestMessage.sender?.name || latestMessage.sender?.email || 'sender'} ${subject || latestMessage.subject || ''}`,
            )
          }
        >
          <Search className="mr-1 h-3.5 w-3.5" />
          Research
        </Button>
      </div>

      <div className="rounded-2xl border border-white/60 bg-white/70 p-3 dark:border-white/10 dark:bg-white/5">
        <p className="text-xs font-medium uppercase tracking-[0.16em] text-[#8C78D8]">Summary</p>
        <div className="mt-2 text-sm leading-6 text-black dark:text-white">
          <Markdown markdownContainerStyles={{ fontSize: 15 }}>{assistant.summary}</Markdown>
        </div>
        <p className="mt-2 text-xs text-[#6B6484] dark:text-[#B3A8D9]">{assistant.reason}</p>
      </div>

      {assistant.actionItems.length > 0 && (
        <div className="space-y-2">
          <p className="text-xs font-medium uppercase tracking-[0.16em] text-[#8C78D8]">Detected actions</p>
          <div className="flex flex-col gap-2">
            {assistant.actionItems.map((item) => (
              <div
                key={item}
                className="flex items-start gap-2 rounded-xl border border-white/60 bg-white/70 px-3 py-2 text-sm dark:border-white/10 dark:bg-white/5"
              >
                <ListTodo className="mt-0.5 h-4 w-4 shrink-0 text-[#7C63E6]" />
                <span>{item}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {assistantPolicy?.suggestTasksFromEmail !== false && assistant.suggestedTasks.length > 0 && (
        <div className="space-y-2">
          <p className="text-xs font-medium uppercase tracking-[0.16em] text-[#8C78D8]">Suggested tasks</p>
          <div className="flex flex-col gap-2">
            {assistant.suggestedTasks.map((task) => (
              <div
                key={task.title}
                className="flex flex-wrap items-start justify-between gap-3 rounded-xl border border-white/60 bg-white/70 px-3 py-3 dark:border-white/10 dark:bg-white/5"
              >
                <div className="space-y-1">
                  <p className="text-sm font-medium text-black dark:text-white">{task.title}</p>
                  {task.description && (
                    <p className="text-xs leading-5 text-[#6B6484] dark:text-[#B3A8D9]">
                      {task.description}
                    </p>
                  )}
                </div>
                <Button
                  type="button"
                  size="xs"
                  variant="secondary"
                  className="h-7 rounded-full px-2.5 text-[11px]"
                  onClick={() => void handleCreateTask(task)}
                  disabled={isCreatingTask}
                >
                  Create task
                </Button>
              </div>
            ))}
          </div>
        </div>
      )}

      {assistantPolicy?.suggestEventsFromEmail !== false && assistant.suggestedEvent && (
        <div className="space-y-2">
          <p className="text-xs font-medium uppercase tracking-[0.16em] text-[#8C78D8]">Suggested event</p>
          <div className="flex flex-wrap items-start justify-between gap-3 rounded-xl border border-white/60 bg-white/70 px-3 py-3 dark:border-white/10 dark:bg-white/5">
            <div className="space-y-1">
              <p className="text-sm font-medium text-black dark:text-white">{assistant.suggestedEvent.title}</p>
              <p className="text-xs leading-5 text-[#6B6484] dark:text-[#B3A8D9]">
                {assistant.suggestedEvent.startAt
                  ? `${format(new Date(assistant.suggestedEvent.startAt), 'PPp')} · ${format(new Date(assistant.suggestedEvent.endAt || assistant.suggestedEvent.startAt), 'p')}`
                  : 'Needs a quick review before creating the calendar event.'}
              </p>
            </div>
            <Button
              type="button"
              size="xs"
              variant="secondary"
              className="h-7 rounded-full px-2.5 text-[11px]"
              onClick={handleCreateEvent}
              disabled={!assistant.suggestedEvent.startAt || !assistant.suggestedEvent.endAt || isCreatingEvent}
            >
              Create event
            </Button>
          </div>
        </div>
      )}

      {(assistant.draftEligible || assistant.existingDraft) && (
        <div className="flex flex-wrap items-start justify-between gap-3 rounded-xl border border-white/60 bg-white/70 px-3 py-3 dark:border-white/10 dark:bg-white/5">
          <div className="space-y-1">
            <p className="text-sm font-medium text-black dark:text-white">
              {assistant.existingDraft ? 'Draft already attached' : 'Assistant can draft the reply'}
            </p>
            <p className="text-xs leading-5 text-[#6B6484] dark:text-[#B3A8D9]">
              {assistant.autoSendReason ||
                'Drafts use the thread, related tasks, and scheduling context before suggesting a reply.'}
            </p>
          </div>
          <Button
            type="button"
            size="xs"
            variant="secondary"
            className="h-7 rounded-full px-2.5 text-[11px]"
            onClick={handleGenerateDraft}
            disabled={isGeneratingDraft}
          >
            {assistant.existingDraft ? 'Open draft' : 'Draft reply'}
          </Button>
        </div>
      )}
    </div>
  );
};

type ActionButtonProps = {
  onClick: (e: React.MouseEvent) => void;
  icon: React.ReactNode;
  text: string;
  shortcut?: string;
};

const ActionButton = ({ onClick, icon, text, shortcut }: ActionButtonProps) => {
  return (
    <button
      type="button"
      onClick={onClick}
      className="inline-flex h-7 cursor-pointer items-center justify-center gap-1 overflow-hidden rounded-md border bg-white px-1.5 transition-colors hover:bg-gray-100 dark:border-none dark:bg-[#313131] dark:hover:bg-[#3d3d3d]"
    >
      {icon}
      <div className="flex items-center justify-center gap-2.5 pl-0.5 pr-1">
        <div className="justify-start text-sm leading-none text-black dark:text-white">{text}</div>
      </div>
      {shortcut && (
        <kbd
          className={cn(
            'border-muted-foreground/10 bg-accent h-6 rounded-[6px] border px-1.5 font-mono text-xs leading-6',
            '-me-1 ms-auto hidden max-h-full items-center md:inline-flex',
          )}
        >
          {shortcut}
        </kbd>
      )}
    </button>
  );
};

const downloadAttachment = async (attachment: {
  body: string;
  mimeType: string;
  filename: string;
  attachmentId: string;
}) => {
  try {
    const attachmentData = attachment.body;

    if (!attachmentData) {
      throw new Error('Attachment data not found');
    }

    const byteCharacters = atob(attachmentData);
    const byteNumbers: number[] = Array(byteCharacters.length);
    for (let i = 0; i < byteCharacters.length; i++) {
      byteNumbers[i] = byteCharacters.charCodeAt(i);
    }
    const byteArray = new Uint8Array(byteNumbers);
    const blob = new Blob([byteArray], { type: attachment.mimeType });

    const url = window.URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = attachment.filename;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    window.URL.revokeObjectURL(url);
  } catch (error) {
    console.error('Error downloading attachment:', error);
    toast.error('Failed to download attachment');
  }
};

const handleDownloadAllAttachments =
  (subject: string, attachments: { body: string; mimeType: string; filename: string }[]) =>
  async () => {
    if (!attachments.length) return;

    const JSZip = (await import('jszip')).default;
    const zip = new JSZip();

    console.log('attachments', attachments);
    attachments.forEach((attachment) => {
      try {
        const byteCharacters = atob(attachment.body);
        const byteNumbers: number[] = Array(byteCharacters.length);
        for (let i = 0; i < byteCharacters.length; i++) {
          byteNumbers[i] = byteCharacters.charCodeAt(i);
        }
        const byteArray = new Uint8Array(byteNumbers);

        zip.file(attachment.filename, byteArray, {
          binary: true,
          date: new Date(),
          unixPermissions: 0o644,
        });
      } catch (error) {
        console.error(`Error adding ${attachment.filename} to zip:`, error);
      }
    });

    // Generate and download the zip file
    zip
      .generateAsync({
        type: 'blob',
        compression: 'DEFLATE',
        compressionOptions: {
          level: 9,
        },
      })
      .then((content) => {
        const url = window.URL.createObjectURL(content);
        const link = document.createElement('a');
        link.href = url;
        link.download = `attachments-${subject || 'email'}.zip`;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        window.URL.revokeObjectURL(url);
      })
      .catch((error) => {
        console.error('Error generating zip file:', error);
      });

    console.log('downloaded', subject, attachments);
  };

const openAttachment = async (attachment: {
  body: string;
  mimeType: string;
  filename: string;
  attachmentId: string;
}) => {
  try {
    const attachmentData = attachment.body;

    if (!attachmentData) {
      throw new Error('Attachment data not found');
    }

    const byteCharacters = atob(attachmentData);
    const byteNumbers: number[] = Array(byteCharacters.length);
    for (let i = 0; i < byteCharacters.length; i++) {
      byteNumbers[i] = byteCharacters.charCodeAt(i);
    }
    const byteArray = new Uint8Array(byteNumbers);
    const blob = new Blob([byteArray], { type: attachment.mimeType });
    const url = window.URL.createObjectURL(blob);

    const width = 800;
    const height = 600;
    const left = (window.screen.width - width) / 2;
    const top = (window.screen.height - height) / 2;

    const popup = window.open(
      url,
      'attachment-viewer',
      `width=${width},height=${height},left=${left},top=${top},resizable=yes,scrollbars=yes,status=no,location=no,menubar=no`,
    );

    if (popup) {
      popup.focus();
      // Clean up the URL after a short delay to ensure the browser has time to load it
      setTimeout(() => window.URL.revokeObjectURL(url), 1000);
    }
  } catch (error) {
    console.error('Error opening attachment:', error);
    toast.error('Failed to open attachment');
  }
};

const MoreAboutPerson = ({
  person,
  open,
  onOpenChange,
}: {
  person: Sender;
  extra?: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) => {
  const trpc = useTRPC();
  const {
    mutate: doSearch,
    isPending,
    data,
    error,
  } = useMutation(trpc.ai.webSearch.mutationOptions());
  const handleSearch = useCallback(() => {
    doSearch({
      query: `In 50 words or less: What is the background of ${person.name} & ${person.email}, of ${person.email.split('@')[1]}.
      This could be a phishing email address, indicate if the domain is suspicious, example: x.io is not a valid domain for x.com | example: x.com is a valid domain for x.com | example: paypalcom.com is not a valid domain for paypal.com`,
    });
  }, [person.name]);

  useEffect(() => {
    if (open) {
      handleSearch();
    }
  }, [open]);

  const findSource = useCallback(
    (id: string) => {
      const sources = data?.sources;
      if (!sources) return;
      return sources.find((source) => source.id === id);
    },
    [data],
  );

  const replaceSourcesInText = useCallback(
    (text: string) => {
      const sources = data?.sources;
      if (!sources) return text;
      const sourcesRegex = /\[(\d+)\]/g;
      return text.replaceAll(sourcesRegex, (match, p1) => {
        console.log('p1', p1);
        const source = findSource(p1);
        return source ? `SOURCE HERE` : match;
      });
    },
    [data],
  );

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent showOverlay>
        <DialogHeader>
          <DialogTitle>More about {cleanNameDisplay(person.name)}</DialogTitle>
        </DialogHeader>
        <div className="mt-4 flex justify-center">
          {isPending ? (
            <Loader2 className="animate-spin" />
          ) : data ? (
            <StreamingText text={replaceSourcesInText(data.text)} />
          ) : error ? (
            <p>Error: {error.message}</p>
          ) : (
            <Loader2 className="animate-spin" />
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
};

const MoreAboutQuery = ({
  query,
  open,
  onOpenChange,
}: {
  query: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) => {
  const trpc = useTRPC();
  const {
    mutate: doSearch,
    isPending,
    data,
    error,
  } = useMutation(trpc.ai.webSearch.mutationOptions());

  const handleSearch = useCallback(() => {
    doSearch({
      query: query,
    });
  }, [query, doSearch]);

  useEffect(() => {
    if (open && query) {
      handleSearch();
    }
  }, [open, query, handleSearch]);

  const findSource = useCallback(
    (id: string) => {
      const sources = data?.sources;
      if (!sources) return;
      return sources.find((source) => source.id === id);
    },
    [data],
  );

  const replaceSourcesInText = useCallback(
    (text: string) => {
      const sources = data?.sources;
      if (!sources) return text;
      const sourcesRegex = /\[(\d+)\]/g;
      return text.replaceAll(sourcesRegex, (match, p1) => {
        const source = findSource(p1);
        return source ? `SOURCE HERE` : match;
      });
    },
    [data, findSource],
  );

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent showOverlay>
        <DialogHeader>
          <DialogTitle>Search Results</DialogTitle>
        </DialogHeader>
        <div className="mt-4 flex justify-center">
          {isPending ? (
            <Loader2 className="animate-spin" />
          ) : data ? (
            <StreamingText text={replaceSourcesInText(data.text)} />
          ) : error ? (
            <p>Error: {error.message}</p>
          ) : (
            <Loader2 className="animate-spin" />
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
};

const MailDisplay = ({ emailData, index, totalEmails, demo, threadAttachments }: Props) => {
  const [isCollapsed, setIsCollapsed] = useState<boolean>(false);
  const { data: threadData } = useThread(emailData.threadId ?? null);
  const { data: messageAttachments } = useAttachments(emailData.id);
  //   const [unsubscribed, setUnsubscribed] = useState(false);
  //   const [isUnsubscribing, setIsUnsubscribing] = useState(false);
  const [preventCollapse, setPreventCollapse] = useState(false);
  const { folder } = useParams<{ folder: string }>();
  //   const [selectedAttachment, setSelectedAttachment] = useState<null | {
  //     id: string;
  //     name: string;
  //     type: string;
  //     url: string;
  //   }>(null);
  const [openDetailsPopover, setOpenDetailsPopover] = useState<boolean>(false);
  const triggerRef = useRef<HTMLButtonElement | null>(null);
  const collapseTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const trpc = useTRPC();
  const { toggleOpen: toggleAISidebar } = useAISidebar();

  const [activeReplyId, setActiveReplyId] = useQueryState('activeReplyId');
  const [threadId] = useQueryState('threadId');
  const { labels: threadLabels } = useThreadLabels(
    emailData.tags ? emailData.tags.map((l) => l.id) : [],
  );
  const { data: activeConnection } = useActiveConnection();
  const [researchSender, setResearchSender] = useState<Sender | null>(null);
  const [searchQuery, setSearchQuery] = useState<string | null>(null);
  const assistantQuery = useQuery(
    trpc.mailAssistant.getThread.queryOptions(
      { threadId: threadId! },
      { enabled: !!threadId && !demo },
    ),
  );
  const { mutateAsync: createTaskFromSuggestion } = useMutation(
    trpc.mailAssistant.createTaskFromSuggestion.mutationOptions(),
  );
  const { mutateAsync: createEventFromSuggestion } = useMutation(
    trpc.mailAssistant.createEventFromSuggestion.mutationOptions(),
  );

  const isLastEmail = useMemo(
    () => emailData.id === threadData?.latest?.id,
    [emailData.id, threadData?.latest?.id],
  );

  const [, setMode] = useQueryState('mode');

  useEffect(() => {
    if (!demo) {
      if (activeReplyId === emailData.id) {
        // Always expand the email being replied to
        setIsCollapsed(false);
      } else {
        // For emails not being replied to, use the default behavior:
        // - Last email should be expanded
        // - All other emails should be collapsed
        setIsCollapsed(!isLastEmail);
      }
      // Set all emails to collapsed by default except the last one
      if (totalEmails && index === totalEmails - 1) {
        if (totalEmails > 5) {
          setTimeout(() => {
            const element = document.getElementById(`mail-${emailData.id}`);
            element?.scrollIntoView({ behavior: 'smooth' });
          }, 100);
        }
      }
    }
  }, [demo, emailData.id, isLastEmail, activeReplyId]);

  //   const listUnsubscribeAction = useMemo(
  //     () =>
  //       emailData.listUnsubscribe
  //         ? getListUnsubscribeAction({
  //             listUnsubscribe: emailData.listUnsubscribe,
  //             listUnsubscribePost: emailData.listUnsubscribePost,
  //           })
  //         : undefined,
  //     [emailData.listUnsubscribe, emailData.listUnsubscribePost],
  //   );

  //   const _handleUnsubscribe = async () => {
  //     setIsUnsubscribing(true);
  //     try {
  //       await handleUnsubscribe({
  //         emailData,
  //       });
  //       setIsUnsubscribing(false);
  //       setUnsubscribed(true);
  //     } catch (e) {
  //       setIsUnsubscribing(false);
  //       setUnsubscribed(false);
  //     }
  //   };

  // Clear any pending timeouts when component unmounts
  useEffect(() => {
    return () => {
      if (collapseTimeoutRef.current) {
        clearTimeout(collapseTimeoutRef.current);
      }
    };
  }, []);

  // Function to handle popover state changes
  const handlePopoverChange = useCallback((open: boolean) => {
    setOpenDetailsPopover(open);

    if (!open) {
      // When closing the popover, prevent collapse for a short time
      setPreventCollapse(true);

      // Clear any existing timeout
      if (collapseTimeoutRef.current) {
        clearTimeout(collapseTimeoutRef.current);
      }

      // Set a timeout to allow collapse again after a delay
      collapseTimeoutRef.current = setTimeout(() => {
        setPreventCollapse(false);
      }, 300);
    }
  }, []);

  // Handle email collapse toggle
  const toggleCollapse = useCallback(() => {
    // Only toggle if we're not in prevention mode
    if (!preventCollapse && !openDetailsPopover) {
      setIsCollapsed(!isCollapsed);
    }
  }, [isCollapsed, preventCollapse, openDetailsPopover]);

  // Handle email copy of senders
  const handleCopySenderEmail = useCallback(async (personEmail: string) => {
    if (!personEmail) return;

    await navigator.clipboard.writeText(personEmail || '');
    toast.success('Email copied to clipboard');
  }, []);

  // email printing
  const printMail = () => {
    try {
      // Create a hidden iframe for printing
      const printFrame = document.createElement('iframe');
      printFrame.style.position = 'absolute';
      printFrame.style.top = '-9999px';
      printFrame.style.left = '-9999px';
      printFrame.style.width = '0px';
      printFrame.style.height = '0px';
      printFrame.style.border = 'none';

      document.body.appendChild(printFrame);

      // Generate clean, simple HTML content for printing
      const printContent = `
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="utf-8">
          <title>Print Email - ${emailData.subject || 'No Subject'}</title>
          <style>
            * {
              margin: 0;
              padding: 0;
              box-sizing: border-box;
            }

            body {
              font-family: Arial, sans-serif;
              line-height: 1.5;
              color: #333;
              background: white;
              padding: 20px;
              font-size: 12px;
            }

            .email-container {
              max-width: 100%;
              margin: 0 auto;
              background: white;
            }

            .email-header {
              margin-bottom: 25px;
            }

            .email-title {
              font-size: 18px;
              font-weight: bold;
              color: #000;
              margin-bottom: 15px;
              word-wrap: break-word;
            }

            .email-meta {
              margin-bottom: 20px;
            }

            .meta-row {
              margin-bottom: 5px;
              display: flex;
              align-items: flex-start;
            }

            .meta-label {
              font-weight: bold;
              min-width: 60px;
              color: #333;
              margin-right: 10px;
            }

            .meta-value {
              flex: 1;
              word-wrap: break-word;
              color: #333;
            }

            .separator {
              width: 100%;
              height: 1px;
              background: #ddd;
              margin: 20px 0;
            }

            .email-body {
              margin: 20px 0;
              background: white;
            }

            .email-content {
              word-wrap: break-word;
              overflow-wrap: break-word;
              font-size: 12px;
              line-height: 1.6;
            }

            .email-content img {
              max-width: 100% !important;
              height: auto !important;
              display: block;
              margin: 10px 0;
            }

            .email-content table {
              width: 100%;
              border-collapse: collapse;
              margin: 10px 0;
            }

            .email-content td, .email-content th {
              padding: 6px;
              text-align: left;
              font-size: 11px;
            }

            .email-content a {
              color: #0066cc;
              text-decoration: underline;
            }

            .attachments-section {
              margin-top: 25px;
              background: white;
            }

            .attachments-title {
              font-size: 14px;
              font-weight: bold;
              color: #000;
              margin-bottom: 10px;
            }

            .attachment-item {
              margin-bottom: 5px;
              font-size: 11px;
              padding: 3px 0;
            }

            .attachment-name {
              font-weight: 500;
              color: #333;
            }

            .attachment-size {
              color: #666;
              font-size: 10px;
            }

            .labels-section {
              margin: 10px 0;
            }

            .label-badge {
              display: inline-block;
              padding: 2px 6px;
              background: #f5f5f5;
              color: #333;
              font-size: 10px;
              margin-right: 5px;
              margin-bottom: 3px;
            }

            @media print {
              body {
                margin: 0;
                padding: 15px;
                font-size: 11px;
                -webkit-print-color-adjust: exact;
                print-color-adjust: exact;
              }

              .email-container {
                max-width: none;
                width: 100%;
              }


              .separator {
                background: #000 !important;
              }

              .email-content a {
                color: #000 !important;
              }

              .label-badge {
                background: #f0f0f0 !important;
                border: 1px solid #ccc;
              }

              .no-print {
                display: none !important;
              }

              /* Remove any default borders */
              * {
                border: none !important;
                box-shadow: none !important;
              }

              /* Ensure clean page breaks */
              .email-header {
                page-break-after: avoid;
              }

              .attachments-section {
                page-break-inside: avoid;
              }
            }

            @page {
              margin: 0.5in;
              size: A4;
            }
          </style>
        </head>
        <body>
          <div class="email-container">
            <!-- Email Header -->
            <div class="email-header">
              <h1 class="email-title">${emailData.subject || 'No Subject'}</h1>

              ${
                emailData?.tags && emailData.tags.length > 0
                  ? `
                <div class="labels-section">
                  ${emailData.tags
                    .map((tag) => `<span class="label-badge">${tag.name}</span>`)
                    .join('')}
                </div>
              `
                  : ''
              }

              <div class="email-meta">
                <div class="meta-row">
                  <span class="meta-label">From:</span>
                  <span class="meta-value">
                    ${cleanNameDisplay(emailData.sender?.name)}
                    ${emailData.sender?.email ? `&lt;${emailData.sender.email}&gt;` : ''}
                  </span>
                </div>

                ${
                  emailData.to && emailData.to.length > 0
                    ? `
                  <div class="meta-row">
                    <span class="meta-label">To:</span>
                    <span class="meta-value">
                      ${emailData.to
                        .map(
                          (recipient) =>
                            `${cleanNameDisplay(recipient.name)} &lt;${recipient.email}&gt;`,
                        )
                        .join(', ')}
                    </span>
                  </div>
                `
                    : ''
                }

                ${
                  emailData.cc && emailData.cc.length > 0
                    ? `
                  <div class="meta-row">
                    <span class="meta-label">CC:</span>
                    <span class="meta-value">
                      ${emailData.cc
                        .map(
                          (recipient) =>
                            `${cleanNameDisplay(recipient.name)} &lt;${recipient.email}&gt;`,
                        )
                        .join(', ')}
                    </span>
                  </div>
                `
                    : ''
                }

                ${
                  emailData.bcc && emailData.bcc.length > 0
                    ? `
                  <div class="meta-row">
                    <span class="meta-label">BCC:</span>
                    <span class="meta-value">
                      ${emailData.bcc
                        .map(
                          (recipient) =>
                            `${cleanNameDisplay(recipient.name)} &lt;${recipient.email}&gt;`,
                        )
                        .join(', ')}
                    </span>
                  </div>
                `
                    : ''
                }

                <div class="meta-row">
                  <span class="meta-label">Date:</span>
                  <span class="meta-value">${formatDate(emailData.receivedOn)}</span>
                </div>
              </div>
            </div>

            <div class="separator"></div>

            <!-- Email Body -->
            <div class="email-body">
              <div class="email-content">
                ${cleanHtml(emailData?.decodedBody || '')}
              </div>
            </div>

            <!-- Attachments -->
            ${
              messageAttachments && messageAttachments.length > 0
                ? `
              <div class="attachments-section">
                <h2 class="attachments-title">Attachments (${messageAttachments.length})</h2>
                ${messageAttachments
                  .map(
                    (attachment) => `
                  <div class="attachment-item">
                    <span class="attachment-name">${attachment.filename}</span>
                    ${formatFileSize(attachment.size) ? ` - <span class="attachment-size">${formatFileSize(attachment.size)}</span>` : ''}
                  </div>
                `,
                  )
                  .join('')}
              </div>
            `
                : ''
            }
          </div>
        </body>
      </html>
    `;

      if (printFrame.contentWindow) {
        // Write content to the iframe
        const iframeDoc = printFrame.contentDocument || printFrame.contentWindow.document;
        iframeDoc.open();
        iframeDoc.write(printContent);
        iframeDoc.close();

        // Wait for content to load, then print
        printFrame.onload = function () {
          setTimeout(() => {
            try {
              if (!printFrame.contentWindow) {
                console.error('Failed to get iframe window');
                return;
              }
              // Focus the iframe and print
              printFrame.contentWindow.focus();
              printFrame.contentWindow.print();

              // Clean up - remove the iframe after a delay
              setTimeout(() => {
                if (printFrame && printFrame.parentNode) {
                  document.body.removeChild(printFrame);
                }
              }, 1000);
            } catch (error) {
              console.error('Error during print:', error);
              // Clean up on error
              if (printFrame && printFrame.parentNode) {
                document.body.removeChild(printFrame);
              }
            }
          }, 500);
        };
      }
    } catch (error) {
      console.error('Error printing email:', error);
      toast.error('Failed to print email. Please try again.');
    }
  };

  const renderPerson = useCallback(
    (person: Sender) => (
      <Popover key={person.email}>
        <PopoverTrigger asChild>
          <div
            key={person.email}
            className="dark:bg-panelDark inline-flex items-center justify-start gap-1.5 overflow-hidden rounded-full border bg-white p-1 pr-2"
          >
            <BimiAvatar
              email={person.email}
              name={person.name || person.email}
              className="h-5 w-5"
            />
            <div className="text-panelDark justify-start text-sm font-medium leading-none dark:text-white">
              {person.name || person.email}
            </div>
          </div>
        </PopoverTrigger>
        <PopoverContent className="min-w-fit text-sm">
          <div className="flex items-center gap-2">
            <BimiAvatar
              email={person.email}
              name={person.name || person.email}
              className="h-12 w-12"
            />
            <div>
              <p className="font-medium">{person.name || 'Unknown'}</p>
              <div className="group flex items-center gap-2">
                <p>{person.email || 'No email'}</p>
                <span className="opacity-0 transition-opacity duration-150 group-hover:opacity-100">
                  <CopyIcon
                    size={14}
                    className="cursor-pointer"
                    onClick={() => handleCopySenderEmail(person.email)}
                  />
                </span>
              </div>
            </div>
          </div>
        </PopoverContent>
      </Popover>
    ),
    [],
  );

  const people = useMemo(() => {
    if (!activeConnection) return [];
    const allPeople = [
      ...(folder === 'sent' ? [] : [emailData.sender]),
      ...(emailData.to || []),
      ...(emailData.cc || []),
      ...(emailData.bcc || []),
    ];
    return allPeople.filter(
      (p): p is Sender =>
        Boolean(p?.email) &&
        p.email !== activeConnection!.email &&
        p.name !== 'No Sender Name' &&
        p === allPeople.find((other) => other?.email === p?.email),
    );
  }, [emailData, activeConnection]);

  return (
    <div
      className={cn('relative flex-1 overflow-hidden')}
      id={`mail-${emailData.id}`}
      onClick={(e) => {
        if (openDetailsPopover) {
          e.stopPropagation();
        }
      }}
    >
      <>
        {searchQuery && (
          <MoreAboutQuery
            query={searchQuery}
            open={!!searchQuery}
            onOpenChange={(open) => (open ? void 0 : setSearchQuery(null))}
          />
        )}
        {researchSender && (
          <MoreAboutPerson
            open={!!researchSender}
            onOpenChange={(open) => (open ? void 0 : setResearchSender(null))}
            person={researchSender}
          />
        )}
        <div className="relative h-full overflow-y-auto">
          <div className={cn('px-4', index === 0 && 'border-b py-4')}>
            {index === 0 && (
              <>
                <span className="inline-flex items-center gap-2 font-medium text-black dark:text-white">
                  <span>
                    {emailData.subject}{' '}
                    <span className="text-muted-foreground dark:text-[#8C8C8C]">
                      {totalEmails && totalEmails > 1 && `[${totalEmails}]`}
                    </span>
                  </span>
                </span>

                <div className="mt-2 flex items-center gap-2">
                  {emailData?.tags?.length ? (
                    <MailDisplayLabels labels={emailData?.tags.map((t) => t.name) || []} />
                  ) : null}
                  {emailData?.tags?.length ? (
                    <div className="bg-iconLight dark:bg-iconDark/20 relative h-3 w-0.5 rounded-full" />
                  ) : null}
                  <RenderLabels labels={threadLabels} />
                  {threadLabels.length ? (
                    <div className="bg-iconLight dark:bg-iconDark/20 relative h-3 w-0.5 rounded-full" />
                  ) : null}
                  <div className="text-muted-foreground flex items-center gap-2 text-sm dark:text-[#8C8C8C]">
                    {(() => {
                      if (people.length <= 2) {
                        return people.map(renderPerson);
                      }

                      // Only show first two people plus count if we have at least two people
                      const firstPerson = people[0];
                      const secondPerson = people[1];

                      if (firstPerson && secondPerson) {
                        return (
                          <>
                            {renderPerson(firstPerson)}
                            {renderPerson(secondPerson)}
                            <Tooltip>
                              <TooltipTrigger asChild>
                                <span className="text-sm">
                                  +{people.length - 2}{' '}
                                  {people.length - 2 === 1 ? 'other' : 'others'}
                                </span>
                              </TooltipTrigger>
                              <TooltipContent className="flex flex-col gap-1">
                                {people.slice(2).map((person) => (
                                  <div key={person.email}>{renderPerson(person)}</div>
                                ))}
                              </TooltipContent>
                            </Tooltip>
                          </>
                        );
                      }

                      return null;
                    })()}
                  </div>
                </div>
                <MailAssistantCard
                  subject={emailData.subject}
                  latestMessage={emailData}
                  onAskAI={() => {
                    toggleAISidebar();
                  }}
                  onResearch={(query) => {
                    setSearchQuery(query);
                  }}
                />
                {threadAttachments && threadAttachments.length > 0 && (
                  <ThreadAttachments attachments={threadAttachments} />
                )}
              </>
            )}
          </div>
          <div className="flex cursor-pointer flex-col pb-2 duration-200" onClick={toggleCollapse}>
            <div className="mt-3 flex w-full items-start justify-between gap-4 px-4">
              <div className="flex w-full justify-center gap-4">
                <BimiAvatar
                  email={emailData?.sender?.email}
                  name={emailData?.sender?.name}
                  className="mt-3 h-8 w-8"
                />

                <div className="flex w-full items-center justify-between">
                  <div className="flex w-full items-center justify-start">
                    <div className="flex w-full flex-col">
                      <div className="flex w-full items-center justify-between">
                        <div className="flex items-center gap-1">
                          <div className="flex items-center gap-2">
                            <span
                              onClick={(e) => {
                                e.stopPropagation();
                                e.preventDefault();
                                setResearchSender({
                                  name: emailData?.sender?.name || '',
                                  email: emailData?.sender?.email || '',
                                  //   extra: emailData?.sender?.extra || '',
                                });
                              }}
                              className="hover:bg-muted font-semibold"
                            >
                              {cleanNameDisplay(emailData?.sender?.name)}
                            </span>
                            <EmailVerificationBadge messageId={emailData?.id} />
                          </div>

                          <Popover open={openDetailsPopover} onOpenChange={handlePopoverChange}>
                            <PopoverTrigger asChild>
                              <button
                                className="hover:bg-iconLight/10 dark:hover:bg-iconDark/20 flex cursor-pointer items-center gap-2 rounded-md p-2"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  e.preventDefault();
                                  setOpenDetailsPopover(!openDetailsPopover);
                                }}
                                ref={triggerRef}
                              >
                                <p className="text-muted-foreground text-xs underline dark:text-[#8C8C8C]">
                                  {m['common.mailDisplay.details']()}
                                </p>
                              </button>
                            </PopoverTrigger>
                            <PopoverContent
                              className="dark:bg-panelDark flex w-[420px] overflow-auto rounded-lg border p-4 text-left shadow-lg md:w-auto"
                              onBlur={(e) => {
                                if (!triggerRef.current?.contains(e.relatedTarget)) {
                                  setOpenDetailsPopover(false);
                                }
                              }}
                              onClick={(e) => e.stopPropagation()}
                            >
                              <div className="space-y-1 text-sm">
                                <div className="flex">
                                  <span className="w-24 text-end text-gray-500">
                                    {m['common.mailDisplay.from']()}:
                                  </span>
                                  <div className="ml-3">
                                    <span className="text-muted-foreground text-nowrap pr-1 font-bold">
                                      {cleanNameDisplay(emailData?.sender?.name)}
                                    </span>
                                    {emailData?.sender?.name !== emailData?.sender?.email && (
                                      <span className="text-muted-foreground text-nowrap">
                                        {cleanEmailDisplay(emailData?.sender?.email)}
                                      </span>
                                    )}
                                  </div>
                                </div>
                                <div className="flex">
                                  <span className="w-24 text-nowrap text-end text-gray-500">
                                    {m['common.mailDisplay.to']()}:
                                  </span>
                                  <span className="text-muted-foreground ml-3 text-nowrap">
                                    {emailData?.to
                                      ?.map((t) => cleanEmailDisplay(t.email))
                                      .join(', ')}
                                  </span>
                                </div>
                                {emailData?.replyTo && emailData.replyTo.length > 0 && (
                                  <div className="flex">
                                    <span className="w-24 text-nowrap text-end text-gray-500">
                                      {m['common.mailDisplay.replyTo']()}:
                                    </span>
                                    <span className="text-muted-foreground ml-3 text-nowrap">
                                      {cleanEmailDisplay(emailData?.replyTo)}
                                    </span>
                                  </div>
                                )}
                                {emailData?.cc && emailData.cc.length > 0 && (
                                  <div className="flex">
                                    <span className="shrink-0text-nowrap w-24 text-end text-gray-500">
                                      {m['common.mailDisplay.cc']()}:
                                    </span>
                                    <span className="text-muted-foreground ml-3 text-nowrap">
                                      {emailData?.cc
                                        ?.map((t) => cleanEmailDisplay(t.email))
                                        .join(', ')}
                                    </span>
                                  </div>
                                )}
                                {emailData?.bcc && emailData.bcc.length > 0 && (
                                  <div className="flex">
                                    <span className="w-24 text-end text-gray-500">
                                      {m['common.mailDisplay.bcc']()}:
                                    </span>
                                    <span className="text-muted-foreground ml-3 text-nowrap">
                                      {emailData?.bcc
                                        ?.map((t) => cleanEmailDisplay(t.email))
                                        .join(', ')}
                                    </span>
                                  </div>
                                )}
                                <div className="flex">
                                  <span className="w-24 text-end text-gray-500">
                                    {m['common.mailDisplay.date']()}:
                                  </span>
                                  <span className="text-muted-foreground ml-3 text-nowrap">
                                    {emailData?.receivedOn &&
                                    !isNaN(new Date(emailData.receivedOn).getTime())
                                      ? format(new Date(emailData.receivedOn), 'PPpp')
                                      : ''}
                                  </span>
                                </div>
                                <div className="flex">
                                  <span className="w-24 text-end text-gray-500">
                                    {m['common.mailDisplay.mailedBy']()}:
                                  </span>
                                  <span className="text-muted-foreground ml-3 text-nowrap">
                                    {cleanEmailDisplay(emailData?.sender?.email)}
                                  </span>
                                </div>
                                <div className="flex">
                                  <span className="w-24 text-end text-gray-500">
                                    {m['common.mailDisplay.signedBy']()}:
                                  </span>
                                  <span className="text-muted-foreground ml-3 text-nowrap">
                                    {cleanEmailDisplay(emailData?.sender?.email)}
                                  </span>
                                </div>
                                {emailData.tls && (
                                  <div className="flex items-center">
                                    <span className="w-24 text-end text-gray-500">
                                      {m['common.mailDisplay.security']()}:
                                    </span>
                                    <div className="text-muted-foreground ml-3 flex items-center gap-1">
                                      <Lock className="h-4 w-4 text-green-600" />{' '}
                                      {m['common.mailDisplay.standardEncryption']()}
                                    </div>
                                  </div>
                                )}
                              </div>
                            </PopoverContent>
                          </Popover>
                        </div>

                        <div className="flex items-center justify-center">
                          <div className="text-muted-foreground flex-nowrap! mr-2 flex flex-col items-end text-sm font-medium dark:text-[#8C8C8C]">
                            <time className="whitespace-nowrap">
                              {emailData?.receivedOn ? formatDate(emailData.receivedOn) : ''}
                            </time>
                            {shouldShowSeparateTime(emailData?.receivedOn) && (
                              <time className="whitespace-nowrap text-xs opacity-75">
                                {emailData?.receivedOn && formatTime(emailData.receivedOn)}
                              </time>
                            )}
                          </div>

                          {/* options menu */}
                          <DropdownMenu>
                            <DropdownMenuTrigger asChild>
                              <button
                                onClick={(e) => {
                                  e.stopPropagation();
                                  e.preventDefault();
                                }}
                                className="inline-flex h-7 w-7 cursor-pointer items-center justify-center gap-1 overflow-hidden rounded-md bg-white transition-colors hover:bg-gray-100 focus:outline-none focus:ring-0 dark:bg-[#313131] dark:hover:bg-[#3d3d3d]"
                              >
                                <ThreeDots className="fill-iconLight dark:fill-iconDark" />
                              </button>
                            </DropdownMenuTrigger>
                            <DropdownMenuContent align="end" className="bg-white dark:bg-[#313131]">
                              <DropdownMenuItem
                                onClick={(e) => {
                                  e.preventDefault();
                                  e.stopPropagation();
                                  printMail();
                                }}
                              >
                                <Printer className="fill-iconLight dark:fill-iconDark mr-2 h-4 w-4" />
                                {m['common.mailDisplay.print']()}
                              </DropdownMenuItem>
                              {(messageAttachments?.length ?? 0) > 0 && (
                                <DropdownMenuItem
                                  disabled={!messageAttachments?.length}
                                  className={
                                    !messageAttachments?.length
                                      ? 'data-disabled:pointer-events-auto'
                                      : ''
                                  }
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    e.preventDefault();
                                    handleDownloadAllAttachments(
                                      emailData.subject || 'email',
                                      messageAttachments || [],
                                    )();
                                  }}
                                >
                                  <HardDriveDownload className="fill-iconLight dark:text-iconDark dark:fill-iconLight mr-2 h-4 w-4" />
                                  Download All Attachments
                                </DropdownMenuItem>
                              )}
                            </DropdownMenuContent>
                          </DropdownMenu>
                        </div>
                      </div>
                      <div className="flex justify-between">
                        <div className="flex gap-1">
                          <p className="text-muted-foreground text-sm font-medium dark:text-[#8C8C8C]">
                            {m['common.mailDisplay.to']()}:{' '}
                            {(() => {
                              // Combine to and cc recipients
                              const allRecipients = [
                                ...(emailData?.to || []),
                                ...(emailData?.cc || []),
                              ];

                              // If you're the only recipient
                              if (allRecipients.length === 1 && folder !== 'sent') {
                                return <span key="you">You</span>;
                              }

                              // Show first 3 recipients + count of others
                              const visibleRecipients = allRecipients.slice(0, 3);
                              const remainingCount = allRecipients.length - 3;

                              return (
                                <>
                                  {visibleRecipients.map((recipient, index) => (
                                    <span key={recipient.email}>
                                      {cleanNameDisplay(recipient.name) ||
                                        cleanEmailDisplay(recipient.email)}
                                      {index < visibleRecipients.length - 1 ? ', ' : ''}
                                    </span>
                                  ))}
                                  {remainingCount > 0 && (
                                    <span key="others">{`, +${remainingCount} others`}</span>
                                  )}
                                </>
                              );
                            })()}
                          </p>
                          {(emailData?.bcc?.length || 0) > 0 && (
                            <p className="text-muted-foreground text-sm font-medium dark:text-[#8C8C8C]">
                              Bcc:{' '}
                              {emailData?.bcc?.map((recipient, index) => (
                                <span key={recipient.email}>
                                  {cleanNameDisplay(recipient.name) ||
                                    cleanEmailDisplay(recipient.email)}
                                  {index < (emailData?.bcc?.length || 0) - 1 ? ', ' : ''}
                                </span>
                              ))}
                            </p>
                          )}
                        </div>
                      </div>
                    </div>

                    {/* Pending, needs a storage to make the unsubscribe status consitent */}
                    {/* <span className="text-muted-foreground flex grow-0 items-center gap-2 text-sm">
                    {listUnsubscribeAction && (
                      <Dialog>
                        <DialogTrigger asChild>
                          <Button
                            size="xs"
                            variant="secondary"
                            disabled={unsubscribed || isUnsubscribing}
                          >
                            {unsubscribed && <Check className="h-4 w-4" />}
                            {isUnsubscribing && (
                              <LoaderCircleIcon className="h-4 w-4 animate-spin" />
                            )}
                            {unsubscribed
                              ? t('common.mailDisplay.unsubscribed')
                              : t('common.mailDisplay.unsubscribe')}
                          </Button>
                        </DialogTrigger>

                        <DialogContent>
                          <DialogHeader>
                            <DialogTitle>{t('common.mailDisplay.unsubscribe')}</DialogTitle>
                            <DialogDescription className="break-words">
                              {t('common.mailDisplay.unsubscribeDescription')}
                            </DialogDescription>
                          </DialogHeader>
                          <DialogFooter className="gap-2">
                            <DialogClose asChild>
                              <Button disabled={isUnsubscribing} variant="outline">
                                {t('common.mailDisplay.cancel')}
                              </Button>
                            </DialogClose>
                            <DialogClose asChild>
                              <Button disabled={isUnsubscribing} onClick={_handleUnsubscribe}>
                                {t('common.mailDisplay.unsubscribe')}
                              </Button>
                            </DialogClose>
                          </DialogFooter>
                        </DialogContent>
                      </Dialog>
                    )}
                  </span> */}
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div className={cn('h-0 overflow-hidden duration-200', !isCollapsed && 'h-px')}></div>

          <div
            className={cn(
              'grid overflow-hidden duration-200',
              isCollapsed ? 'grid-rows-[0fr]' : 'grid-rows-[1fr]',
            )}
            onClick={(e) => e.stopPropagation()}
          >
            <div className="min-h-0 overflow-hidden">
              <div className="h-fit w-full p-0">
                {/* mail main body */}
                {emailData?.decodedBody ? (
                  <MailContent
                    id={emailData.id}
                    html={emailData?.decodedBody}
                    senderEmail={emailData.sender.email}
                  />
                ) : null}
                {/* mail attachments */}
                {messageAttachments && messageAttachments.length > 0 ? (
                  <div className="mb-4 flex flex-wrap items-center gap-2 px-4 pt-4">
                    {messageAttachments.map((attachment) => (
                      <div
                        key={`${attachment.filename}-${attachment.attachmentId}`}
                        className="flex"
                      >
                        <button
                          className="flex cursor-pointer items-center gap-1 rounded-[5px] bg-[#FAFAFA] px-1.5 py-1 text-sm font-medium hover:bg-[#F0F0F0] dark:bg-[#262626] dark:hover:bg-[#303030]"
                          onClick={() => openAttachment(attachment)}
                        >
                          {getFileIcon(attachment.filename)}
                          <span className="max-w-[15ch] truncate text-sm text-black dark:text-white">
                            {attachment.filename}
                          </span>{' '}
                          <span className="text-muted-foreground whitespace-nowrap text-sm dark:text-[#929292]">
                            {formatFileSize(attachment.size)}
                          </span>
                        </button>
                        <button
                          onClick={() => downloadAttachment(attachment)}
                          className="flex cursor-pointer items-center gap-1 rounded-[5px] px-1.5 py-1 text-sm"
                        >
                          <HardDriveDownload className="text-muted-foreground dark:text-muted-foreground h-4 w-4 fill-[#FAFAFA] dark:fill-[#262626]" />
                        </button>
                        {index < (messageAttachments?.length || 0) - 1 && (
                          <div className="m-auto h-2 w-px bg-[#E0E0E0] dark:bg-[#424242]" />
                        )}
                      </div>
                    ))}
                  </div>
                ) : null}
                <div className="my-2.5 flex gap-2 px-4">
                  <ActionButton
                    onClick={(e) => {
                      e.stopPropagation();
                      setIsCollapsed(false);
                      setMode('reply');
                      setActiveReplyId(emailData.id);
                    }}
                    icon={<Reply className="fill-muted-foreground dark:fill-[#9B9B9B]" />}
                    text={m['common.mail.reply']()}
                    shortcut={isLastEmail ? 'r' : undefined}
                  />
                  <ActionButton
                    onClick={(e) => {
                      e.stopPropagation();
                      setIsCollapsed(false);
                      setMode('replyAll');
                      setActiveReplyId(emailData.id);
                    }}
                    icon={<ReplyAll className="fill-muted-foreground dark:fill-[#9B9B9B]" />}
                    text={m['common.mail.replyAll']()}
                    shortcut={isLastEmail ? 'a' : undefined}
                  />
                  <ActionButton
                    onClick={(e) => {
                      e.stopPropagation();
                      setIsCollapsed(false);
                      setMode('forward');
                      setActiveReplyId(emailData.id);
                    }}
                    icon={<Forward className="fill-muted-foreground dark:fill-[#9B9B9B]" />}
                    text={m['common.mail.forward']()}
                    shortcut={isLastEmail ? 'f' : undefined}
                  />
                  <ActionButton
                    onClick={(e) => {
                      e.stopPropagation();
                      if (!threadId) return;

                      void createTaskFromSuggestion({
                        threadId,
                        task: buildTaskSuggestionFromMessage(emailData),
                      })
                        .then(() => {
                          toast.success('Task created from email');
                        })
                        .catch((error) => {
                          console.error('Failed to create task from message', error);
                          toast.error('Failed to create task');
                        });
                    }}
                    icon={<ListTodo className="text-muted-foreground dark:text-[#9B9B9B] h-3.5 w-3.5" />}
                    text="Task"
                  />
                  <ActionButton
                    onClick={(e) => {
                      e.stopPropagation();
                      const suggestedEvent = assistantQuery.data?.suggestedEvent;

                      if (!threadId || !suggestedEvent?.startAt || !suggestedEvent.endAt) {
                        setSearchQuery(`Double check scheduling details for ${emailData.subject}`);
                        return;
                      }

                      void createEventFromSuggestion({
                        threadId,
                        event: {
                          ...suggestedEvent,
                          startAt: suggestedEvent.startAt,
                          endAt: suggestedEvent.endAt,
                        },
                      })
                        .then(() => {
                          toast.success('Calendar event created');
                        })
                        .catch((error) => {
                          console.error('Failed to create event from message', error);
                          toast.error('Failed to create calendar event');
                        });
                    }}
                    icon={<CalendarClock className="text-muted-foreground dark:text-[#9B9B9B] h-3.5 w-3.5" />}
                    text="Event"
                  />
                  <ActionButton
                    onClick={(e) => {
                      e.stopPropagation();
                      toggleAISidebar();
                    }}
                    icon={<Lightning className="fill-muted-foreground dark:fill-[#9B9B9B]" />}
                    text="Ask AI"
                  />
                  <ActionButton
                    onClick={(e) => {
                      e.stopPropagation();
                      setSearchQuery(
                        assistantQuery.data?.researchQueries?.[0] ||
                          `${emailData.sender?.name || emailData.sender?.email || 'sender'} ${emailData.subject || ''}`,
                      );
                    }}
                    icon={<Search className="text-muted-foreground dark:text-[#9B9B9B] h-3.5 w-3.5" />}
                    text="Research"
                  />
                </div>
              </div>
            </div>
          </div>
        </div>
      </>
    </div>
  );
};

export default memo(MailDisplay);
