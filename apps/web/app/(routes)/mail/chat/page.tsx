/**
 * Chat page — iOS/macOS parity.
 * Left sidebar: conversation history (ai.listConversations), new chat button.
 * Auto-save: on first assistant response, saves conversation with title = first 60 chars of user message.
 * Responses render as plain text to match the current web dependency surface.
 */
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuSub,
  DropdownMenuSubContent,
  DropdownMenuSubTrigger,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import {
  SendHorizontal,
  StopCircle,
  Plus,
  MessageSquare,
  Trash2,
  MoreHorizontal,
  FolderIcon,
  PanelLeft,
} from 'lucide-react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useRef, useEffect, useState, useCallback, useMemo, memo, type FormEvent, type ClipboardEvent } from 'react';
import { useActiveConnection } from '@/hooks/use-connections';
import { ScrollArea } from '@/components/ui/scroll-area';
import { useTRPC } from '@/providers/query-provider';
import { Textarea } from '@/components/ui/textarea';
import { Button } from '@/components/ui/button';
import { Sheet, SheetContent, SheetTitle } from '@/components/ui/sheet';
import { useAgentChat } from 'agents/ai-react';
import { formatDistanceToNow } from 'date-fns';
import { authProxy } from '@/lib/auth-proxy';
import type { Route } from './+types/page';
import { useAgent } from 'agents/react';
import { cn } from '@/lib/utils';
import { toast } from 'sonner';

// Auth guard
export async function clientLoader({ request }: Route.ClientLoaderArgs) {
  const { redirect } = await import('react-router');
  const session = await authProxy.api.getSession({ headers: request.headers });
  if (!session) throw redirect('/login');
  return {};
}

const EXAMPLE_QUERIES = [
  'Find all unread emails from today',
  'Label all GitHub emails as OSS',
  'Summarize my most important emails',
  'Show recent emails from my team',
  'Create a task to reply to the latest invoice',
];

type ChatMessageRecord = {
  role: 'user' | 'assistant';
  content: string;
  mentions?: Array<{ id: string; type: string; label: string }>;
};

function extractTextContent(content: unknown): string {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';

  return content
    .map((part) => {
      if (typeof part === 'string') return part;
      if (part && typeof part === 'object' && 'text' in part) {
        const text = (part as { text?: unknown }).text;
        return typeof text === 'string' ? text : '';
      }
      return '';
    })
    .join('');
}

type ChatPart = { type: string; text?: string };
type ChatMsg = ChatMessage & { experimental_attachments?: { name?: string; url?: string }[] };

const ChatMessageBubble = memo(function ChatMessageBubble({ message }: { message: ChatMsg }) {
  const textParts = (message.parts as ChatPart[] | undefined)?.filter((p) => p.type === 'text') ?? [];
  const hasText = textParts.some((p) => p.text?.trim());
  const userAtt = message.experimental_attachments;
  if (!hasText && !userAtt?.length) return null;
  const isUser = message.role === 'user';
  return (
    <div className={cn('flex', isUser ? 'justify-end' : 'justify-start')}>
      <div
        className={cn(
          'max-w-[82%] rounded-2xl px-4 py-2.5 text-[13px] leading-relaxed',
          isUser ? 'bg-primary text-primary-foreground' : 'bg-card text-foreground border',
        )}
      >
        {isUser ? (
          <>
            {userAtt && userAtt.length > 0 ? (
              <p className="text-primary-foreground/80 mb-1 text-[11px] font-medium">
                {userAtt.map((a) => a.name || 'Attachment').filter(Boolean).join(', ')}
              </p>
            ) : null}
            {textParts.map((part, idx) =>
              part.text ? (
                <p key={`${message.id}-user-${idx}-${part.text.slice(0, 24)}`} className="whitespace-pre-wrap">
                  {part.text}
                </p>
              ) : null,
            )}
          </>
        ) : (
          textParts.map((part, idx) =>
            part.text ? (
              <p key={`${message.id}-assistant-${idx}-${part.text.slice(0, 24)}`} className="whitespace-pre-wrap">
                {part.text}
              </p>
            ) : null,
          )
        )}
      </div>
    </div>
  );
});

// Stable UUID generator (crypto.randomUUID fallback)
function newId() {
  if (typeof crypto !== 'undefined' && crypto.randomUUID) return crypto.randomUUID();
  return `${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

function toSafeISOString(value: unknown, fallback: Date = new Date()) {
  const fallbackISOString = fallback.toISOString();
  if (value == null) return fallbackISOString;

  const date =
    value instanceof Date
      ? value
      : typeof value === 'string' || typeof value === 'number'
        ? new Date(value)
        : null;

  return date && !Number.isNaN(date.getTime()) ? date.toISOString() : fallbackISOString;
}

export default function ChatPage() {
  const { data: activeConnection } = useActiveConnection();
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  // Active conversation ID in memory — not persisted to URL to keep it simple
  const [conversationId, setConversationId] = useState<string>(() => newId());
  const [conversationFolderId, setConversationFolderId] = useState<string | null>(null);
  // Whether the current session has been saved to backend yet
  const [isSaved, setIsSaved] = useState(false);
  const [folderFilter, setFolderFilter] = useState<'all' | 'unfiled' | string>('all');
  // Mobile drawer for the conversation history sidebar (the desktop aside is hidden below md)
  const [mobileSidebarOpen, setMobileSidebarOpen] = useState(false);
  // Tracks previous user message count to detect new messages and reset isSaved
  const prevUserMsgCountRef = useRef(0);
  // Guard against double-firing the save mutation while one is still in
  // flight — the auto-save effect re-runs as soon as messages.length changes
  // (streaming token chunks growing the message array), which would otherwise
  // queue a second `saveConversation.mutate` on top of the first, producing
  // duplicate sidebar rows.
  const isSavingRef = useRef(false);

  const { data: foldersData } = useQuery(trpc.folders.list.queryOptions());
  const folders = useMemo(() => foldersData?.folders ?? [], [foldersData]);

  // Fetch conversation list for sidebar
  const { data: conversationsData, refetch: refetchConversations } = useQuery(
    trpc.ai.listConversations.queryOptions(),
  );
  const conversations = useMemo(() => conversationsData?.conversations ?? [], [conversationsData]);
  const visibleConversations = conversations.filter((convo) => {
    if (folderFilter === 'all') return true;
    if (folderFilter === 'unfiled') return !convo.folderId;
    return convo.folderId === folderFilter;
  });
  const conversationCounts = useMemo(() => {
    const counts = {
      all: conversations.length,
      unfiled: conversations.filter((convo) => !convo.folderId).length,
      folders: new Map<string, number>(),
    };

    for (const convo of conversations) {
      if (!convo.folderId) continue;
      counts.folders.set(convo.folderId, (counts.folders.get(convo.folderId) ?? 0) + 1);
    }

    return counts;
  }, [conversations]);

  // Save / update a conversation
  const saveConversation = useMutation(trpc.ai.saveConversation.mutationOptions());
  // Delete a conversation
  const deleteConversation = useMutation({
    ...trpc.ai.deleteConversation.mutationOptions(),
    onSuccess: () => {
      void refetchConversations();
    },
  });

  const resolveConversationFolderName = useCallback(
    (folderId: string | null) => {
      if (!folderId) return 'Unfiled';
      return folders.find((folder) => folder.id === folderId)?.name ?? 'Folder';
    },
    [folders],
  );

  const handleConversationFolderMove = useCallback(
    async (id: string, folderId: string | null) => {
      try {
        const convo = await queryClient.fetchQuery(trpc.ai.getConversation.queryOptions({ id }));
        if (!convo?.messages) return;

        const messages = Array.isArray(convo.messages)
          ? (convo.messages as ChatMessageRecord[])
          : [];
        const createdAt = toSafeISOString(convo.createdAt);

        saveConversation.mutate(
          {
            id: convo.id,
            title: convo.title,
            messages,
            folderId,
            createdAt,
          },
          {
            onSuccess: () => {
              void refetchConversations();
              if (conversationId === id) {
                setConversationFolderId(folderId);
              }
            },
          },
        );
      } catch (err) {
        console.error('Failed to move conversation:', err);
        toast.error('Failed to move conversation.');
      }
    },
    [conversationId, queryClient, refetchConversations, saveConversation, trpc.ai.getConversation],
  );

  // Connect to the ZeroAgent Durable Object via WebSocket
  const agent = useAgent({
    agent: 'ZeroAgent',
    name: String(activeConnection?.id ?? 'general'),
    host: `${import.meta.env.VITE_PUBLIC_BACKEND_URL}`,
    onError: (e) => console.error('Agent error:', e),
  });

  const { messages, input, handleInputChange, append, setInput, status, stop, setMessages } =
    useAgentChat({
      agent,
      maxSteps: 10,
      getInitialMessages: async () => [],
    });

  const isLoading = status === 'submitted' || status === 'streaming';

  // Stable snapshot of the latest messages array, updated every render. The
  // auto-save effect intentionally doesn't include `messages` in its dep
  // array (to avoid re-saving on every streamed token). Reading from this
  // ref guarantees we serialize the truly-latest list at save time instead
  // of a stale closure captured before the last token arrived.
  const latestMessagesRef = useRef(messages);
  latestMessagesRef.current = messages;

  const [pendingClipboardFiles, setPendingClipboardFiles] = useState<File[]>([]);

  const fileToChatAttachment = useCallback((f: File) => {
    return new Promise<{ name: string; contentType?: string; url: string }>((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => {
        resolve({
          name: f.name,
          contentType: f.type || undefined,
          url: String(reader.result),
        });
      };
      reader.onerror = () => reject(reader.error);
      reader.readAsDataURL(f);
    });
  }, []);

  const handleComposerPaste = useCallback(
    (e: ClipboardEvent<HTMLTextAreaElement>) => {
      const files = e.clipboardData?.files;
      if (!files?.length) return;
      e.preventDefault();
      setPendingClipboardFiles((prev) => [...prev, ...Array.from(files)]);
    },
    [],
  );

  const handleChatFormSubmit = useCallback(
    async (ev: FormEvent) => {
      ev.preventDefault();
      const trimmed = input.trim();
      if ((!trimmed && pendingClipboardFiles.length === 0) || isLoading) return;

      const attachments =
        pendingClipboardFiles.length > 0
          ? await Promise.all(pendingClipboardFiles.map(fileToChatAttachment))
          : undefined;
      setPendingClipboardFiles([]);

      await append(
        {
          role: 'user',
          content: trimmed,
          ...(attachments?.length ? { experimental_attachments: attachments } : {}),
        },
        {
          allowEmptySubmit: !trimmed && (attachments?.length ?? 0) > 0,
        },
      );
      setInput('');
    },
    [
      append,
      fileToChatAttachment,
      input,
      isLoading,
      pendingClipboardFiles,
      setInput,
    ],
  );

  // Auto-scroll to bottom on new messages
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  // Close the mobile sidebar drawer whenever the active conversation changes
  // (user picked a chat or hit "New chat" from the drawer).
  useEffect(() => {
    setMobileSidebarOpen(false);
  }, [conversationId]);

  // Reset isSaved when a new user message is sent so each exchange gets persisted once
  useEffect(() => {
    const userCount = messages.filter((m) => m.role === 'user').length;
    if (userCount > prevUserMsgCountRef.current) {
      prevUserMsgCountRef.current = userCount;
      setIsSaved(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [messages.length]);

  // Auto-save conversation after each assistant response (once per exchange via isSaved guard).
  // Title = first 60 chars of the first user message.
  useEffect(() => {
    // Guard: don't re-save the same exchange if already saved or in-flight
    if (isSaved) return;
    if (isSavingRef.current) return;

    // Read from the ref so we always serialize the latest message array,
    // even if the closure was created before the last streamed token arrived.
    const latestMessages = latestMessagesRef.current;
    const assistantMessages = latestMessages.filter((m) => m.role === 'assistant');
    const firstUserMessage = latestMessages.find((m) => m.role === 'user');

    // Only trigger once we have at least one assistant reply and we're not mid-stream
    if (assistantMessages.length === 0 || isLoading) return;

    // Defensively extract title — content may be a string or an array of content parts
    const rawContent = firstUserMessage?.content;
    const title = (() => {
      if (!rawContent) return 'New conversation';
      if (typeof rawContent === 'string')
        return rawContent.slice(0, 60).trim() || 'New conversation';
      const text = extractTextContent(rawContent).trim();
      return text.slice(0, 60) || 'New conversation';
    })();

    // Serialize messages for storage — extract text content only
    const serialized = latestMessages
      .filter((m) => m.role === 'user' || m.role === 'assistant')
      .map<ChatMessageRecord>((m) => ({
        role: m.role as 'user' | 'assistant',
        content: typeof m.content === 'string' ? m.content : extractTextContent(m.content),
      }));

    isSavingRef.current = true;
    saveConversation.mutate(
      { id: conversationId, title, messages: serialized, folderId: conversationFolderId },
      {
        onSuccess: () => {
          setIsSaved(true);
          void refetchConversations();
        },
        onError: (err) => {
          console.error('Failed to auto-save conversation:', err);
        },
        onSettled: () => {
          isSavingRef.current = false;
        },
      },
    );
    // Intentionally not exhaustive — only re-run when message count, loading, or isSaved changes
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [messages.length, isLoading, isSaved]);

  // Start a brand new chat session — abort any in-flight stream first so its
  // tokens don't bleed into the next conversation's message list and corrupt
  // the auto-saved record.
  const handleNewChat = useCallback(() => {
    if (isLoading) stop();
    setMessages([]);
    setConversationId(newId());
    setConversationFolderId(
      folderFilter === 'all' || folderFilter === 'unfiled' ? null : folderFilter,
    );
    setIsSaved(false);
    prevUserMsgCountRef.current = 0;
  }, [folderFilter, isLoading, setMessages, stop]);

  // Load a past conversation — show its messages in read-only mode. Abort any
  // active stream first so it doesn't keep emitting tokens into the loaded
  // conversation after the user switched away.
  const handleLoadConversation = useCallback(
    async (id: string) => {
      try {
        if (isLoading) stop();
        // Fetch full conversation from backend
        const result = await queryClient.fetchQuery(trpc.ai.getConversation.queryOptions({ id }));
        if (!result?.messages) return;

        // Build message objects compatible with useAgentChat
        const loaded = (Array.isArray(result.messages) ? result.messages : []).map((m, i) => ({
          id: `loaded-${id}-${i}`,
          role: m.role as 'user' | 'assistant',
          content: String(m.content ?? ''),
          parts: [{ type: 'text' as const, text: String(m.content ?? '') }],
        }));
        setMessages(loaded);
        setConversationId(id);
        setConversationFolderId(result.folderId ?? null);
        setIsSaved(true);
      } catch (err) {
        console.error('Failed to load conversation:', err);
        toast.error('Failed to load conversation. Please try again.');
      }
    },
    [isLoading, queryClient, stop, trpc.ai.getConversation, setMessages],
  );

  // Stop any in-flight stream on unmount (route change away from /mail/chat).
  // Without this the chat keeps writing into the discarded React tree.
  useEffect(() => {
    return () => {
      if (isLoading) stop();
    };
    // We deliberately want this to run only on unmount, not on isLoading flips.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const handleDeleteConversation = useCallback(
    (id: string, e: React.MouseEvent) => {
      e.stopPropagation();
      // Confirm before destroying a saved conversation — there is no undo path
      // and "Delete" sits one click into a hover menu, easy to fire by accident.
      if (typeof window !== 'undefined' && !window.confirm('Delete this conversation?')) {
        return;
      }
      deleteConversation.mutate(
        { id },
        {
          onSuccess: () => {
            // Only start fresh after successful deletion to avoid UI flicker on failure
            if (id === conversationId) {
              handleNewChat();
            }
            toast.success('Conversation deleted');
          },
          onError: (err) => {
            console.error('Failed to delete conversation:', err);
            toast.error('Failed to delete conversation. Please try again.');
          },
        },
      );
    },
    [conversationId, deleteConversation, handleNewChat],
  );

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      if ((input.trim() || pendingClipboardFiles.length > 0) && !isLoading) {
        void handleChatFormSubmit(e as unknown as FormEvent<HTMLFormElement>);
      }
    }
  };

  // Click a suggestion chip — populate the textarea value
  const handleExampleClick = (query: string) => {
    const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
      window.HTMLTextAreaElement.prototype,
      'value',
    )?.set;
    if (textareaRef.current && nativeInputValueSetter) {
      nativeInputValueSetter.call(textareaRef.current, query);
      textareaRef.current.dispatchEvent(new Event('input', { bubbles: true }));
    }
    textareaRef.current?.focus();
  };

  // Sidebar contents are reused for both the desktop aside and the mobile sheet drawer.
  const sidebarBody = (
    <>
      <div className="border-b px-3 py-3">
        <div className="flex items-center justify-between">
          <span className="text-[13px] font-semibold">Chats</span>
          <Button
            variant="ghost"
            size="icon"
            className="h-7 w-7"
            onClick={handleNewChat}
            title="New chat"
          >
            <Plus className="h-3.5 w-3.5" />
          </Button>
        </div>
        <div className="mt-2 flex flex-wrap gap-1.5">
          <button
            type="button"
            onClick={() => setFolderFilter('all')}
            className={cn(
              'inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-[11px] font-medium transition-colors',
              folderFilter === 'all'
                ? 'border-accent/20 bg-accent/10 text-accent-foreground'
                : 'border-border bg-background text-muted-foreground hover:bg-accent/50',
            )}
          >
            <MessageSquare className="h-3 w-3" />
            All
            <span className="text-[10px] opacity-70">{conversationCounts.all}</span>
          </button>
          <button
            type="button"
            onClick={() => setFolderFilter('unfiled')}
            className={cn(
              'inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-[11px] font-medium transition-colors',
              folderFilter === 'unfiled'
                ? 'border-accent/20 bg-accent/10 text-accent-foreground'
                : 'border-border bg-background text-muted-foreground hover:bg-accent/50',
            )}
          >
            <FolderIcon className="h-3 w-3" />
            Unfiled
            <span className="text-[10px] opacity-70">{conversationCounts.unfiled}</span>
          </button>
          {folders.map((folder) => (
            <button
              key={folder.id}
              type="button"
              onClick={() => setFolderFilter(folder.id)}
              className={cn(
                'inline-flex max-w-full items-center gap-1.5 rounded-full border px-2.5 py-1 text-[11px] font-medium transition-colors',
                folderFilter === folder.id
                  ? 'border-accent/20 bg-accent/10 text-accent-foreground'
                  : 'border-border bg-background text-muted-foreground hover:bg-accent/50',
              )}
            >
              <FolderIcon className="h-3 w-3" />
              <span className="truncate">{folder.name}</span>
              <span className="text-[10px] opacity-70">
                {conversationCounts.folders.get(folder.id) ?? 0}
              </span>
            </button>
          ))}
        </div>
      </div>

      <ScrollArea className="flex-1 py-1">
        {visibleConversations.length === 0 ? (
          <div className="flex flex-col items-center gap-1 px-4 py-8 text-center">
            <MessageSquare className="text-muted-foreground/40 h-6 w-6" />
            <p className="text-muted-foreground text-[12px]">No saved chats yet</p>
          </div>
        ) : (
          visibleConversations.map((convo) => {
            const isActive = convo.id === conversationId;
            return (
              <div
                key={convo.id}
                role="button"
                tabIndex={0}
                aria-current={isActive ? 'true' : undefined}
                className={cn(
                  'group relative mx-1 flex cursor-pointer items-start gap-2 rounded-lg px-2.5 py-2 transition-colors',
                  isActive ? 'bg-accent text-accent-foreground' : 'hover:bg-accent/60',
                )}
                onClick={() => void handleLoadConversation(convo.id)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault();
                    void handleLoadConversation(convo.id);
                  }
                }}
              >
                <div className="min-w-0 flex-1">
                  <p className="truncate text-[12px] font-medium leading-snug">{convo.title}</p>
                  <div className="text-muted-foreground flex items-center gap-1.5 text-[11px]">
                    <span>
                      {convo.updatedAt
                        ? formatDistanceToNow(new Date(convo.updatedAt), { addSuffix: true })
                        : ''}
                    </span>
                    {convo.folderId ? (
                      <>
                        <span className="opacity-50">•</span>
                        <span className="inline-flex items-center gap-1">
                          <FolderIcon className="h-3 w-3" />
                          {resolveConversationFolderName(convo.folderId)}
                        </span>
                      </>
                    ) : null}
                  </div>
                </div>
                {/* Delete via dropdown — visible by default on touch, hover-reveal on desktop */}
                <div className="shrink-0 md:invisible md:group-hover:visible md:focus-within:visible">
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-5 w-5 p-0"
                        onClick={(e) => e.stopPropagation()}
                        aria-label="Conversation options"
                      >
                        <MoreHorizontal className="h-3.5 w-3.5" />
                      </Button>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end" className="w-32">
                      <DropdownMenuSub>
                        <DropdownMenuSubTrigger>
                          <FolderIcon className="mr-2 h-3.5 w-3.5" />
                          Move to
                        </DropdownMenuSubTrigger>
                        <DropdownMenuSubContent className="w-44">
                          <DropdownMenuItem
                            onClick={() => void handleConversationFolderMove(convo.id, null)}
                          >
                            <FolderIcon className="mr-2 h-3.5 w-3.5" />
                            Unfiled
                          </DropdownMenuItem>
                          {folders.length > 0 ? <DropdownMenuSeparator /> : null}
                          {folders.map((folder) => (
                            <DropdownMenuItem
                              key={folder.id}
                              onClick={() =>
                                void handleConversationFolderMove(convo.id, folder.id)
                              }
                            >
                              <FolderIcon className="mr-2 h-3.5 w-3.5" />
                              {folder.name}
                            </DropdownMenuItem>
                          ))}
                        </DropdownMenuSubContent>
                      </DropdownMenuSub>
                      <DropdownMenuSeparator />
                      <DropdownMenuItem
                        className="text-destructive focus:text-destructive"
                        onClick={(e) => handleDeleteConversation(convo.id, e)}
                      >
                        <Trash2 className="mr-2 h-3.5 w-3.5" />
                        Delete
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </div>
              </div>
            );
          })
        )}
      </ScrollArea>
    </>
  );

  return (
    <div className="bg-background flex h-screen overflow-hidden">
      {/* ── Conversation History Sidebar (desktop) ───────────────────────── */}
      <aside className="bg-sidebar hidden w-56 shrink-0 flex-col border-r md:flex">
        {sidebarBody}
      </aside>

      {/* ── Conversation History Sidebar (mobile drawer) ─────────────────── */}
      <Sheet open={mobileSidebarOpen} onOpenChange={setMobileSidebarOpen}>
        <SheetContent side="left" className="bg-sidebar w-72 p-0 md:hidden">
          <SheetTitle className="sr-only">Chats</SheetTitle>
          <div className="flex h-full flex-col">{sidebarBody}</div>
        </SheetContent>
      </Sheet>

      {/* ── Main Chat Panel ──────────────────────────────────────────────── */}
      <div className="flex min-w-0 flex-1 flex-col">
        {/* Header */}
        <div className="flex items-center justify-between border-b px-6 py-3.5">
          <div className="flex items-center gap-2">
            <Button
              variant="ghost"
              size="icon"
              className="-ml-2 h-8 w-8 md:hidden"
              onClick={() => setMobileSidebarOpen(true)}
              title="Show conversations"
              aria-label="Show conversations"
            >
              <PanelLeft className="h-4 w-4" />
            </Button>
            <h1 className="text-[15px] font-semibold">AI Assistant</h1>
            {conversationFolderId ? (
              <span className="border-border bg-muted/60 text-muted-foreground inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[11px] font-medium">
                <FolderIcon className="h-3 w-3" />
                {resolveConversationFolderName(conversationFolderId)}
              </span>
            ) : null}
          </div>
          {messages.length > 0 && (
            <Button
              variant="outline"
              size="sm"
              className="h-7 gap-1.5 text-[12px]"
              onClick={handleNewChat}
            >
              <Plus className="h-3.5 w-3.5" />
              New chat
            </Button>
          )}
        </div>

        {/* Messages */}
        <div className="flex-1 overflow-y-auto">
          {messages.length === 0 ? (
            /* Empty state with logo + example queries */
            <div className="flex h-full flex-col items-center justify-center px-4">
              <div className="mb-4 h-10 w-10">
                <img src="/black-icon.svg" alt="AI" className="h-full w-full dark:hidden" />
                <img src="/white-icon.svg" alt="AI" className="hidden h-full w-full dark:block" />
              </div>
              <p className="mb-1 text-[15px] font-semibold">Ask anything about your emails</p>
              <p className="text-muted-foreground mb-7 max-w-sm text-center text-[13px]">
                Use natural language to search, organize, and act on your inbox.
              </p>
              <div className="flex max-w-lg flex-wrap justify-center gap-2">
                {EXAMPLE_QUERIES.map((query) => (
                  <button
                    key={query}
                    type="button"
                    onClick={() => handleExampleClick(query)}
                    className="border-border bg-muted/50 text-muted-foreground hover:bg-accent hover:text-foreground rounded-lg border px-3 py-1.5 text-[12px] transition-colors"
                  >
                    {query}
                  </button>
                ))}
              </div>
            </div>
          ) : (
            <div className="mx-auto max-w-2xl px-4 py-5">
              <div className="flex flex-col gap-3">
                {messages.map((message, index) => (
                  <ChatMessageBubble key={`${message.id}-${index}`} message={message as ChatMsg} />
                ))}

                {/* Typing indicator (animated dots) */}
                {isLoading && (
                  <div className="flex justify-start">
                    <div className="bg-card rounded-2xl border px-4 py-3">
                      <div className="flex gap-1">
                        <span className="bg-muted-foreground/60 h-1.5 w-1.5 animate-bounce rounded-full [animation-delay:-0.3s]" />
                        <span className="bg-muted-foreground/60 h-1.5 w-1.5 animate-bounce rounded-full [animation-delay:-0.15s]" />
                        <span className="bg-muted-foreground/60 h-1.5 w-1.5 animate-bounce rounded-full" />
                      </div>
                    </div>
                  </div>
                )}
              </div>
              <div ref={messagesEndRef} />
            </div>
          )}
        </div>

        {/* Input bar */}
        <div className="border-t p-4">
          <div className="mx-auto max-w-2xl">
            <form onSubmit={handleChatFormSubmit}>
              {pendingClipboardFiles.length > 0 ? (
                <div className="border-border bg-muted/40 mb-2 flex flex-wrap gap-1.5 rounded-lg border px-2 py-1.5">
                  {pendingClipboardFiles.map((f, i) => (
                    <span
                      key={`${f.name}-${f.size}-${i}`}
                      className="text-muted-foreground border-border inline-flex max-w-[200px] items-center gap-1 rounded-md border bg-background px-2 py-0.5 text-[11px]"
                    >
                      <span className="truncate">{f.name || 'File'}</span>
                      <button
                        type="button"
                        className="text-muted-foreground hover:text-foreground shrink-0 p-0.5"
                        onClick={() =>
                          setPendingClipboardFiles((prev) => prev.filter((_, j) => j !== i))
                        }
                        aria-label="Remove"
                      >
                        ×
                      </button>
                    </span>
                  ))}
                </div>
              ) : null}
              <div className="border-input bg-background focus-within:ring-ring flex items-end gap-2 rounded-xl border px-4 py-2 focus-within:ring-1">
                <Textarea
                  ref={textareaRef}
                  value={input}
                  onChange={handleInputChange}
                  onKeyDown={handleKeyDown}
                  onPaste={handleComposerPaste}
                  placeholder="Ask anything about your emails… (paste files or images)"
                  className="min-h-[40px] flex-1 resize-none border-0 bg-transparent p-0 text-[13px] shadow-none focus-visible:ring-0"
                  rows={1}
                  disabled={isLoading}
                />
                {isLoading ? (
                  <Button
                    type="button"
                    size="icon"
                    variant="ghost"
                    className="h-8 w-8 shrink-0"
                    onClick={stop}
                    aria-label="Stop generating"
                  >
                    <StopCircle className="h-4 w-4" />
                  </Button>
                ) : (
                  <Button
                    type="submit"
                    size="icon"
                    className="h-8 w-8 shrink-0"
                    disabled={!input.trim() && pendingClipboardFiles.length === 0}
                    aria-label="Send message"
                  >
                    <SendHorizontal className="h-4 w-4" />
                  </Button>
                )}
              </div>
            </form>
            <p className="text-muted-foreground mt-2 text-center text-[11px]">
              AI can make mistakes. Verify important information.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
