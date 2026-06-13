import { useState, useRef, useEffect, useCallback } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useTRPC } from '@/providers/query-provider';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { cn } from '@/lib/utils';
import { Users, Link as LinkIcon, Bot, Loader2 } from 'lucide-react';
import { toast } from 'sonner';

interface Props {
  groupId: string;
}

// Inferred from tRPC output type
type GroupMessage = {
  id: string;
  content: string;
  senderType: 'user' | 'ai' | 'system';
  senderUserId: string | null;
  senderName: string | null;
  senderImage: string | null;
  createdAt: Date;
};

export function GroupChatView({ groupId }: Props) {
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const [message, setMessage] = useState('');
  const bottomRef = useRef<HTMLDivElement>(null);

  // Group details (name, members, aiMode)
  const { data: group } = useQuery(
    trpc.groups.get.queryOptions({ groupId }),
  );

  // Messages — polled every 5 seconds.
  // Messages — polled. Interval tightened to 2.5s (from 5s) and refetch-on-focus
  // added so returning to the tab updates instantly. TanStack pauses polling
  // while the tab is hidden by default (refetchIntervalInBackground is false),
  // so this doesn't hammer the backend in the background.
  //
  // TODO(realtime): true push requires a new Group Durable Object (rooms with
  // WebSocket hibernation + broadcast on new message), a `wrangler.jsonc` DO
  // binding, server `sendMessage` triggering the DO broadcast, and a client WS
  // subscription here that writes incoming messages straight into the React
  // Query cache. That DO does not exist yet — see groups.ts:72/348/363 TODOs.
  const { data: messageData, isLoading } = useQuery(
    trpc.groups.listMessages.queryOptions(
      { groupId, limit: 50 },
      { refetchInterval: 2500, refetchOnWindowFocus: true },
    ),
  );

  const messages: GroupMessage[] = (messageData?.messages as GroupMessage[]) ?? [];

  // Scroll to bottom when new messages arrive
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages.length]);

  const sendMessage = useMutation(
    trpc.groups.sendMessage.mutationOptions({
      onSuccess: () => {
        // Optimistically invalidate so the new message appears immediately
        queryClient.invalidateQueries({ queryKey: trpc.groups.listMessages.queryKey({ groupId }) });
      },
      onError: () => toast.error('Failed to send message.'),
    }),
  );

  const handleSend = useCallback(() => {
    const text = message.trim();
    if (!text) return;
    // Clear optimistically; restore on error so the user doesn't lose their message
    setMessage('');
    sendMessage.mutate({ groupId, content: text }, {
      onError: () => setMessage(text),
    });
  }, [message, groupId, sendMessage]);

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  const copyInviteLink = async () => {
    if (!group) return;
    if (typeof group.inviteToken !== 'string' || !group.inviteToken.trim()) {
      toast.error('Invite link is not available yet.');
      return;
    }
    const url = `${window.location.origin}/g/${group.inviteToken}`;
    try {
      await navigator.clipboard.writeText(url);
      toast.success('Invite link copied!');
    } catch {
      toast.error('Failed to copy invite link.');
    }
  };

  return (
    <div className="flex h-full flex-col">
      {/* Header */}
      <div className="border-b px-4 py-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Users className="text-muted-foreground h-4 w-4" />
            <span className="font-medium">{group?.name ?? '…'}</span>
            {group && (
              <span className="text-muted-foreground text-xs">
                {group.members.length} {group.members.length === 1 ? 'member' : 'members'}
              </span>
            )}
          </div>
          <Button variant="ghost" size="sm" onClick={copyInviteLink} className="h-fit px-2 text-xs">
            <LinkIcon className="mr-1 h-3 w-3" />
            Invite
          </Button>
        </div>

        {/* Member avatars */}
        {group && group.members.length > 0 && (
          <div className="mt-2 flex -space-x-1.5 overflow-hidden">
            {group.members.slice(0, 8).map((m) => (
              <Avatar key={m.userId} className="h-6 w-6 ring-2 ring-background">
                <AvatarImage src={m.image ?? undefined} />
                <AvatarFallback className="text-[10px]">
                  {m.name?.[0]?.toUpperCase() ?? '?'}
                </AvatarFallback>
              </Avatar>
            ))}
            {group.members.length > 8 && (
              <div className="bg-muted text-muted-foreground ring-background flex h-6 w-6 items-center justify-center rounded-full text-[10px] ring-2">
                +{group.members.length - 8}
              </div>
            )}
          </div>
        )}
      </div>

      {/* Messages */}
      <div className="flex-1 overflow-y-auto px-4 py-4">
        {isLoading ? (
          <div className="flex h-full items-center justify-center">
            <Loader2 className="text-muted-foreground h-5 w-5 animate-spin" />
          </div>
        ) : messages.length === 0 ? (
          <div className="flex h-full flex-col items-center justify-center gap-2 text-center">
            <Users className="text-muted-foreground h-8 w-8" />
            <p className="text-muted-foreground text-sm">
              No messages yet. Say hello!
            </p>
            {group?.aiMode === 'mention' && (
              <p className="text-muted-foreground text-xs">
                Type <code className="bg-muted rounded px-1">@ai</code> to ask the AI.
              </p>
            )}
          </div>
        ) : (
          <div className="flex flex-col gap-3">
            {messages.map((msg) => (
              <GroupMessageBubble key={msg.id} message={msg} />
            ))}
            <div ref={bottomRef} />
          </div>
        )}
      </div>

      {/* Composer */}
      <div className="border-t px-4 py-3">
        <div className="flex items-end gap-2">
          <Textarea
            value={message}
            onChange={(e) => setMessage(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder={
              group?.aiMode === 'mention'
                ? 'Message (type @ai for AI)…'
                : 'Message…'
            }
            className="min-h-[40px] max-h-[120px] resize-none text-sm"
            rows={1}
          />
          <Button
            onClick={handleSend}
            disabled={!message.trim() || sendMessage.isPending}
            size="sm"
          >
            Send
          </Button>
        </div>
      </div>
    </div>
  );
}

function GroupMessageBubble({ message }: { message: GroupMessage }) {
  if (message.senderType === 'system') {
    return (
      <div className="flex justify-center">
        <span className="text-muted-foreground text-xs">{message.content}</span>
      </div>
    );
  }

  const isAI = message.senderType === 'ai';

  return (
    <div className={cn('flex gap-2', isAI ? 'justify-start' : 'items-end flex-col')}>
      {isAI && (
        <div className="bg-primary flex h-7 w-7 shrink-0 items-center justify-center rounded-full">
          <Bot className="text-primary-foreground h-3.5 w-3.5" />
        </div>
      )}
      <div className={cn('flex max-w-[80%] flex-col gap-0.5', !isAI && 'items-end')}>
        {!isAI && message.senderName && (
          <span className="text-muted-foreground px-1 text-xs">{message.senderName}</span>
        )}
        <div
          className={cn(
            'rounded-2xl px-3.5 py-2 text-sm',
            isAI
              ? 'bg-muted text-foreground rounded-tl-sm'
              : 'bg-primary text-primary-foreground rounded-br-sm',
          )}
        >
          <p className="whitespace-pre-wrap">{message.content}</p>
        </div>
      </div>
    </div>
  );
}
