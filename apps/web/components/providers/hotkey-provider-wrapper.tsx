import { KeyboardShortcutsDialog } from '@/components/shortcuts/keyboard-shortcuts-dialog';
import { ThreadDisplayHotkeys } from '@/lib/hotkeys/thread-display-hotkeys';
import { NavigationHotkeys } from '@/lib/hotkeys/navigation-hotkeys';
import { MailListHotkeys } from '@/lib/hotkeys/mail-list-hotkeys';
import { ComposeHotkeys } from '@/lib/hotkeys/compose-hotkeys';
import { GlobalHotkeys } from '@/lib/hotkeys/global-hotkeys';
import { HotkeysProvider, useHotkeysContext } from 'react-hotkeys-hook';
import { useQueryState } from 'nuqs';
import React, { useEffect } from 'react';

interface HotkeyProviderWrapperProps {
  children: React.ReactNode;
}

/**
 * Toggles the `mail-list` and `thread-display` scopes based on whether a
 * thread pane is open. Without this, shared keys (`r`, `a`) fire BOTH the
 * list-level handler (markAsRead / bulkArchive) and the thread-level handler
 * (reply / replyAll), which competes destructively (see bug #4).
 */
function MailScopeController() {
  const { enableScope, disableScope } = useHotkeysContext();
  const [threadId] = useQueryState('threadId');
  const threadOpen = !!threadId;

  useEffect(() => {
    if (threadOpen) {
      enableScope('thread-display');
      disableScope('mail-list');
    } else {
      enableScope('mail-list');
      disableScope('thread-display');
    }
  }, [threadOpen, enableScope, disableScope]);

  return null;
}

export function HotkeyProviderWrapper({ children }: HotkeyProviderWrapperProps) {
  return (
    <HotkeysProvider initiallyActiveScopes={['global', 'navigation', 'mail-list']}>
      <NavigationHotkeys />
      <GlobalHotkeys />
      <MailListHotkeys />
      <ThreadDisplayHotkeys />
      <ComposeHotkeys />
      <KeyboardShortcutsDialog />
      <MailScopeController />
      {children}
    </HotkeysProvider>
  );
}
