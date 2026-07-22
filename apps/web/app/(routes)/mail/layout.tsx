import { SubscriptionSuccessWatcher } from '@/components/subscription-success-watcher';
import { ConnectionWrapper } from '@/components/connection/connection-wrapper';
import { useActiveConnection } from '@/hooks/use-connections';
import { OnboardingWrapper } from '@/components/onboarding';
import AIToggleButton from '@/components/ai-toggle-button';
import { AppSidebar } from '@/components/ui/app-sidebar';
import { useAISidebar } from '@/hooks/use-ai-sidebar';
import { Outlet, useLocation } from 'react-router';
import { lazy, Suspense } from 'react';

const AISidebar = lazy(() => import('@/components/ui/ai-sidebar'));

// AISidebar opens a WebSocket to the ZeroAgent Durable Object inside its
// body via `useAgent`. Mounting it with no active connection still opens a
// socket against the synthetic `general` agent and burns billing/credit on
// users who haven't connected an inbox. Gate the mount here so the inner
// hooks never run until there's a real account to chat about.
function AISidebarGate() {
  const { data: activeConnection } = useActiveConnection();
  const { open } = useAISidebar();
  if (!activeConnection?.id || !open) return null;
  return <AISidebar />;
}

// HotkeyProviderWrapper lives in the parent (routes) layout. Mounting it here
// too would register every shortcut twice (every keypress fires twice — see
// bug #3). The mail-specific hotkey scopes are still active because the
// parent provider renders MailListHotkeys + ThreadDisplayHotkeys.
export default function MailLayout() {
  const location = useLocation();
  // Skip AISidebar (and its WebSocket / billing tracking) when the user is
  // already on /mail/chat — that route mounts its own useAgent + useAgentChat
  // pair, and rendering the sidebar here too opens a second WebSocket to the
  // same Durable Object, doubling chat-message billing and possibly firing
  // tool calls twice.
  const isOnChatPage = location.pathname.startsWith('/mail/chat');

  return (
    <>
      <AppSidebar />
      <div className="bg-sidebar dark:bg-sidebar w-full">
        <Outlet />
      </div>
      <OnboardingWrapper />
      <ConnectionWrapper />
      {/* AI chat persists across all mail pages — gated above on activeConnection */}
      {!isOnChatPage && (
        <Suspense fallback={null}>
          <AISidebarGate />
        </Suspense>
      )}
      {!isOnChatPage && <AIToggleButton />}
      {/* Detects `?success=true` after Stripe Checkout and refreshes plan cache */}
      <SubscriptionSuccessWatcher />
    </>
  );
}
