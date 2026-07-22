import {
  X,
  Expand,
  Plus,
  Share2,
  ArrowLeft,
  PanelRight,
  Maximize2,
  Move,
  ExternalLink,
  Sparkles,
  MailOpen,
  Pencil,
  CheckCircle2,
  CalendarPlus,
  Search,
  Newspaper,
  BellOff,
  Paperclip,
  Clock,
  Tag,
  Lightbulb,
  Languages,
  type LucideIcon,
} from 'lucide-react';
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
} from '@/components/ui/dropdown-menu';
import {
  useAISidebar,
  useAssistantDisplayMode,
  type AssistantDisplayMode,
} from '@/hooks/use-ai-sidebar';
import { Tooltip, TooltipTrigger, TooltipContent, TooltipProvider } from '@/components/ui/tooltip';
import { ShareConversationModal } from '@/components/ui/share-conversation-modal';
import { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import { ArrowsPointingIn, PanelLeftOpen, Phone } from '../icons/icons';
import { AI_PROMPTS, type AIPrompt } from '@/components/ui/ai-prompts';
import { useQueryClient, useQuery } from '@tanstack/react-query';
import { GroupChatView } from '@/components/ui/group-chat-view';
import { ModelSelector } from '@/components/ui/model-selector';
import { useActiveConnection } from '@/hooks/use-connections';
import { useSearchValue } from '@/hooks/use-search-value';
import useSearchLabels from '@/hooks/use-labels-search';
import { useNavigate, useParams } from 'react-router';
import { AIChat } from '@/components/create/ai-chat';
import { useTRPC } from '@/providers/query-provider';
import { useSettings } from '@/hooks/use-settings';
import { Tools } from '../../../server/src/types';
import { useDoState } from '../mail/use-do-state';
import { useBilling } from '@/hooks/use-billing';
import { PromptsDialog } from './prompts-dialog';
import { Button } from '@/components/ui/button';
import { useHotkeys } from 'react-hotkeys-hook';
import { useLabels } from '@/hooks/use-labels';
import { useAgentChat } from 'agents/ai-react';
import type { MentionRef } from '@zero/shared';
import { IncomingMessageType } from '../party';
import { Gauge } from '@/components/ui/gauge';
import { createPortal } from 'react-dom';
import { useAgent } from 'agents/react';
import { useQueryState } from 'nuqs';
import { cn } from '@/lib/utils';
import posthog from 'posthog-js';
import { toast } from 'sonner';

// ---------------------------------------------------------------------------
// Display modes
// ---------------------------------------------------------------------------

const FLOATING_GEOM_KEY = 'mail.ai.floatingGeometry';

interface FloatingGeometry {
  x: number;
  y: number;
  width: number;
  height: number;
}

const DEFAULT_FLOATING_GEOMETRY: FloatingGeometry = {
  x: 120,
  y: 120,
  width: 380,
  height: 520,
};

const MIN_FLOATING_WIDTH = 320;
const MIN_FLOATING_HEIGHT = 360;

function loadFloatingGeometry(): FloatingGeometry {
  if (typeof window === 'undefined') return DEFAULT_FLOATING_GEOMETRY;
  try {
    const raw = window.localStorage.getItem(FLOATING_GEOM_KEY);
    if (!raw) return DEFAULT_FLOATING_GEOMETRY;
    const parsed = JSON.parse(raw) as Partial<FloatingGeometry>;
    if (
      typeof parsed.x !== 'number' ||
      typeof parsed.y !== 'number' ||
      typeof parsed.width !== 'number' ||
      typeof parsed.height !== 'number'
    ) {
      return DEFAULT_FLOATING_GEOMETRY;
    }
    return {
      x: parsed.x,
      y: parsed.y,
      width: Math.max(parsed.width, MIN_FLOATING_WIDTH),
      height: Math.max(parsed.height, MIN_FLOATING_HEIGHT),
    };
  } catch {
    return DEFAULT_FLOATING_GEOMETRY;
  }
}

function clampToViewport(geom: FloatingGeometry): FloatingGeometry {
  if (typeof window === 'undefined') return geom;
  const vw = window.innerWidth;
  const vh = window.innerHeight;
  const width = Math.min(geom.width, Math.max(vw - 16, MIN_FLOATING_WIDTH));
  const height = Math.min(geom.height, Math.max(vh - 16, MIN_FLOATING_HEIGHT));
  const x = Math.min(Math.max(geom.x, 8), Math.max(vw - width - 8, 8));
  const y = Math.min(Math.max(geom.y, 8), Math.max(vh - height - 8, 8));
  return { x, y, width, height };
}

// ---------------------------------------------------------------------------
// Prompt gallery
// ---------------------------------------------------------------------------

const PROMPT_ICONS: Record<string, LucideIcon> = {
  MailOpen,
  Pencil,
  CheckCircle2,
  CalendarPlus,
  Search,
  Newspaper,
  BellOff,
  Paperclip,
  Clock,
  Tag,
  Lightbulb,
  Languages,
};

interface PromptGalleryProps {
  prompts: AIPrompt[];
  onSelect: (prompt: AIPrompt) => void;
}

function PromptGallery({ prompts, onSelect }: PromptGalleryProps) {
  return (
    <div
      className="pointer-events-auto absolute inset-x-0 bottom-0 z-10 max-h-[55%] overflow-y-auto px-3 pb-3 pt-2"
      data-testid="ai-prompt-gallery"
    >
      <div className="mb-2 flex items-center gap-1.5 px-1 text-[11px] font-medium uppercase tracking-wide text-[#8C8C8C] dark:text-[#929292]">
        <Sparkles className="h-3 w-3" />
        Prompt library
      </div>
      <div className="grid grid-cols-2 gap-2">
        {prompts.map((prompt) => {
          const Icon = prompt.icon ? (PROMPT_ICONS[prompt.icon] ?? Sparkles) : Sparkles;
          return (
            <button
              key={prompt.id}
              type="button"
              onClick={() => onSelect(prompt)}
              className={cn(
                'group flex flex-col items-start gap-1 rounded-lg border border-[#E7E7E7] bg-white/60 p-2.5 text-left',
                'transition-colors hover:border-[#D4D4D4] hover:bg-white',
                'dark:border-[#252525] dark:bg-[#1A1A1A]/60 dark:hover:border-[#333] dark:hover:bg-[#1F1F1F]',
              )}
            >
              <div className="flex w-full items-center gap-1.5">
                <Icon className="h-3.5 w-3.5 shrink-0 text-[#555] dark:text-[#929292]" />
                <span className="truncate text-[12px] font-medium text-black dark:text-white">
                  {prompt.title}
                </span>
              </div>
              <span className="line-clamp-2 text-[11px] leading-snug text-[#8C8C8C] dark:text-[#929292]">
                {prompt.body}
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Detached-window portal
// ---------------------------------------------------------------------------

interface DetachedWindowProps {
  onClose: () => void;
  children: React.ReactNode;
}

/**
 * Renders `children` inside a fresh `window.open(...)` document via a portal.
 * Copies the parent document's `<style>` / `<link>` tags so Tailwind utility
 * classes resolve. Calls `onClose` if the OS-level window is closed by the user.
 */
function DetachedWindow({ onClose, children }: DetachedWindowProps) {
  const [container, setContainer] = useState<HTMLDivElement | null>(null);
  const externalWindowRef = useRef<Window | null>(null);

  useEffect(() => {
    if (typeof window === 'undefined') return;

    const externalWindow = window.open(
      'about:blank',
      'todus-ai',
      'width=480,height=640,menubar=no,toolbar=no,location=no,status=no',
    );

    if (!externalWindow) {
      // Pop-up blocked — fall back gracefully by flipping the mode back.
      toast.error('Pop-up blocked. Allow pop-ups for Todus to open the AI in its own window.');
      onClose();
      return;
    }

    externalWindowRef.current = externalWindow;
    externalWindow.document.title = 'Todus AI';

    // Copy parent stylesheets so Tailwind classes render correctly.
    const head = externalWindow.document.head;
    document.querySelectorAll('style, link[rel="stylesheet"]').forEach((node) => {
      head.appendChild(node.cloneNode(true));
    });

    // Mirror the active theme class on <html> so dark mode applies.
    externalWindow.document.documentElement.className = document.documentElement.className;

    const mount = externalWindow.document.createElement('div');
    mount.style.cssText = 'height:100vh;width:100vw;display:flex;';
    externalWindow.document.body.style.cssText = 'margin:0;padding:0;overflow:hidden;';
    externalWindow.document.body.appendChild(mount);
    setContainer(mount);

    const handleBeforeUnload = () => onClose();
    const handlePagehide = () => onClose();
    externalWindow.addEventListener('beforeunload', handleBeforeUnload);
    externalWindow.addEventListener('pagehide', handlePagehide);

    // Polling fallback — some browsers do not fire beforeunload for popups.
    const closeWatch = window.setInterval(() => {
      if (externalWindow.closed) {
        window.clearInterval(closeWatch);
        onClose();
      }
    }, 500);

    // Close the popup if the parent unloads to avoid orphaned windows.
    const handleParentUnload = () => externalWindow.close();
    window.addEventListener('beforeunload', handleParentUnload);

    return () => {
      window.clearInterval(closeWatch);
      window.removeEventListener('beforeunload', handleParentUnload);
      externalWindow.removeEventListener('beforeunload', handleBeforeUnload);
      externalWindow.removeEventListener('pagehide', handlePagehide);
      if (!externalWindow.closed) externalWindow.close();
      externalWindowRef.current = null;
    };
    // We intentionally only run once per mount — `onClose` is stable from the caller.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (!container) return null;
  return createPortal(children, container);
}

interface ChatHeaderProps {
  onClose: () => void;
  onToggleFullScreen: () => void;
  onToggleViewMode: () => void;
  isFullScreen: boolean;
  isPopup: boolean;
  isPro: boolean;
  onNewChat: () => void;
  /** When a group is active, show back button + group name instead of new-chat button */
  activeGroupId?: string | null;
  onBackFromGroup?: () => void;
  /** Current saved conversation ID — enables the Share button */
  currentConversationId?: string | null;
  currentConversationTitle?: string;
  /** Display-mode picker — added for floating/window parity with macOS. */
  displayMode: AssistantDisplayMode;
  onChangeDisplayMode: (mode: AssistantDisplayMode) => void;
  /** Optional ref the floating shell attaches a mousedown listener to so the
   *  header acts as the drag handle. */
  dragHandleRef?: React.RefObject<HTMLDivElement | null>;
}

function ChatHeader({
  onClose,
  onToggleFullScreen,
  onToggleViewMode,
  isFullScreen,
  isPopup,
  isPro,
  onNewChat,
  activeGroupId,
  onBackFromGroup,
  currentConversationId,
  currentConversationTitle,
  displayMode,
  onChangeDisplayMode,
  dragHandleRef,
}: ChatHeaderProps) {
  const [, setPricingDialog] = useQueryState('pricingDialog');
  const { chatMessages } = useBilling();
  const [shareOpen, setShareOpen] = useState(false);

  const displayModeMeta = useMemo(() => {
    switch (displayMode) {
      case 'sidebar':
        return { label: 'Sidebar', Icon: PanelRight };
      case 'full':
        return { label: 'Full screen', Icon: Maximize2 };
      case 'floating':
        return { label: 'Floating', Icon: Move };
      case 'window':
        return { label: 'Detached window', Icon: ExternalLink };
    }
  }, [displayMode]);

  return (
    <div
      ref={dragHandleRef}
      className={cn(
        'relative flex items-center justify-between px-2.5 pb-[10px] pt-[13px]',
        displayMode === 'floating' && 'cursor-grab select-none active:cursor-grabbing',
      )}
    >
      <div className="flex items-center gap-1">
        <TooltipProvider delayDuration={0}>
          <Tooltip>
            <TooltipTrigger asChild>
              <Button onClick={onClose} variant="ghost" className="md:h-fit md:px-2">
                <X className="dark:text-iconDark text-iconLight" />
                <span className="sr-only">Close chat</span>
              </Button>
            </TooltipTrigger>
            <TooltipContent>Close chat</TooltipContent>
          </Tooltip>
        </TooltipProvider>

        {/* Compact model selector — lets users switch AI provider/model mid-conversation */}
        <ModelSelector variant="compact" />
      </div>

      <div className="flex items-center gap-2">
        {isFullScreen ? (
          <TooltipProvider delayDuration={0}>
            <Tooltip>
              <TooltipTrigger asChild>
                <Button
                  onClick={onToggleFullScreen}
                  variant="ghost"
                  className="hidden md:flex md:h-fit md:px-2"
                >
                  <ArrowsPointingIn className="dark:fill-iconDark fill-iconLight" />
                  <span className="sr-only">Toggle view mode</span>
                </Button>
              </TooltipTrigger>
              <TooltipContent>Remove full screen</TooltipContent>
            </Tooltip>
          </TooltipProvider>
        ) : (
          <>
            <TooltipProvider delayDuration={0}>
              <Tooltip>
                <TooltipTrigger asChild>
                  <Button
                    onClick={onToggleFullScreen}
                    variant="ghost"
                    className="hidden md:flex md:h-fit md:px-2"
                  >
                    <Expand className="dark:text-iconDark text-iconLight" />
                    <span className="sr-only">Toggle view mode</span>
                  </Button>
                </TooltipTrigger>
                <TooltipContent>Go to full screen</TooltipContent>
              </Tooltip>
            </TooltipProvider>

            <TooltipProvider delayDuration={0}>
              <Tooltip>
                <TooltipTrigger asChild>
                  <Button
                    onClick={onToggleViewMode}
                    variant="ghost"
                    className="hidden md:flex md:h-fit md:px-2"
                  >
                    {isPopup ? (
                      <PanelLeftOpen className="dark:fill-iconDark fill-iconLight" />
                    ) : (
                      <Phone className="dark:fill-iconDark fill-iconLight" />
                    )}
                    <span className="sr-only"></span>
                  </Button>
                </TooltipTrigger>
                <TooltipContent>Go to {isPopup ? 'sidebar' : 'popup'}</TooltipContent>
              </Tooltip>
            </TooltipProvider>
          </>
        )}

        {/* Display-mode picker — sidebar / full / floating / detached window */}
        <DropdownMenu>
          <TooltipProvider delayDuration={0}>
            <Tooltip>
              <TooltipTrigger asChild>
                <DropdownMenuTrigger asChild>
                  <Button variant="ghost" className="hidden md:flex md:h-fit md:px-2">
                    <displayModeMeta.Icon className="dark:text-iconDark text-iconLight h-4 w-4" />
                    <span className="sr-only">Change display mode</span>
                  </Button>
                </DropdownMenuTrigger>
              </TooltipTrigger>
              <TooltipContent>Display mode ({displayModeMeta.label})</TooltipContent>
            </Tooltip>
          </TooltipProvider>
          <DropdownMenuContent align="end" className="w-52">
            <DropdownMenuLabel>Display mode</DropdownMenuLabel>
            <DropdownMenuSeparator />
            <DropdownMenuItem
              onClick={() => onChangeDisplayMode('sidebar')}
              disabled={displayMode === 'sidebar'}
            >
              <PanelRight className="mr-2 h-4 w-4" />
              Sidebar
            </DropdownMenuItem>
            <DropdownMenuItem
              onClick={() => onChangeDisplayMode('floating')}
              disabled={displayMode === 'floating'}
            >
              <Move className="mr-2 h-4 w-4" />
              Floating panel
            </DropdownMenuItem>
            <DropdownMenuItem
              onClick={() => onChangeDisplayMode('window')}
              disabled={displayMode === 'window'}
            >
              <ExternalLink className="mr-2 h-4 w-4" />
              Detached window
            </DropdownMenuItem>
            <DropdownMenuItem
              onClick={() => onChangeDisplayMode('full')}
              disabled={displayMode === 'full'}
            >
              <Maximize2 className="mr-2 h-4 w-4" />
              Full screen
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>

        {!isPro && (
          <>
            <TooltipProvider delayDuration={0}>
              <Tooltip>
                <TooltipTrigger asChild className="md:h-fit md:px-2">
                  <div>
                    <Gauge
                      max={chatMessages.included_usage}
                      value={chatMessages.usage}
                      size="small"
                      showValue={true}
                    />
                  </div>
                </TooltipTrigger>
                <TooltipContent>
                  <p>
                    You have used {chatMessages.usage} out of {chatMessages.included_usage} chat
                    messages.
                  </p>
                  <p className="mb-2">Upgrade for unlimited messages!</p>
                  <Button
                    onClick={(e) => {
                      e.stopPropagation();
                      setPricingDialog('true');
                    }}
                    className="h-8 w-full"
                  >
                    Start 7 day free trial
                  </Button>
                </TooltipContent>
              </Tooltip>
            </TooltipProvider>
          </>
        )}

        <PromptsDialog />

        {/* Share button — only visible when viewing a saved conversation (not a group) */}
        {currentConversationId && !activeGroupId && (
          <>
            <TooltipProvider delayDuration={0}>
              <Tooltip>
                <TooltipTrigger asChild>
                  <Button
                    onClick={() => setShareOpen(true)}
                    variant="ghost"
                    className="md:h-fit md:px-2"
                  >
                    <Share2 className="dark:text-iconDark text-iconLight h-4 w-4" />
                    <span className="sr-only">Share conversation</span>
                  </Button>
                </TooltipTrigger>
                <TooltipContent>Share conversation</TooltipContent>
              </Tooltip>
            </TooltipProvider>
            <ShareConversationModal
              open={shareOpen}
              onOpenChange={setShareOpen}
              conversationId={currentConversationId}
              conversationTitle={currentConversationTitle ?? ''}
            />
          </>
        )}

        {/* Back-to-AI button when inside a group chat */}
        {activeGroupId && onBackFromGroup && (
          <TooltipProvider delayDuration={0}>
            <Tooltip>
              <TooltipTrigger asChild>
                <Button onClick={onBackFromGroup} variant="ghost" className="md:h-fit md:px-2">
                  <ArrowLeft className="dark:text-iconDark text-iconLight h-4 w-4" />
                  <span className="sr-only">Back to AI chat</span>
                </Button>
              </TooltipTrigger>
              <TooltipContent>Back to AI chat</TooltipContent>
            </Tooltip>
          </TooltipProvider>
        )}

        {!activeGroupId && (
          <TooltipProvider delayDuration={0}>
            <Tooltip>
              <TooltipTrigger asChild>
                <Button onClick={onNewChat} variant="ghost" className="md:h-fit md:px-2">
                  <Plus className="dark:text-iconDark text-iconLight" />
                  <span className="sr-only">New chat</span>
                </Button>
              </TooltipTrigger>
              <TooltipContent>New chat</TooltipContent>
            </Tooltip>
          </TooltipProvider>
        )}
      </div>
    </div>
  );
}

interface AISidebarProps {
  className?: string;
}

// ---------------------------------------------------------------------------
// Floating shell — draggable + resizable, fixed-positioned chat panel.
// ---------------------------------------------------------------------------

interface FloatingShellProps {
  children: (dragHandleRef: React.RefObject<HTMLDivElement | null>) => React.ReactNode;
}

function FloatingShell({ children }: FloatingShellProps) {
  const [geom, setGeom] = useState<FloatingGeometry>(() => clampToViewport(loadFloatingGeometry()));
  const dragHandleRef = useRef<HTMLDivElement | null>(null);
  const dragStateRef = useRef<{
    mode: 'move' | 'resize' | null;
    pointerX: number;
    pointerY: number;
    startGeom: FloatingGeometry;
  }>({ mode: null, pointerX: 0, pointerY: 0, startGeom: geom });

  // Persist geometry whenever it changes.
  useEffect(() => {
    if (typeof window === 'undefined') return;
    try {
      window.localStorage.setItem(FLOATING_GEOM_KEY, JSON.stringify(geom));
    } catch {
      // Storage quota / disabled storage — non-fatal.
    }
  }, [geom]);

  // Keep geometry inside the viewport when the window resizes.
  useEffect(() => {
    if (typeof window === 'undefined') return;
    const onResize = () => setGeom((current) => clampToViewport(current));
    window.addEventListener('resize', onResize);
    return () => window.removeEventListener('resize', onResize);
  }, []);

  // Drag from the header.
  useEffect(() => {
    const handle = dragHandleRef.current;
    if (!handle) return;

    const onMouseDown = (event: MouseEvent) => {
      // Ignore drags that originate from interactive controls in the header.
      const target = event.target as HTMLElement | null;
      if (target?.closest('button, a, input, textarea, [role="menuitem"]')) return;
      event.preventDefault();
      dragStateRef.current = {
        mode: 'move',
        pointerX: event.clientX,
        pointerY: event.clientY,
        startGeom: geom,
      };
      window.addEventListener('mousemove', onMouseMove);
      window.addEventListener('mouseup', onMouseUp);
    };

    const onMouseMove = (event: MouseEvent) => {
      const state = dragStateRef.current;
      if (state.mode !== 'move') return;
      const dx = event.clientX - state.pointerX;
      const dy = event.clientY - state.pointerY;
      setGeom(
        clampToViewport({
          ...state.startGeom,
          x: state.startGeom.x + dx,
          y: state.startGeom.y + dy,
        }),
      );
    };

    const onMouseUp = () => {
      dragStateRef.current.mode = null;
      window.removeEventListener('mousemove', onMouseMove);
      window.removeEventListener('mouseup', onMouseUp);
    };

    handle.addEventListener('mousedown', onMouseDown);
    return () => {
      handle.removeEventListener('mousedown', onMouseDown);
      window.removeEventListener('mousemove', onMouseMove);
      window.removeEventListener('mouseup', onMouseUp);
    };
  }, [geom]);

  // Resize from the bottom-right corner handle.
  const onResizeMouseDown = useCallback(
    (event: React.MouseEvent<HTMLDivElement>) => {
      event.preventDefault();
      event.stopPropagation();
      dragStateRef.current = {
        mode: 'resize',
        pointerX: event.clientX,
        pointerY: event.clientY,
        startGeom: geom,
      };

      const onMove = (ev: MouseEvent) => {
        const state = dragStateRef.current;
        if (state.mode !== 'resize') return;
        const dx = ev.clientX - state.pointerX;
        const dy = ev.clientY - state.pointerY;
        setGeom(
          clampToViewport({
            ...state.startGeom,
            width: Math.max(MIN_FLOATING_WIDTH, state.startGeom.width + dx),
            height: Math.max(MIN_FLOATING_HEIGHT, state.startGeom.height + dy),
          }),
        );
      };
      const onUp = () => {
        dragStateRef.current.mode = null;
        window.removeEventListener('mousemove', onMove);
        window.removeEventListener('mouseup', onUp);
      };
      window.addEventListener('mousemove', onMove);
      window.addEventListener('mouseup', onUp);
    },
    [geom],
  );

  return (
    <div
      className="bg-panelLight dark:bg-panelDark fixed z-50 hidden flex-col overflow-hidden rounded-2xl border border-[#E7E7E7] shadow-2xl md:flex dark:border-[#252525]"
      style={{
        left: geom.x,
        top: geom.y,
        width: geom.width,
        height: geom.height,
      }}
      data-testid="ai-floating-shell"
    >
      {children(dragHandleRef)}
      <div
        onMouseDown={onResizeMouseDown}
        className="absolute bottom-0 right-0 z-20 h-4 w-4 cursor-nwse-resize"
        aria-hidden
      >
        <svg viewBox="0 0 16 16" className="text-[#8C8C8C] dark:text-[#929292]" fill="currentColor">
          <path d="M14 6L6 14M14 10L10 14" stroke="currentColor" strokeWidth="1.2" />
        </svg>
      </div>
    </div>
  );
}

function AISidebar({ className }: AISidebarProps) {
  const { open, setOpen, isFullScreen, setIsFullScreen, toggleViewMode, isSidebar, isPopup } =
    useAISidebar();
  const { displayMode, setDisplayMode } = useAssistantDisplayMode(setIsFullScreen);
  const { isPro, track, refetch: refetchBilling } = useBilling();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  // groupId query param — when set the sidebar shows GroupChatView instead of AIChat
  const [groupId, setGroupId] = useQueryState('groupId');
  // Track the current saved conversation ID to enable the Share button
  const [currentConversationId] = useQueryState('conversationId');
  const trpc = useTRPC();
  // Fetch the title for the active conversation so the ShareModal can prefill it
  const { data: currentConversationData } = useQuery(
    trpc.ai.getConversation.queryOptions(
      { id: currentConversationId! },
      { enabled: !!currentConversationId },
    ),
  );
  const currentConversationTitle = currentConversationData?.title ?? '';
  const [threadId] = useQueryState('threadId');
  const { folder } = useParams<{ folder: string }>();
  const { refetch: refetchLabels } = useLabels();
  const [searchValue] = useSearchValue();
  const { data: activeConnection } = useActiveConnection();
  const [, setDoState] = useDoState();
  const { labels } = useSearchLabels();
  const [pendingMentions, setPendingMentions] = useState<MentionRef[]>([]);

  const onMessage = useCallback(
    (message: MessageEvent<string>) => {
      try {
        const parsedData = JSON.parse(message.data);
        const { type } = parsedData;
        if (type === IncomingMessageType.Mail_Get) {
          const { threadId } = parsedData;
          queryClient.invalidateQueries({
            queryKey: trpc.mail.get.queryKey({ id: threadId }),
          });
        } else if (type === IncomingMessageType.Mail_List) {
          const { folder } = parsedData;
          queryClient.invalidateQueries({
            queryKey: trpc.mail.listThreads.infiniteQueryKey({
              folder,
              labelIds: labels,
              q: searchValue.value,
            }),
          });
        } else if (type === IncomingMessageType.User_Topics) {
          queryClient.invalidateQueries({
            queryKey: trpc.labels.list.queryKey(),
          });
        } else if (type === IncomingMessageType.Do_State) {
          const { isSyncing, syncingFolders, storageSize, counts, shards } = parsedData;
          setDoState({ isSyncing, syncingFolders, storageSize, counts: counts ?? [], shards });
        }
      } catch (error) {
        console.error('error parsing party message', error, { rawMessage: message.data });
      }
    },
    [queryClient, trpc, labels, searchValue.value, setDoState],
  );

  // User's AI provider/model preferences — passed to backend so it uses the right model
  const { data: userSettings } = useSettings();

  const agent = useAgent({
    agent: 'ZeroAgent',
    name: String(activeConnection?.id ?? 'general'),
    host: `${import.meta.env.VITE_PUBLIC_BACKEND_URL}`,
    onError: (e) => console.error('[ZeroAgent] error:', e),
    onMessage,
  });

  const chatState = useAgentChat({
    getInitialMessages: async () => {
      return [];
    },
    agent,
    maxSteps: 10,
    body: {
      threadId: threadId ?? undefined,
      currentFolder: folder ?? undefined,
      currentFilter: searchValue.value ?? undefined,
      mentions: pendingMentions,
      // Send user's AI preferences so the backend can route to the right model
      aiProvider: userSettings?.settings?.aiProvider ?? 'auto',
      aiModel: userSettings?.settings?.aiModel ?? '',
      ollamaBaseUrl: userSettings?.settings?.ollamaBaseUrl ?? 'http://localhost:11434',
    },
    onError(error) {
      console.error('Error in useChat', error);
      posthog.capture('AI Chat Error', {
        error: error.message,
        threadId: threadId ?? undefined,
        currentFolder: folder ?? undefined,
        currentFilter: searchValue.value ?? undefined,
        messages: chatState.messages,
      });
      const isCreditsExhausted =
        error.message?.includes('AI_CREDITS_EXHAUSTED') ||
        error.message?.includes('ai_credits_exhausted');
      if (isCreditsExhausted) {
        // Refresh the cached billing state in case the user just upgraded in
        // another tab — and surface a clear upgrade CTA either way.
        refetchBilling().catch(() => {});
        toast.error("You're out of AI credits this period.", {
          action: {
            label: 'Upgrade',
            onClick: () => navigate('/settings/billing'),
          },
        });
      } else {
        toast.error('Error, please try again later');
      }
    },
    onResponse: (response) => {
      posthog.capture('AI Chat Response', {
        response,
        threadId: threadId ?? undefined,
        currentFolder: folder ?? undefined,
        currentFilter: searchValue.value ?? undefined,
        messages: chatState.messages,
      });
      if (!response.ok) {
        throw new Error('Failed to send message');
      }
    },
    async onToolCall({ toolCall }) {
      posthog.capture('AI Chat Tool Call', {
        toolCall,
        threadId: threadId ?? undefined,
        currentFolder: folder ?? undefined,
        currentFilter: searchValue.value ?? undefined,
        messages: chatState.messages,
      });
      switch (toolCall.toolName) {
        case Tools.CreateLabel:
        case Tools.DeleteLabel:
          await refetchLabels();
          break;
        case Tools.SendEmail:
          await queryClient.invalidateQueries({
            queryKey: trpc.mail.listThreads.queryKey({ folder: 'sent' }),
          });
          break;
        case Tools.MarkThreadsRead:
        case Tools.MarkThreadsUnread:
        case Tools.ModifyLabels:
        case Tools.BulkDelete:
          await refetchLabels();
          await Promise.all(
            (toolCall.args as { threadIds: string[] }).threadIds.map((id) =>
              queryClient.invalidateQueries({
                queryKey: trpc.mail.get.queryKey({ id }),
              }),
            ),
          );
          break;
      }
      await track({ featureId: 'chat-messages', value: 1 });
      await refetchBilling();
    },
  });

  useHotkeys('Meta+0', () => {
    setOpen(!open);
  });

  // Cmd/Ctrl+Shift+L toggles floating mode for parity with the macOS shortcut.
  useHotkeys(
    'meta+shift+l, ctrl+shift+l',
    (event) => {
      event.preventDefault();
      if (!open) setOpen(true);
      setDisplayMode(displayMode === 'floating' ? 'sidebar' : 'floating');
    },
    { enableOnFormTags: true, preventDefault: true },
    [open, displayMode, setDisplayMode, setOpen],
  );

  const handleNewChat = useCallback(() => {
    chatState.setMessages([]);
    setPendingMentions([]);
  }, [chatState]);

  const handlePromptSelect = useCallback(
    (prompt: AIPrompt) => {
      chatState
        .append({ role: 'user', content: prompt.body })
        .catch((err) => console.error('[ai-sidebar] prompt append failed', err));
    },
    [chatState],
  );

  const showPromptGallery = !groupId && chatState.messages.length === 0;

  // Shared chat body — reused across sidebar / floating / window shells so we
  // only ever mount one AIChat instance (preserves agent state).
  const chatBody = (dragHandleRef?: React.RefObject<HTMLDivElement | null>) => (
    <>
      <ChatHeader
        onClose={() => {
          setOpen(false);
          setIsFullScreen(false);
        }}
        onToggleFullScreen={() => {
          const next = !isFullScreen;
          setIsFullScreen(next);
          setDisplayMode(next ? 'full' : 'sidebar');
        }}
        onToggleViewMode={toggleViewMode}
        isFullScreen={isFullScreen}
        isPopup={isPopup}
        isPro={isPro ?? false}
        onNewChat={handleNewChat}
        activeGroupId={groupId}
        onBackFromGroup={() => setGroupId(null)}
        currentConversationId={currentConversationId}
        currentConversationTitle={currentConversationTitle}
        displayMode={displayMode}
        onChangeDisplayMode={setDisplayMode}
        dragHandleRef={dragHandleRef}
      />
      <div className="relative flex-1 overflow-hidden">
        {/* Switch between group chat and regular AI chat based on groupId param */}
        {groupId ? (
          <GroupChatView groupId={groupId} />
        ) : (
          <AIChat {...chatState} onMentionsChange={setPendingMentions} />
        )}
        {showPromptGallery && <PromptGallery prompts={AI_PROMPTS} onSelect={handlePromptSelect} />}
      </div>
    </>
  );

  // Don't render if user has no active email connection (all hooks must be called above this)
  if (!activeConnection?.id) return null;

  if (!open) return null;

  // Floating shell — fixed, draggable, resizable. Desktop-only (the existing
  // mobile popup overlay still handles small screens through the legacy path).
  if (displayMode === 'floating' && !isFullScreen) {
    return (
      <>
        <FloatingShell>
          {(dragHandleRef) => (
            <div className={cn('flex h-full flex-col', className)}>{chatBody(dragHandleRef)}</div>
          )}
        </FloatingShell>
        {/* Keep the mobile/popup overlay available on small screens. */}
        <MobilePopupShell
          isFullScreen={isFullScreen}
          isPopup={isPopup}
          className={className}
          renderBody={() => chatBody()}
        />
      </>
    );
  }

  // Detached browser window — render via portal into a new window.
  if (displayMode === 'window' && !isFullScreen) {
    return (
      <DetachedWindow onClose={() => setDisplayMode('sidebar')}>
        <div className="bg-panelLight dark:bg-panelDark flex h-full w-full flex-col">
          {chatBody()}
        </div>
      </DetachedWindow>
    );
  }

  return (
    <>
      {/* Desktop sidebar — fixed right panel, works on all pages */}
      {isSidebar && !isFullScreen && (
        <div className="bg-panelLight dark:bg-panelDark fixed bottom-1 right-1 top-2 z-40 hidden w-[360px] flex-col rounded-2xl shadow-sm md:flex">
          <div className={cn('flex h-full flex-col', className)}>{chatBody()}</div>
        </div>
      )}

      {/* Popup view - visible on small screens or when popup mode is selected */}
      <MobilePopupShell
        isFullScreen={isFullScreen}
        isPopup={isPopup}
        className={className}
        renderBody={() => chatBody()}
      />
    </>
  );
}

interface MobilePopupShellProps {
  isFullScreen: boolean;
  isPopup: boolean;
  className?: string;
  renderBody: () => React.ReactNode;
}

/**
 * Extracted from the original render so floating + window modes can still fall
 * back to the existing mobile popup on small screens without duplicating markup.
 */
function MobilePopupShell({ isFullScreen, isPopup, className, renderBody }: MobilePopupShellProps) {
  return (
    <div
      tabIndex={0}
      className={cn(
        'fixed inset-0 z-50 flex items-center justify-center bg-transparent p-4 backdrop-blur-sm transition-opacity duration-150 sm:inset-auto sm:bottom-4 sm:right-4 sm:flex-col sm:items-end sm:justify-end sm:p-0',
        'md:hidden',
        isPopup && !isFullScreen && 'md:flex',
        isFullScreen && 'inset-0! flex! p-0! opacity-100! backdrop-blur-none!',
        'rounded-2xl focus:opacity-100',
      )}
    >
      <div
        className={cn(
          'bg-panelLight dark:bg-panelDark w-full overflow-hidden rounded-2xl border border-[#E7E7E7] shadow-lg dark:border-[#252525]',
          'md:hidden',
          isPopup && !isFullScreen && 'w-[600px] max-w-[90vw] sm:w-[400px] md:block',
          isFullScreen && 'block! max-w-none! rounded-none! border-none!',
        )}
      >
        <div
          className={cn(
            'flex w-full flex-col',
            isFullScreen ? 'h-screen' : 'h-[90vh] sm:h-[600px] sm:max-h-[85vh]',
            className,
          )}
        >
          {renderBody()}
        </div>
      </div>
    </div>
  );
}

export default AISidebar;
