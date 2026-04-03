import {
  Archive2,
  ExclamationCircle,
  GroupPeople,
  Star2,
  Trash,
  PencilCompose,
} from '../icons/icons';
import {
  memo,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  type ComponentProps,
  useState,
} from 'react';
import { useOptimisticThreadState } from '@/components/mail/optimistic-thread-state';
import { focusedIndexAtom, useMailNavigation } from '@/hooks/use-mail-navigation';
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip';
import { useIsFetching, useIsRestoring, useQuery, useInfiniteQuery, type UseQueryResult } from '@tanstack/react-query';
import type { MailSelectMode, ParsedMessage, ThreadProps } from '@/types';
import type { ParsedDraft } from '../../../server/src/lib/driver/types';
import { ThreadContextMenu } from '@/components/context/thread-context';
import { useOptimisticActions } from '@/hooks/use-optimistic-actions';
import { useMail, type Config } from '@/components/mail/use-mail';
import { type ThreadDestination } from '@/lib/thread-actions';
import { useThread, useThreads } from '@/hooks/use-threads';
import { useSearchValue } from '@/hooks/use-search-value';
import { EmptyStateIcon } from '../icons/empty-state-svg';
import { highlightText } from '@/lib/email-utils.client';
import { cn, FOLDERS, formatDate } from '@/lib/utils';
import { useTRPC } from '@/providers/query-provider';
import { useThreadLabels } from '@/hooks/use-labels';
import { useSettings } from '@/hooks/use-settings';
import { useKeyState } from '@/hooks/use-hot-key';
import { VList, type VListHandle } from 'virtua';
import { BimiAvatar } from '../ui/bimi-avatar';
import { RenderLabels } from './render-labels';
import { Badge } from '@/components/ui/badge';
import { useDraft } from '@/hooks/use-drafts';
import { Check, Star, ChevronRight, ChevronLeft, Users } from 'lucide-react';
import { Skeleton } from '../ui/skeleton';
import { m } from '@/paraglide/messages';
import { useParams } from 'react-router';
import { Button } from '../ui/button';
import { Avatar } from '../ui/avatar';
import { useQueryState } from 'nuqs';
import { useAtom } from 'jotai';

const Thread = memo(
  function Thread({
    message,
    onClick,
    isKeyboardFocused,
    index,
  }: ThreadProps & { index?: number }) {
    const [searchValue] = useSearchValue();
    const { folder } = useParams<{ folder: string }>();
    const [, threads] = useThreads();
    const [threadId] = useQueryState('threadId');
    const { data: getThreadData, isGroupThread, latestDraft } = useThread(message.id);
    const [id, setThreadId] = useQueryState('threadId');
    const [focusedIndex, setFocusedIndex] = useAtom(focusedIndexAtom);

    const { latestMessage, idToUse, cleanName } = useMemo(() => {
      const latestMessage = getThreadData?.latest;
      const idToUse = latestMessage?.threadId ?? latestMessage?.id;
      const cleanName = latestMessage?.sender?.name
        ? latestMessage.sender.name.trim().replace(/^['"]|['"]$/g, '')
        : '';

      return { latestMessage, idToUse, cleanName };
    }, [getThreadData?.latest]);

    const optimisticState = useOptimisticThreadState(idToUse ?? '');

    const { displayStarred, displayImportant, displayUnread, optimisticLabels, emailContent } =
      useMemo(() => {
        const emailContent = getThreadData?.latest?.body;
        const displayStarred =
          optimisticState.optimisticStarred !== null
            ? optimisticState.optimisticStarred
            : (getThreadData?.latest?.tags?.some((tag) => tag.name === 'STARRED') ?? false);

        const displayImportant =
          optimisticState.optimisticImportant !== null
            ? optimisticState.optimisticImportant
            : (getThreadData?.latest?.tags?.some((tag) => tag.name === 'IMPORTANT') ?? false);

        const displayUnread =
          optimisticState.optimisticRead !== null
            ? !optimisticState.optimisticRead
            : (getThreadData?.hasUnread ?? false);

        let labels: { id: string; name: string }[] = [];
        if (getThreadData?.labels) {
          labels = [...getThreadData.labels];
          const hasStarredLabel = labels.some((label) => label.name === 'STARRED');

          if (optimisticState.optimisticStarred !== null) {
            if (optimisticState.optimisticStarred && !hasStarredLabel) {
              labels.push({ id: 'starred-optimistic', name: 'STARRED' });
            } else if (!optimisticState.optimisticStarred && hasStarredLabel) {
              labels = labels.filter((label) => label.name !== 'STARRED');
            }
          }

          if (optimisticState.optimisticLabels) {
            labels = labels.filter(
              (label) => !optimisticState.optimisticLabels.removedLabelIds.includes(label.id),
            );

            optimisticState.optimisticLabels.addedLabelIds.forEach((labelId) => {
              if (!labels.some((label) => label.id === labelId)) {
                labels.push({ id: labelId, name: labelId });
              }
            });
          }
        }

        return {
          displayStarred,
          displayImportant,
          displayUnread,
          optimisticLabels: labels,
          emailContent,
        };
      }, [
        optimisticState.optimisticStarred,
        optimisticState.optimisticImportant,
        optimisticState.optimisticRead,
        getThreadData?.latest?.tags,
        getThreadData?.hasUnread,
        getThreadData?.labels,
        optimisticState.optimisticLabels,
      ]);

    const { optimisticToggleStar, optimisticToggleImportant, optimisticMoveThreadsTo } =
      useOptimisticActions();

    const handleToggleStar = useCallback(
      async (e: React.MouseEvent) => {
        e.stopPropagation();
        if (!getThreadData || !idToUse) return;

        const newStarredState = !displayStarred;
        optimisticToggleStar([idToUse], newStarredState);
      },
      [getThreadData, idToUse, displayStarred, optimisticToggleStar],
    );

    const handleToggleImportant = useCallback(
      async (e: React.MouseEvent) => {
        e.stopPropagation();
        if (!getThreadData || !idToUse) return;

        const newImportantState = !displayImportant;
        optimisticToggleImportant([idToUse], newImportantState);
      },
      [getThreadData, idToUse, displayImportant, optimisticToggleImportant],
    );

    const handleNext = useCallback(
      (id: string) => {
        if (!id || !threads.length || focusedIndex === null) return setThreadId(null);
        if (focusedIndex < threads.length - 1) {
          const nextThread = threads[focusedIndex];
          if (nextThread) {
            setThreadId(nextThread.id);
            // Don't clear activeReplyId - let ThreadDisplay handle Reply All auto-opening
            setFocusedIndex(focusedIndex);
          }
        }
      },
      [threads, id, focusedIndex],
    );

    const moveThreadTo = useCallback(
      async (destination: ThreadDestination) => {
        if (!idToUse) return;
        handleNext(idToUse);
        optimisticMoveThreadsTo([idToUse], folder ?? '', destination);
      },
      [idToUse, folder, optimisticMoveThreadsTo, handleNext],
    );

    const { labels: threadLabels } = useThreadLabels(
      optimisticLabels ? optimisticLabels.map((l) => l.id) : [],
    );

    const [mailState, setMail] = useMail();
    const { isMailSelected, isMailBulkSelected } = useMemo(() => {
      const isSelected =
        !threadId || !idToUse ? false : idToUse === threadId || threadId === mailState.selected;
      const isBulkSelected = idToUse ? mailState.bulkSelected.includes(idToUse) : false;

      return { isMailSelected: isSelected, isMailBulkSelected: isBulkSelected };
    }, [threadId, idToUse, mailState.selected, mailState.bulkSelected]);

    const { isFolderInbox, isFolderSpam, isFolderSent, isFolderBin } = useMemo(
      () => ({
        isFolderInbox: folder === FOLDERS.INBOX || !folder,
        isFolderSpam: folder === FOLDERS.SPAM,
        isFolderSent: folder === FOLDERS.SENT,
        isFolderBin: folder === FOLDERS.BIN,
      }),
      [folder],
    );

    // Check if thread has a draft
    const hasDraft = useMemo(() => {
      return !!latestDraft;
    }, [latestDraft]);

    const content = useMemo(() => {
      if (!latestMessage || !getThreadData) return null;

      return (
        <div
          className={cn('select-none border-b md:my-1 md:border-none')}
          onClick={onClick ? onClick(latestMessage) : undefined}
          //   onMouseEnter={() => {
          //     window.dispatchEvent(new CustomEvent('emailHover', { detail: { id: idToUse } }));
          //   }}
          //   onMouseLeave={() => {
          //     window.dispatchEvent(new CustomEvent('emailHover', { detail: { id: null } }));
          //   }}
        >
          <div
            data-thread-id={idToUse}
            key={idToUse}
            className={cn(
              'hover:bg-accent/60 group relative mx-1 flex cursor-pointer flex-col items-start rounded-lg py-2 text-left text-[13px] transition-colors duration-100',
              (isMailSelected || isMailBulkSelected || isKeyboardFocused) &&
                'bg-accent/70 opacity-100',
              isKeyboardFocused && 'ring-2 ring-ring/30',
            )}
          >
            <div
              className={cn(
                'z-25 absolute right-2 flex -translate-y-1/2 items-center gap-0.5 rounded-lg border bg-popover p-0.5 shadow-[0_2px_8px_rgba(0,0,0,0.06)] transition-opacity duration-100',
                // Visible on hover (pointer devices) and when thread is selected/focused (touch devices)
                'opacity-0 group-hover:opacity-100 focus-within:opacity-100',
                (isMailSelected || isKeyboardFocused) && 'opacity-100',
                index === 0 ? 'top-4' : 'top-[-1px]',
              )}
            >
              <Tooltip>
                <TooltipTrigger asChild>
                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-6 w-6 overflow-visible [&_svg]:size-3.5"
                    onClick={handleToggleStar}
                  >
                    <Star2
                      className={cn(
                        'h-4 w-4',
                        displayStarred
                          ? 'fill-yellow-400 stroke-yellow-400'
                          : 'fill-transparent stroke-[#9D9D9D] dark:stroke-[#9D9D9D]',
                      )}
                    />
                  </Button>
                </TooltipTrigger>
                <TooltipContent
                  side={index === 0 ? 'bottom' : 'top'}
                  className="mb-1"
                >
                  {displayStarred
                    ? m['common.threadDisplay.unstar']()
                    : m['common.threadDisplay.star']()}
                </TooltipContent>
              </Tooltip>
              <Tooltip>
                <TooltipTrigger asChild>
                  <Button
                    variant="ghost"
                    size="icon"
                    className={cn(
                      'h-6 w-6 [&_svg]:size-3.5',
                      displayImportant ? 'hover:bg-orange-200/70 dark:hover:bg-orange-800/40' : '',
                    )}
                    onClick={handleToggleImportant}
                  >
                    <ExclamationCircle
                      className={cn(displayImportant ? 'fill-orange-400' : 'fill-[#9D9D9D]')}
                    />
                  </Button>
                </TooltipTrigger>
                <TooltipContent
                  side={index === 0 ? 'bottom' : 'top'}
                  className="mb-1"
                >
                  {m['common.mail.toggleImportant']()}
                </TooltipContent>
              </Tooltip>
              <Tooltip>
                <TooltipTrigger asChild>
                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-6 w-6 [&_svg]:size-3.5"
                    onClick={(e) => {
                      e.stopPropagation();
                      moveThreadTo('archive');
                    }}
                  >
                    <Archive2 className="fill-[#9D9D9D]" />
                  </Button>
                </TooltipTrigger>
                <TooltipContent
                  side={index === 0 ? 'bottom' : 'top'}
                  className="mb-1"
                >
                  {m['common.threadDisplay.archive']()}
                </TooltipContent>
              </Tooltip>
              {!isFolderBin ? (
                <Tooltip>
                  <TooltipTrigger asChild>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-6 w-6 hover:bg-destructive/10 [&_svg]:size-3.5"
                      onClick={(e: React.MouseEvent) => {
                        e.stopPropagation();
                        moveThreadTo('bin');
                      }}
                    >
                      <Trash className="fill-[#F43F5E]" />
                    </Button>
                  </TooltipTrigger>
                  <TooltipContent
                    side={index === 0 ? 'bottom' : 'top'}
                    className="mb-1"
                  >
                    {m['common.actions.bin']()}
                  </TooltipContent>
                </Tooltip>
              ) : null}
            </div>

            <div
              className={`relative flex w-full items-center justify-between gap-4 px-4 ${displayUnread ? '' : 'opacity-60'}`}
            >
              <div>
                {isMailBulkSelected ? (
                  <Avatar
                    className={cn(
                      'h-8 w-8 rounded-full',
                      displayUnread && !isMailSelected && !isFolderSent ? '' : 'border',
                    )}
                  >
                    <div
                      className="flex h-full w-full items-center justify-center rounded-full bg-mainBlue p-2"
                      onClick={(e: React.MouseEvent) => {
                        e.stopPropagation();
                        setMail((prev: Config) => ({
                          ...prev,
                          bulkSelected: prev.bulkSelected.filter((id: string) => id !== idToUse),
                        }));
                      }}
                    >
                      <Check className="h-4 w-4 text-white" />
                    </div>
                  </Avatar>
                ) : isGroupThread ? (
                  <Avatar
                    className={cn(
                      'h-8 w-8 rounded-full',
                      displayUnread && !isMailSelected && !isFolderSent ? '' : 'border',
                    )}
                  >
                    <div className="flex h-full w-full items-center justify-center rounded-full bg-secondary p-2">
                      <GroupPeople className="h-4 w-4" />
                    </div>
                  </Avatar>
                ) : (
                  <BimiAvatar
                    email={latestMessage.sender.email}
                    name={cleanName || latestMessage.sender.email}
                    className={cn(
                      'h-8 w-8 rounded-full',
                      displayUnread && !isMailSelected && !isFolderSent ? '' : 'border',
                    )}
                  />
                )}
                {/* {displayUnread && !isMailSelected && !isFolderSent ? (
                  <>
                    <span className="absolute left-2 top-2 size-1.5 rounded bg-[#006FFE]" />
                    <span className="absolute left-[11px] top-4 size-1 rounded bg-[#006FFE]" />
                  </>
                ) : null} */}
              </div>

              <div className="flex w-full justify-between">
                <div className="w-full">
                  <div className="flex w-full flex-row items-center justify-between">
                    <div className="flex flex-row items-center gap-[4px]">
                      <span
                        className={cn(
                          displayUnread && !isMailSelected ? 'font-bold' : 'font-medium',
                          'text-md flex items-baseline gap-1 group-hover:opacity-100',
                        )}
                      >
                        {isFolderSent ? (
                          <span
                            className={cn(
                              'overflow-hidden truncate text-sm md:max-w-[15ch] xl:max-w-[25ch]',
                            )}
                          >
                            {highlightText(latestMessage.subject, searchValue.highlight)}
                          </span>
                        ) : (
                          <div className="flex items-center gap-1">
                            <span className={cn('line-clamp-1 overflow-hidden text-sm')}>
                              {highlightText(
                                cleanNameDisplay(latestMessage.sender.name) || '',
                                searchValue.highlight,
                              )}
                            </span>
                            {displayUnread && !isMailSelected && !isFolderSent ? (
                              <>
                                <span className="ml-0.5 size-1.5 rounded-full bg-mainBlue" />
                              </>
                            ) : null}
                          </div>
                        )}{' '}
                        {/* {!isFolderSent ? (
                          <span className="hidden items-center space-x-2 md:flex">
                            <RenderLabels labels={threadLabels} />
                          </span>
                        ) : null} */}
                      </span>
                      {getThreadData.totalReplies > 1 ? (
                        <Tooltip>
                          <TooltipTrigger asChild>
                            <span className="rounded-md text-xs opacity-70">
                              [{getThreadData.totalReplies}]
                            </span>
                          </TooltipTrigger>
                          <TooltipContent className="p-1 text-xs">
                            {m['common.mail.replies']({ count: getThreadData.totalReplies })}
                          </TooltipContent>
                        </Tooltip>
                      ) : null}
                      {hasDraft ? (
                        <Tooltip>
                          <TooltipTrigger asChild>
                            <span className="inline-flex items-center">
                              <PencilCompose className="h-3 w-3 fill-blue-500 dark:fill-blue-400" />
                            </span>
                          </TooltipTrigger>
                          <TooltipContent className="p-1 text-xs">Draft</TooltipContent>
                        </Tooltip>
                      ) : null}
                      {/* {hasNotes ? (
                        <span className="inline-flex items-center">
                          <StickyNote className="h-3 w-3 fill-amber-500 stroke-amber-500 dark:fill-amber-400 dark:stroke-amber-400" />
                        </span>
                      ) : null} */}
                      <MailLabels labels={optimisticLabels} />
                    </div>
                    {latestMessage.receivedOn ? (
                      <p
                        className={cn(
                          'text-muted-foreground text-nowrap text-[11px] font-normal opacity-70 transition-opacity group-hover:opacity-100',
                          isMailSelected && 'opacity-100',
                        )}
                      >
                        {formatDate(latestMessage.receivedOn.split('.')[0] || '')}
                      </p>
                    ) : null}
                  </div>
                  <div className="flex justify-between">
                    {isFolderSent ? (
                      <p
                        className={cn(
                          'mt-1 line-clamp-1 max-w-[50ch] overflow-hidden text-[13px] text-muted-foreground md:max-w-[25ch]',
                        )}
                      >
                        {latestMessage.to.map((e) => e.email).join(', ')}
                      </p>
                    ) : (
                      <p
                        className={cn(
                          'mt-1 line-clamp-1 w-[95%] min-w-0 overflow-hidden text-[13px] text-muted-foreground',
                        )}
                      >
                        {highlightText(latestMessage.subject, searchValue.highlight)}
                      </p>
                    )}
                    {/* <div className="hidden md:flex">
                      {getThreadData.labels ? <MailLabels labels={getThreadData.labels} /> : null}
                    </div> */}
                    {threadLabels && (
                      <div className="mr-0 flex w-fit items-center justify-end gap-1">
                        {!isFolderSent ? <RenderLabels labels={threadLabels} /> : null}
                        {/* {getThreadData.labels ? <MailLabels labels={getThreadData.labels} /> : null} */}
                      </div>
                    )}
                  </div>
                  {emailContent && (
                    <div className="text-muted-foreground mt-1.5 line-clamp-2 text-[12px] leading-relaxed">
                      {highlightText(emailContent, searchValue.highlight)}
                    </div>
                  )}
                  {/* {mainSearchTerm && (
                    <div className="text-muted-foreground mt-1 flex items-center gap-1 text-xs">
                      <span className="bg-primary/10 text-primary rounded px-1.5 py-0.5">
                        {mainSearchTerm}
                      </span>
                    </div>
                  )} */}
                </div>
              </div>
            </div>
          </div>
        </div>
      );
    }, [
      latestMessage,
      getThreadData,
      optimisticState,
      idToUse,
      folder,
      isFolderBin,
      isFolderSent,
      isFolderSpam,
      isFolderInbox,
      onClick,
      searchValue,
      displayUnread,
      isMailSelected,
      isMailBulkSelected,
      threadLabels,
      optimisticLabels,
      emailContent,
    ]);

    return latestMessage ? (
      !optimisticState.shouldHide && idToUse ? (
        <ThreadContextMenu
          threadId={idToUse}
          isInbox={isFolderInbox}
          isSpam={isFolderSpam}
          isSent={isFolderSent}
          isBin={isFolderBin}
        >
          {content}
        </ThreadContextMenu>
      ) : null
    ) : null;
  },
  (prev, next) => {
    const isSameMessage =
      prev.message.id === next.message.id &&
      prev.isKeyboardFocused === next.isKeyboardFocused &&
      prev.index === next.index &&
      Object.is(prev.onClick, next.onClick);
    return isSameMessage;
  },
);

const Draft = memo(({ message, index }: { message: { id: string }; index: number }) => {
  const draftQuery = useDraft(message.id) as UseQueryResult<ParsedDraft>;
  const draft = draftQuery.data;
  const [, setComposeOpen] = useQueryState('isComposeOpen');
  const [, setDraftId] = useQueryState('draftId');
  const { optimisticDeleteDraft } = useOptimisticActions();
  const optimisticState = useOptimisticThreadState(message.id);

  const handleMailClick = useCallback(() => {
    setComposeOpen('true');
    setDraftId(message.id);
    return;
  }, [message.id]);

  const handleDeleteDraft = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      optimisticDeleteDraft(message.id);
    },
    [message.id, optimisticDeleteDraft],
  );

  if (optimisticState.shouldHide) {
    return null;
  }

  if (!draft) {
    return (
      <div className="select-none py-1">
        <div
          key={message.id}
          className={cn(
            'group relative mx-[8px] flex cursor-pointer flex-col items-start overflow-clip rounded-[10px] border-transparent py-3 text-left text-sm',
          )}
        >
          <div
            className={cn(
              'bg-primary absolute inset-y-0 left-0 w-1 -translate-x-2 transition-transform ease-out',
            )}
          />
          <div className="flex w-full items-center justify-between gap-4 px-4">
            <div className="flex w-full justify-between">
              <div className="w-full">
                <div className="flex w-full flex-row items-center justify-between">
                  <div className="flex flex-row items-center gap-[4px]">
                    <Skeleton className="bg-muted h-4 w-32 rounded" />
                  </div>
                </div>
                <div className="flex justify-between">
                  <Skeleton className="bg-muted mt-1 h-4 w-48 rounded" />
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="select-none py-1" onClick={handleMailClick}>
      <div
        key={message.id}
        className={cn(
          'hover:bg-offsetLight dark:hover:bg-primary/5 group relative mx-[8px] flex cursor-pointer flex-col items-start overflow-visible rounded-[10px] border-transparent py-3 text-left text-sm hover:opacity-100',
        )}
      >
        <div
          className={cn(
            'shadow-xs absolute right-2 z-20 flex -translate-y-1/2 items-center gap-1 rounded-xl border bg-popover p-1 opacity-0 group-hover:opacity-100 focus-within:opacity-100',
            index === 0 ? 'top-4' : 'top-[-1px]',
          )}
          aria-busy={optimisticState.isRemoving}
        >
          <Tooltip>
            <TooltipTrigger asChild>
              <Button
                variant="ghost"
                size="icon"
                className="h-6 w-6 hover:bg-[#FDE4E9] dark:hover:bg-[#411D23] [&_svg]:size-3.5"
                aria-label="Delete draft"
                disabled={optimisticState.isRemoving}
                onClick={handleDeleteDraft}
              >
                <Trash className="fill-[#F43F5E]" />
              </Button>
            </TooltipTrigger>
            <TooltipContent
              side={index === 0 ? 'bottom' : 'top'}
              className="mb-1"
            >
              {m['common.actions.bin']()}
            </TooltipContent>
          </Tooltip>
        </div>
        <div className="flex w-full items-center justify-between gap-4 px-4">
          <div className="flex w-full justify-between">
            <div className="w-full">
              <div className="flex w-full flex-row items-center justify-between">
                <div className="flex flex-row items-center gap-[4px]">
                  <span
                    className={cn(
                      'font-medium',
                      'text-md flex items-baseline gap-1 group-hover:opacity-100',
                    )}
                  >
                    <span className={cn('max-w-[25ch] truncate text-sm')}>
                      {cleanNameDisplay(draft?.to?.[0] || 'No Recipient') || ''}
                    </span>
                  </span>
                </div>
                {draft.rawMessage?.internalDate && (
                  <p
                    className={cn(
                      'text-muted-foreground text-nowrap text-[11px] font-normal opacity-70 transition-opacity group-hover:opacity-100',
                    )}
                  >
                    {formatDate(Number(draft.rawMessage?.internalDate))}
                  </p>
                )}
              </div>
              <div className="flex justify-between">
                <p
                  className={cn(
                    'mt-1 line-clamp-1 max-w-[50ch] text-[13px] text-muted-foreground md:max-w-[30ch]',
                  )}
                >
                  {draft?.subject}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
});

Draft.displayName = 'Draft';

// ─── People View ─────────────────────────────────────────────────────────────

interface SenderEntry {
  email: string;
  name: string | null;
  threadCount: number;
  latestDate: string | null;
  latestSubject: string | null;
}

/** A single sender row in the People list */
const PersonRow = memo(function PersonRow({
  sender,
  onClick,
}: {
  sender: SenderEntry;
  onClick: () => void;
}) {
  const displayName = sender.name || sender.email;
  return (
    <button
      type="button"
      onClick={onClick}
      className="hover:bg-offsetLight dark:hover:bg-primary/5 mx-1 flex w-[calc(100%-8px)] cursor-pointer items-center gap-3 rounded-lg px-3 py-2.5 text-left transition-colors"
    >
      <BimiAvatar
        email={sender.email}
        name={sender.name ?? undefined}
        className="h-10 w-10 flex-shrink-0 rounded-full border dark:border-none"
      />
      <div className="min-w-0 flex-1">
        <div className="flex items-center justify-between gap-2">
          <span className="truncate text-sm font-semibold">{displayName}</span>
          <span className="text-muted-foreground shrink-0 text-xs">
            {sender.latestDate ? formatDate(sender.latestDate) : ''}
          </span>
        </div>
        <div className="flex items-center gap-1.5">
          <span className="text-muted-foreground line-clamp-1 text-sm">
            {sender.latestSubject || sender.email}
          </span>
          {sender.threadCount > 1 && (
            <span className="text-muted-foreground shrink-0 text-xs">[{sender.threadCount}]</span>
          )}
        </div>
      </div>
      <ChevronRight className="text-muted-foreground h-4 w-4 shrink-0" />
    </button>
  );
});

/** Full People list — groups inbox threads by sender */
const PeopleList = memo(function PeopleList({
  onSelectPerson,
}: {
  onSelectPerson: (email: string) => void;
}) {
  const { folder } = useParams<{ folder: string }>();
  const trpc = useTRPC();

  const { data: senders, isLoading } = useQuery(
    trpc.mail.listSenders.queryOptions(
      { folder: folder ?? 'inbox' },
      { staleTime: 60 * 1000, refetchOnWindowFocus: false },
    ),
  );

  if (isLoading) {
    return (
      <div className="flex flex-1 flex-col gap-0.5 px-1 pt-2">
        {Array.from({ length: 9 }).map((_, i) => (
          <div key={i} className="flex items-center gap-3 rounded-lg px-3 py-3">
            <Skeleton className="h-10 w-10 flex-shrink-0 rounded-full" />
            <div className="flex flex-1 flex-col gap-2">
              <div className="flex justify-between">
                <Skeleton className="h-3.5 w-28 rounded" />
                <Skeleton className="h-3 w-10 rounded" />
              </div>
              <Skeleton className={`h-3 rounded ${i % 3 === 0 ? 'w-44' : i % 3 === 1 ? 'w-36' : 'w-52'}`} />
            </div>
          </div>
        ))}
      </div>
    );
  }

  if (!senders || senders.length === 0) {
    return (
      <div className="flex h-full w-full items-center justify-center">
        <div className="flex flex-col items-center gap-2 text-center">
          <Users className="text-muted-foreground h-12 w-12 opacity-30" />
          <p className="text-muted-foreground text-sm">No senders found</p>
        </div>
      </div>
    );
  }

  return (
    <div className="scrollbar-none flex flex-1 flex-col overflow-y-auto py-1">
      {senders.map((sender) => (
        <PersonRow
          key={sender.email}
          sender={sender}
          onClick={() => onSelectPerson(sender.email)}
        />
      ))}
    </div>
  );
});

/** Shows all threads from a specific sender with a back button */
const PersonThreadsView = memo(function PersonThreadsView({
  email,
  name,
  onBack,
}: {
  email: string;
  name?: string | null;
  onBack: () => void;
}) {
  const trpc = useTRPC();
  const { folder } = useParams<{ folder: string }>();
  const [, setThreadId] = useQueryState('threadId');
  const [, setDraftId] = useQueryState('draftId');

  const { data, isLoading, isFetchingNextPage, fetchNextPage, hasNextPage } = useInfiniteQuery(
    trpc.mail.listThreads.infiniteQueryOptions(
      { q: `from:${email}`, folder: folder ?? 'inbox' },
      {
        initialCursor: '',
        getNextPageParam: (lastPage) => lastPage?.nextPageToken ?? null,
        staleTime: 60 * 1000,
      },
    ),
  );

  const threads = useMemo(
    () => data?.pages.flatMap((p) => p.threads).filter(Boolean) ?? [],
    [data],
  );

  const vListRef = useRef<VListHandle>(null);
  const displayName = name || email;

  return (
    <div className="flex h-full flex-col">
      {/* Back header */}
      <div className="flex items-center gap-2 px-3 py-2">
        <button
          type="button"
          onClick={onBack}
          className="hover:bg-accent/50 flex items-center gap-1 rounded-md px-2 py-1.5 text-sm transition-colors"
        >
          <ChevronLeft className="h-4 w-4" />
          <span>People</span>
        </button>
        <div className="flex items-center gap-2">
          <BimiAvatar
            email={email}
            name={displayName}
            className="h-6 w-6 rounded-full border dark:border-none"
          />
          <span className="truncate text-sm font-medium">{displayName}</span>
        </div>
      </div>

      {/* Thread list for this person */}
      {isLoading ? (
        <div className="flex flex-1 flex-col gap-0.5 px-1 pt-1">
          {Array.from({ length: 5 }).map((_, i) => (
            <div key={i} className="flex items-center gap-3 rounded-lg px-3 py-3">
              <Skeleton className="h-9 w-9 flex-shrink-0 rounded-full" />
              <div className="flex flex-1 flex-col gap-2">
                <div className="flex justify-between">
                  <Skeleton className="h-3.5 w-28 rounded" />
                  <Skeleton className="h-3 w-10 rounded" />
                </div>
                <Skeleton className="h-3 w-44 rounded" />
              </div>
            </div>
          ))}
        </div>
      ) : threads.length === 0 ? (
        <div className="flex flex-1 items-center justify-center">
          <p className="text-muted-foreground text-sm">No threads found</p>
        </div>
      ) : (
        <div className="flex flex-1 flex-col overflow-hidden">
          <VList
            ref={vListRef}
            count={threads.length}
            overscan={5}
            itemSize={100}
            className="scrollbar-none flex-1 overflow-x-hidden"
            onScroll={() => {
              if (!vListRef.current) return;
              const endIndex = vListRef.current.findEndIndex();
              if (Math.abs(threads.length - 1 - endIndex) < 5 && !isFetchingNextPage && hasNextPage) {
                void fetchNextPage();
              }
            }}
          >
            {(index) => {
              const item = threads[index];
              return item ? (
                <Thread
                  key={item.id}
                  message={item}
                  isKeyboardFocused={false}
                  index={index}
                  onClick={(msg) => async () => {
                    const id = msg.threadId ?? msg.id;
                    setThreadId(id);
                    setDraftId(null);
                  }}
                />
              ) : <></>;
            }}
          </VList>
          {isFetchingNextPage && (
            <div className="flex w-full justify-center py-3">
              <div className="h-4 w-4 animate-spin rounded-full border-2 border-neutral-900 border-t-transparent dark:border-white dark:border-t-transparent" />
            </div>
          )}
        </div>
      )}
    </div>
  );
});

export const MailList = memo(
  function MailList() {
    const { folder } = useParams<{ folder: string }>();
    const { data: settingsData } = useSettings();
    const [, setThreadId] = useQueryState('threadId');
    const [, setDraftId] = useQueryState('draftId');
    const [searchValue, setSearchValue] = useSearchValue();
    const [anchorIndex, setAnchorIndex] = useState<number | null>(null);

    // People view state — persisted in URL so refresh preserves position
    const [viewMode, setViewMode] = useQueryState('viewMode');
    const [personEmail, setPersonEmail] = useQueryState('personEmail');
    const isPeopleView = viewMode === 'people';

    // Only show the toggle for inbox (meaningful to group by sender)
    const showViewToggle = !folder || folder === 'inbox';

    useEffect(() => {
      const handleKeyDown = (event: KeyboardEvent) => {
        if (event.key === 'Escape') {
          setAnchorIndex(null);
        }
      };

      window.addEventListener('keydown', handleKeyDown);

      return () => {
        window.removeEventListener('keydown', handleKeyDown);
      };
    }, [setAnchorIndex]);

    const [{ refetch, isLoading, isFetching, isFetchingNextPage, hasNextPage }, items, , loadMore] =
      useThreads();
    const trpc = useTRPC();
    // True while PersistQueryClientProvider is restoring the IDB cache — during this window
    // the query is paused (isFetching=false, isLoading=false) but items is still empty,
    // so we must treat it like loading to avoid flashing "It's empty here".
    const isRestoring = useIsRestoring();
    const isFetchingMail = useIsFetching({ queryKey: trpc.mail.get.queryKey() }) > 0;
    const itemsRef = useRef(items);
    const parentRef = useRef<HTMLDivElement>(null);
    const vListRef = useRef<VListHandle>(null);

    useEffect(() => {
      itemsRef.current = items;
    }, [items]);

    // Add event listener for refresh
    useEffect(() => {
      const handleRefresh = () => {
        void refetch();
      };

      window.addEventListener('refreshMailList', handleRefresh);
      return () => window.removeEventListener('refreshMailList', handleRefresh);
    }, [refetch]);

    const handleNavigateToThread = useCallback(
      (threadId: string | null) => {
        setThreadId(threadId);
        return;
      },
      [setThreadId],
    );

    const { focusedIndex, handleMouseEnter, keyboardActive } = useMailNavigation({
      items,
      containerRef: parentRef,
      onNavigate: handleNavigateToThread,
    });

    const isKeyPressed = useKeyState();

    const getSelectMode = useCallback((): MailSelectMode => {
      const isAltPressed =
        isKeyPressed('Alt') || isKeyPressed('AltLeft') || isKeyPressed('AltRight');
      const isShiftPressed =
        isKeyPressed('Shift') || isKeyPressed('ShiftLeft') || isKeyPressed('ShiftRight');
      const isCtrlPressed = isKeyPressed('Control') || isKeyPressed('Meta');

      if (isShiftPressed && !isCtrlPressed) {
        return 'range';
      }
      if (isCtrlPressed) {
        return 'mass';
      }
      if (isAltPressed && isShiftPressed) {
        console.log('Select All Below mode activated'); // Debug log
        return 'selectAllBelow';
      }
      return 'single';
    }, [isKeyPressed]);

    const [, setActiveReplyId] = useQueryState('activeReplyId');
    const [, setMail] = useMail();

    const handleSelectMail = useCallback(
      (message: ParsedMessage) => {
        const itemId = message.threadId ?? message.id;
        const currentMode = getSelectMode();
        console.log('Selection mode:', currentMode, 'for item:', itemId);

        setMail((prevMail) => {
          const mail = prevMail;
          const clickedIndex = itemsRef.current.findIndex((item) => item.id === itemId);
          if (clickedIndex === -1) return mail;

          switch (currentMode) {
            case 'mass': {
              const newSelected = mail.bulkSelected.includes(itemId)
                ? mail.bulkSelected.filter((id) => id !== itemId)
                : [...mail.bulkSelected, itemId];
              console.log('Mass selection mode - selected items:', newSelected.length);
              return { ...mail, bulkSelected: newSelected };
            }
            case 'selectAllBelow': {
              const clickedIndex = itemsRef.current.findIndex((item) => item.id === itemId);
              console.log(
                'SelectAllBelow - clicked index:',
                clickedIndex,
                'total items:',
                itemsRef.current.length,
              );

              if (clickedIndex !== -1) {
                const itemsBelow = itemsRef.current.slice(clickedIndex);
                const idsBelow = itemsBelow.map((item) => item.id);
                console.log('Selecting all items below - count:', idsBelow.length);
                return { ...mail, bulkSelected: idsBelow };
              }
              console.log('Item not found in list, selecting just this item');
              return { ...mail, bulkSelected: [itemId] };
            }
            case 'range': {
              console.log('Range selection mode');
              if (anchorIndex === null) {
                return { ...mail, bulkSelected: [itemId] };
              }
              const start = Math.min(anchorIndex, clickedIndex);
              const end = Math.max(anchorIndex, clickedIndex);
              const rangeIds = itemsRef.current.slice(start, end + 1).map((item) => item.id);
              const newSelected = [...new Set([...mail.bulkSelected, ...rangeIds])];

              return { ...mail, bulkSelected: newSelected };
            }
            default: {
              console.log('Single selection mode');
              return { ...mail, bulkSelected: [itemId] };
            }
          }
        });
      },
      [getSelectMode, setMail, anchorIndex],
    );

    const [, setFocusedIndex] = useAtom(focusedIndexAtom);

    const { optimisticMarkAsRead } = useOptimisticActions();
    const handleMailClick = useCallback(
      (message: ParsedMessage) => async () => {
        const mode = getSelectMode();
        const autoRead = settingsData?.settings?.autoRead ?? true;
        console.log('Mail click with mode:', mode);

        if (mode !== 'single') {
          const messageThreadId = message.threadId ?? message.id;
          const clickedIndex = itemsRef.current.findIndex((item) => item.id === messageThreadId);
          if (clickedIndex !== -1 && mode !== 'range') {
            setAnchorIndex(clickedIndex);
          }
          return handleSelectMail(message);
        }

        handleMouseEnter(message.id);

        const messageThreadId = message.threadId ?? message.id;
        const clickedIndex = itemsRef.current.findIndex((item) => item.id === messageThreadId);
        setFocusedIndex(clickedIndex);
        if (message.unread && autoRead) optimisticMarkAsRead([messageThreadId], true);
        setThreadId(messageThreadId);
        setDraftId(null);
        // Don't clear activeReplyId - let ThreadDisplay handle Reply All auto-opening
      },
      [
        getSelectMode,
        handleSelectMail,
        handleMouseEnter,
        setFocusedIndex,
        optimisticMarkAsRead,
        setThreadId,
        setDraftId,
        settingsData,
        setActiveReplyId,
      ],
    );

    const isFiltering = searchValue.value.trim().length > 0;

    useEffect(() => {
      if (isFiltering && !isLoading) {
        setSearchValue({
          ...searchValue,
          isLoading: false,
        });
      }
    }, [isLoading, isFiltering, setSearchValue]);

    const clearFilters = () => {
      setSearchValue({
        value: '',
        highlight: '',
        folder: '',
      });
    };

    const filteredItems = useMemo(() => items.filter((item) => item.id), [items]);

    const Comp = useMemo(() => (folder === FOLDERS.DRAFT ? Draft : Thread), [folder]);

    const vListRenderer = useCallback(
      (index: number) => {
        const item = filteredItems[index];
        return item ? (
          <>
            <Comp
              key={item.id}
              message={item}
              isKeyboardFocused={focusedIndex === index && keyboardActive}
              index={index}
              onClick={handleMailClick}
            />
            {index === filteredItems.length - 1 && (isFetchingNextPage || isFetchingMail) ? (
              <div className="flex w-full justify-center py-4">
                <div className="h-4 w-4 animate-spin rounded-full border-2 border-neutral-900 border-t-transparent dark:border-white dark:border-t-transparent" />
              </div>
            ) : null}
          </>
        ) : (
          <></>
        );
      },
      [
        folder,
        filteredItems,
        focusedIndex,
        keyboardActive,
        isFetchingMail,
        isFetchingNextPage,
        handleMailClick,
        isLoading,
        isFetching,
        hasNextPage,
      ],
    );

    return (
      <>
        {/* View toggle pill — Threads vs People. Only shown in inbox. */}
        {showViewToggle && (
          <div className="flex items-center px-3 pt-2 pb-1">
            <div className="bg-muted flex items-center gap-0.5 rounded-lg p-1">
              <button
                type="button"
                className={cn(
                  'rounded-md px-3 py-1 text-xs font-medium transition-colors',
                  !isPeopleView
                    ? 'bg-background text-foreground shadow-sm'
                    : 'text-muted-foreground hover:text-foreground',
                )}
                onClick={() => { void setViewMode(null); void setPersonEmail(null); }}
              >
                Threads
              </button>
              <button
                type="button"
                className={cn(
                  'rounded-md px-3 py-1 text-xs font-medium transition-colors',
                  isPeopleView
                    ? 'bg-background text-foreground shadow-sm'
                    : 'text-muted-foreground hover:text-foreground',
                )}
                onClick={() => { void setViewMode('people'); void setPersonEmail(null); }}
              >
                People
              </button>
            </div>
          </div>
        )}

        {/* People view — sender list or drill-down into a person's threads */}
        {isPeopleView && (
          <div className="flex h-[calc(100%-44px)] flex-col">
            {personEmail ? (
              <PersonThreadsView
                email={personEmail}
                onBack={() => setPersonEmail(null)}
              />
            ) : (
              <PeopleList onSelectPerson={(email) => setPersonEmail(email)} />
            )}
          </div>
        )}

        {/* Standard threads view */}
        {!isPeopleView && (
        <>
        <div
          ref={parentRef}
          className={cn(
            'hide-link-indicator flex w-full',
            // Reserve space for the toggle pill only when it's visible
            showViewToggle ? 'h-[calc(100%-44px)]' : 'h-full',
            getSelectMode() === 'range' && 'select-none',
          )}
        >
          <>
            {isLoading || isRestoring || (isFetching && items.length === 0) ? (
              // Show skeleton rows while loading/restoring IDB cache so user sees structure, not "It's empty here"
              <div className="flex flex-1 flex-col gap-0.5 px-1 pt-2">
                {Array.from({ length: 9 }).map((_, i) => (
                  <div key={i} className="flex items-center gap-3 rounded-lg px-3 py-3">
                    <Skeleton className="h-9 w-9 flex-shrink-0 rounded-full" />
                    <div className="flex flex-1 flex-col gap-2">
                      <div className="flex justify-between">
                        <Skeleton className="h-3.5 w-32 rounded" />
                        <Skeleton className="h-3 w-10 rounded" />
                      </div>
                      <Skeleton className={`h-3 rounded ${i % 3 === 0 ? 'w-48' : i % 3 === 1 ? 'w-40' : 'w-52'}`} />
                    </div>
                  </div>
                ))}
              </div>
            ) : !items || items.length === 0 ? (
              <div className="flex w-full items-center justify-center">
                <div className="flex flex-col items-center justify-center gap-2 text-center">
                  <EmptyStateIcon width={200} height={200} />
                  <div className="mt-5">
                    <p className="text-base font-medium">
                      {isFiltering ? 'No results found' : 'It\u2019s empty here'}
                    </p>
                    <p className="mt-1 text-[13px] text-muted-foreground">
                      {isFiltering ? (
                        <>
                          Try a different search or{' '}
                          <button type="button" className="underline cursor-pointer" onClick={clearFilters}>
                            clear filters
                          </button>
                        </>
                      ) : (
                        'No emails in this folder yet'
                      )}
                    </p>
                  </div>
                </div>
              </div>
            ) : (
              <div className="flex flex-1 flex-col" id="mail-list-scroll">
                <VList
                  ref={vListRef}
                  count={filteredItems.length}
                  overscan={5}
                  itemSize={100}
                  className="scrollbar-none flex-1 overflow-x-hidden"
                  onScroll={() => {
                    if (!vListRef.current) return;
                    const endIndex = vListRef.current.findEndIndex();
                    if (
                      // if the shown items are last 5 items, load more
                      Math.abs(filteredItems.length - 1 - endIndex) < 7 &&
                      !isLoading &&
                      !isFetchingNextPage &&
                      !isFetchingMail &&
                      hasNextPage
                    ) {
                      void loadMore();
                    }
                  }}
                >
                  {vListRenderer}
                </VList>
              </div>
            )}
          </>
        </div>
        <div className="w-full pt-2 text-center">
          {isFetching ? (
            <div className="text-center">
              <div className="mx-auto h-4 w-4 animate-spin rounded-full border-2 border-neutral-900 border-t-transparent dark:border-white dark:border-t-transparent" />
            </div>
          ) : (
            <div className="h-2" />
          )}
        </div>
        </>
        )}
      </>
    );
  },
  () => true,
);

export const MailLabels = memo(
  function MailListLabels({ labels }: { labels: { id: string; name: string }[] }) {
    if (!labels?.length) return null;

    const visibleLabels = labels.filter(
      (label) => !['unread', 'inbox'].includes(label.name.toLowerCase()),
    );

    if (!visibleLabels.length) return null;

    return (
      <div className={cn('flex select-none items-center')}>
        {visibleLabels.map((label) => {
          const style = getDefaultBadgeStyle(label.name);
          if (label.name.toLowerCase() === 'notes') {
            return (
              <Tooltip key={label.id}>
                <TooltipTrigger asChild>
                  <Badge className="rounded-md bg-amber-100 p-1 text-amber-700 hover:bg-amber-200 dark:bg-amber-900/30 dark:text-amber-400">
                    {getLabelIcon(label.name)}
                  </Badge>
                </TooltipTrigger>
                <TooltipContent className="hidden px-1 py-0 text-xs">
                  {m['common.notes.title']()}
                </TooltipContent>
              </Tooltip>
            );
          }

          // Skip rendering if style is "secondary" (default case)
          if (style === 'secondary') return null;
          const content = getLabelIcon(label.name);

          return content ? (
            <Badge key={label.id} className="rounded-md p-1" variant={style}>
              {content}
            </Badge>
          ) : null;
        })}
      </div>
    );
  },
  (prev, next) => {
    return JSON.stringify(prev.labels) === JSON.stringify(next.labels);
  },
);

function getLabelIcon(label: string) {
  const normalizedLabel = label.toLowerCase().replace(/^category_/i, '');

  switch (normalizedLabel) {
    case 'starred':
      return <Star className="h-[12px] w-[12px] fill-yellow-400 stroke-yellow-400" />;
    default:
      return null;
  }
}

function getDefaultBadgeStyle(label: string): ComponentProps<typeof Badge>['variant'] {
  const normalizedLabel = label.toLowerCase().replace(/^category_/i, '');

  switch (normalizedLabel) {
    case 'starred':
    case 'important':
      return 'important';
    case 'promotions':
      return 'promotions';
    case 'personal':
      return 'personal';
    case 'updates':
      return 'updates';
    case 'work':
      return 'default';
    case 'forums':
      return 'forums';
    case 'notes':
      return 'secondary';
    default:
      return 'secondary';
  }
}

// Helper function to clean name display
const cleanNameDisplay = (name?: string) => {
  if (!name) return '';
  const match = name.match(/^[^\p{L}\p{N}.]*(.*?)[^\p{L}\p{N}.]*$/u);
  return match ? match[1] : name;
};
