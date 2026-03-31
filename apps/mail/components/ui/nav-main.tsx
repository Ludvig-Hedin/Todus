import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { SidebarGroup, SidebarMenu, SidebarMenuButton, SidebarMenuItem } from './sidebar';
import { useCommandPalette } from '../context/command-palette-context.jsx';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { type NavChildItem, type NavItem } from '@/config/navigation';
import { LabelDialog } from '@/components/labels/label-dialog';
import { useActiveConnection } from '@/hooks/use-connections';
import { useSidebar } from '../context/sidebar-context';
import { useTRPC } from '@/providers/query-provider';
import { useMutation } from '@tanstack/react-query';
import { ChevronRight, Plus } from 'lucide-react';
import type { Label as LabelType } from '@/types';
import { Link, useLocation } from 'react-router';
import { Button } from '@/components/ui/button';
import { useLabels } from '@/hooks/use-labels';
import { Badge } from '@/components/ui/badge';
import { useStats } from '@/hooks/use-stats';
import SidebarLabels from './sidebar-labels';
import { BASE_URL } from '@/lib/constants';
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
  const searchParams = useMemo(() => new URLSearchParams(location.search), [location.search]);
  const trpc = useTRPC();
  const { mutateAsync: createLabel } = useMutation(trpc.labels.create.mutationOptions());
  const { userLabels, refetch } = useLabels();
  const { state } = useSidebar();
  const { data: activeAccount } = useActiveConnection();

  const isValidInternalUrl = useCallback((url: string) => {
    if (!url) return false;
    if (url.startsWith('/')) return true;

    try {
      const urlObj = new URL(url, BASE_URL);
      return urlObj.origin === BASE_URL;
    } catch {
      return false;
    }
  }, []);

  const getHref = useCallback(
    (item: NavItemProps) => {
      const currentFrom = searchParams.get('from');

      if (item.isSettingsButton) {
        return `${item.url}?from=${encodeURIComponent(pathname)}`;
      }

      if (item.isBackButton) {
        if (currentFrom) {
          const decodedFrom = decodeURIComponent(currentFrom);
          if (isValidInternalUrl(decodedFrom)) {
            return decodedFrom;
          }
        }
        return '/mail/home';
      }

      if (item.isSettingsPage && currentFrom) {
        const decodedFrom = decodeURIComponent(currentFrom);
        if (isValidInternalUrl(decodedFrom)) {
          return `${item.url}?from=${encodeURIComponent(currentFrom)}`;
        }
        return `${item.url}?from=/mail/home`;
      }

      return item.url;
    },
    [isValidInternalUrl, pathname, searchParams],
  );

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
                    <NavItemExpandable
                      key={item.url}
                      {...item}
                      href={getHref(item)}
                      isActive={
                        item.children.some((child) => isUrlActive(child.url)) ||
                        isUrlActive(item.url)
                      }
                    />
                  ) : (
                    <NavItemRow
                      key={item.url}
                      {...item}
                      href={getHref(item)}
                      isActive={isUrlActive(item.url)}
                      target={item.target}
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
                ) : null}
              </div>

              {activeAccount ? <SidebarLabels data={userLabels ?? []} /> : null}
            </SidebarMenuItem>
          </Collapsible>
        )}
      </SidebarMenu>
    </SidebarGroup>
  );
}

function NavItemExpandable(item: NavItemProps & { href: string; children: NavChildItem[] }) {
  const { state, setOpenMobile } = useSidebar();
  const { clearAllFilters } = useCommandPalette();
  const { data: stats } = useStats();
  const [open, setOpen] = useState(item.isActive ?? false);

  useEffect(() => {
    setOpen(item.isActive ?? false);
  }, [item.isActive]);

  if (state === 'collapsed') {
    return <NavItemRow {...item} href={item.href} title={item.title} />;
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
  const isActive = location.pathname === child.url;
  const stat = stats?.find((entry) => entry.label?.toLowerCase() === child.id?.toLowerCase());
  const badge = child.badge ?? stat?.count;

  return (
    <SidebarMenuButton
      asChild
      className={cn(
        'hover:bg-accent min-h-8 transition-colors duration-100',
        isActive && 'bg-accent text-accent-foreground',
      )}
    >
      <Link to={child.url} onClick={onNavigate}>
        <span className="text-[13px]">{child.title}</span>
        {typeof badge === 'number' ? (
          <Badge className="text-muted-foreground ml-auto shrink-0 rounded-full border-none bg-transparent">
            {badge.toLocaleString()}
          </Badge>
        ) : null}
      </Link>
    </SidebarMenuButton>
  );
}

function NavItemRow(item: NavItemProps & { href: string }) {
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
        {item.icon && <item.icon ref={iconRef} className="relative mr-2.5 h-3 w-3.5" />}
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
        {item.icon && <item.icon ref={iconRef} className="mr-2 shrink-0" />}
        <p className="relative bottom-px mt-0.5 min-w-0 flex-1 truncate text-[13px]">
          {item.title}
        </p>
        {stats?.some((stat) => stat.label?.toLowerCase() === item.id?.toLowerCase()) ? (
          <Badge className="text-muted-foreground ml-auto shrink-0 rounded-full border-none bg-transparent">
            {stats
              .find((stat) => stat.label?.toLowerCase() === item.id?.toLowerCase())
              ?.count?.toLocaleString() ?? '0'}
          </Badge>
        ) : null}
      </Link>
    </SidebarMenuButton>
  );
}
