import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuTrigger,
} from '../ui/context-menu';
import { ChatSpecRenderer, extractUISpecFromMessage } from '../generative-ui';
import { useAIFullScreen, useAISidebar } from '@/hooks/use-ai-sidebar';
import { Avatar, AvatarFallback, AvatarImage } from '../ui/avatar';
import { extractMentionRefsFromDoc } from '@/lib/editor-mentions';
import { useRef, useCallback, useEffect, useState } from 'react';
import { VoiceProvider } from '@/providers/voice-provider';
import type { Message as AiMessage, Attachment } from 'ai';
import useComposeEditor from '@/hooks/use-compose-editor';
import { useConnections } from '@/hooks/use-connections';
import type { useAgentChat } from 'agents/ai-react';
import { Markdown } from '@react-email/components';
import { useBilling } from '@/hooks/use-billing';
import { TextShimmer } from '../ui/text-shimmer';
import { useThread } from '@/hooks/use-threads';
import { MailLabels } from '../mail/mail-list';
import type { MentionRef } from '@zero/shared';
import { cn, getEmailLogo } from '@/lib/utils';
import { VoiceButton } from '../voice-button';
import { EditorContent } from '@tiptap/react';
import { CurvedArrow } from '../icons/icons';
import { Copy, Pencil } from 'lucide-react';
import { Tools } from '../../types/tools';
import { Button } from '../ui/button';
import { format } from 'date-fns-tz';
import { useQueryState } from 'nuqs';
import { toast } from 'sonner';
import './prosemirror.css';

const ThreadPreview = ({ threadId }: { threadId: string }) => {
  const [, setThreadId] = useQueryState('threadId');
  const { data: getThread } = useThread(threadId);
  const [, setIsFullScreen] = useQueryState('isFullScreen');

  const handleClick = () => {
    setThreadId(threadId);
    setIsFullScreen(null);
  };

  if (!getThread?.latest) return null;

  return (
    <div
      onClick={handleClick}
      key={threadId}
      className="hover:bg-offsetLight/30 dark:hover:bg-offsetDark/30 cursor-pointer rounded-lg"
    >
      <div className="flex cursor-pointer items-center justify-between p-2">
        <div className="flex w-full items-center gap-3">
          <Avatar className="h-8 w-8">
            <AvatarImage
              className="rounded-full"
              src={getEmailLogo(getThread.latest?.sender?.email)}
            />
            <AvatarFallback className="rounded-full bg-[#FFFFFF] font-bold text-[#9F9F9F] dark:bg-[#373737]">
              {getThread.latest?.sender?.name?.[0]?.toUpperCase()}
            </AvatarFallback>
          </Avatar>
          <div className="flex w-full flex-col gap-1.5">
            <div className="flex w-full items-center justify-between gap-2">
              <p className="max-w-[20ch] truncate text-sm font-medium text-black dark:text-white">
                {getThread.latest?.sender?.name}
              </p>
              <span className="max-w-[180px] truncate text-xs text-[#8C8C8C] dark:text-[#8C8C8C]">
                {getThread.latest.receivedOn ? format(getThread.latest.receivedOn, 'MMMM do') : ''}
              </span>
            </div>
            <div className="flex items-center justify-between">
              <span className="max-w-[220px] truncate text-xs text-[#8C8C8C] dark:text-[#8C8C8C]">
                {getThread.latest?.subject}
              </span>
              <MailLabels labels={getThread.latest?.tags || []} />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

const ExampleQueries = ({
  onQueryClick,
  hasEmailConnection,
}: {
  onQueryClick: (query: string) => void;
  hasEmailConnection: boolean;
}) => {
  // All example queries are email-focused — hide them when no email account is connected
  // and show a connect CTA instead.
  if (!hasEmailConnection) {
    return (
      <div className="mt-6 flex flex-col items-center gap-3">
        <p className="text-sm text-[#8C8C8C] dark:text-[#929292]">
          Connect an email account to get started
        </p>
        <a
          href="/settings/connections"
          className="flex items-center gap-2 rounded-lg bg-blue-500/10 px-4 py-2 text-sm font-medium text-blue-500 transition-colors hover:bg-blue-500/20"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            className="h-4 w-4"
            viewBox="0 0 20 20"
            fill="currentColor"
          >
            <path d="M2.003 5.884L10 9.882l7.997-3.998A2 2 0 0016 4H4a2 2 0 00-1.997 1.884z" />
            <path d="M18 8.118l-8 4-8-4V14a2 2 0 002 2h12a2 2 0 002-2V8.118z" />
          </svg>
          Connect Email Account
        </a>
      </div>
    );
  }

  const firstRowQueries = [
    'Find all work meetings today',
    'Label all emails from Github as OSS',
    'Show recent Linear feedback',
  ];

  const secondRowQueries = ['Find receipt from OpenAI', 'What Asana projects do I have coming up'];

  return (
    <div className="relative mt-6 flex w-full max-w-xl flex-col items-center gap-2">
      {/* First row */}
      <div className="no-scrollbar relative flex w-full justify-center overflow-x-auto">
        <div className="flex gap-4 px-4">
          {firstRowQueries.map((query) => (
            <button
              key={query}
              onClick={() => onQueryClick(query)}
              className="shrink-0 whitespace-nowrap rounded-md bg-[#f0f0f0] p-1 px-2 text-sm text-[#555555] dark:bg-[#262626] dark:text-[#929292]"
            >
              {query}
            </button>
          ))}
        </div>
      </div>
      {/* Second row */}
      <div className="no-scrollbar relative flex w-full justify-center overflow-x-auto">
        <div className="flex gap-4 px-4">
          {secondRowQueries.map((query) => (
            <button
              key={query}
              onClick={() => onQueryClick(query)}
              className="shrink-0 whitespace-nowrap rounded-md bg-[#f0f0f0] p-1 px-2 text-sm text-[#555555] dark:bg-[#262626] dark:text-[#929292]"
            >
              {query}
            </button>
          ))}
        </div>
      </div>
      {/* Left mask */}
      <div className="from-panelLight dark:from-panelDark bg-linear-to-r pointer-events-none absolute bottom-0 left-0 top-0 w-12 to-transparent"></div>
      {/* Right mask */}
      <div className="from-panelLight dark:from-panelDark bg-linear-to-l pointer-events-none absolute bottom-0 right-0 top-0 w-12 to-transparent"></div>
    </div>
  );
};

// interface Message {
//   id: string;
//   role: 'user' | 'assistant' | 'data' | 'system';
//   parts: Array<{
//     type: string;
//     text?: string;
//     toolInvocation?: {
//       toolName: string;
//       result?: {
//         threads?: Array<{ id: string; title: string; snippet: string }>;
//       };
//       args?: any;
//     };
//   }>;
// }

// Shared markdown styles for chat messages — extracted to avoid duplication.
// Headings use weight/size differentiation so responses render with visual hierarchy
// instead of a flat text dump. Lists use `outside` positioning for clean indentation.
const markdownStyles = {
  h1: { fontSize: '0.9375rem', fontWeight: '700', marginBottom: '0.25rem', marginTop: '0.5rem' },
  h2: { fontSize: '0.9375rem', fontWeight: '600', marginBottom: '0.2rem', marginTop: '0.4rem' },
  h3: { fontSize: '0.875rem', fontWeight: '600', marginBottom: '0.15rem', marginTop: '0.35rem' },
  h4: { fontSize: '0.875rem', fontWeight: '600' },
  h5: { fontSize: '0.875rem', fontWeight: '600' },
  h6: { fontSize: '0.875rem', fontWeight: '600' },
  p: { fontSize: '0.875rem', marginBottom: '0.35rem' },
  li: {
    fontSize: '0.875rem',
    marginBottom: '0.15rem',
    listStyleType: 'disc' as const,
    listStylePosition: 'outside' as const,
    marginLeft: '1.25rem',
  },
  ul: { fontSize: '0.875rem', marginBottom: '0.35rem' },
  ol: { fontSize: '0.875rem', marginBottom: '0.35rem' },
  blockQuote: {
    fontSize: '0.875rem',
    borderLeft: '2px solid #888',
    paddingLeft: '0.6rem',
    opacity: '0.75',
    marginBottom: '0.35rem',
  },
  codeBlock: {
    fontSize: '0.8125rem',
    fontFamily: 'monospace',
    backgroundColor: 'rgba(128,128,128,0.12)',
    padding: '0.5rem 0.625rem',
    borderRadius: '0.375rem',
    display: 'block',
    marginBottom: '0.35rem',
    overflowX: 'auto' as const,
  },
  codeInline: {
    fontSize: '0.8125rem',
    fontFamily: 'monospace',
    backgroundColor: 'rgba(128,128,128,0.12)',
    padding: '0.1rem 0.3rem',
    borderRadius: '0.25rem',
  },
  link: { fontSize: '0.875rem', color: '#3b82f6', textDecoration: 'underline' },
  image: { maxWidth: '100%', borderRadius: '0.5rem' },
};

// Normalize single newlines to double so Markdown sees paragraph breaks.
// AI responses frequently use single \n which CommonMark collapses to a space,
// making the entire response render as one unbroken paragraph.
const normalizeMarkdown = (text: string) => {
  const sentinel = '\u0000DN\u0000';
  return text.replace(/\n\n/g, sentinel).replace(/\n/g, '\n\n').replaceAll(sentinel, '\n\n');
};

const EMAIL_CONNECTION_PATTERNS = [
  /\bno (email|mail) (account|connection) (connected|found)\b/i,
  /\bplease connect (your )?(email|mail|account)\b/i,
  /\bnot connected to (your )?(email|mail|inbox)\b/i,
  /\b(email|mail|inbox) (isn't|is not|not) connected\b/i,
];

export interface AIChatProps {
  messages: AiMessage[];
  input: string;
  setInput: (input: string) => void;
  error?: Error;
  handleSubmit: (e: React.FormEvent<HTMLFormElement>) => void;
  status: string;
  stop: () => void;
  className?: string;
  onModelChange?: (model: string) => void;
  setMessages: (messages: AiMessage[]) => void;
}

// Subcomponents for ToolResponse
const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null;

const GetThreadToolResponse = ({ result, args }: { result: unknown; args: unknown }) => {
  // Extract threadId from result or args
  let threadId: string | null = null;
  if (typeof result === 'string') {
    const match = result.match(/<thread id="([^"]+)" ?\/>/);
    if (match?.[1]) threadId = match[1];
  }
  if (!threadId && isRecord(args) && typeof args.id === 'string') threadId = args.id;
  if (!threadId) return null;
  return <ThreadPreview threadId={threadId} />;
};

const GetUserLabelsToolResponse = ({ result }: { result: unknown }) => {
  if (!isRecord(result) || !Array.isArray(result.labels)) return null;
  const labels = result.labels.filter(
    (label): label is { id: string; name: string } =>
      isRecord(label) && typeof label.id === 'string' && typeof label.name === 'string',
  );
  return (
    <div className="flex flex-wrap gap-2">
      {labels.map((label) => (
        <MailLabels key={label.id} labels={[label]} />
      ))}
    </div>
  );
};

const ComposeEmailToolResponse = ({ result }: { result: unknown }) => {
  if (!isRecord(result) || typeof result.newBody !== 'string') return null;
  return (
    <div className="rounded-lg border border-gray-200 p-4 dark:border-gray-800">
      <div className="prose dark:prose-invert max-w-none">
        <Markdown>{result.newBody}</Markdown>
      </div>
    </div>
  );
};

// Main ToolResponse switcher
const ToolResponse = ({
  toolName,
  result,
  args,
}: {
  toolName: string;
  result: unknown;
  args: unknown;
}) => {
  switch (toolName) {
    case Tools.GetThread:
      return <GetThreadToolResponse result={result} args={args} />;
    case Tools.GetUserLabels:
      return <GetUserLabelsToolResponse result={result} />;
    case Tools.ComposeEmail:
      return <ComposeEmailToolResponse result={result} />;
    default:
      return null;
  }
};

const AI_CHAT_MAX_PENDING_IMAGES = 8;
const AI_CHAT_MAX_PASTE_IMAGE_BYTES = 5 * 1024 * 1024;

export function AIChat({
  messages,
  input,
  setInput,
  error,
  status,
  append,
  setMessages,
  onMentionsChange,
}: ReturnType<typeof useAgentChat> & {
  onMentionsChange?: (mentions: MentionRef[]) => void;
}): React.ReactElement {
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const messagesContainerRef = useRef<HTMLDivElement>(null);
  const [pendingImages, setPendingImages] = useState<Array<Attachment & { _id: string }>>([]);
  const pendingImagesRef = useRef(pendingImages);
  pendingImagesRef.current = pendingImages;
  const { chatMessages, isLoading: isBillingLoading } = useBilling();
  const { data: connectionsData } = useConnections();
  const hasEmailConnection = (connectionsData?.connections?.length ?? 0) > 0;
  const { isFullScreen } = useAIFullScreen();
  const [, setPricingDialog] = useQueryState('pricingDialog');
  const [aiSidebarOpen] = useQueryState('aiSidebar');
  const { toggleOpen } = useAISidebar();
  const isChatEnabled = !isBillingLoading && chatMessages.enabled;

  const scrollToBottom = useCallback(() => {
    if (messagesEndRef.current) {
      messagesEndRef.current.scrollIntoView({ behavior: 'smooth' });
    }
  }, []);

  useEffect(() => {
    if (!['submitted', 'streaming'].includes(status)) {
      scrollToBottom();
    }
  }, [status, scrollToBottom]);

  const handlePasteFiles = useCallback((files: File[]) => {
    const room = Math.max(0, AI_CHAT_MAX_PENDING_IMAGES - pendingImagesRef.current.length);
    if (room <= 0) return;

    const imageFiles = files.filter((f) => f.type.startsWith('image/'));
    const toRead = imageFiles.filter((f) => f.size <= AI_CHAT_MAX_PASTE_IMAGE_BYTES).slice(0, room);

    for (const file of toRead) {
      const reader = new FileReader();
      const nameKey =
        file.name && file.name.trim().length > 0
          ? file.name.trim()
          : `image-${globalThis.crypto?.randomUUID?.() ?? `${Date.now()}-${Math.random().toString(16).slice(2)}`}`;
      const stableId = `paste-${nameKey}-${file.size}-${file.lastModified}`;
      reader.onerror = () => {
        console.error('[ai-chat] FileReader failed for paste', file.name);
      };
      reader.onload = () => {
        setPendingImages((prev) => {
          if (prev.length >= AI_CHAT_MAX_PENDING_IMAGES) return prev;
          if (prev.some((p) => p._id === stableId)) return prev;
          return [
            ...prev,
            {
              _id: stableId,
              name: file.name?.trim() ? file.name.trim() : nameKey,
              contentType: file.type,
              url: reader.result as string,
            },
          ];
        });
      };
      reader.readAsDataURL(file);
    }
  }, []);

  const editor = useComposeEditor({
    surface: 'ai-chat',
    placeholder: 'Ask Todus to do anything...',
    onTextChange: (text, content) => {
      setInput(text);
      onMentionsChange?.(extractMentionRefsFromDoc(content));
    },
    onPasteFiles: handlePasteFiles,
    onKeydown(event) {
      if (event.key === '0' && event.metaKey) {
        return toggleOpen();
      }

      if (event.key === 'Enter' && !event.metaKey && !event.shiftKey) {
        if (!isChatEnabled) {
          event.preventDefault();
          void setPricingDialog('true');
          return;
        }

        onSubmit(event as unknown as React.FormEvent<HTMLFormElement>);
      }
    },
  });

  const onSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();

    if (!isChatEnabled) {
      void setPricingDialog('true');
      return;
    }

    const trimmed = input.trim();
    const attachments = pendingImages.map((image) => ({
      name: image.name,
      contentType: image.contentType,
      url: image.url,
    }));
    const previousPendingImages = pendingImages;
    if (!trimmed && attachments.length === 0) return;

    // Reset composer + attachment state BEFORE awaiting append() — otherwise any keystrokes
    // typed during the in-flight network call get cleared once we finally clear the editor.
    // The editor's onChange (from clearContent) syncs setInput('') for us; an explicit
    // setInput('') here would also wipe the new keystrokes.
    editor.commands.clearContent(true);
    setPendingImages([]);
    onMentionsChange?.([]);

    try {
      await append(
        {
          role: 'user',
          content: trimmed,
          ...(attachments.length ? { experimental_attachments: attachments } : {}),
        },
        {
          allowEmptySubmit: attachments.length > 0,
        },
      );
    } catch (error) {
      console.error('[ai-chat] append failed', error);
      setPendingImages(previousPendingImages);
      editor.commands.setContent(trimmed);
      setInput(trimmed);
      onMentionsChange?.([]);
      toast.error('Failed to send message. Please try again.');
      return;
    }
    setTimeout(() => {
      scrollToBottom();
    }, 100);
  };

  const handleQueryClick = (query: string) => {
    editor.commands.setContent(query);
    setInput(query);
    onMentionsChange?.([]);
    editor.commands.focus();
  };

  /// Copy the plain-text payload of a message to the clipboard.
  /// Falls back silently if the Clipboard API is unavailable (older iOS Safari
  /// embedded contexts) — toast still fires so the user knows the action registered.
  const copyMessageText = useCallback(async (text: string) => {
    const trimmed = text.trim();
    if (!trimmed) return;
    try {
      await navigator.clipboard.writeText(trimmed);
      toast.success('Copied');
    } catch {
      const ua =
        typeof navigator !== 'undefined' ? `${navigator.platform} ${navigator.userAgent}` : '';
      const isMac = /Mac|iPhone|iPad|iPod/i.test(ua);
      const shortcut = isMac ? '⌘C' : 'Ctrl+C';
      toast.error(`Couldn't copy — try selecting and using ${shortcut}`);
    }
  }, []);

  /// Right-click / long-press "Edit message" on a user bubble:
  /// drop the edited turn and every reply after it, pre-fill the composer with
  /// the old wording, and focus it. User edits and presses enter to re-run.
  const editUserMessage = useCallback(
    (index: number, text: string) => {
      if (status === 'streaming' || status === 'submitted') return;
      setMessages(messages.slice(0, index));
      setInput(text);
      editor.commands.setContent(text);
      onMentionsChange?.([]);
      editor.commands.focus('end');
    },
    [messages, setMessages, setInput, editor, onMentionsChange, status],
  );

  useEffect(() => {
    if (aiSidebarOpen === 'true') {
      editor.commands.focus();
    }
  }, [aiSidebarOpen, editor]);

  return (
    <div className={cn('flex h-full flex-col', isFullScreen ? 'mx-auto max-w-xl' : '')}>
      {/* relative here scopes the paywall absolute overlay to just this area, not the input below */}
      <div className="no-scrollbar relative flex-1 overflow-y-auto" ref={messagesContainerRef}>
        <div className="min-h-full px-2 py-4">
          {!isChatEnabled ? (
            <div className="absolute inset-0 z-10 flex flex-col items-center justify-center">
              <TextShimmer className="max-w-full px-4 text-center text-xl font-medium">
                Upgrade to Todus Pro for unlimited AI chat
              </TextShimmer>
              <Button onClick={() => setPricingDialog('true')} className="mt-2 h-8 w-52">
                Start 7 day free trial
              </Button>
            </div>
          ) : !messages.length ? (
            <div className="absolute inset-0 flex flex-col items-center justify-center">
              <div className="relative mb-4 h-[44px] w-[44px]">
                <img src="/black-icon.svg" alt="Todus Logo" className="dark:hidden" />
                <img src="/white-icon.svg" alt="Todus Logo" className="hidden dark:block" />
              </div>
              <p className="mb-1 mt-2 hidden text-center text-sm font-medium text-black md:block dark:text-white">
                Ask anything about your emails
              </p>
              <p className="mb-3 text-center text-sm text-[#8C8C8C] dark:text-[#929292]">
                Ask to do or show anything using natural language
              </p>

              {/* Example Thread */}
              <ExampleQueries
                onQueryClick={handleQueryClick}
                hasEmailConnection={hasEmailConnection}
              />
            </div>
          ) : (
            messages.map((message, index) => {
              const textParts = message.parts.filter((part) => part.type === 'text');
              const toolParts = message.parts.filter((part) => part.type === 'tool-invocation');

              return (
                <div
                  key={`${message.id}-${index}`}
                  className="mb-2 flex flex-col"
                  data-message-role={message.role}
                >
                  {toolParts.map((part, index) => {
                    const invocation = part.toolInvocation;
                    return (
                      invocation.state === 'result' && (
                        <ToolResponse
                          key={`${invocation.toolName}-${index}`}
                          toolName={invocation.toolName}
                          result={invocation.result}
                          args={invocation.args}
                        />
                      )
                    );
                  })}
                  {message.role === 'user' &&
                    (
                      message as AiMessage & { experimental_attachments?: Attachment[] }
                    ).experimental_attachments
                      ?.filter((a) => a.contentType?.startsWith('image/'))
                      .map((att, i) => (
                        <img
                          key={`${att.url ?? att.name ?? 'att'}-${i}`}
                          src={att.url}
                          alt={att.name ?? 'image'}
                          className="ml-auto max-h-48 max-w-xs rounded-lg object-cover"
                        />
                      ))}
                  {textParts.length > 0 && (
                    <ContextMenu>
                      <ContextMenuTrigger asChild>
                        <div
                          className={cn(
                            'flex w-fit flex-col gap-2 rounded-lg text-sm',
                            message.role === 'user'
                              ? 'overflow-wrap-anywhere text-offsetDark dark:text-subtleWhite ml-auto break-words bg-[#f0f0f0] px-2 py-1 dark:bg-[#252525]'
                              : 'overflow-wrap-anywhere mr-auto break-words p-2',
                          )}
                        >
                          {textParts.map((part) => {
                            if (!part.text) return null;

                            // Check for embedded UI specs in assistant messages
                            if (message.role === 'assistant') {
                              const { textBefore, spec, textAfter } = extractUISpecFromMessage(
                                part.text,
                              );

                              if (spec) {
                                return (
                                  <div key={part.text} className="flex flex-col gap-2">
                                    {textBefore && (
                                      <Markdown markdownCustomStyles={markdownStyles}>
                                        {normalizeMarkdown(textBefore)}
                                      </Markdown>
                                    )}
                                    <ChatSpecRenderer spec={spec} className="my-1 w-full" />
                                    {textAfter && (
                                      <Markdown markdownCustomStyles={markdownStyles}>
                                        {normalizeMarkdown(textAfter)}
                                      </Markdown>
                                    )}
                                  </div>
                                );
                              }
                            }

                            return (
                              <Markdown markdownCustomStyles={markdownStyles} key={part.text}>
                                {normalizeMarkdown(part.text || ' ')}
                              </Markdown>
                            );
                          })}

                          {/* Connect CTA — shown when AI mentions email not being connected */}
                          {message.role === 'assistant' &&
                            !hasEmailConnection &&
                            textParts.some((p) => {
                              const text = p.text?.toLowerCase();
                              if (!text) return false;

                              const hasEmailToken = /\b(email|mail|inbox|gmail)\b/.test(text);
                              const hasConnectionToken =
                                /\b(not connected|connect|connection|connected|found)\b/.test(text);

                              return (
                                (hasEmailToken && hasConnectionToken) ||
                                EMAIL_CONNECTION_PATTERNS.some((pattern) => pattern.test(text))
                              );
                            }) && (
                              <a
                                href="/settings/connections"
                                className="mt-1 inline-flex items-center gap-1.5 self-start rounded-lg bg-blue-500/10 px-3 py-1.5 text-xs font-medium text-blue-500 transition-colors hover:bg-blue-500/20"
                              >
                                Connect Email Account
                                <span aria-hidden="true">→</span>
                              </a>
                            )}
                        </div>
                      </ContextMenuTrigger>
                      <ContextMenuContent className="w-48">
                        <ContextMenuItem
                          onSelect={() => {
                            const plain = textParts.map((p) => p.text ?? '').join('\n');
                            void copyMessageText(plain);
                          }}
                        >
                          <Copy className="mr-2 h-3.5 w-3.5" />
                          Copy
                        </ContextMenuItem>
                        {message.role === 'user' && (
                          <ContextMenuItem
                            disabled={status === 'streaming' || status === 'submitted'}
                            onSelect={() => {
                              const plain = textParts.map((p) => p.text ?? '').join('\n');
                              editUserMessage(index, plain);
                            }}
                          >
                            <Pencil className="mr-2 h-3.5 w-3.5" />
                            Edit message
                          </ContextMenuItem>
                        )}
                      </ContextMenuContent>
                    </ContextMenu>
                  )}
                </div>
              );
            })
          )}

          {(status === 'submitted' || status === 'streaming') && (
            <div className="absolute bottom-0 ml-2 flex items-center gap-2">
              <TextShimmer className="text-muted-foreground text-xs">
                zero is thinking...
              </TextShimmer>
            </div>
          )}
          {(status === 'error' || !!error) && (
            <div className="text-sm text-red-500">Error, please try again later</div>
          )}
          <div className="h-0 w-0" ref={messagesEndRef} />
        </div>
      </div>

      {/* Fixed input at bottom */}
      <div className={cn('mb-4 shrink-0 px-4', isFullScreen ? 'px-0' : '')}>
        <div className="bg-offsetLight relative rounded-lg p-2 dark:bg-[#202020]">
          <div className="flex flex-col">
            <div className="w-full">
              <form id="ai-chat-form" onSubmit={onSubmit} className="relative">
                <div className="grow self-stretch overflow-y-auto outline-white/5 dark:bg-[#202020]">
                  <div
                    onClick={() => {
                      if (!isChatEnabled) {
                        void setPricingDialog('true');
                        return;
                      }

                      editor.commands.focus();
                    }}
                    className={cn(
                      'max-h-[100px] w-full',
                      '[&_.ProseMirror]:min-h-[40px] [&_.ProseMirror]:px-3 [&_.ProseMirror]:py-2 [&_.ProseMirror]:text-sm [&_.ProseMirror]:outline-none',
                      '[&_.ProseMirror_p.is-editor-empty:first-child]:relative [&_.ProseMirror_p.is-editor-empty:first-child]:before:pointer-events-none',
                      '[&_.ProseMirror_p.is-editor-empty:first-child]:before:absolute [&_.ProseMirror_p.is-editor-empty:first-child]:before:left-0 [&_.ProseMirror_p.is-editor-empty:first-child]:before:top-0',
                      '[&_.ProseMirror_p.is-editor-empty:first-child]:before:text-[#8C8C8C] [&_.ProseMirror_p.is-editor-empty:first-child]:before:content-[attr(data-placeholder)] dark:[&_.ProseMirror_p.is-editor-empty:first-child]:before:text-[#929292]',
                      !isChatEnabled && 'cursor-pointer opacity-70',
                    )}
                  >
                    <EditorContent editor={editor} className="h-full w-full" />
                  </div>
                </div>
              </form>
            </div>
            {pendingImages.length > 0 && (
              <div className="flex flex-wrap gap-2 px-3 pb-1 pt-2">
                {pendingImages.map((img) => (
                  <div key={img._id} className="relative shrink-0">
                    <img src={img.url} alt={img.name} className="h-16 w-16 rounded object-cover" />
                    <button
                      type="button"
                      title="Remove image"
                      aria-label={`Remove image ${img.name} (${img._id})`}
                      onClick={() =>
                        setPendingImages((prev) => prev.filter((i) => i._id !== img._id))
                      }
                      className="absolute -right-1 -top-1 flex h-4 w-4 items-center justify-center rounded-full bg-black/70 text-[10px] leading-none text-white"
                    >
                      ×
                    </button>
                  </div>
                ))}
              </div>
            )}
            <div className="grid">
              <div className="flex justify-end gap-1">
                <VoiceProvider>
                  <VoiceButton />
                </VoiceProvider>
                <button
                  form="ai-chat-form"
                  type="submit"
                  className="inline-flex cursor-pointer gap-1.5 rounded-lg"
                  disabled={!isChatEnabled}
                >
                  <div className="dark:bg[#141414] flex h-7 items-center justify-center gap-1 rounded-sm bg-[#262626] px-2 pr-1">
                    <CurvedArrow className="mt-1.5 h-4 w-4 fill-white dark:fill-[#929292]" />
                  </div>
                </button>
              </div>
            </div>
          </div>
        </div>

        {/* Old model selector removed — now handled by ModelSelector in ai-sidebar.tsx header */}
      </div>
    </div>
  );
}
