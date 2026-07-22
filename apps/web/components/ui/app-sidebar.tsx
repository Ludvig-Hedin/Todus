import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog';
import { Sidebar, SidebarContent, SidebarFooter, SidebarHeader } from '@/components/ui/sidebar';
import { navigationConfig, bottomNavItems } from '@/config/navigation';
import { useAIFullScreen } from '@/hooks/use-ai-sidebar';
import { useSidebar } from '@/components/ui/sidebar';
import { CreateEmail } from '../create/create-email';
// import { useMutation } from '@tanstack/react-query';
import { PencilCompose, X } from '../icons/icons';
import { useBilling } from '@/hooks/use-billing';
import { useIsMobile } from '@/hooks/use-mobile';
import React, { useMemo, useState } from 'react';
import { Button } from '@/components/ui/button';
import { useSession } from '@/lib/auth-client';
import { useStats } from '@/hooks/use-stats';
import { useLocation } from 'react-router';
// import { useTRPC } from '@/providers/query-provider';
import { APP_NAME } from '@/lib/branding';
import { cn, FOLDERS } from '@/lib/utils';
import { m } from '@/paraglide/messages';
// import { Video } from 'lucide-react';
import { NavUser } from './nav-user';
import { NavMain } from './nav-main';
import { useQueryState } from 'nuqs';
// import { toast } from 'sonner';

export function AppSidebar({ ...props }: React.ComponentProps<typeof Sidebar>) {
  const { isPro, isLoading } = useBilling();
  //   const trpc = useTRPC();
  //   const { mutateAsync: createMeet } = useMutation(trpc.meet.create.mutationOptions());
  const [showUpgrade, setShowUpgrade] = useState(() => {
    if (typeof window !== 'undefined') {
      return localStorage.getItem('hideUpgradeCard') !== 'true';
    }
    return true;
  });
  const [, setPricingDialog] = useQueryState('pricingDialog');
  const { isFullScreen } = useAIFullScreen();
  const { data: stats } = useStats();
  const location = useLocation();
  const { data: session } = useSession();
  const { currentSection, navItems } = useMemo(() => {
    // Find which section we're in based on the pathname
    const section = Object.entries(navigationConfig).find(([, config]) =>
      location.pathname.startsWith(config.path),
    );

    const currentSection = section?.[0] || 'mail';
    if (navigationConfig[currentSection]) {
      const items = navigationConfig[currentSection].sections.map((section) => ({
        ...section,
        items: section.items.map((item) => ({
          ...item,
          children: item.children?.map((child) => ({ ...child })),
        })),
      }));

      if (currentSection === 'mail' && stats && stats.length) {
        const emailItem = items
          .flatMap((section) => section.items)
          .find((item) => item.id === 'email');

        if (emailItem?.children) {
          emailItem.children = emailItem.children.map((child) => ({
            ...child,
            badge:
              child.id === 'inbox'
                ? stats.find((stat) => stat.label?.toLowerCase() === FOLDERS.INBOX)?.count
                : child.id === 'sent'
                  ? stats.find((stat) => stat.label?.toLowerCase() === FOLDERS.SENT)?.count
                  : undefined,
          }));
        }
      }

      return { currentSection, navItems: items };
    } else {
      return {
        currentSection: '',
        navItems: [],
      };
    }
  }, [location.pathname, stats]);

  const showComposeButton = currentSection === 'mail';
  const { state } = useSidebar();

  //   const handleCreateMeet = async () => {
  //     try {
  //       const {
  //         data: { id },
  //       } = await createMeet();
  //       navigator.clipboard.writeText(`https://meet.todus.app/${id}`);
  //       toast.success('Meeting linked copied to clipboard');
  //     } catch (error) {
  //       console.error(error);
  //       toast.error('Failed to create meeting');
  //     }
  //   };

  return (
    <div>
      {!isFullScreen && (
        <Sidebar
          collapsible="icon"
          {...props}
          className={`bg-sidebar dark:bg-sidebar flex h-screen select-none flex-col items-center pb-2`}
        >
          <SidebarHeader
            className={`relative top-2 flex flex-col gap-2 ${state === 'collapsed' ? 'px-2' : 'md:px-2'}`}
          >
            {session && <NavUser />}

            {showComposeButton && (
              <div className="flex gap-1">
                <div className={cn('w-full')}>
                  <ComposeButton />
                </div>
                {/* {isPro ? (
                  <button
                    onClick={handleCreateMeet}
                    className="hover:bg-muted-foreground/10 inline-flex h-8 w-[20%] items-center justify-center gap-1 overflow-hidden rounded-lg border bg-white px-1.5 dark:border-none dark:bg-[#313131]"
                  >
                    <Video className="text-muted-foreground h-4 w-4" />
                  </button>
                ) : null} */}
              </div>
            )}
          </SidebarHeader>
          <SidebarContent
            className={`scrollbar scrollbar-w-1 scrollbar-thumb-accent/40 scrollbar-track-transparent hover:scrollbar-thumb-accent scrollbar-thumb-rounded-full overflow-x-hidden py-0 pt-0 ${state !== 'collapsed' ? 'mt-4 md:px-2' : 'px-2'}`}
          >
            <div className="flex-1 py-0">
              <NavMain items={navItems} />
            </div>
          </SidebarContent>

          {!isLoading && !isPro && showUpgrade && state !== 'collapsed' && (
            <div className="relative mx-3 mb-3 mt-2 rounded-lg border bg-white px-3.5 py-3.5 dark:border-[#252527] dark:bg-[#1C1C1E]">
              <Button
                variant="ghost"
                size="icon"
                className="absolute right-1.5 top-1.5 h-5 w-5 rounded-full opacity-40 hover:opacity-70 [&>svg]:h-2.5 [&>svg]:w-2.5"
                onClick={() => {
                  setShowUpgrade(false);
                  localStorage.setItem('hideUpgradeCard', 'true');
                }}
              >
                <X className="h-2.5 w-2.5 fill-current" />
              </Button>
              <div className="flex items-start gap-2">
                <div className="flex-1 space-y-0.5">
                  {/* Use APP_NAME from branding.ts — avoids hardcoded "Todus" diverging from branding source */}
                  <h3 className="text-foreground text-[13px] font-semibold">Get {APP_NAME} Pro</h3>
                  <p className="text-muted-foreground text-[12px] leading-snug">
                    Unlimited AI chats, auto-labeling, writing assistant, and more.
                  </p>
                </div>
              </div>
              <button
                onClick={() => setPricingDialog('true')}
                className="bg-mainBlue hover:bg-mainBlue/90 mt-2.5 inline-flex h-7 w-full items-center justify-center gap-0.5 overflow-hidden rounded-full px-2 transition-colors"
              >
                <span className="whitespace-nowrap text-[12px] font-medium leading-none text-white">
                  Start 7 day free trial
                </span>
              </button>
            </div>
          )}

          <SidebarFooter className={`px-0 pb-0 ${state === 'collapsed' ? 'md:px-2' : 'md:px-3'}`}>
            <NavMain items={bottomNavItems} />
          </SidebarFooter>
        </Sidebar>
      )}
    </div>
  );
}

function ComposeButton() {
  const { state } = useSidebar();
  const isMobile = useIsMobile();

  const [dialogOpen, setDialogOpen] = useQueryState('isComposeOpen');
  const [, setDraftId] = useQueryState('draftId');
  const [, setTo] = useQueryState('to');
  const [, setActiveReplyId] = useQueryState('activeReplyId');
  const [, setMode] = useQueryState('mode');

  const handleOpenChange = async (open: boolean) => {
    if (!open) {
      setDialogOpen(null);
    } else {
      setDialogOpen('true');
    }
    setDraftId(null);
    setTo(null);
    setActiveReplyId(null);
    setMode(null);
  };
  return (
    <Dialog open={!!dialogOpen} onOpenChange={handleOpenChange}>
      <DialogTrigger asChild>
        <button
          type="button"
          className="bg-mainBlue hover:bg-mainBlue/90 duration-(--motion-duration-fast) ease-(--motion-easing-standard) relative mb-1 inline-flex h-8 w-full cursor-pointer items-center justify-center gap-1 self-stretch overflow-hidden rounded-full transition-all dark:border-none"
        >
          {state === 'collapsed' && !isMobile ? (
            <PencilCompose className="mt-0.5 fill-white text-black" />
          ) : (
            <div className="flex items-center justify-center gap-2.5 pl-0.5 pr-1">
              <PencilCompose className="fill-white" />
              <div className="justify-start text-sm leading-none text-white">
                {m['common.commandPalette.commands.newEmail']()}
              </div>
            </div>
          )}
        </button>
      </DialogTrigger>

      <DialogContent className="bg-background h-screen w-screen max-w-none border-none p-0 shadow-none">
        <DialogTitle className="sr-only">Compose email</DialogTitle>
        <DialogDescription className="sr-only">
          Compose a new email message with recipients, subject, body, and attachments.
        </DialogDescription>
        <CreateEmail />
      </DialogContent>
    </Dialog>
  );
}
