import {
  HelpCircle,
  LogOut,
  MoonIcon,
  Settings,
  Plus,
  CopyCheckIcon,
  BadgeCheck,
  BanknoteIcon,
  RefreshCcw,
  Trash2,
  Star,
} from 'lucide-react';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuTrigger,
} from '@/components/ui/context-menu';
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip';
import { useConnectionFilter } from '@/providers/connection-filter-provider';
import { useActiveConnection, useConnections } from '@/hooks/use-connections';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { useDoState } from '@/components/mail/use-do-state';
import { useLoading } from '../context/loading-context';
import { signOut, useSession } from '@/lib/auth-client';
import { AddConnectionDialog } from '../connection/add';
import { CircleCheck, ThreeDots } from '../icons/icons';
import { useTRPC } from '@/providers/query-provider';
import { useSidebar } from '@/components/ui/sidebar';
import { useBilling } from '@/hooks/use-billing';
import { SunIcon } from '../icons/animated/sun';
import { clear as idbClear } from 'idb-keyval';
import { useLocation } from 'react-router';
import { m } from '@/paraglide/messages';
import { useTheme } from 'next-themes';
import { useQueryState } from 'nuqs';
import { Button } from './button';
import { cn } from '@/lib/utils';
import { toast } from 'sonner';

const bytesToMB = (bytes: number) => (bytes / 1024 / 1024).toFixed(2);

interface SyncingStatusIndicatorProps {
  isSyncing: boolean;
  storageSize: number;
  syncingFolders: string[];
}

function SyncingStatusIndicator({
  isSyncing,
  storageSize,
  syncingFolders,
}: SyncingStatusIndicatorProps) {
  const statusContent = (
    <div className="flex items-center gap-2">
      <div className="flex h-4 w-4 items-center justify-center">
        <div
          className={cn(
            'h-2 w-2 rounded-full',
            isSyncing || storageSize === 0 ? 'animate-pulse bg-orange-500' : 'bg-green-500',
          )}
        />
      </div>
      <p className="text-[13px] opacity-60">
        {isSyncing || storageSize === 0
          ? 'Syncing emails...'
          : `Synced${storageSize ? ` • ${bytesToMB(storageSize)} MB` : ''}`}
      </p>
    </div>
  );

  if (isSyncing && syncingFolders.length > 0) {
    return (
      <Tooltip>
        <TooltipTrigger asChild>
          <DropdownMenuItem className="cursor-default">{statusContent}</DropdownMenuItem>
        </TooltipTrigger>
        <TooltipContent side="right" sideOffset={10} avoidCollisions={false}>
          <p className="text-xs">Syncing: {syncingFolders.join(', ')}</p>
        </TooltipContent>
      </Tooltip>
    );
  }

  return <DropdownMenuItem className="cursor-default">{statusContent}</DropdownMenuItem>;
}

export function NavUser() {
  const { data: session } = useSession();
  const { data } = useConnections();
  const [isRendered, setIsRendered] = useState(false);
  const { theme, resolvedTheme, setTheme } = useTheme();
  const { state } = useSidebar();
  const trpc = useTRPC();
  const [, setThreadId] = useQueryState('threadId');
  const { mutateAsync: setDefaultConnection } = useMutation(
    trpc.connections.setDefault.mutationOptions(),
  );
  const { mutateAsync: handleForceSync } = useMutation(trpc.mail.forceSync.mutationOptions());
  const { openBillingPortal, customer: billingCustomer, isPro } = useBilling();
  const pathname = useLocation().pathname;
  const queryClient = useQueryClient();
  const { data: activeConnection, refetch: refetchActiveConnection } = useActiveConnection();
  const [, setPricingDialog] = useQueryState('pricingDialog');
  const [category] = useQueryState('category', { defaultValue: 'All Mail' });
  const { setLoading } = useLoading();
  const [{ isSyncing, syncingFolders, storageSize, shards }] = useDoState();

  const getSettingsHref = useCallback(() => {
    const currentPath = category
      ? `${pathname}?category=${encodeURIComponent(category)}`
      : pathname;
    return `/settings/general?from=${encodeURIComponent(currentPath)}`;
  }, [pathname, category]);

  const handleClearCache = useCallback(async () => {
    queryClient.clear();
    await idbClear();
    toast.success('Cache cleared successfully');
  }, []);

  const handleCopyConnectionId = useCallback(async () => {
    await navigator.clipboard.writeText(activeConnection?.id || '');
    toast.success('Connection ID copied to clipboard');
  }, [activeConnection]);

  const { data: activeAccount } = useActiveConnection();
  const { enabledConnectionIds, toggleConnection, totalConnections } = useConnectionFilter();

  useEffect(() => setIsRendered(true), []);

  /** Set a connection as the default (for compose "from" address) */
  const handleSetDefault = (connectionId: string) => async () => {
    if (connectionId === activeConnection?.id) return;

    try {
      setLoading(true, m['common.navUser.switchingAccounts']());
      setThreadId(null);
      await setDefaultConnection({ connectionId });
      queryClient.clear();
      await queryClient.refetchQueries({ queryKey: trpc.mail.listThreads.infiniteQueryKey() });
    } catch (error) {
      console.error('Error switching accounts:', error);
      toast.error(m['common.navUser.failedToSwitchAccount']());

      await refetchActiveConnection();
    } finally {
      setLoading(false);
    }
  };

  /** Toggle a connection's visibility in the unified view (click behavior) */
  const handleToggleVisibility = (connectionId: string) => () => {
    // If only one connection total, toggle is meaningless — act as set-default
    if (totalConnections <= 1) return;
    toggleConnection(connectionId);
  };

  const handleLogout = async () => {
    toast.promise(signOut(), {
      loading: 'Signing out...',
      success: () => 'Signed out successfully!',
      error: 'Error signing out',
      async finally() {
        // await handleClearCache();
        window.location.href = '/login';
      },
    });
  };

  const otherConnections = useMemo(() => {
    if (!data || !activeAccount) return [];
    return data.connections.filter((connection) => connection.id !== activeAccount?.id);
  }, [data, activeAccount]);

  const handleThemeToggle = () => {
    setTheme(theme === 'dark' ? 'light' : 'dark');
  };

  if (!isRendered) return null;
  if (!session) return null;

  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-center gap-3">
        {state === 'collapsed' ? (
          activeAccount && (
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <div className="flex cursor-pointer items-center">
                  <div className="relative">
                    <Avatar className="relative left-0.5 size-7 rounded-[5px]">
                      <AvatarImage
                        className="rounded-[5px]"
                        src={activeAccount?.picture || undefined}
                        alt={activeAccount?.name || activeAccount?.email}
                      />

                      <AvatarFallback className="rounded-[5px] text-[10px]">
                        {(activeAccount?.name || activeAccount?.email || '')
                          .split(' ')
                          .map((n: string) => n[0])
                          .join('')
                          .toUpperCase()
                          .slice(0, 2)}
                      </AvatarFallback>
                    </Avatar>
                  </div>
                </div>
              </DropdownMenuTrigger>
              <DropdownMenuContent
                className="w-(--radix-dropdown-menu-trigger-width) ml-3 min-w-56 bg-popover font-medium"
                align="end"
                side={'bottom'}
                sideOffset={8}
              >
                {session && activeAccount && (
                  <>
                    <div className="flex flex-col items-center p-3 text-center">
                      <Avatar className="border-border/50 mb-2 size-14 rounded-xl border">
                        <AvatarImage
                          className="rounded-xl"
                          src={
                            (activeAccount.picture ?? undefined) ||
                            (session.user.image ?? undefined)
                          }
                          alt={activeAccount.name || session.user.name || 'User'}
                        />
                        <AvatarFallback className="rounded-xl">
                          <span>
                            {(activeAccount.name || session.user.name || 'User')
                              .split(' ')
                              .map((n) => n[0])
                              .join('')
                              .toUpperCase()
                              .slice(0, 2)}
                          </span>
                        </AvatarFallback>
                      </Avatar>
                      <div className="w-full">
                        <div className="flex items-center justify-center gap-0.5 text-sm font-medium">
                          {activeAccount.name || session.user.name || 'User'}
                          {isPro && (
                            <BadgeCheck
                              className="h-4 w-4 text-background"
                              fill="#1D9BF0"
                            />
                          )}
                        </div>
                        <div className="text-muted-foreground text-xs">{activeAccount.email}</div>
                      </div>
                    </div>
                    <DropdownMenuSeparator />
                  </>
                )}
                <div className="space-y-1">
                  <>
                    <p className="text-muted-foreground px-2 py-1 text-[11px] font-medium">
                      {m['common.navUser.accounts']()}
                    </p>

                    {data?.connections
                      ?.filter((connection) => connection.id !== activeConnection?.id)
                      .map((connection) => {
                        const isEnabled = enabledConnectionIds.has(connection.id);
                        return (
                        <DropdownMenuItem
                          key={connection.id}
                          onClick={handleToggleVisibility(connection.id)}
                          className="flex cursor-pointer items-center gap-3 py-1"
                          style={{ opacity: isEnabled ? 1 : 0.5 }}
                        >
                          <div
                            className="size-2 shrink-0 rounded-full"
                            style={{ backgroundColor: connection.color ?? '#007AFF' }}
                          />
                          <Avatar className="size-7 rounded-lg">
                            <AvatarImage
                              className="rounded-lg"
                              src={connection.picture || undefined}
                              alt={connection.name || connection.email}
                            />
                            <AvatarFallback className="rounded-lg text-[10px]">
                              {(connection.name || connection.email)
                                .split(' ')
                                .map((n) => n[0])
                                .join('')
                                .toUpperCase()
                                .slice(0, 2)}
                            </AvatarFallback>
                          </Avatar>
                          <div className="-space-y-0.5">
                            <p className="text-[12px]">{connection.name || connection.email}</p>
                            {connection.name && (
                              <p className="text-muted-foreground text-[11px]">
                                {connection.email.length > 25
                                  ? `${connection.email.slice(0, 25)}...`
                                  : connection.email}
                              </p>
                            )}
                          </div>
                        </DropdownMenuItem>
                        );
                      })}
                    <AddConnectionDialog />

                    <DropdownMenuSeparator className="my-1" />

                    <DropdownMenuItem asChild>
                      <a href={getSettingsHref()} className="cursor-pointer">
                        <div className="flex items-center gap-2">
                          <Settings size={16} className="opacity-60" />
                          <p className="text-[13px] opacity-60">{m['common.actions.settings']()}</p>
                        </div>
                      </a>
                    </DropdownMenuItem>
                  </>
                </div>
                <>
                  <DropdownMenuSeparator className="mt-1" />
                  {/* Sync actions are user-facing (cache/re-sync help with stuck inboxes);
                      raw dev metrics (Connection ID, Shards) are only shown in dev mode */}
                  <p className="text-muted-foreground px-2 py-1 text-[11px] font-medium">Sync</p>
                  <DropdownMenuItem onClick={handleClearCache}>
                    <div className="flex items-center gap-2">
                      <Trash2 size={16} className="opacity-60" />
                      <p className="text-[13px] opacity-60">Clear Local Cache</p>
                    </div>
                  </DropdownMenuItem>
                  <DropdownMenuItem onClick={() => handleForceSync()}>
                    <div className="flex items-center gap-2">
                      <RefreshCcw size={16} className="opacity-60" />
                      <p className="text-[13px] opacity-60">Force re-sync</p>
                    </div>
                  </DropdownMenuItem>
                  <SyncingStatusIndicator
                    isSyncing={isSyncing}
                    storageSize={storageSize}
                    syncingFolders={syncingFolders}
                  />
                  {/* Dev-only: raw connection diagnostics — hidden in production to reduce noise */}
                  {import.meta.env.DEV && (
                    <>
                      <DropdownMenuItem onClick={handleCopyConnectionId}>
                        <div className="flex items-center gap-2">
                          <CopyCheckIcon size={16} className="opacity-60" />
                          <p className="text-[13px] opacity-60">Copy Connection ID</p>
                        </div>
                      </DropdownMenuItem>
                      <DropdownMenuItem>
                        <div className="flex items-center gap-2">
                          <p className="text-[13px] opacity-60">Shards: {shards}</p>
                        </div>
                      </DropdownMenuItem>
                    </>
                  )}
                  <DropdownMenuSeparator className="mt-1" />
                  <DropdownMenuItem onSelect={() => handleThemeToggle()} className="cursor-pointer">
                    <div className="flex w-full items-center gap-2">
                    {resolvedTheme === 'dark' ? (
                        <MoonIcon className="size-4 opacity-60" />
                      ) : (
                        <SunIcon className="size-4 opacity-60" />
                      )}
                      <p className="text-[13px] opacity-60">{m['common.navUser.appTheme']()}</p>
                    </div>
                  </DropdownMenuItem>
                  <DropdownMenuItem asChild>
                    <a
                      href="https://discord.gg/mail0"
                      target="_blank"
                      rel="noopener noreferrer"
                      className="w-full"
                    >
                      <div className="flex items-center gap-2">
                        <HelpCircle size={16} className="opacity-60" />
                        <p className="text-[13px] opacity-60">
                          {m['common.navUser.customerSupport']()}
                        </p>
                      </div>
                    </a>
                  </DropdownMenuItem>
                  <DropdownMenuItem className="cursor-pointer" onSelect={() => handleLogout()}>
                    <div className="flex items-center gap-2">
                      <LogOut size={16} className="opacity-60" />
                      <p className="text-[13px] opacity-60">{m['common.actions.logout']()}</p>
                    </div>
                  </DropdownMenuItem>
                  <DropdownMenuSeparator className="mt-1" />
                  <div className="text-muted-foreground/60 flex items-center justify-center gap-1 px-2 pb-2 pt-1 text-[10px]">
                    <a href="/privacy" className="hover:underline">
                      Privacy
                    </a>
                    <span>·</span>
                    <a href="/terms" className="hover:underline">
                      Terms
                    </a>
                  </div>
                </>
              </DropdownMenuContent>
            </DropdownMenu>
          )
        ) : (
          <div className="flex w-full items-center justify-between">
            <div className="flex items-center gap-2">
              {data ? (
                data.connections.slice(0, 4).map((connection) => {
                  const isEnabled = enabledConnectionIds.has(connection.id);
                  const isDefault = connection.id === activeConnection?.id;
                  const connectionColor = connection.color ?? '#007AFF';

                  return (
                    <ContextMenu key={connection.id}>
                      <ContextMenuTrigger asChild>
                        <Tooltip>
                          <TooltipTrigger asChild>
                            <div
                              onClick={handleToggleVisibility(connection.id)}
                              className="flex cursor-pointer items-center"
                              style={{
                                opacity: isEnabled ? 1 : 0.35,
                              }}
                            >
                              <div className="relative">
                                <Avatar
                                  className="size-7 rounded-[5px]"
                                  style={
                                    isEnabled && data.connections.length > 1
                                      ? { outline: `2px solid ${connectionColor}`, outlineOffset: '1px' }
                                      : undefined
                                  }
                                >
                                  <AvatarImage
                                    className="rounded-[5px]"
                                    src={connection.picture || undefined}
                                    alt={connection.name || connection.email}
                                  />
                                  <AvatarFallback className="rounded-[5px] text-[10px]">
                                    {(connection.name || connection.email)
                                      .split(' ')
                                      .map((n: string) => n[0])
                                      .join('')
                                      .toUpperCase()
                                      .slice(0, 2)}
                                  </AvatarFallback>
                                </Avatar>
                                {isDefault && data.connections.length > 1 && (
                                  <Star
                                    className="absolute -bottom-1.5 -right-1.5 size-3 rounded-full bg-background"
                                    style={{ fill: connectionColor, color: connectionColor }}
                                  />
                                )}
                              </div>
                            </div>
                          </TooltipTrigger>
                          <TooltipContent className="text-muted-foreground text-xs">
                            <div>
                              <p>{connection.email}</p>
                              {data.connections.length > 1 && (
                                <p className="text-[10px] opacity-60">
                                  Click to {isEnabled ? 'hide' : 'show'} · Right-click for more
                                </p>
                              )}
                            </div>
                          </TooltipContent>
                        </Tooltip>
                      </ContextMenuTrigger>
                      <ContextMenuContent>
                        <ContextMenuItem onClick={handleSetDefault(connection.id)} disabled={isDefault}>
                          <Star className="mr-2 size-4" />
                          {isDefault ? 'Default account' : 'Set as default'}
                        </ContextMenuItem>
                        <ContextMenuItem onClick={handleToggleVisibility(connection.id)} disabled={totalConnections <= 1}>
                          {isEnabled ? 'Hide from inbox' : 'Show in inbox'}
                        </ContextMenuItem>
                      </ContextMenuContent>
                    </ContextMenu>
                  );
                })
              ) : (
                <div className="flex cursor-pointer items-center">
                  <div className="relative">
                    <div className="bg-muted size-6 animate-pulse rounded-[5px]" />
                  </div>
                </div>
              )}

              {data && data.connections.length > 4 && (
                <DropdownMenu>
                  <DropdownMenuTrigger asChild>
                    <button className="hover:bg-muted flex h-7 w-7 cursor-pointer items-center justify-center rounded-[5px]">
                      <span className="text-[10px]">+{data.connections.length - 4}</span>
                    </button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent
                    className="ml-3 min-w-56 bg-popover font-medium"
                    align="end"
                    side={'bottom'}
                    sideOffset={8}
                  >
                    {data.connections.slice(4).map((connection) => {
                      const isEnabled = enabledConnectionIds.has(connection.id);
                      return (
                        <DropdownMenuItem
                          key={connection.id}
                          onClick={handleToggleVisibility(connection.id)}
                          className="flex cursor-pointer items-center gap-3 py-1"
                          style={{ opacity: isEnabled ? 1 : 0.5 }}
                        >
                          <div
                            className="size-2 rounded-full"
                            style={{ backgroundColor: connection.color ?? '#007AFF' }}
                          />
                          <Avatar className="size-7 rounded-lg">
                            <AvatarImage
                              className="rounded-lg"
                              src={connection.picture || undefined}
                              alt={connection.name || connection.email}
                            />
                            <AvatarFallback className="rounded-lg text-[10px]">
                              {(connection.name || connection.email)
                                .split(' ')
                                .map((n) => n[0])
                                .join('')
                                .toUpperCase()
                                .slice(0, 2)}
                            </AvatarFallback>
                          </Avatar>
                          <div className="-space-y-0.5">
                            <p className="text-[12px]">{connection.name || connection.email}</p>
                            {connection.name && (
                              <p className="text-muted-foreground text-[11px]">
                                {connection.email.length > 25
                                  ? `${connection.email.slice(0, 25)}...`
                                  : connection.email}
                              </p>
                            )}
                          </div>
                        </DropdownMenuItem>
                      );
                    })}
                  </DropdownMenuContent>
                </DropdownMenu>
              )}

              {isPro ? (
                <AddConnectionDialog>
                  <Button className="hover:bg-accent flex h-7 w-7 cursor-pointer items-center justify-center rounded-[5px] border border-dashed bg-transparent px-0 text-foreground/60 transition-colors">
                    <Plus className="size-4" />
                  </Button>
                </AddConnectionDialog>
              ) : (
                <>
                  <Button
                    onClick={() => setPricingDialog('true')}
                    className="hover:bg-accent flex h-7 w-7 cursor-pointer items-center justify-center rounded-[5px] border border-dashed bg-transparent px-0 text-foreground/60 transition-colors"
                  >
                    <Plus className="size-4" />
                  </Button>
                </>
              )}
            </div>

            <div className="flex items-center justify-center gap-1">
              {/* {isSessionPending ? null : !session.user.phoneNumberVerified ? (
                <SetupInboxDialog />
              ) : (
                <CallInboxDialog />
              )} */}
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button variant="ghost" className={cn('md:h-fit md:px-2')}>
                    <ThreeDots className="fill-iconLight dark:fill-iconDark" />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent
                  className="ml-3 min-w-56 bg-popover font-medium"
                  align="end"
                  side={'bottom'}
                  sideOffset={8}
                >
                  <div className="space-y-1">
                    {billingCustomer?.stripe_id ? (
                      <DropdownMenuItem onClick={() => openBillingPortal()}>
                        <div className="flex items-center gap-2">
                          <BanknoteIcon size={16} className="opacity-60" />
                          <p className="text-[13px] opacity-60">Billing</p>
                        </div>
                      </DropdownMenuItem>
                    ) : null}
                  </div>
                  {import.meta.env.DEV && (
                    <>
                      <p className="text-muted-foreground px-2 py-1 text-[11px] font-medium">Debug</p>
                      <DropdownMenuItem onClick={handleCopyConnectionId}>
                        <div className="flex items-center gap-2">
                          <CopyCheckIcon size={16} className="opacity-60" />
                          <p className="text-[13px] opacity-60">Copy Connection ID</p>
                        </div>
                      </DropdownMenuItem>
                      <DropdownMenuItem onClick={handleClearCache}>
                        <div className="flex items-center gap-2">
                          <Trash2 size={16} className="opacity-60" />
                          <p className="text-[13px] opacity-60">Clear Local Cache</p>
                        </div>
                      </DropdownMenuItem>
                      <DropdownMenuItem onClick={() => handleForceSync()}>
                        <div className="flex items-center gap-2">
                          <RefreshCcw size={16} className="opacity-60" />
                          <p className="text-[13px] opacity-60">Force re-sync</p>
                        </div>
                      </DropdownMenuItem>
                      <SyncingStatusIndicator
                        isSyncing={isSyncing}
                        storageSize={storageSize}
                        syncingFolders={syncingFolders}
                      />
                      <DropdownMenuItem>
                        <div className="flex items-center gap-2">
                          <p className="text-[13px] opacity-60">Shards: {shards}</p>
                        </div>
                      </DropdownMenuItem>
                    </>
                  )}
                  <DropdownMenuSeparator className="mt-1" />
                  <DropdownMenuItem onClick={handleThemeToggle} className="cursor-pointer">
                    <div className="flex w-full items-center gap-2">
                      {theme === 'dark' ? (
                        <MoonIcon className="size-4 opacity-60" />
                      ) : (
                        <SunIcon className="size-4 opacity-60" />
                      )}
                      <p className="text-[13px] opacity-60">{m['common.navUser.appTheme']()}</p>
                    </div>
                  </DropdownMenuItem>
                  <DropdownMenuItem>
                    <a
                      href="https://discord.gg/mail0"
                      target="_blank"
                      rel="noopener noreferrer"
                      className="w-full"
                    >
                      <div className="flex items-center gap-2">
                        <HelpCircle size={16} className="opacity-60" />
                        <p className="text-[13px] opacity-60">
                          {m['common.navUser.customerSupport']()}
                        </p>
                      </div>
                    </a>
                  </DropdownMenuItem>
                  <DropdownMenuItem className="cursor-pointer" onClick={handleLogout}>
                    <div className="flex items-center gap-2">
                      <LogOut size={16} className="opacity-60" />
                      <p className="text-[13px] opacity-60">{m['common.actions.logout']()}</p>
                    </div>
                  </DropdownMenuItem>
                  <DropdownMenuSeparator className="mt-1" />
                  <div className="text-muted-foreground/60 flex items-center justify-center gap-1 px-2 pb-2 pt-1 text-[10px]">
                    <a href="/privacy" className="hover:underline">
                      Privacy
                    </a>
                    <span>·</span>
                    <a href="/terms" className="hover:underline">
                      Terms
                    </a>
                  </div>
                </DropdownMenuContent>
              </DropdownMenu>
            </div>
          </div>
        )}
      </div>

      {state !== 'collapsed' && (
        <div className="mt-1.5 flex items-center justify-between gap-2">
          <div className="mt-px flex flex-col items-start gap-0.5 space-y-0.5">
            <div className="flex items-center gap-1 text-[13px] leading-none text-foreground">
              <p className={cn('max-w-[14.5ch] truncate text-[13px]')}>
                {activeAccount?.name || session.user.name || 'User'}
              </p>
              {isPro ? (
                <BadgeCheck className="h-4 w-4 text-background" fill="#1D9BF0" />
              ) : null}
            </div>
            <div className="h-5 max-w-[200px] overflow-hidden truncate text-xs font-normal leading-none text-muted-foreground">
              {activeAccount?.email || session.user.email}
            </div>
            {!isPro && (
              <button
                onClick={() => setPricingDialog('true')}
                className="flex h-5 items-center gap-1 rounded-full border px-1 pr-1.5 transition-colors hover:bg-accent"
              >
                <BadgeCheck className="h-3.5 w-3.5 text-background" fill="#1D9BF0" />
                <span className="text-muted-foreground text-[10px] uppercase tracking-wide">Get verified</span>
              </button>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
