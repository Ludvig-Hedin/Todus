import { SidebarToggle } from '@/components/ui/sidebar-toggle';
import { AppSidebar } from '@/components/ui/app-sidebar';
import { ScrollArea } from '@/components/ui/scroll-area';

export function SettingsLayoutContent({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex h-full w-full md:py-1 bg-background">
      <AppSidebar className="hidden lg:flex" />
      <div className="w-full flex-1">
        <div className="bg-card h-dvh max-w-full flex-1 flex-col overflow-y-auto overflow-x-hidden border border-border/60 md:mr-1 md:flex md:h-[calc(100dvh-(0.5rem))] md:rounded-xl md:shadow-[0_1px_3px_0_rgba(0,0,0,0.04)]">
          <div className="sticky top-0 z-15 flex items-center justify-between gap-1.5 border-b border-border/60 p-2 px-5 transition-colors md:min-h-12">
            <SidebarToggle className="h-fit px-2" />
          </div>
          <ScrollArea className="h-[calc(100dvh-49px)] overflow-hidden pt-0">
            <div className="p-5">{children}</div>
          </ScrollArea>
        </div>
      </div>
    </div>
  );
}
