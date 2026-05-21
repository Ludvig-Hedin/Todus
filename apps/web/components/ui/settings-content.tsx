import { SidebarToggle } from '@/components/ui/sidebar-toggle';
import { AppSidebar } from '@/components/ui/app-sidebar';
import { ScrollArea } from '@/components/ui/scroll-area';

export function SettingsLayoutContent({ children }: { children: React.ReactNode }) {
  return (
    <div className="bg-background flex h-full w-full">
      <AppSidebar className="hidden lg:flex" />
      <div className="flex w-full flex-1 flex-col">
        <div className="sticky top-0 z-15 flex min-h-11 items-center justify-between gap-1.5 px-4 py-2 transition-colors">
          <SidebarToggle className="h-fit px-2" />
        </div>
        <ScrollArea className="h-[calc(100dvh-44px)] overflow-hidden">
          <div className="mx-auto max-w-3xl px-6 pb-12 pt-2">{children}</div>
        </ScrollArea>
      </div>
    </div>
  );
}
