/**
 * Chat page — iOS/macOS parity.
 * Left sidebar: conversation history (ai.listConversations), new chat button.
 * Auto-save: on first assistant response, saves conversation with title = first 60 chars of user message.
 * Markdown: AI responses rendered with react-markdown + remark-gfm.
 */
import { useRef, useEffect, useState, useCallback } from 'react';
import { useAgent } from 'agents/react';
import { useAgentChat } from 'agents/ai-react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { formatDistanceToNow } from 'date-fns';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { authProxy } from '@/lib/auth-proxy';
import { useActiveConnection } from '@/hooks/use-connections';
import { useTRPC } from '@/providers/query-provider';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { ScrollArea } from '@/components/ui/scroll-area';
import { cn } from '@/lib/utils';
import {
  SendHorizontal,
  StopCircle,
  Plus,
  MessageSquare,
  Trash2,
  MoreHorizontal,
} from 'lucide-react';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import type { Route } from './+types/page';

// Auth guard
export async function clientLoader({ request }: Route.ClientLoaderArgs) {
  const session = await authProxy.api.getSession({ headers: request.headers });
  if (!session) return Response.redirect(`${import.meta.env.VITE_PUBLIC_APP_URL}/login`);
  return {};
}

const EXAMPLE_QUERIES = [
  'Find all unread emails from today',
  'Label all GitHub emails as OSS',
  'Summarize my most important emails',
  'Show recent emails from my team',
  'Create a task to reply to the latest invoice',
];

// Stable UUID generator (crypto.randomUUID fallback)
function newId() {
  if (typeof crypto !== 'undefined' && crypto.randomUUID) return crypto.randomUUID();
  return `${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

export default function ChatPage() {
  const { data: activeConnection } = useActiveConnection();
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  // Active conversation ID in memory — not persisted to URL to keep it simple
  const [conversationId, setConversationId] = useState<string>(() => newId());
  // Whether the current session has been saved to backend yet
  const [isSaved, setIsSaved] = useState(false);
  // Tracks previous user message count to detect new messages and reset isSaved
  const prevUserMsgCountRef = useRef(0);

  // Fetch conversation list for sidebar
  const { data: conversationsData, refetch: refetchConversations } = useQuery(
    trpc.ai.listConversations.queryOptions(),
  );
  const conversations = conversationsData?.conversations ?? [];

  // Save / update a conversation
  const saveConversation = useMutation(trpc.ai.saveConversation.mutationOptions());
  // Delete a conversation
  const deleteConversation = useMutation({
    ...trpc.ai.deleteConversation.mutationOptions(),
    onSuccess: () => {
      void refetchConversations();
    },
  });

  // Connect to the ZeroAgent Durable Object via WebSocket
  const agent = useAgent({
    agent: 'ZeroAgent',
    name: activeConnection?.id ? String(activeConnection.id) : 'general',
    host: `${import.meta.env.VITE_PUBLIC_BACKEND_URL}`,
    onError: (e) => console.error('Agent error:', e),
  });

  const {
    messages,
    input,
    handleInputChange,
    handleSubmit,
    status,
    stop,
    setMessages,
  } = useAgentChat({
    agent,
    maxSteps: 10,
    getInitialMessages: async () => [],
  });

  const isLoading = status === 'submitted' || status === 'streaming';

  // Auto-scroll to bottom on new messages
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

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
    // Guard: don't re-save the same exchange if already saved
    if (isSaved) return;

    const assistantMessages = messages.filter((m) => m.role === 'assistant');
    const userMessages = messages.filter((m) => m.role === 'user');

    // Only trigger once we have at least one assistant reply and we're not mid-stream
    if (assistantMessages.length === 0 || isLoading) return;

    // Defensively extract title — content may be a string or an array of content parts
    const rawContent = userMessages[0]?.content;
    const title = (() => {
      if (!rawContent) return 'New conversation';
      if (typeof rawContent === 'string') return rawContent.slice(0, 60).trim() || 'New conversation';
      if (Array.isArray(rawContent)) {
        const text = rawContent
          .map((p: { text?: string }) => (typeof p === 'string' ? p : (p.text ?? '')))
          .join('')
          .trim();
        return text.slice(0, 60) || 'New conversation';
      }
      return 'New conversation';
    })();

    // Serialize messages for storage — extract text content only
    const serialized = messages
      .filter((m) => m.role === 'user' || m.role === 'assistant')
      .map((m) => ({
        role: m.role,
        content: typeof m.content === 'string' ? m.content : JSON.stringify(m.content),
      }));

    saveConversation.mutate(
      { id: conversationId, title, messages: serialized },
      {
        onSuccess: () => {
          setIsSaved(true);
          void refetchConversations();
        },
      },
    );
  // Intentionally not exhaustive — only re-run when message count, loading, or isSaved changes
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [messages.length, isLoading, isSaved]);

  // Start a brand new chat session
  const handleNewChat = useCallback(() => {
    setMessages([]);
    setConversationId(newId());
    setIsSaved(false);
    prevUserMsgCountRef.current = 0;
  }, [setMessages]);

  // Load a past conversation — show its messages in read-only mode
  const handleLoadConversation = useCallback(
    async (id: string) => {
      try {
        // Fetch full conversation from backend
        const result = await queryClient.fetchQuery(
          trpc.ai.getConversation.queryOptions({ id }),
        );
        if (!result?.messages) return;

        // Build message objects compatible with useAgentChat
        const loaded = (result.messages as Array<{ role: string; content: string }>).map(
          (m, i) => ({
            id: `loaded-${id}-${i}`,
            role: m.role as 'user' | 'assistant',
            content: m.content,
            parts: [{ type: 'text' as const, text: m.content }],
          }),
        );
        setMessages(loaded);
        setConversationId(id);
        setIsSaved(true);
      } catch (err) {
        console.error('Failed to load conversation:', err);
        toast.error('Failed to load conversation. Please try again.');
      }
    },
    [queryClient, trpc.ai.getConversation, setMessages],
  );

  const handleDeleteConversation = useCallback(
    (id: string, e: React.MouseEvent) => {
      e.stopPropagation();
      deleteConversation.mutate({ id });
      // If the deleted conversation is the active one, start fresh
      if (id === conversationId) {
        handleNewChat();
      }
    },
    [conversationId, deleteConversation, handleNewChat],
  );

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      if (input.trim() && !isLoading) {
        handleSubmit(e as unknown as React.FormEvent);
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

  return (
    <div className="flex h-screen overflow-hidden bg-background">
      {/* ── Conversation History Sidebar ─────────────────────────────────── */}
      <aside className="hidden w-56 shrink-0 flex-col border-r bg-sidebar md:flex">
        <div className="flex items-center justify-between px-3 py-3.5 border-b">
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

        <ScrollArea className="flex-1 py-1">
          {conversations.length === 0 ? (
            <div className="flex flex-col items-center gap-1 px-4 py-8 text-center">
              <MessageSquare className="h-6 w-6 text-muted-foreground/40" />
              <p className="text-[12px] text-muted-foreground">No saved chats yet</p>
            </div>
          ) : (
            conversations.map((convo) => {
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
                    <p className="truncate text-[12px] font-medium leading-snug">
                      {convo.title}
                    </p>
                    <p className="text-[11px] text-muted-foreground">
                      {convo.updatedAt
                        ? formatDistanceToNow(new Date(convo.updatedAt), { addSuffix: true })
                        : ''}
                    </p>
                  </div>
                  {/* Delete via dropdown — only visible on hover */}
                  <div className="invisible shrink-0 group-hover:visible">
                    <DropdownMenu>
                      <DropdownMenuTrigger asChild>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-5 w-5 p-0"
                          onClick={(e) => e.stopPropagation()}
                        >
                          <MoreHorizontal className="h-3.5 w-3.5" />
                        </Button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="end" className="w-32">
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
      </aside>

      {/* ── Main Chat Panel ──────────────────────────────────────────────── */}
      <div className="flex min-w-0 flex-1 flex-col">
        {/* Header */}
        <div className="flex items-center justify-between border-b px-6 py-3.5">
          <div className="flex items-center gap-2">
            <h1 className="text-[15px] font-semibold">AI Assistant</h1>
          </div>
          {messages.length > 0 && (
            <Button variant="outline" size="sm" className="h-7 gap-1.5 text-[12px]" onClick={handleNewChat}>
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
              <p className="mb-7 max-w-sm text-center text-[13px] text-muted-foreground">
                Use natural language to search, organize, and act on your inbox.
              </p>
              <div className="flex flex-wrap justify-center gap-2 max-w-lg">
                {EXAMPLE_QUERIES.map((query) => (
                  <button
                    key={query}
                    type="button"
                    onClick={() => handleExampleClick(query)}
                    className="rounded-lg border border-border bg-muted/50 px-3 py-1.5 text-[12px] text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
                  >
                    {query}
                  </button>
                ))}
              </div>
            </div>
          ) : (
            <div className="mx-auto max-w-2xl px-4 py-5">
              <div className="flex flex-col gap-3">
                {messages.map((message, index) => {
                  const textParts = message.parts?.filter((p) => p.type === 'text') ?? [];
                  const hasText = textParts.some(
                    (p) => 'text' in p && (p as { text: string }).text?.trim(),
                  );
                  if (!hasText) return null;

                  const isUser = message.role === 'user';

                  return (
                    <div
                      key={`${message.id}-${index}`}
                      className={cn('flex', isUser ? 'justify-end' : 'justify-start')}
                    >
                      <div
                        className={cn(
                          'max-w-[82%] rounded-2xl px-4 py-2.5 text-[13px] leading-relaxed',
                          isUser
                            ? 'bg-primary text-primary-foreground'
                            : 'border bg-card text-foreground',
                        )}
                      >
                        {isUser ? (
                          // User messages: plain text with whitespace-pre-wrap
                          textParts.map((part, i) => {
                            const text = 'text' in part ? (part as { text: string }).text : '';
                            return text ? (
                              <p key={i} className="whitespace-pre-wrap">
                                {text}
                              </p>
                            ) : null;
                          })
                        ) : (
                          // AI messages: markdown rendered with react-markdown + remark-gfm.
                          // Wrapped in a div because react-markdown v10 doesn't accept className directly.
                          textParts.map((part, i) => {
                            const text = 'text' in part ? (part as { text: string }).text : '';
                            return text ? (
                              <div
                                key={i}
                                className="prose prose-sm dark:prose-invert max-w-none [&_code]:text-[12px] [&_pre]:overflow-x-auto"
                              >
                                <ReactMarkdown remarkPlugins={[remarkGfm]}>
                                  {text}
                                </ReactMarkdown>
                              </div>
                            ) : null;
                          })
                        )}
                      </div>
                    </div>
                  );
                })}

                {/* Typing indicator (animated dots) */}
                {isLoading && (
                  <div className="flex justify-start">
                    <div className="rounded-2xl border bg-card px-4 py-3">
                      <div className="flex gap-1">
                        <span className="h-1.5 w-1.5 animate-bounce rounded-full bg-muted-foreground/60 [animation-delay:-0.3s]" />
                        <span className="h-1.5 w-1.5 animate-bounce rounded-full bg-muted-foreground/60 [animation-delay:-0.15s]" />
                        <span className="h-1.5 w-1.5 animate-bounce rounded-full bg-muted-foreground/60" />
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
            <form onSubmit={handleSubmit}>
              <div className="flex items-end gap-2 rounded-xl border border-input bg-background px-4 py-2 focus-within:ring-1 focus-within:ring-ring">
                <Textarea
                  ref={textareaRef}
                  value={input}
                  onChange={handleInputChange}
                  onKeyDown={handleKeyDown}
                  placeholder="Ask anything about your emails..."
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
                  >
                    <StopCircle className="h-4 w-4" />
                  </Button>
                ) : (
                  <Button
                    type="submit"
                    size="icon"
                    className="h-8 w-8 shrink-0"
                    disabled={!input.trim()}
                  >
                    <SendHorizontal className="h-4 w-4" />
                  </Button>
                )}
              </div>
            </form>
            <p className="mt-2 text-center text-[11px] text-muted-foreground">
              AI can make mistakes. Verify important information.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
