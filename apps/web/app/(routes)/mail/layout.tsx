import { HotkeyProviderWrapper } from '@/components/providers/hotkey-provider-wrapper';
import { OnboardingWrapper } from '@/components/onboarding';
import { ConnectionWrapper } from '@/components/connection/connection-wrapper';
import { AppSidebar } from '@/components/ui/app-sidebar';
import AISidebar from '@/components/ui/ai-sidebar';
import AIToggleButton from '@/components/ai-toggle-button';
import { useActiveConnection } from '@/hooks/use-connections';
import { useLocation } from 'react-router';
import { Outlet } from 'react-router';

// Named routes that DO NOT use mail.tsx (which already mounts its own AISidebar
// inside the ResizablePanelGroup). We inject a popup-only AISidebar + FAB here
// so those pages get the AI assistant without a ResizablePanelGroup conflict.
// The /mail/chat page is excluded because it has its own dedicated chat UI.
const AI_PANEL_ROUTES = new Set([
  '/mail/home',
  '/mail/tasks',
  '/mail/calendar',
  '/mail/search',
]);

function GlobalAIPanel() {
  const location = useLocation();
  const { data: activeConnection } = useActiveConnection();

  // Only show on the specific named routes that don't already have AISidebar
  if (!AI_PANEL_ROUTES.has(location.pathname) || !activeConnection?.id) {
    return null;
  }

  return (
    <>
      {/* popupOnly prevents ResizablePanel render outside ResizablePanelGroup */}
      <AISidebar popupOnly />
      <AIToggleButton />
    </>
  );
}

export default function MailLayout() {
  return (
    <HotkeyProviderWrapper>
      <AppSidebar />
      <div className="bg-sidebar dark:bg-sidebar w-full">
        <Outlet />
      </div>
      <GlobalAIPanel />
      <ConnectionWrapper />
      <OnboardingWrapper />
    </HotkeyProviderWrapper>
  );
}
