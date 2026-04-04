import { HotkeyProviderWrapper } from '@/components/providers/hotkey-provider-wrapper';
import { OnboardingWrapper } from '@/components/onboarding';
import { ConnectionWrapper } from '@/components/connection/connection-wrapper';
import { AppSidebar } from '@/components/ui/app-sidebar';
import AISidebar from '@/components/ui/ai-sidebar';
import AIToggleButton from '@/components/ai-toggle-button';
import { Outlet } from 'react-router';

export default function MailLayout() {
  return (
    <HotkeyProviderWrapper>
      <AppSidebar />
      <div className="bg-sidebar dark:bg-sidebar w-full">
        <Outlet />
      </div>
      <ConnectionWrapper />
      <OnboardingWrapper />
      {/* AI chat persists across all mail pages — AISidebar self-gates on activeConnection */}
      <AISidebar />
      <AIToggleButton />
    </HotkeyProviderWrapper>
  );
}
