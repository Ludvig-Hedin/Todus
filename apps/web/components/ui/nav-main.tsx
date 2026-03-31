import {
  SidebarGroup,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from './sidebar';
import {
  Collapsible,
  CollapsibleTrigger,
  CollapsibleContent,
} from '@/components/ui/collapsible';
import { useCommandPalette } from '../context/command-palette-context.jsx';
import { LabelDialog } from '@/components/labels/label-dialog';
import { useActiveConnection } from '@/hooks/use-connections';
import { useMutation, useQuery } from '@tanstack/react-query';
import { useSidebar } from '../context/sidebar-context';
import { useTRPC } from '@/providers/query-provider';
import { type NavItem, type NavChildItem } from '@/config/navigation';
import type { Label as LabelType } from '@/types';
import { Link, useLocation } from 'react-router';
import { m } from '../../paraglide/messages.js';
import { Button } from '@/components/ui/button';
import { useLabels } from '@/hooks/use-labels';
import { Badge } from '@/components/ui/badge';
import { useStats } from '@/hooks/use-stats';
import SidebarLabels from './sidebar-labels';
import { useCallback, useEffect, useRef, useState } from 'react';
import { BASE_URL } from '@/lib/constants';
import { ChevronRight, Plus } from 'lucide-react';
import { cn } from '@/lib/utils';
import { toast } from 'sonner';
import * as React from 'react';

interface IconProps extends React.SVGProps<SVGSVGElement> {
  ref?: React.Ref<SVGSVGElement>;
  startAnimation?: () => void;
  stopAnimation?: () => void;
}
interface NavItemProps extends NavItem {
  isActive?: boolean;
  isExpanded?: boolean;
  onClick?: (e: React.MouseEvent<HTMLAnchorElement>) => void;
  suffix?: React.ComponentType<IconProps>;
  isSettingsPage?: boolean;
}

interface NavMainProps {
  items: {
    id?: string;
    title: string;
    items: NavItemProps[];
    isActive?: boolean;
  }[];
}

type IconRefType = SVGSVGElement & {
  startAnimation?: () => void;
  stopAnimation?: () => void;
};

export function NavMain({ items }: NavMainProps) {
  const location = useLocation();
  const pathname = location.pathname;
  const searchParams = new URLSearchParams(location.search);

  const trpc = useTRPC();

  const { mutateAsync: createLabel } = useMutation(trpc.labels.create.mutationOptions());

  const { userLabels, refetch } = useLabels();

  const { state } = useSidebar();

  /**
   * Validates URLs to prevent open redirect vulnerabilities.
   * Only allows two types of URLs:
   * 1. Absolute paths that start with '/' (e.g., '/mail', '/settings')
   * 2. Full URLs that match our application's base URL
   *
   * @param url - The URL to validate
   * @returns boolean - True if the URL is internal and safe to use
   */
  const isValidInternalUrl = useCallback((url: string) => {
    if (!url) return false;
    // Accept absolute paths as they are always internal
    if (url.startsWith('/')) return true;
    try {
      const urlObj = new URL(url, BASE_URL);
      // Prevent redirects to external domains by checking against our base URL
      return urlObj.origin === BASE_URL;
    } catch {
      return false;
    }
  }, []);

  const getHref = useCallback(
    (item: NavItemProps) => {
      // Get the current 'from' parameter
      const currentFrom = searchParams.get('from');

      // Handle settings navigation
      if (item.isSettingsButton) {
        // Include current path with category query parameter if present
        const currentPath = pathname;
        return `${item.url}?from=${encodeURIComponent(currentPath)}`;
      }

      // Handle back button with redirect protection
      if (item.isBackButton) {
        if (currentFrom) {
          const decodedFrom = decodeURIComponent(currentFrom);
          if (isValidInternalUrl(decodedFrom)) {
            return decodedFrom;
          }
        }
        // Fall back to safe default if URL is missing or invalid
        return '/mail';
      }

      // Handle settings pages navigation
      if (item.isSettingsPage && currentFrom) {
        // Validate and sanitize the 'from' parameter to prevent open redirects
        const decodedFrom = decodeURIComponent(currentFrom);
        if (isValidInternalUrl(decodedFrom)) {
          return `${item.url}?from=${encodeURIComponent(currentFrom)}`;
        }
        // Fall back to safe default if URL validation fails
        return `${item.url}?from=/mail`;
      }

      return item.url;
    },
    [pathname, searchParams, isValidInternalUrl],
  );

  const { data: activeAccount } = useActiveConnection();

  const isUrlActive = useCallback(
    (url: string) => {
      const urlObj = new URL(
        url,
        typeof window === 'undefined' ? BASE_URL : window.location.origin,
      );
      const cleanPath = pathname.replace(/\/$/, '');
      const cleanUrl = urlObj.pathname.replace(/\/$/, '');

      if (cleanPath !== cleanUrl) return false;

      const urlParams = new URLSearchParams(urlObj.search);
      const currentParams = new URLSearchParams(searchParams);

      for (const [key, value] of urlParams) {
        if (currentParams.get(key) !== value) return false;
      }
      return true;
    },
    [pathname, searchParams],
  );

  const onSubmit = async (data: LabelType) => {
    try {
      const promise = createLabel(data).then(async (result) => {
        await refetch();
        return result;
      });

      toast.promise(promise, {
        loading: 'Creating label...',
        success: 'Label created successfully',
        error: 'Failed to create label',
      });

      await promise;
    } catch (error) {
      console.error('Failed to create label:', error);
    }
  };

  return (
    <SidebarGroup className={`${state !== 'collapsed' ? '' : 'mt-1'} space-y-2.5 py-0 md:px-0`}>
      <SidebarMenu>
        {/* Feedback link removed — feedback.todus.app subdomain is empty */}
        {items.map((section) => (
          <Collapsible
            key={section.id ?? section.title}
            defaultOpen={section.isActive}
            className="group/collapsible"
          >
            <SidebarMenuItem>
              {state !== 'collapsed' ? (
                section.title ? (
                  <p className="text-muted-foreground mx-2 mb-1.5 text-[11px] font-medium uppercase tracking-wide">
                    {section.title}
                  </p>
                ) : null
              ) : (
                <div className="bg-border mx-2 mb-3 mt-1.5 h-px" />
              )}
              <div className="z-20 space-y-0.5 pb-2">
                {section.items.map((item) =>
                  item.children && item.children.length > 0 ? (
                    // Items with children render as collapsible expandable groups
                    <NavItemExpandable
                      key={item.url}
                      {...item}
                      // Non-null assertion safe: guarded by item.children check above
                      children={item.children!}
                      isActive={
                        item.children.some((child) => isUrlActive(child.url)) ||
                        isUrlActive(item.url)
                      }
                      href={getHref(item)}
                    />
                  ) : (
                    <NavItem
                      key={item.url}
                      {...item}
                      isActive={isUrlActive(item.url)}
                      href={getHref(item)}
                      target={item.target}
                      title={item.title}
                    />
                  ),
                )}
              </div>
            </SidebarMenuItem>
          </Collapsible>
        ))}
        {!pathname.includes('/settings') && state !== 'collapsed' && (
          <Collapsible defaultOpen={true} className="group/collapsible flex-col">
            <SidebarMenuItem className="mb-4" style={{ height: 'auto' }}>
              <div className="mx-2 mb-4 flex items-center justify-between">
                <span className="text-muted-foreground text-[11px] font-medium uppercase tracking-wide">
                  {activeAccount?.providerId === 'google' ? 'Labels' : 'Folders'}
                </span>
                {activeAccount?.providerId === 'google' ? (
                  <LabelDialog
                    trigger={
                      <Button
                        variant="ghost"
                        size="icon"
                        className="mr-1 h-4 w-4 p-0 hover:bg-transparent"
                      >
                        <Plus className="text-muted-foreground h-3 w-3" />
                      </Button>
                    }
                    onSubmit={onSubmit}
                  />
                ) : activeAccount?.providerId === 'microsoft' ? null : null}
              </div>

              {activeAccount ? <SidebarLabels data={userLabels ?? []} /> : null}
            </SidebarMenuItem>
          </Collapsible>
        )}
      </SidebarMenu>
    </SidebarGroup>
  );
}

// ─── NavItemExpandable ────────────────────────────────────────────────────────
// Renders a parent nav item with a chevron that expands to show child links.
// Matches the macOS sidebar pattern where Email expands to Inbox/Drafts/Sent.

function NavItemExpandable(
  item: NavItemProps & { href: string; children: NavChildItem[] },
) {
  const { state, setOpenMobile } = useSidebar();
  const { clearAllFilters } = useCommandPalette();
  const { data: stats } = useStats();

  // Default open when any child is active
  const [open, setOpen] = useState(item.isActive ?? false);

  // Keep open state in sync when active route changes (e.g., external navigation)
  useEffect(() => {
    setOpen(item.isActive ?? false);
  }, [item.isActive]);

  // When collapsed to icon-only, navigate to the parent URL (inbox default)
  if (state === 'collapsed') {
    return (
      <NavItem
        {...item}
        href={item.href}
        title={item.title}
      />
    );
  }

  return (
    <Collapsible open={open} onOpenChange={setOpen}>
      <CollapsibleTrigger asChild>
        <SidebarMenuButton
          className={cn(
            'hover:bg-accent flex w-full items-center transition-colors duration-100',
            item.isActive && 'bg-accent text-accent-foreground',
          )}
        >
          {item.icon && <item.icon className="mr-2 h-3.5 w-3.5 shrink-0" />}
          <p className="relative bottom-px mt-0.5 min-w-0 flex-1 truncate text-[13px]">
            {item.title}
          </p>
          {/* Chevron rotates 90° when expanded */}
          <ChevronRight
            className={cn(
              'text-muted-foreground ml-auto h-3.5 w-3.5 shrink-0 transition-transform duration-200',
              open && 'rotate-90',
            )}
          />
        </SidebarMenuButton>
      </CollapsibleTrigger>

      <CollapsibleContent>
        <div className="mt-0.5 space-y-0.5 pb-1 pl-[1.375rem]">
          {item.children.map((child) => (
            <NavChildRow
              key={child.url}
              child={child}
              stats={stats}
              onNavigate={() => {
                clearAllFilters();
                setOpenMobile(false);
              }}
            />
          ))}
        </div>
      </CollapsibleContent>
    </Collapsible>
  );
}

// ─── NavChildRow ──────────────────────────────────────────────────────────────
// Indented child link inside an expandable group. Shows unread badge via stats.

function NavChildRow({
  child,
  stats,
  onNavigate,
}: {
  child: NavChildItem;
  stats: ReturnType<typeof useStats>['data'];
  onNavigate: () => void;
}) {
  const location = useLocation();
  const pathname = location.pathname;

  // Simple path match — children don't have query params
  const isActive = pathname === child.url || pathname.replace(/\/$/, '') === child.url;

  const unreadCount = stats?.find(
    (stat) => stat.label?.toLowerCase() === child.id?.toLowerCase(),
  )?.count;

  return (
    <SidebarMenuButton
      asChild
      className={cn(
        'hover:bg-accent flex items-center transition-colors duration-100',
        isActive && 'bg-accent text-accent-foreground',
      )}
      onClick={onNavigate}
    >
      <Link to={child.url}>
        <p className="relative bottom-px mt-0.5 min-w-0 flex-1 truncate text-[13px]">
          {child.title}
        </p>
        {unreadCount != null && unreadCount > 0 && (
          <Badge className="text-muted-foreground ml-auto shrink-0 rounded-full border-none bg-transparent text-[11px]">
            {unreadCount.toLocaleString()}
          </Badge>
        )}
      </Link>
    </SidebarMenuButton>
  );
}

// ─── NavItem ──────────────────────────────────────────────────────────────────

function NavItem(item: NavItemProps & { href: string }) {
  const iconRef = useRef<IconRefType>(null);
  const { data: stats } = useStats();
  const { clearAllFilters } = useCommandPalette();

  const { state, setOpenMobile } = useSidebar();

  if (item.disabled) {
    return (
      <SidebarMenuButton
        tooltip={state === 'collapsed' ? item.title : undefined}
        className="flex cursor-not-allowed items-center opacity-50"
      >
        {item.icon && (
          <item.icon ref={iconRef} className="relative mr-2 h-3.5 w-3.5 shrink-0" />
        )}
        <p className="relative bottom-px mt-0.5 truncate text-[13px]">{item.title}</p>
      </SidebarMenuButton>
    );
  }

  const handleClick = (e: React.MouseEvent) => {
    if (item.onClick) {
      item.onClick(e as React.MouseEvent<HTMLAnchorElement>);
    }
    clearAllFilters();
    setOpenMobile(false);
  };

  return (
    <Collapsible defaultOpen={item.isActive}>
      <CollapsibleTrigger asChild>
        <SidebarMenuButton
          asChild
          tooltip={state === 'collapsed' ? item.title : undefined}
          className={cn(
            'hover:bg-accent flex items-center transition-colors duration-100',
            item.isActive && 'bg-accent text-accent-foreground',
          )}
          onClick={handleClick}
        >
          <Link target={item.target} to={item.href}>
            {item.icon && (
              <item.icon ref={iconRef} className="mr-2 h-3.5 w-3.5 shrink-0" />
            )}
            <p className="relative bottom-px mt-0.5 min-w-0 flex-1 truncate text-[13px]">
              {item.title}
            </p>
            {stats &&
              stats.some((stat) => stat.label?.toLowerCase() === item.id?.toLowerCase()) && (
                <Badge className="text-muted-foreground ml-auto shrink-0 rounded-full border-none bg-transparent text-[11px]">
                  {stats
                    .find((stat) => stat.label?.toLowerCase() === item.id?.toLowerCase())
                    ?.count?.toLocaleString() || '0'}
                </Badge>
              )}
          </Link>
        </SidebarMenuButton>
      </CollapsibleTrigger>
    </Collapsible>
  );
}
