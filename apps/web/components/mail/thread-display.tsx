import {
  Archive,
  ArchiveX,
  Folders,
  Lightning,
  Mail,
  Printer,
  Reply,
  Sparkles,
  Star,
  ThreeDots,
  Trash,
  X,
} from '../icons/icons';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { useOptimisticThreadState } from '@/components/mail/optimistic-thread-state';
import { useCreateTaskFromThread } from '@/hooks/use-create-task-from-thread';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useOptimisticActions } from '@/hooks/use-optimistic-actions';
import { focusedIndexAtom } from '@/hooks/use-mail-navigation';
import { type ThreadDestination } from '@/lib/thread-actions';
import { handleUnsubscribe } from '@/lib/email-utils.client';
import { Inbox, ListChecks, StickyNote } from 'lucide-react';
import { useThread, useThreads } from '@/hooks/use-threads';
import { EmptyStateIcon } from '../icons/empty-state-svg';
import { ScrollArea } from '@/components/ui/scroll-area';
import type { ParsedMessage, Attachment } from '@/types';
import { useAnimations } from '@/hooks/use-animations';
import { AnimatePresence, motion } from 'motion/react';
import { useAISidebar } from '@/hooks/use-ai-sidebar';
import { MailDisplaySkeleton } from './mail-skeleton';
import { useTRPC } from '@/providers/query-provider';
import { useMutation } from '@tanstack/react-query';
import { useIsMobile } from '@/hooks/use-mobile';
import { Button } from '@/components/ui/button';
import { cleanHtml } from '@/lib/email-utils';
import ReplyCompose from './reply-composer';
import { APP_NAME } from '@/lib/branding';
import { NotesPanel } from './note-panel';
import { cn, FOLDERS } from '@/lib/utils';
import { m } from '@/paraglide/messages';
import MailDisplay from './mail-display';
import { useParams } from 'react-router';
import { useQueryState } from 'nuqs';
import { format } from 'date-fns';
import { useAtom } from 'jotai';
import { toast } from 'sonner';

const formatFileSize = (size: number) => {
  const sizeInMB = (size / (1024 * 1024)).toFixed(2);
  return sizeInMB === '0.00' ? '' : `${sizeInMB} MB`;
};

const cleanNameDisplay = (name?: string) => {
  if (!name) return '';
  return name.replace(/["<>]/g, '');
};

// HTML-escape arbitrary email metadata before interpolating it into the print
// iframe. Without this a hostile sender could exec JS in the iframe (same
// origin as the app → access to cookies/IDB) via a crafted subject, name, or
// attachment filename. Used by every interpolation in handlePrintThread.
const escapeHtml = (str: unknown) =>
  String(str ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');

interface ThreadDisplayProps {
  threadParam?: unknown;
  onClose?: () => void;
  isMobile?: boolean;
  messages?: ParsedMessage[];
  id?: string;
}

export function ThreadDemo({ messages, isMobile }: ThreadDisplayProps) {
  const isFullscreen = false;
  return (
    <div
      className={cn(
        'flex flex-col',
        isFullscreen ? 'h-screen' : isMobile ? 'h-full' : 'h-[calc(100dvh-2rem)]',
      )}
    >
      <div
        className={cn(
          'bg-offsetLight dark:bg-offsetDark relative flex flex-col overflow-hidden duration-300',
          isMobile ? 'h-full' : 'h-full',
          !isMobile && !isFullscreen && 'rounded-r-lg',
          isFullscreen ? 'fixed inset-0 z-50' : '',
        )}
      >
        <div className="flex min-h-0 flex-1 flex-col overflow-hidden">
          <ScrollArea className="flex-1" type="scroll">
            <div className="pb-4">
              {[...(messages || [])].reverse().map((message, index) => (
                <div
                  key={message.id}
                  className={cn('duration-200', index > 0 && 'border-border border-t')}
                >
                  <MailDisplay
                    demo
                    emailData={message}
                    isFullscreen={isFullscreen}
                    isMuted={false}
                    isLoading={false}
                    index={index}
                  />
                </div>
              ))}
            </div>
          </ScrollArea>
        </div>
      </div>
    </div>
  );
}

function ThreadActionButton({
  icon: Icon,
  label,
  onClick,
  disabled = false,
  className,
}: {
  icon: React.ComponentType<React.SVGProps<SVGSVGElement>> & {
    startAnimation?: () => void;
    stopAnimation?: () => void;
  };
  label: string;
  onClick?: () => void;
  disabled?: boolean;
  className?: string;
}) {
  const iconRef = useRef<SVGSVGElement | null>(null);

  return (
    <TooltipProvider delayDuration={0}>
      <Tooltip>
        <TooltipTrigger asChild>
          <Button
            disabled={disabled}
            onClick={onClick}
            variant="ghost"
            className={cn('md:h-fit md:px-2', className)}
            onMouseEnter={() => iconRef.current?.startAnimation?.()}
            onMouseLeave={() => iconRef.current?.stopAnimation?.()}
          >
            <Icon ref={iconRef} className="dark:fill-iconDark fill-iconLight" />
            <span className="sr-only">{label}</span>
          </Button>
        </TooltipTrigger>
        {/* <TooltipContent>{label}</TooltipContent> */}
      </Tooltip>
    </TooltipProvider>
  );
}
const isFullscreen = false;
export function ThreadDisplay() {
  const isMobile = useIsMobile();
  const { toggleOpen: toggleAISidebar } = useAISidebar();
  const params = useParams<{ folder: string }>();

  const folder = params?.folder ?? 'inbox';
  const [id, setThreadId] = useQueryState('threadId');
  const {
    data: emailData,
    isLoading,
    isError,
    error,
    refetch: refetchThread,
  } = useThread(id ?? null);
  const [, items] = useThreads();
  const [isStarred, setIsStarred] = useState(false);
  const [isImportant, setIsImportant] = useState(false);
  const [isNotesOpen, setIsNotesOpen] = useState(false);

  const [navigationDirection, setNavigationDirection] = useState<'previous' | 'next' | null>(null);

  const animationsEnabled = useAnimations();

  // Collect all attachments from all messages in the thread
  const allThreadAttachments = useMemo(() => {
    if (!emailData?.messages) return [];
    return emailData.messages.reduce<Attachment[]>((acc, message) => {
      if (message.attachments && message.attachments.length > 0) {
        acc.push(...message.attachments);
      }
      return acc;
    }, []);
  }, [emailData?.messages]);

  const [mode, setMode] = useQueryState('mode');
  const [activeReplyId, setActiveReplyId] = useQueryState('activeReplyId');
  const [, setDraftId] = useQueryState('draftId');

  const [focusedIndex, setFocusedIndex] = useAtom(focusedIndexAtom);
  const trpc = useTRPC();
  const { mutateAsync: toggleImportant } = useMutation(trpc.mail.toggleImportant.mutationOptions());
  const { createTaskFromThread, isPending: isCreatingTask } = useCreateTaskFromThread();
  const [, setIsComposeOpen] = useQueryState('isComposeOpen');

  // Get optimistic state for this thread
  const optimisticState = useOptimisticThreadState(id ?? '');

  const handleNext = useCallback(() => {
    if (!id || !items.length || focusedIndex === null) return setThreadId(null);
    if (focusedIndex < items.length - 1) {
      const nextIndex = Math.max(1, focusedIndex + 1);
      //   console.log('nextIndex', nextIndex);

      const nextThread = items[nextIndex];
      if (nextThread) {
        setMode(null);
        setActiveReplyId(null);
        setDraftId(null);
        setThreadId(nextThread.id);
        setFocusedIndex(focusedIndex + 1);
        if (animationsEnabled) {
          setNavigationDirection('next');
        }
      }
    }
  }, [
    items,
    id,
    focusedIndex,
    setThreadId,
    setFocusedIndex,
    setMode,
    setActiveReplyId,
    setDraftId,
    animationsEnabled,
  ]);

  const handleUnsubscribeProcess = () => {
    if (!emailData?.latest) return;
    toast.promise(handleUnsubscribe({ emailData: emailData.latest }), {
      success: 'Unsubscribed successfully!',
      error: 'Failed to unsubscribe',
    });
  };

  const isInArchive = folder === FOLDERS.ARCHIVE;
  const isInSpam = folder === FOLDERS.SPAM;
  const isInBin = folder === FOLDERS.BIN;
  const handleClose = useCallback(() => {
    setThreadId(null);
    setMode(null);
    setActiveReplyId(null);
    setDraftId(null);
    setIsNotesOpen(false);
  }, [setThreadId, setMode, setActiveReplyId, setDraftId]);

  const { optimisticMoveThreadsTo } = useOptimisticActions();

  const moveThreadTo = useCallback(
    async (destination: ThreadDestination) => {
      if (!id) return;

      setMode(null);
      setActiveReplyId(null);
      setDraftId(null);

      optimisticMoveThreadsTo([id], folder, destination);
      handleNext();
    },
    [id, folder, optimisticMoveThreadsTo, handleNext, setMode, setActiveReplyId, setDraftId],
  );

  const { optimisticToggleStar } = useOptimisticActions();

  const handleToggleStar = useCallback(async () => {
    if (!emailData || !id) return;

    const newStarredState = !isStarred;
    optimisticToggleStar([id], newStarredState);
    setIsStarred(newStarredState);
  }, [emailData, id, isStarred, optimisticToggleStar]);

  const printThread = () => {
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

      // escapeHtml is now defined at module scope so it can be reused for
      // every interpolation below. Without per-field escaping a crafted
      // sender name like `<img src=x onerror=...>` would execute JS inside
      // this iframe (same origin → cookie/IDB access).

      // Generate clean, simple HTML content for printing
      const printContent = `
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="utf-8">
          <title>Print Thread - ${escapeHtml(emailData?.latest?.subject || 'No Subject')}</title>
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

              * {
                border: none !important;
                box-shadow: none !important;
              }

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
          ${emailData?.messages
            ?.map(
              (message, index) => `
            <div class="email-container">
              <div class="email-header">
                ${
                  index === 0
                    ? `<h1 class="email-title">${escapeHtml(message.subject || 'No Subject')}</h1>`
                    : ''
                }


                ${
                  message?.tags && message.tags.length > 0
                    ? `
                  <div class="labels-section">
                    ${message.tags
                      .map((tag) => `<span class="label-badge">${escapeHtml(tag.name)}</span>`)
                      .join('')}
                  </div>
                `
                    : ''
                }


                <div class="email-meta">
                  <div class="meta-row">
                    <span class="meta-label">From:</span>
                    <span class="meta-value">
                      ${escapeHtml(cleanNameDisplay(message.sender?.name))}
                      ${message.sender?.email ? `&lt;${escapeHtml(message.sender.email)}&gt;` : ''}
                    </span>
                  </div>


                  ${
                    message.to && message.to.length > 0
                      ? `
                    <div class="meta-row">
                      <span class="meta-label">To:</span>
                      <span class="meta-value">
                        ${message.to
                          .map(
                            (recipient) =>
                              `${escapeHtml(cleanNameDisplay(recipient.name))} &lt;${escapeHtml(recipient.email)}&gt;`,
                          )
                          .join(', ')}
                      </span>
                    </div>
                  `
                      : ''
                  }


                  ${
                    message.cc && message.cc.length > 0
                      ? `
                    <div class="meta-row">
                      <span class="meta-label">CC:</span>
                      <span class="meta-value">
                        ${message.cc
                          .map(
                            (recipient) =>
                              `${escapeHtml(cleanNameDisplay(recipient.name))} &lt;${escapeHtml(recipient.email)}&gt;`,
                          )
                          .join(', ')}
                      </span>
                    </div>
                  `
                      : ''
                  }


                  ${
                    message.bcc && message.bcc.length > 0
                      ? `
                    <div class="meta-row">
                      <span class="meta-label">BCC:</span>
                      <span class="meta-value">
                        ${message.bcc
                          .map(
                            (recipient) =>
                              `${escapeHtml(cleanNameDisplay(recipient.name))} &lt;${escapeHtml(recipient.email)}&gt;`,
                          )
                          .join(', ')}
                      </span>
                    </div>
                  `
                      : ''
                  }


                  <div class="meta-row">
                    <span class="meta-label">Date:</span>
                    <span class="meta-value">${escapeHtml(
                      format(new Date(message.receivedOn), 'PPpp'),
                    )}</span>
                  </div>
                </div>
              </div>

              <div class="separator"></div>

              <div class="email-body">
                <div class="email-content">
                  ${cleanHtml(message.decodedBody ?? '<p><em>No email content available</em></p>')}
                </div>
              </div>


              ${
                message.attachments && message.attachments.length > 0
                  ? `
                <div class="attachments-section">
                  <h2 class="attachments-title">Attachments (${message.attachments.length})</h2>
                  ${message.attachments
                    .map(
                      (attachment) => `
                    <div class="attachment-item">
                      <span class="attachment-name">${escapeHtml(attachment.filename)}</span>
                      ${
                        formatFileSize(attachment.size)
                          ? ` - <span class="attachment-size">${escapeHtml(formatFileSize(attachment.size))}</span>`
                          : ''
                      }
                    </div>
                  `,
                    )
                    .join('')}
                </div>
              `
                  : ''
              }
            </div>
            ${index < emailData.messages.length - 1 ? '<div class="separator"></div>' : ''}
          `,
            )
            .join('')}
        </body>
      </html>
    `;

      // Write content to the iframe
      const iframeDoc = printFrame.contentDocument || printFrame.contentWindow?.document;
      if (!iframeDoc) {
        throw new Error('Could not access iframe document');
      }
      iframeDoc.open();
      iframeDoc.write(printContent);
      iframeDoc.close();

      // Wait for content to load, then print
      printFrame.onload = function () {
        setTimeout(() => {
          try {
            // Focus the iframe and print
            printFrame.contentWindow?.focus();
            printFrame.contentWindow?.print();

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
    } catch (error) {
      console.error('Error printing thread:', error);
      toast.error('Failed to print thread. Please try again.');
    }
  };

  const handleToggleImportant = useCallback(async () => {
    if (!emailData || !id) return;
    // Capture the NEXT important state (toggle is from current value) so the
    // success toast describes what just happened instead of the pre-toggle
    // value (which would always be `!isImportant` for the visible menu item
    // → success branch was unreachable and every success hit the error toast).
    const willBeImportant = !isImportant;
    try {
      await toggleImportant({ ids: [id] });
      await refetchThread();
      toast.success(
        willBeImportant ? m['common.mail.markedAsImportant']() : 'Removed from Important',
      );
    } catch (error) {
      console.error('Failed to toggle important:', error);
      toast.error(
        willBeImportant ? 'Failed to mark as important' : 'Failed to remove from Important',
      );
    }
  }, [emailData, id, isImportant, refetchThread, toggleImportant]);

  // Set initial star state based on email data
  useEffect(() => {
    if (emailData?.latest?.tags) {
      // Check if any tag has the name 'STARRED'
      setIsStarred(emailData.latest.tags.some((tag) => tag.name === 'STARRED'));
      setIsImportant(emailData.latest.tags.some((tag) => tag.name === 'IMPORTANT'));
    }
  }, [emailData?.latest?.tags]);

  useEffect(() => {
    if (optimisticState.optimisticStarred !== null) {
      setIsStarred(optimisticState.optimisticStarred);
    }
  }, [optimisticState.optimisticStarred]);

  //   // Automatically open Reply All composer when email thread is loaded
  //   useEffect(() => {
  //     if (emailData?.latest?.id) {
  //       // Small delay to ensure other effects have completed
  //       const timer = setTimeout(() => {
  //         setMode('replyAll');
  //         setActiveReplyId(emailData.latest!.id);
  //       }, 50);

  //       return () => clearTimeout(timer);
  //     }
  //   }, [emailData?.latest?.id, setMode, setActiveReplyId]);

  // Removed conflicting useEffect that was clearing activeReplyId

  // Scroll to the active reply composer when it's opened
  useEffect(() => {
    if (mode && activeReplyId) {
      setTimeout(() => {
        const replyElement = document.getElementById(`reply-composer-${activeReplyId}`);
        if (replyElement) {
          replyElement.scrollIntoView({ behavior: 'smooth', block: 'center' });
        }
      }, 100); // Short delay to ensure the component is rendered
    }
  }, [mode, activeReplyId]);

  const handleAnimationComplete = useCallback(() => {
    setNavigationDirection(null);
  }, [setNavigationDirection]);

  return (
    <div
      className={cn(
        'flex flex-col',
        isFullscreen ? 'h-screen' : isMobile ? 'h-full' : 'h-[calc(100dvh-19px)] rounded-xl',
      )}
    >
      <div
        className={cn(
          'bg-card relative flex flex-col overflow-hidden rounded-xl transition-all duration-200',
          isMobile ? 'h-full' : 'h-full',
          !isMobile && !isFullscreen && 'rounded-r-lg',
          isFullscreen ? 'fixed inset-0 z-50' : '',
        )}
      >
        {!id ? (
          <div className="flex h-full items-center justify-center">
            <div className="flex flex-col items-center justify-center gap-2 text-center">
              <EmptyStateIcon width={200} height={200} />
              <div className="mt-4">
                {/* "Select a conversation" is clearer than "It's empty here" — the latter implies
                    something is missing/broken rather than communicating that nothing is selected yet */}
                <p className="text-foreground text-base font-medium">Select a conversation</p>
                <p className="text-muted-foreground mt-1 text-[13px]">
                  Choose a thread from the list to read, reply, or archive it
                </p>
                <div className="mt-4 grid grid-cols-1 gap-2 xl:grid-cols-2">
                  {/* Compose is the primary action in an empty thread pane; AI is secondary */}
                  <button
                    onClick={() => setIsComposeOpen('true')}
                    className="bg-card hover:bg-accent inline-flex h-8 cursor-pointer items-center justify-center gap-1 overflow-hidden rounded-full border px-3 transition-colors duration-100"
                  >
                    <Mail className="fill-muted-foreground/50 h-3.5 w-3.5" />
                    <span className="text-foreground text-[13px] leading-none">Compose email</span>
                  </button>
                  <button
                    onClick={toggleAISidebar}
                    className="bg-card hover:bg-accent inline-flex h-8 cursor-pointer items-center justify-center gap-1 overflow-hidden rounded-full border px-3 transition-colors duration-100"
                  >
                    <Sparkles className="fill-muted-foreground/50 h-3.5 w-3.5" />
                    <span className="text-foreground text-[13px] leading-none">
                      Ask {APP_NAME} AI
                    </span>
                  </button>
                </div>
              </div>
            </div>
          </div>
        ) : isError ? (
          <div className="flex min-h-0 flex-1 items-center justify-center px-6">
            <div className="flex max-w-sm flex-col items-center gap-3 text-center">
              <p className="text-base font-medium">Could not load this conversation</p>
              <p className="text-muted-foreground text-[13px]">
                {error instanceof Error ? error.message : 'Check your connection and try again.'}
              </p>
              <Button size="sm" onClick={() => void refetchThread()}>
                Try again
              </Button>
            </div>
          </div>
        ) : !emailData || isLoading ? (
          <div className="flex min-h-0 flex-1 flex-col overflow-hidden">
            <ScrollArea className="h-full flex-1" type="auto">
              <div className="pb-4">
                <MailDisplaySkeleton isFullscreen={isFullscreen} />
              </div>
            </ScrollArea>
          </div>
        ) : (
          <>
            <div
              className={cn(
                'flex shrink-0 items-center px-1 pb-[10px] md:px-3 md:pb-[11px] md:pt-[12px]',
                isMobile && 'bg-card sticky top-0 z-10 mt-2',
              )}
            >
              <div className="flex flex-1 items-center gap-1.5">
                <TooltipProvider delayDuration={0}>
                  <Tooltip>
                    <TooltipTrigger asChild>
                      <button
                        onClick={handleClose}
                        className="hover:bg-accent inline-flex h-7 w-7 items-center justify-center gap-1 overflow-hidden rounded-full transition-colors duration-100 md:hidden"
                      >
                        <X className="fill-iconLight dark:fill-iconDark h-3.5 w-3.5" />
                      </button>
                    </TooltipTrigger>
                    <TooltipContent side="bottom">{m['common.actions.close']()}</TooltipContent>
                  </Tooltip>
                </TooltipProvider>
                <ThreadActionButton
                  icon={X}
                  label={m['common.actions.close']()}
                  onClick={handleClose}
                  className="hidden md:flex"
                />
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    setMode('replyAll');
                    setActiveReplyId(emailData?.latest?.id ?? '');
                  }}
                  className="bg-mainBlue hover:bg-mainBlue/90 inline-flex h-8 cursor-pointer items-center justify-center gap-1 overflow-hidden rounded-full px-3 transition-colors duration-100"
                >
                  <Reply className="fill-white" />
                  <span className="whitespace-nowrap pl-0.5 pr-0.5 text-[13px] leading-none text-white">
                    {m['common.threadDisplay.replyAll']()}
                  </span>
                </button>
                <TooltipProvider delayDuration={0}>
                  <Tooltip>
                    <TooltipTrigger asChild>
                      <button
                        onClick={handleToggleStar}
                        className="bg-card hover:bg-accent inline-flex h-7 w-7 cursor-pointer items-center justify-center gap-1 overflow-hidden rounded-full border transition-colors duration-100"
                      >
                        <Star
                          className={cn(
                            'ml-[2px] mt-[2.4px] h-5 w-5',
                            isStarred
                              ? 'fill-yellow-400 stroke-yellow-400'
                              : 'fill-transparent stroke-[#9D9D9D] dark:stroke-[#9D9D9D]',
                          )}
                        />
                      </button>
                    </TooltipTrigger>
                    <TooltipContent side="bottom" className="bg-card">
                      {isStarred
                        ? m['common.threadDisplay.unstar']()
                        : m['common.threadDisplay.star']()}
                    </TooltipContent>
                  </Tooltip>
                </TooltipProvider>

                <TooltipProvider delayDuration={0}>
                  <Tooltip>
                    <TooltipTrigger asChild>
                      <button
                        onClick={() => moveThreadTo('archive')}
                        className="bg-card hover:bg-accent inline-flex h-7 w-7 cursor-pointer items-center justify-center gap-1 overflow-hidden rounded-full transition-colors"
                      >
                        <Archive className="fill-iconLight dark:fill-iconDark" />
                      </button>
                    </TooltipTrigger>
                    <TooltipContent side="bottom" className="bg-card">
                      {m['common.threadDisplay.archive']()}
                    </TooltipContent>
                  </Tooltip>
                </TooltipProvider>

                {!isInBin && (
                  <TooltipProvider delayDuration={0}>
                    <Tooltip>
                      <TooltipTrigger asChild>
                        <button
                          onClick={() => moveThreadTo('bin')}
                          className="inline-flex h-7 w-7 cursor-pointer items-center justify-center gap-1 overflow-hidden rounded-full border border-[#FCCDD5] bg-[#FDE4E9] transition-colors hover:bg-[#fccdd5]/70 dark:border-[#6E2532] dark:bg-[#411D23] dark:hover:bg-[#6E2532]/70"
                        >
                          <Trash className="fill-[#F43F5E]" />
                        </button>
                      </TooltipTrigger>
                      <TooltipContent side="bottom" className="bg-card">
                        {m['common.mail.moveToBin']()}
                      </TooltipContent>
                    </Tooltip>
                  </TooltipProvider>
                )}

                <DropdownMenu>
                  <DropdownMenuTrigger asChild>
                    <button
                      type="button"
                      aria-label="Thread actions"
                      aria-haspopup="menu"
                      className="focus:outline-hidden inline-flex h-7 w-7 cursor-pointer items-center justify-center gap-1 overflow-hidden rounded-full bg-white transition-colors focus:ring-0 dark:bg-[#313131]"
                    >
                      <ThreeDots className="fill-iconLight dark:fill-iconDark" />
                    </button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent align="end" className="bg-card">
                    <DropdownMenuItem onClick={toggleAISidebar}>
                      <Sparkles className="fill-iconLight dark:fill-iconDark mr-2 h-4 w-4" />
                      <span>Ask AI about this thread</span>
                    </DropdownMenuItem>
                    <DropdownMenuItem onClick={() => setIsNotesOpen(true)}>
                      <StickyNote className="mr-2 h-4 w-4" />
                      <span>{m['common.notes.title']()}</span>
                    </DropdownMenuItem>
                    <DropdownMenuItem
                      onClick={() => void createTaskFromThread()}
                      disabled={isCreatingTask}
                    >
                      <ListChecks className="mr-2 h-4 w-4" />
                      <span>Create task from email</span>
                    </DropdownMenuItem>
                    {/* <DropdownMenuItem onClick={() => setIsFullscreen(!isFullscreen)}>
                      <Expand className="fill-iconLight dark:fill-iconDark mr-2" />
                      <span>
                        {isFullscreen
                          ? t('common.threadDisplay.exitFullscreen')
                          : t('common.threadDisplay.enterFullscreen')}
                      </span>
                    </DropdownMenuItem> */}

                    {isInSpam || isInArchive || isInBin ? (
                      <DropdownMenuItem onClick={() => moveThreadTo('inbox')}>
                        <Inbox className="mr-2 h-4 w-4" />
                        <span>{m['common.mail.moveToInbox']()}</span>
                      </DropdownMenuItem>
                    ) : (
                      <>
                        <DropdownMenuItem
                          onClick={(e) => {
                            e.stopPropagation();
                            printThread();
                          }}
                        >
                          <Printer className="fill-iconLight dark:fill-iconDark mr-2 h-4 w-4" />
                          <span>{m['common.threadDisplay.printThread']()}</span>
                        </DropdownMenuItem>
                        <DropdownMenuItem onClick={() => moveThreadTo('spam')}>
                          <ArchiveX className="fill-iconLight dark:fill-iconDark mr-2" />
                          <span>{m['common.threadDisplay.moveToSpam']()}</span>
                        </DropdownMenuItem>
                        {emailData.latest?.listUnsubscribe ||
                        emailData.latest?.listUnsubscribePost ? (
                          <DropdownMenuItem onClick={handleUnsubscribeProcess}>
                            <Folders className="fill-iconLight dark:fill-iconDark mr-2" />
                            <span>{m['common.mailDisplay.unsubscribe']()}</span>
                          </DropdownMenuItem>
                        ) : null}
                      </>
                    )}
                    {!isImportant && (
                      <DropdownMenuItem onClick={handleToggleImportant}>
                        <Lightning className="fill-iconLight dark:fill-iconDark mr-2" />
                        {m['common.mail.markAsImportant']()}
                      </DropdownMenuItem>
                    )}
                  </DropdownMenuContent>
                </DropdownMenu>
              </div>
            </div>
            <div className={cn('flex min-h-0 flex-1 flex-col', isMobile && 'h-full')}>
              <div className="absolute right-3 top-14 z-20">
                <NotesPanel
                  threadId={id}
                  open={isNotesOpen}
                  onOpenChange={setIsNotesOpen}
                  showTrigger={false}
                />
              </div>
              {animationsEnabled ? (
                <AnimatePresence mode="wait" initial={false}>
                  <motion.div
                    key={id}
                    initial={{
                      opacity: 0,
                      x:
                        navigationDirection === 'previous'
                          ? -25
                          : navigationDirection === 'next'
                            ? 25
                            : 0,
                    }}
                    animate={{
                      opacity: 1,
                      x: 0,
                    }}
                    exit={{
                      opacity: 0,
                      x:
                        navigationDirection === 'previous'
                          ? 25
                          : navigationDirection === 'next'
                            ? -25
                            : 0,
                    }}
                    transition={{
                      duration: 0.08,
                      ease: [0.4, 0, 0.2, 1],
                    }}
                    onAnimationComplete={handleAnimationComplete}
                    className="h-full w-full"
                  >
                    <MessageList
                      messages={emailData.messages}
                      isFullscreen={isFullscreen}
                      totalReplies={emailData?.totalReplies}
                      allThreadAttachments={allThreadAttachments}
                      mode={mode || undefined}
                      activeReplyId={activeReplyId || undefined}
                      isMobile={isMobile}
                    />
                  </motion.div>
                </AnimatePresence>
              ) : (
                <MessageList
                  messages={emailData.messages}
                  isFullscreen={isFullscreen}
                  totalReplies={emailData?.totalReplies}
                  allThreadAttachments={allThreadAttachments}
                  mode={mode || undefined}
                  activeReplyId={activeReplyId || undefined}
                  isMobile={isMobile}
                />
              )}

              {mode &&
                activeReplyId &&
                activeReplyId === emailData.messages[emailData.messages.length - 1]?.id && (
                  <div
                    className="border-border bg-panelLight dark:bg-panelDark sticky bottom-0 z-10 border-t px-4 py-2"
                    id={`reply-composer-${activeReplyId}`}
                  >
                    <ReplyCompose messageId={activeReplyId} />
                  </div>
                )}
            </div>
          </>
        )}
      </div>
    </div>
  );
}

interface MessageListProps {
  messages: ParsedMessage[];
  isFullscreen: boolean;
  totalReplies?: number;
  allThreadAttachments?: Attachment[];
  mode?: string;
  activeReplyId?: string;
  isMobile: boolean;
}

const MessageList = ({
  messages,
  isFullscreen,
  totalReplies,
  allThreadAttachments,
  mode,
  activeReplyId,
  isMobile,
}: MessageListProps) => (
  <ScrollArea className={cn('flex-1', isMobile ? 'h-[calc(100%-1px)]' : 'h-full')} type="auto">
    <div className="pb-4">
      {(messages || []).map((message, index) => {
        const isLastMessage = index === messages.length - 1;
        const isReplyingToThisMessage = mode && activeReplyId === message.id;

        return (
          <div
            key={message.id}
            className={cn('duration-200', index > 0 && 'border-border border-t')}
          >
            <MailDisplay
              emailData={message}
              isFullscreen={isFullscreen}
              isMuted={false}
              isLoading={false}
              index={index}
              totalEmails={totalReplies}
              threadAttachments={index === 0 ? allThreadAttachments : undefined}
            />
            {isReplyingToThisMessage && !isLastMessage && (
              <div className="px-4 py-2" id={`reply-composer-${message.id}`}>
                <ReplyCompose messageId={message.id} />
              </div>
            )}
          </div>
        );
      })}
    </div>
  </ScrollArea>
);
