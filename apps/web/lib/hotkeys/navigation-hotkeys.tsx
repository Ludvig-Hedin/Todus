import { enhancedKeyboardShortcuts } from '@/config/shortcuts';
import { useShortcuts } from './use-hotkey-utils';
import { useHotkeys } from 'react-hotkeys-hook';
import { useNavigate } from 'react-router';

export function NavigationHotkeys() {
  const navigate = useNavigate();
  const scope = 'navigation';

  const handlers = {
    goToDrafts: () => navigate('/mail/draft'),
    inbox: () => navigate('/mail/inbox'),
    sentMail: () => navigate('/mail/sent'),
    goToArchive: () => navigate('/mail/archive'),
    goToBin: () => navigate('/mail/bin'),
    goToSettings: () => navigate('/settings'),
    // helpWithShortcuts is now handled by the KeyboardShortcutsDialog component
    helpWithShortcuts: () => {},
  };

  const globalShortcuts = enhancedKeyboardShortcuts.filter((shortcut) => shortcut.scope === scope);

  useShortcuts(globalShortcuts, handlers, { scope });

  // macOS-parity section nav: ⌘1–5 / Ctrl+1–5 hop to Home / Tasks / Email /
  // Calendar / Meetings. Registered outside the shortcut schema so we don't
  // change the help-dialog UX; they're documented separately.
  //
  // Tiptap (rich-text editor in compose) renders a contenteditable div which
  // react-hotkeys-hook's `enableOnFormTags` does NOT treat as a form tag.
  // Without this guard, typing `Cmd+3` to add a `3` to your email body would
  // navigate away to the inbox mid-draft. Skip the hotkey whenever the
  // active element is contenteditable.
  const navIfNotEditing = (path: string) => (e: KeyboardEvent) => {
    const active = document.activeElement as HTMLElement | null;
    if (active?.isContentEditable) return;
    e.preventDefault();
    navigate(path);
  };
  useHotkeys('meta+1, ctrl+1', navIfNotEditing('/mail/home'), { enableOnFormTags: false, preventDefault: true });
  useHotkeys('meta+2, ctrl+2', navIfNotEditing('/mail/tasks'), { enableOnFormTags: false, preventDefault: true });
  useHotkeys('meta+3, ctrl+3', navIfNotEditing('/mail/inbox'), { enableOnFormTags: false, preventDefault: true });
  useHotkeys('meta+4, ctrl+4', navIfNotEditing('/mail/calendar'), { enableOnFormTags: false, preventDefault: true });
  useHotkeys('meta+5, ctrl+5', navIfNotEditing('/mail/meetings'), { enableOnFormTags: false, preventDefault: true });

  return null;
}
