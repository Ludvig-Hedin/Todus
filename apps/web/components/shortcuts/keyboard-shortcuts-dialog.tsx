import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { keyboardShortcuts, getDisplayKeysForShortcut, type Shortcut } from '@/config/shortcuts';
import { useEffect, useMemo, useCallback, useState } from 'react';

/** Scope display names and ordering */
const SCOPE_META: Record<string, { label: string; order: number }> = {
  navigation: { label: 'Navigation', order: 0 },
  global: { label: 'Global', order: 1 },
  'mail-list': { label: 'Mail List', order: 2 },
  'thread-display': { label: 'Thread', order: 3 },
  compose: { label: 'Compose', order: 4 },
};

function ShortcutKey({ children }: { children: string }) {
  return (
    <kbd className="inline-flex h-5 min-w-5 items-center justify-center rounded border bg-muted px-1.5 text-[11px] font-medium text-muted-foreground">
      {children}
    </kbd>
  );
}

function ShortcutRow({ shortcut }: { shortcut: Shortcut }) {
  const displayKeys = getDisplayKeysForShortcut(shortcut);
  return (
    <div className="flex items-center justify-between py-1.5">
      <span className="text-[13px] text-foreground">{shortcut.description}</span>
      <div className="flex items-center gap-0.5">
        {displayKeys.map((key, i) => (
          <span key={i} className="flex items-center gap-0.5">
            {i > 0 && shortcut.type === 'combination' && (
              <span className="text-[10px] text-muted-foreground">+</span>
            )}
            {i > 0 && shortcut.type !== 'combination' && (
              <span className="text-[10px] text-muted-foreground">then</span>
            )}
            <ShortcutKey>{key}</ShortcutKey>
          </span>
        ))}
      </div>
    </div>
  );
}

export function KeyboardShortcutsDialog() {
  const [open, setOpen] = useState(false);

  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      // Open on "?" (Shift + /) — ignore if user is typing in an input
      const target = e.target as HTMLElement;
      const isInput =
        target.tagName === 'INPUT' ||
        target.tagName === 'TEXTAREA' ||
        target.isContentEditable;

      if (e.key === '?' && !isInput) {
        e.preventDefault();
        setOpen((prev) => !prev);
      }
    },
    [],
  );

  useEffect(() => {
    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [handleKeyDown]);

  // Group and filter shortcuts (skip ignored ones like alt+shift+click)
  const grouped = useMemo(() => {
    const visible = keyboardShortcuts.filter((s) => !s.ignore);
    const groups = new Map<string, Shortcut[]>();
    for (const s of visible) {
      const list = groups.get(s.scope) ?? [];
      list.push(s);
      groups.set(s.scope, list);
    }
    // Sort groups by order
    return [...groups.entries()].sort(
      (a, b) => (SCOPE_META[a[0]]?.order ?? 99) - (SCOPE_META[b[0]]?.order ?? 99),
    );
  }, []);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent className="max-h-[80vh] max-w-lg overflow-y-auto p-0">
        <DialogHeader className="sticky top-0 z-10 border-b bg-background px-5 py-4">
          <DialogTitle className="text-base font-semibold">Keyboard Shortcuts</DialogTitle>
          <p className="text-[12px] text-muted-foreground">
            Press <ShortcutKey>?</ShortcutKey> to toggle this dialog
          </p>
        </DialogHeader>
        <div className="space-y-5 px-5 pb-5">
          {grouped.map(([scope, shortcuts]) => (
            <div key={scope}>
              <h3 className="mb-1.5 text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
                {SCOPE_META[scope]?.label ?? scope}
              </h3>
              <div className="divide-y divide-border/50">
                {shortcuts.map((s) => (
                  <ShortcutRow key={s.action} shortcut={s} />
                ))}
              </div>
            </div>
          ))}
        </div>
      </DialogContent>
    </Dialog>
  );
}
