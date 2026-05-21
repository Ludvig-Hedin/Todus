import {
  DropdownMenu,
  DropdownMenuItem,
  DropdownMenuContent,
  DropdownMenuTrigger,
} from '../ui/dropdown-menu';
import {
  Bell,
  Lightning,
  Mail,
  PencilCompose,
  ScanEye,
  Tag,
  User,
  X,
  Search,
} from '../icons/icons';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { ResizablePanel, ResizablePanelGroup, ResizableHandle } from '@/components/ui/resizable';
import { useCategorySettings, useDefaultCategoryId } from '@/hooks/use-categories';
import { useCommandPalette } from '../context/command-palette-context';
import { useHotkeys, useHotkeysContext } from 'react-hotkeys-hook';
import { ThreadDisplay } from '@/components/mail/thread-display';
import { useCallback, useEffect, useRef, useState } from 'react';
import { useActiveConnection } from '@/hooks/use-connections';
import { Check, ChevronDown, RefreshCcw } from 'lucide-react';
import { useMediaQuery } from '../../hooks/use-media-query';
import useSearchLabels from '@/hooks/use-labels-search';
import * as CustomIcons from '@/components/icons/icons';
import { MailList } from '@/components/mail/mail-list';
import { Link, useNavigate, useParams } from 'react-router';
import { useTRPC } from '@/providers/query-provider';
import { useMail } from '@/components/mail/use-mail';
import { SidebarToggle } from '../ui/sidebar-toggle';
import { PricingDialog } from '../ui/pricing-dialog';
import { useMutation, useQuery } from '@tanstack/react-query';
import { clearBulkSelectionAtom } from './use-mail';
import { useThreads } from '@/hooks/use-threads';
import { useOptimisticActions } from '@/hooks/use-optimistic-actions';
import { toast } from 'sonner';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { useIsMobile } from '@/hooks/use-mobile';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { useSession } from '@/lib/auth-client';
import { useSettings } from '@/hooks/use-settings';
import { m } from '@/paraglide/messages';
import { isMac } from '@/lib/platform';
import { useQueryState } from 'nuqs';
import { cn } from '@/lib/utils';
import { useAtom } from 'jotai';

const LOCAL_AUTO_SYNC_INTERVAL_MS = 60_000;
const isLocalAutoSyncEnabled =
  import.meta.env.DEV &&
  String(import.meta.env.VITE_PUBLIC_BACKEND_URL ?? '').includes('localhost');

function MailAssistantNudges({ folder }: { folder: string }) {
  const trpc = useTRPC();
  const { data: settings } = useSettings();
  const [, setThreadId] = useQueryState('threadId');
  const loopsQuery = useQuery(
    trpc.assistant.listOpenLoops.queryOptions(
      { limit: 30 },
      {
        enabled:
          settings?.settings.assistantAutomationPolicy.assistantThreadActionsVisible !== false,
        staleTime: 60 * 1000,
      },
    ),
  );

  const queueLabels: Record<string, { title: string; description: string }> = {
    needs_you: {
      title: 'Needs reply',
      description: 'Threads where you appear to be the next blocker.',
    },
    waiting_on: {
      title: 'Waiting on others',
      description: 'Conversations you already moved forward and are now waiting on.',
    },
    scheduling: {
      title: 'Scheduling',
      description: 'Threads that look like meeting coordination or follow-up scheduling.',
    },
    drafts_ready: {
      title: 'Drafts ready',
      description: 'Prepared replies or thread drafts ready for review.',
    },
    likely_dropped: {
      title: 'Likely dropped',
      description: 'Open loops that are at risk of slipping without explicit tracking.',
    },
  };

  const groupedQueues = Object.entries(
    (loopsQuery.data?.loops ?? []).reduce<
      Record<string, Array<{ queue: string; threadId: string | null; summary: string }>>
    >((acc, loop) => {
      if (!acc[loop.queue]) acc[loop.queue] = [];
      acc[loop.queue].push({
        queue: loop.queue,
        threadId: loop.threadId,
        summary: loop.summary,
      });
      return acc;
    }, {}),
  )
    .map(([queue, loops]) => {
      const metadata = queueLabels[queue];
      const threadIds = Array.from(
        new Set(loops.map((loop) => loop.threadId).filter((value): value is string => Boolean(value))),
      );

      return {
        queue,
        title: metadata?.title ?? queue,
        description: metadata?.description ?? loops[0]?.summary ?? '',
        count: loops.length,
        threadIds,
      };
    })
    .filter((queue) => queue.count > 0)
    .sort((a, b) => b.count - a.count)
    .slice(0, 5);

  if (!groupedQueues.length) return null;

  return (
    <div className="px-4 pb-3">
      <div className="rounded-[18px] border border-border/60 bg-background/95 p-3 shadow-[0_1px_2px_rgba(0,0,0,0.04)] backdrop-blur-sm dark:bg-[#121212]">
        <div className="mb-2.5 flex items-start justify-between gap-3">
          <div>
            <p className="text-[10px] font-semibold uppercase tracking-[0.12em] text-muted-foreground">
              Assistant
            </p>
            <p className="mt-1 text-[12px] leading-5 text-muted-foreground">
              Your assistant grouped the inbox into the queues most likely to need attention.
            </p>
          </div>
          {loopsQuery.isFetching && <RefreshCcw className="text-muted-foreground h-3.5 w-3.5 animate-spin" />}
        </div>

        <div className="flex flex-col gap-2">
          {groupedQueues.map((queue) => (
            <button
              key={queue.queue}
              type="button"
              className="flex w-full items-start justify-between gap-3 rounded-2xl border border-border/50 bg-muted/30 px-3 py-2.5 text-left transition-colors hover:bg-muted/45 dark:bg-[#181818] dark:hover:bg-[#1d1d1d]"
              onClick={() => {
                const [firstThreadId] = queue.threadIds;
                if (firstThreadId) {
                  setThreadId(firstThreadId);
                }
              }}
            >
              <div className="space-y-0.5">
                <p className="text-[13px] font-medium tracking-[-0.01em] text-foreground">
                  {queue.title}
                </p>
                <p className="text-[12px] leading-5 text-muted-foreground">
                  {queue.description}
                </p>
              </div>
              <Badge
                variant="outline"
                className="rounded-full border-border/60 bg-background/80 px-2.5 py-0.5 text-[10px] font-medium text-muted-foreground dark:bg-[#141414]"
              >
                {queue.count}
              </Badge>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

// const AutoLabelingSettings = () => {
//   const trpc = useTRPC();
//   const [open, setOpen] = useState(false);
//   const { data: storedLabels, refetch: refetchStoredLabels } = useQuery(
//     trpc.brain.getLabels.queryOptions(void 0, {
//       staleTime: 1000 * 60 * 60, // 1 hour
//     }),
//   );
//   const { mutateAsync: updateLabels, isPending } = useMutation(
//     trpc.brain.updateLabels.mutationOptions({
//       onSuccess: () => {
//         refetchStoredLabels();
//       },
//     }),
//   );
//   const [, setPricingDialog] = useQueryState('pricingDialog');
//   const [labels, setLabels] = useState<ITag[]>([]);
//   const [newLabel, setNewLabel] = useState({ name: '', usecase: '' });
//   const { mutateAsync: EnableBrain, isPending: isEnablingBrain } = useMutation(
//     trpc.brain.enableBrain.mutationOptions(),
//   );
//   const { mutateAsync: DisableBrain, isPending: isDisablingBrain } = useMutation(
//     trpc.brain.disableBrain.mutationOptions(),
//   );
//   const { data: brainState, refetch: refetchBrainState } = useBrainState();
//   const { isLoading, isPro } = useBilling();

//   useEffect(() => {
//     if (storedLabels) {
//       setLabels(
//         storedLabels.map((label) => ({
//           id: label.name,
//           name: label.name,
//           text: label.name,
//           usecase: label.usecase,
//         })),
//       );
//     }
//   }, [storedLabels]);

//   const handleResetToDefault = useCallback(() => {
//     setLabels(
//       defaultLabels.map((label) => ({
//         id: label.name,
//         name: label.name,
//         text: label.name,
//         usecase: label.usecase,
//       })),
//     );
//   }, [storedLabels]);

//   const handleAddLabel = () => {
//     if (!newLabel.name || !newLabel.usecase) return;
//     setLabels([...labels, { id: newLabel.name, ...newLabel, text: newLabel.name }]);
//     setNewLabel({ name: '', usecase: '' });
//   };

//   const handleDeleteLabel = (id: string) => {
//     setLabels(labels.filter((label) => label.id !== id));
//   };

//   const handleUpdateLabel = (id: string, field: 'name' | 'usecase', value: string) => {
//     setLabels(
//       labels.map((label) =>
//         label.id === id
//           ? { ...label, [field]: value, text: field === 'name' ? value : label.text }
//           : label,
//       ),
//     );
//   };

//   const handleSubmit = async () => {
//     const updatedLabels = labels.map((label) => ({
//       name: label.name,
//       usecase: label.usecase,
//     }));

//     if (newLabel.name.trim() && newLabel.usecase.trim()) {
//       updatedLabels.push({
//         name: newLabel.name,
//         usecase: newLabel.usecase,
//       });
//     }
//     await updateLabels({ labels: updatedLabels });
//     setOpen(false);
//     toast.success('Labels updated successfully, Zero will start using them.');
//   };

//   const handleEnableBrain = useCallback(async () => {
//     toast.promise(EnableBrain, {
//       loading: 'Enabling autolabeling...',
//       success: 'Autolabeling enabled successfully',
//       error: 'Failed to enable autolabeling',
//       finally: async () => {
//         await refetchBrainState();
//       },
//     });
//   }, []);

//   const handleDisableBrain = useCallback(async () => {
//     toast.promise(DisableBrain, {
//       loading: 'Disabling autolabeling...',
//       success: 'Autolabeling disabled successfully',
//       error: 'Failed to disable autolabeling',
//       finally: async () => {
//         await refetchBrainState();
//       },
//     });
//   }, []);

//   const handleToggleAutolabeling = useCallback(() => {
//     if (brainState?.enabled) {
//       handleDisableBrain();
//     } else {
//       handleEnableBrain();
//     }
//   }, [brainState?.enabled]);

//   return (
//     <Dialog
//       open={open}
//       onOpenChange={(state) => {
//         if (!isPro) {
//           setPricingDialog('true');
//         } else {
//           setOpen(state);
//         }
//       }}
//     >
//       <DialogTrigger asChild>
//         <div className="flex items-center gap-2">
//           <Switch
//             disabled={isEnablingBrain || isDisablingBrain || isLoading}
//             checked={brainState?.enabled ?? false}
//           />
//           <span className="text-muted-foreground cursor-pointer text-xs font-medium">
//             Auto label
//           </span>
//         </div>
//       </DialogTrigger>
//       <DialogContent showOverlay className="max-w-2xl">
//         <DialogHeader>
//           <div className="flex items-center justify-between">
//             <DialogTitle>Label Settings</DialogTitle>
//             <button
//               onClick={handleToggleAutolabeling}
//               className="bg-offsetLight dark:bg-offsetDark flex items-center gap-2 rounded-lg border px-1.5 py-1"
//             >
//               <span className="text-muted-foreground text-sm">
//                 {isEnablingBrain || isDisablingBrain
//                   ? 'Updating...'
//                   : brainState?.enabled
//                     ? 'Disable autolabeling'
//                     : 'Enable autolabeling'}
//               </span>
//               <Switch checked={brainState?.enabled} />
//             </button>
//           </div>
//           <DialogDescription className="mt-2">
//             Configure the labels that Zero uses to automatically organize your emails.
//           </DialogDescription>
//         </DialogHeader>

//         <ScrollArea className="h-[400px]">
//           <div className="space-y-3">
//             {labels.map((label, index) => (
//               <div
//                 key={label.id}
//                 className="bg-card group relative space-y-2 rounded-lg border p-4 shadow-sm transition-shadow hover:shadow-md"
//               >
//                 <div className="flex items-center justify-between">
//                   <Label
//                     htmlFor={`label-name-${index}`}
//                     className="text-muted-foreground text-xs font-medium"
//                   >
//                     Label Name
//                   </Label>
//                   <Button
//                     variant="ghost"
//                     size="icon"
//                     className="h-6 w-6 transition-opacity group-hover:opacity-100"
//                     onClick={() => handleDeleteLabel(label.id)}
//                   >
//                     <Trash className="h-3 w-3 fill-[#F43F5E]" />
//                   </Button>
//                 </div>
//                 <Input
//                   id={`label-name-${index}`}
//                   type="text"
//                   value={label.name}
//                   onChange={(e: React.ChangeEvent<HTMLInputElement>) =>
//                     handleUpdateLabel(label.id, 'name', e.target.value)
//                   }
//                   className="h-8"
//                   placeholder="e.g., Important, Follow-up, Archive"
//                 />
//                 <div className="space-y-2">
//                   <Label
//                     htmlFor={`label-usecase-${index}`}
//                     className="text-muted-foreground text-xs font-medium"
//                   >
//                     Use Case Description
//                   </Label>
//                   <Textarea
//                     id={`label-usecase-${index}`}
//                     value={label.usecase}
//                     onChange={(e: React.ChangeEvent<HTMLTextAreaElement>) =>
//                       handleUpdateLabel(label.id, 'usecase', e.target.value)
//                     }
//                     className="min-h-[60px] resize-none"
//                     placeholder="Describe when this label should be applied..."
//                   />
//                 </div>
//               </div>
//             ))}

//             <div className="bg-muted/50 mt-3 space-y-2 rounded-lg border border-dashed p-4">
//               <div className="space-y-2">
//                 <Label
//                   htmlFor="new-label-name"
//                   className="text-muted-foreground text-xs font-medium"
//                 >
//                   New Label Name
//                 </Label>
//                 <Input
//                   id="new-label-name"
//                   type="text"
//                   value={newLabel.name}
//                   onChange={(e: React.ChangeEvent<HTMLInputElement>) =>
//                     setNewLabel({ ...newLabel, name: e.target.value })
//                   }
//                   className="h-8 dark:bg-[#141414]"
//                   placeholder="Enter a new label name"
//                 />
//               </div>
//               <div className="space-y-2">
//                 <Label
//                   htmlFor="new-label-usecase"
//                   className="text-muted-foreground text-xs font-medium"
//                 >
//                   Use Case Description
//                 </Label>
//                 <Textarea
//                   id="new-label-usecase"
//                   value={newLabel.usecase}
//                   onChange={(e: React.ChangeEvent<HTMLTextAreaElement>) =>
//                     setNewLabel({ ...newLabel, usecase: e.target.value })
//                   }
//                   className="min-h-[60px] resize-none dark:bg-[#141414]"
//                   placeholder="Describe when this label should be applied..."
//                 />
//               </div>
//               <Button
//                 className="mt-2 h-8 w-full"
//                 onClick={handleAddLabel}
//                 disabled={!newLabel.name || !newLabel.usecase}
//               >
//                 Add New Label
//               </Button>
//             </div>
//           </div>
//         </ScrollArea>
//         <DialogFooter className="mt-4">
//           <div className="flex w-full justify-end gap-2">
//             <Button size="xs" variant="outline" onClick={handleResetToDefault}>
//               Default Labels
//             </Button>
//             <Button size="xs" onClick={handleSubmit} disabled={isPending}>
//               Save Changes
//             </Button>
//           </div>
//         </DialogFooter>
//       </DialogContent>
//     </Dialog>
//   );
// };

export function MailLayout() {
  const params = useParams<{ folder: string }>();
  const folder = params?.folder ?? 'inbox';
  const [mail, setMail] = useMail();
  const [, clearBulkSelection] = useAtom(clearBulkSelectionAtom);
  const isMobile = useIsMobile();
  const navigate = useNavigate();
  const { data: session, isPending } = useSession();
  const prevFolderRef = useRef(folder);
  const { enableScope, disableScope } = useHotkeysContext();
  const { data: activeConnection } = useActiveConnection();
  const { activeFilters, clearAllFilters } = useCommandPalette();
  const [, setIsCommandPaletteOpen] = useQueryState('isCommandPaletteOpen');
  const localAutoSyncInFlightRef = useRef(false);
  const trpc = useTRPC();

  useEffect(() => {
    if (prevFolderRef.current !== folder && mail.bulkSelected.length > 0) {
      clearBulkSelection();
    }
    prevFolderRef.current = folder;
  }, [folder, mail.bulkSelected.length, clearBulkSelection]);

  useEffect(() => {
    if (!session?.user && !isPending) {
      navigate('/login');
    }
  }, [session?.user, isPending, navigate]);

  const [{ isFetching, refetch: refetchThreads }, threadItems] = useThreads();
  const { mutateAsync: forceSync } = useMutation(trpc.mail.forceSync.mutationOptions());
  const isDesktop = useMediaQuery('(min-width: 768px)');
  const { optimisticMarkAsRead } = useOptimisticActions();

  // Mark every visible unread thread as read. Mirrors macOS ⌘⇧M behavior.
  // Folder is captured at call time, so this naturally respects whichever
  // folder the user is viewing.
  const handleMarkAllRead = useCallback(() => {
    const unreadIds = (threadItems ?? [])
      .filter((t: { id: string; hasUnread?: boolean }) => t.hasUnread !== false)
      .map((t: { id: string }) => t.id);
    if (unreadIds.length === 0) {
      toast('No unread messages here');
      return;
    }
    optimisticMarkAsRead(unreadIds);
  }, [threadItems, optimisticMarkAsRead]);

  useHotkeys('meta+shift+m, ctrl+shift+m', (event) => {
    event.preventDefault();
    handleMarkAllRead();
  }, { enableOnFormTags: false });

  const [threadId] = useQueryState('threadId');

  useEffect(() => {
    if (threadId) {
      console.log('Enabling thread-display scope, disabling mail-list');
      enableScope('thread-display');
      disableScope('mail-list');
    } else {
      console.log('Enabling mail-list scope, disabling thread-display');
      enableScope('mail-list');
      disableScope('thread-display');
    }

    return () => {
      console.log('Cleaning up mail/thread scopes');
      disableScope('thread-display');
      disableScope('mail-list');
    };
  }, [threadId, enableScope, disableScope]);

  //   const handleMailListMouseEnter = useCallback(() => {
  //     enableScope('mail-list');
  //   }, [enableScope]);

  //   const handleMailListMouseLeave = useCallback(() => {
  //     disableScope('mail-list');
  //   }, [disableScope]);

  // Add mailto protocol handler registration
  useEffect(() => {
    // Register as a mailto protocol handler if browser supports it
    if (typeof window !== 'undefined' && 'registerProtocolHandler' in navigator) {
      try {
        // Register the mailto protocol handler
        // When a user clicks a mailto: link, it will be passed to our dedicated handler
        // which will:
        // 1. Parse the mailto URL to extract email, subject and body
        // 2. Create a draft with these values
        // 3. Redirect to the compose page with just the draft ID
        // This ensures we don't keep the email content in the URL
        navigator.registerProtocolHandler('mailto', `/api/mailto-handler?mailto=%s`);
      } catch (error) {
        console.error('Failed to register protocol handler:', error);
      }
    }
  }, []);

  const defaultCategoryId = useDefaultCategoryId();
  const [category] = useQueryState('category', { defaultValue: defaultCategoryId });

  const handleClearFilters = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      clearAllFilters();
    },
    [clearAllFilters],
  );

  const handleExitBulkSelection = useCallback(() => {
    setMail({ ...mail, bulkSelected: [] });
  }, [mail, setMail]);

  const runLocalAutoSync = useCallback(
    async (skipWhenHidden: boolean = true) => {
      if (!isLocalAutoSyncEnabled) return;
      if (!session?.user?.id || !activeConnection?.id) return;
      if (
        skipWhenHidden &&
        typeof document !== 'undefined' &&
        document.visibilityState === 'hidden'
      ) {
        return;
      }
      if (localAutoSyncInFlightRef.current) return;

      localAutoSyncInFlightRef.current = true;

      try {
        await forceSync();
        await refetchThreads();
      } catch (error) {
        console.error('Local auto-sync failed:', error);
      } finally {
        localAutoSyncInFlightRef.current = false;
      }
    },
    [activeConnection?.id, forceSync, refetchThreads, session?.user?.id],
  );

  const handleRefetchThreads = useCallback(() => {
    if (isLocalAutoSyncEnabled) {
      void runLocalAutoSync(false);
      return;
    }

    refetchThreads();
  }, [refetchThreads, runLocalAutoSync]);

  useEffect(() => {
    if (!isLocalAutoSyncEnabled) return;

    void runLocalAutoSync(false);

    const intervalId = window.setInterval(() => {
      void runLocalAutoSync();
    }, LOCAL_AUTO_SYNC_INTERVAL_MS);

    const handleWindowFocus = () => {
      void runLocalAutoSync();
    };

    const handleVisibilityChange = () => {
      if (document.visibilityState === 'visible') {
        void runLocalAutoSync();
      }
    };

    window.addEventListener('focus', handleWindowFocus);
    document.addEventListener('visibilitychange', handleVisibilityChange);

    return () => {
      window.clearInterval(intervalId);
      window.removeEventListener('focus', handleWindowFocus);
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    };
  }, [runLocalAutoSync]);

  const handleOpenCommandPalette = useCallback(() => {
    setIsCommandPaletteOpen('true');
  }, [setIsCommandPaletteOpen]);

  return (
    <TooltipProvider delayDuration={0}>
      <PricingDialog />
      <div className="rounded-inherit z-5 relative flex p-0 md:mr-0.5 md:mt-1">
        <ResizablePanelGroup
          direction="horizontal"
          autoSaveId="mail-panel-layout"
          className="rounded-inherit overflow-hidden"
        >
          <ResizablePanel
            id="mail-list"
            order={1}
            defaultSize={35}
            minSize={35}
            maxSize={35}
            className={cn(
              `bg-panelLight dark:bg-panelDark mb-1 w-fit shadow-sm md:mr-[3px] md:rounded-2xl lg:flex lg:h-[calc(100dvh-8px)] lg:shadow-sm`,
              isDesktop && threadId && 'hidden lg:block',
            )}
            // onMouseEnter={handleMailListMouseEnter}
            // onMouseLeave={handleMailListMouseLeave}
          >
            <div className="w-full md:h-[calc(100dvh-10px)]">
              <div className="z-15 sticky top-0 p-4 pb-0">
                <div className="flex items-center gap-2">
                  <SidebarToggle className="h-10 w-10" />

                  {mail.bulkSelected.length === 0 ? (
                    <>
                      <Button
                        variant="outline"
                        className={cn(
                          'text-muted-foreground border-border/40 bg-background/50 hover:bg-accent/30 focus-visible:ring-ring dark:border-border/20 dark:bg-background/40 relative flex h-10 flex-1 select-none items-center justify-start overflow-hidden rounded-2xl border pl-3 text-left text-sm font-normal shadow-none ring-0 backdrop-blur-sm transition-all focus-visible:ring-2 focus-visible:ring-offset-2',
                        )}
                        onClick={handleOpenCommandPalette}
                      >
                        <Search className="fill-muted-foreground h-4 w-4" />

                        <span className="ml-3 hidden truncate pr-20 lg:inline-block">
                          {activeFilters.length > 0
                            ? activeFilters.map((f) => f.display).join(', ')
                            : 'Search or filter mail'}
                        </span>
                        <span className="ml-3 inline-block truncate pr-20 lg:hidden">
                          {activeFilters.length > 0
                            ? `${activeFilters.length} filter${activeFilters.length > 1 ? 's' : ''}`
                            : 'Search mail'}
                        </span>

                        <div className="absolute right-2 flex items-center gap-2">
                          {/* {activeFilters.length > 0 && (
                            <Badge variant="secondary" className="ml-2 h-5 rounded px-1">
                              {activeFilters.length}
                            </Badge>
                          )} */}
                          {activeFilters.length > 0 && (
                            <Button
                              variant="secondary"
                              size="sm"
                              className="h-6 rounded-full px-2 text-xs"
                              onClick={handleClearFilters}
                            >
                              Clear filters
                            </Button>
                          )}
                          <kbd className="bg-muted border-border/40 dark:bg-muted/40 pointer-events-none hidden h-6 select-none items-center gap-1 rounded border px-2 text-xs font-medium opacity-80 sm:flex">
                            <span className={cn('text-xs', isMac ? 'text-sm' : 'text-xs')}>
                              {isMac ? '⌘' : 'Ctrl'}
                            </span>
                            <span className="text-xs">K</span>
                          </kbd>
                        </div>
                      </Button>

                      {activeConnection?.providerId === 'google' && folder === 'inbox' && (
                        <CategoryDropdown isMultiSelectMode={mail.bulkSelected.length > 0} />
                      )}
                      <Tooltip>
                        <TooltipTrigger asChild>
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-10 w-10 shrink-0 rounded-2xl"
                            onClick={handleMarkAllRead}
                            aria-label="Mark all as read"
                          >
                            <Check className="h-4 w-4" />
                          </Button>
                        </TooltipTrigger>
                        <TooltipContent>
                          <span className="text-xs">
                            Mark all as read
                            <kbd className="bg-muted ml-2 rounded border px-1 py-0.5 text-[10px]">
                              {isMac ? '⌘⇧M' : 'Ctrl ⇧ M'}
                            </kbd>
                          </span>
                        </TooltipContent>
                      </Tooltip>
                      <DailyBriefBell />
                    </>
                  ) : (
                    <div className="flex flex-1 items-center justify-between">
                      <div className="text-foreground text-sm font-medium">
                        {mail.bulkSelected.length} selected
                      </div>
                      <Tooltip>
                        <TooltipTrigger asChild>
                          <Button
                            variant="secondary"
                            size="sm"
                            onClick={handleExitBulkSelection}
                            className="h-8 gap-2 rounded-full"
                          >
                            <X className="h-3 w-3" />
                            <span className="text-xs">ESC</span>
                          </Button>
                        </TooltipTrigger>
                        <TooltipContent>
                          {m['common.actions.exitSelectionModeEsc']()}
                        </TooltipContent>
                      </Tooltip>
                    </div>
                  )}

                  <Button
                    onClick={handleRefetchThreads}
                    variant="ghost"
                    size="icon"
                    className="hover:bg-accent/50 h-10 w-10 rounded-full border-none bg-transparent backdrop-blur-sm"
                  >
                    <RefreshCcw className="text-muted-foreground h-4 w-4" />
                  </Button>
                </div>
              </div>

              <div className="px-4 pt-2">
                <div
                  className={cn(
                    `${category === 'Important' ? 'bg-[#F59E0D]' : category === 'All Mail' ? 'bg-[#006FFE]' : category === 'Personal' ? 'bg-[#39ae4a]' : category === 'Updates' ? 'bg-[#8B5CF6]' : category === 'Promotions' ? 'bg-[#F43F5E]' : category === 'Unread' ? 'bg-[#FF4800]' : 'bg-[#F59E0D]'}`,
                    'h-0.5 w-full rounded-full transition-opacity',
                    isFetching ? 'opacity-100' : 'opacity-0',
                  )}
                />
              </div>

              <div className="z-1 relative flex h-[calc(100dvh-(2px+2px))] flex-col overflow-hidden pt-0 md:h-[calc(100dvh-4rem)]">
                <MailAssistantNudges folder={folder} />
                <div className="min-h-0 flex-1">
                  <MailList />
                </div>
              </div>
            </div>
          </ResizablePanel>

          <ResizableHandle className="mr-0.5 hidden opacity-0 md:block" />

          {isDesktop && (
            <ResizablePanel
              id="thread-display"
              order={2}
              className={cn(
                'bg-panelLight dark:bg-panelDark mb-1 mr-0.5 w-fit rounded-2xl shadow-sm lg:h-[calc(100dvh-8px)]',
                // Only show on md screens and larger when there is a threadId
                !threadId && 'hidden lg:block',
              )}
              defaultSize={30}
              minSize={30}
            >
              <div className="relative flex-1">
                <ThreadDisplay />
              </div>
            </ResizablePanel>
          )}

          {/* Mobile Thread View */}
          {isMobile && threadId && (
            <div className="bg-panelLight dark:bg-panelDark fixed inset-0 z-50">
              <div className="flex h-full flex-col">
                <div className="h-full overflow-y-auto outline-none">
                  <ThreadDisplay />
                </div>
              </div>
            </div>
          )}

        </ResizablePanelGroup>
      </div>
      {isMobile && <ComposeFloatingButton />}
    </TooltipProvider>
  );
}

// Floating compose button for mobile — opens the compose dialog
function ComposeFloatingButton() {
  const [, setDialogOpen] = useQueryState('isComposeOpen');
  const [, setDraftId] = useQueryState('draftId');
  const [, setTo] = useQueryState('to');
  const [, setActiveReplyId] = useQueryState('activeReplyId');
  const [, setMode] = useQueryState('mode');

  const handleCompose = async () => {
    await setDraftId(null);
    await setTo(null);
    await setActiveReplyId(null);
    await setMode(null);
    await setDialogOpen('true');
  };

  return (
    <button
      onClick={handleCompose}
      aria-label="Compose email"
      className="bg-mainBlue hover:bg-mainBlue/90 fixed bottom-20 right-4 z-50 flex h-14 w-14 items-center justify-center rounded-full shadow-lg transition-colors md:hidden"
    >
      <PencilCompose className="h-5 w-5 fill-white" aria-hidden="true" />
    </button>
  );
}

interface CategoryItem {
  id: string;
  name: string;
  searchValue: string;
  icon?: React.ReactNode;
  colors?: string;
}

export const Categories = () => {
  const defaultCategoryIdInner = useDefaultCategoryId();
  const categorySettings = useCategorySettings();
  const [activeCategory] = useQueryState('category', {
    defaultValue: defaultCategoryIdInner,
  });

  const categories = categorySettings.map((cat) => {
    const base = {
      id: cat.id,
      name: (() => {
        const key = `common.mailCategories.${cat.id
          .split(' ')
          .map((w, i) => (i === 0 ? w.toLowerCase() : w))
          .join('')}` as keyof typeof m;
        return m[key] && typeof m[key] === 'function' ? (m[key] as () => string)() : cat.name;
      })(),
      searchValue: cat.searchValue,
    } as const;

    // Helper to decide fill colour depending on selection
    const isSelected = activeCategory === cat.id;
    if (cat.icon && cat.icon in CustomIcons) {
      const DynamicIcon = CustomIcons[cat.icon as keyof typeof CustomIcons];
      return {
        ...base,
        icon: (
          <DynamicIcon
            className={cn(
              'fill-muted-foreground h-4 w-4 dark:fill-white',
              isSelected && 'fill-white',
            )}
          />
        ),
      };
    }

    switch (cat.id) {
      case 'Important':
        return {
          ...base,
          icon: (
            <Lightning
              className={cn('fill-muted-foreground dark:fill-white', isSelected && 'fill-white')}
            />
          ),
        };
      case 'All Mail':
        return {
          ...base,
          icon: (
            <Mail
              className={cn('fill-muted-foreground dark:fill-white', isSelected && 'fill-white')}
            />
          ),
          colors: 'border-0 bg-mainBlue text-white hover:bg-mainBlue/90',
        };
      case 'Personal':
        return {
          ...base,
          icon: (
            <User
              className={cn('fill-muted-foreground dark:fill-white', isSelected && 'fill-white')}
            />
          ),
        };
      case 'Promotions':
        return {
          ...base,
          icon: (
            <Tag
              className={cn('fill-muted-foreground dark:fill-white', isSelected && 'fill-white')}
            />
          ),
        };
      case 'Updates':
        return {
          ...base,
          icon: (
            <Bell
              className={cn('fill-muted-foreground dark:fill-white', isSelected && 'fill-white')}
            />
          ),
        };
      case 'Unread':
        return {
          ...base,
          icon: (
            <ScanEye
              className={cn(
                'fill-muted-foreground h-4 w-4 dark:fill-white',
                isSelected && 'fill-white',
              )}
            />
          ),
        };
      default:
        return base;
    }
  });

  return categories as CategoryItem[];
};
interface CategoryDropdownProps {
  isMultiSelectMode?: boolean;
}

function CategoryDropdown({ isMultiSelectMode }: CategoryDropdownProps) {
  const categorySettings = useCategorySettings();
  const { setLabels, labels } = useSearchLabels();
  const params = useParams<{ folder: string }>();
  const folder = params?.folder ?? 'inbox';
  const [isOpen, setIsOpen] = useState(false);

  useHotkeys(
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    (key) => {
      const category = categorySettings[Number(key.key) - 1];
      if (!category) return;
      const isCurrentlyActive = labels.includes(category.searchValue);

      if (isCurrentlyActive) {
        setLabels(labels.filter((label) => label !== category.searchValue));
      } else {
        setLabels([...labels, category.searchValue]);
      }
    },
    {
      scopes: ['mail-list'],
      preventDefault: true,
      enableOnFormTags: false,
    },
  );

  const handleLabelChange = (searchValue: string) => {
    const trimmed = searchValue.trim();
    if (!trimmed) {
      setLabels([]);
      return;
    }

    const parsedLabels = trimmed
      .split(',')
      .map((label) => label.trim())
      .filter((label) => label.length > 0);

    if (parsedLabels.length === 0) {
      setLabels([]);
      return;
    }

    const currentLabelsSet = new Set(labels);
    const parsedLabelsSet = new Set(parsedLabels);

    const allLabelsSelected = parsedLabels.every((label) => currentLabelsSet.has(label));

    if (allLabelsSelected) {
      const updatedLabels = labels.filter((label) => !parsedLabelsSet.has(label));
      setLabels(updatedLabels);
    } else {
      const newLabelsSet = new Set([...labels, ...parsedLabels]);
      setLabels(Array.from(newLabelsSet));
    }
  };

  if (folder !== 'inbox' || isMultiSelectMode) return null;

  return (
    <DropdownMenu open={isOpen} onOpenChange={setIsOpen}>
      <DropdownMenuTrigger asChild>
        <Button
          variant="outline"
          className={cn(
            'text-muted-foreground border-border/40 bg-background/50 hover:bg-accent/30 dark:border-border/20 dark:bg-background/40 flex h-10 min-w-fit items-center gap-2 rounded-lg border px-3 backdrop-blur-sm transition-all',
          )}
          aria-label="Filter inbox"
          aria-expanded={isOpen}
          aria-haspopup="menu"
        >
          <span className="text-sm font-medium">
            {labels.length > 0
              ? `${labels.length} filter${labels.length > 1 ? 's' : ''}`
              : 'Filter inbox'}
          </span>
          <ChevronDown
            className={cn(
              'text-muted-foreground h-4 w-4 transition-transform duration-200',
              isOpen ? 'rotate-180' : 'rotate-0',
            )}
          />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent
        className="border-border/50 bg-popover w-48 rounded-xl border p-2"
        align="start"
        role="menu"
        aria-label="Label filter options"
      >
        {categorySettings.map((category) => (
          <DropdownMenuItem
            key={category.id}
            className="hover:bg-accent/50 flex cursor-pointer items-center gap-3 rounded-lg px-3 py-2.5 text-sm transition-colors"
            onClick={(e) => {
              e.preventDefault();
              e.stopPropagation();
              handleLabelChange(category.searchValue);
            }}
            role="menuitemcheckbox"
            aria-checked={
              category.searchValue === ''
                ? labels.length === 0
                : category.searchValue.split(',').some((value) => labels.includes(value))
            }
          >
            <span className="text-foreground font-medium capitalize">
              {category.name.toLowerCase()}
            </span>
            {/* Special case: empty searchValue means "All Mail" - shows everything */}
            {(category.searchValue === ''
              ? labels.length === 0
              : category.searchValue.split(',').some((val) => labels.includes(val))) && (
              <Check className="text-primary ml-auto h-4 w-4" />
            )}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

// ─── DailyBriefBell ─────────────────────────────────────────────────────────
// Compact AI digest popover. Mirrors macOS `MacNotificationCenterView` so
// users can glance at the most urgent reply, next event, and top task from
// any mail page without bouncing through /mail/home.
const BRIEF_SEEN_KEY = 'mail.dailyBrief.lastSeen';

function DailyBriefBell() {
  const trpc = useTRPC();
  const { data: briefing, isLoading } = useQuery(
    trpc.assistant.getBriefing.queryOptions(undefined, { staleTime: 60_000 }),
  );

  // Track when the user last viewed the brief so the "unread" dot can be
  // dismissed by simply opening the popover. Without this the dot was
  // permanent even after the user had clearly seen the content.
  const [lastSeenAt, setLastSeenAt] = useState<number>(() => {
    if (typeof window === 'undefined') return 0;
    try {
      const raw = window.localStorage.getItem(BRIEF_SEEN_KEY);
      return raw ? Number(raw) : 0;
    } catch {
      return 0;
    }
  });
  const itemCount =
    (briefing?.needsYou?.length ?? 0) +
    (briefing?.waitingOn?.length ?? 0) +
    (briefing?.prepared?.length ?? 0);
  // `briefing.updatedAt` would be ideal — fall back to: "show dot until user
  // opens the popover at least once after the brief query finished."
  const briefingLoadedAt = briefing ? Date.now() : 0;
  const hasUnseen = itemCount > 0 && briefingLoadedAt > lastSeenAt;

  const markSeen = () => {
    const now = Date.now();
    setLastSeenAt(now);
    try {
      window.localStorage.setItem(BRIEF_SEEN_KEY, String(now));
    } catch {
      // ignore
    }
  };

  return (
    <Popover onOpenChange={(open) => open && markSeen()}>
      <PopoverTrigger asChild>
        <Button
          variant="ghost"
          size="icon"
          className="relative h-10 w-10 shrink-0 rounded-2xl"
          aria-label="Daily brief"
        >
          <Bell className="h-4 w-4" />
          {hasUnseen && (
            <span className="absolute right-2 top-2 h-1.5 w-1.5 rounded-full bg-mainBlue" />
          )}
        </Button>
      </PopoverTrigger>
      <PopoverContent align="end" className="w-[340px] p-3">
        <div className="mb-2 flex items-center justify-between">
          <p className="text-[12px] font-semibold uppercase tracking-wider text-muted-foreground">
            Today's brief
          </p>
          <Link to="/mail/home" className="text-[11px] text-muted-foreground hover:text-foreground">
            View full
          </Link>
        </div>
        {isLoading ? (
          <div className="space-y-2">
            {['s1', 's2', 's3'].map((k) => (
              <div key={k} className="bg-muted/50 h-12 animate-pulse rounded-lg" />
            ))}
          </div>
        ) : !briefing ? (
          <p className="py-4 text-center text-[12px] text-muted-foreground">
            No brief available yet.
          </p>
        ) : (
          <div className="space-y-2">
            {briefing.today?.urgentReply ? (
              <Link
                to={
                  briefing.today.urgentReply.threadId
                    ? `/mail/inbox?threadId=${briefing.today.urgentReply.threadId}`
                    : '/mail/inbox'
                }
                className="block rounded-md border bg-muted/15 px-3 py-2 hover:bg-accent/60"
              >
                <p className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground">
                  Urgent reply
                </p>
                <p className="mt-0.5 line-clamp-2 text-[13px] font-medium">
                  {briefing.today.urgentReply.title}
                </p>
              </Link>
            ) : null}
            {briefing.today?.nextEvent ? (
              <Link
                to={`/mail/meetings/${briefing.today.nextEvent.id}`}
                className="block rounded-md border bg-muted/15 px-3 py-2 hover:bg-accent/60"
              >
                <p className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground">
                  Next event
                </p>
                <p className="mt-0.5 line-clamp-2 text-[13px] font-medium">
                  {briefing.today.nextEvent.title}
                </p>
              </Link>
            ) : null}
            {briefing.today?.topTask ? (
              <Link
                to="/mail/tasks"
                className="block rounded-md border bg-muted/15 px-3 py-2 hover:bg-accent/60"
              >
                <p className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground">
                  Top task
                </p>
                <p className="mt-0.5 line-clamp-2 text-[13px] font-medium">
                  {briefing.today.topTask.title}
                </p>
              </Link>
            ) : null}
            {!briefing.today?.urgentReply &&
              !briefing.today?.nextEvent &&
              !briefing.today?.topTask && (
                <p className="py-4 text-center text-[12px] text-muted-foreground">
                  You're all caught up.
                </p>
              )}
          </div>
        )}
      </PopoverContent>
    </Popover>
  );
}
