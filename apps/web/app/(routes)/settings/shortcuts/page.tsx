import { SettingsCard } from '@/components/settings/settings-card';
import { formatDisplayKeys } from '@/lib/hotkeys/use-hotkey-utils';
import { useShortcutCache } from '@/lib/hotkeys/use-hotkey-utils';
import { useCategorySettings } from '@/hooks/use-categories';
import { type Shortcut } from '@/config/shortcuts';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { m } from '@/paraglide/messages';
import { useState, type KeyboardEvent, type ReactNode } from 'react';
import { toast } from 'sonner';

/** Build the app's key tokens from a raw keyboard event (modifiers → 'mod'/'shift'/'alt'). */
function keysFromEvent(e: KeyboardEvent): string[] {
  const mods: string[] = [];
  if (e.metaKey || e.ctrlKey) mods.push('mod');
  if (e.shiftKey) mods.push('shift');
  if (e.altKey) mods.push('alt');
  const k = e.key.toLowerCase();
  if (['meta', 'control', 'shift', 'alt', 'os'].includes(k)) return mods;
  const main =
    k === ' '
      ? 'space'
      : k === 'arrowup'
        ? 'up'
        : k === 'arrowdown'
          ? 'down'
          : k === 'arrowleft'
            ? 'left'
            : k === 'arrowright'
              ? 'right'
              : k;
  return [...mods, main];
}

function HotkeyRecorderDialog({
  shortcut,
  onClose,
  onSave,
  saving,
}: {
  shortcut: Shortcut | null;
  onClose: () => void;
  onSave: (keys: string[]) => void;
  saving: boolean;
}) {
  const [keys, setKeys] = useState<string[]>([]);
  const open = shortcut !== null;

  return (
    <Dialog
      open={open}
      onOpenChange={(o) => {
        if (!o) {
          setKeys([]);
          onClose();
        }
      }}
    >
      <DialogContent className="sm:max-w-[400px]">
        <DialogHeader>
          <DialogTitle className="text-[15px]">Record shortcut</DialogTitle>
          <DialogDescription className="text-[12px]">
            Press the key combination you want, then save.
          </DialogDescription>
        </DialogHeader>

        <div
          tabIndex={0}
          // eslint-disable-next-line jsx-a11y/no-autofocus
          autoFocus
          role="textbox"
          aria-label="Shortcut recorder"
          onKeyDown={(e) => {
            e.preventDefault();
            const next = keysFromEvent(e);
            if (next.length) setKeys(next);
          }}
          className="bg-muted/40 focus-visible:ring-ring flex h-20 items-center justify-center gap-1 rounded-lg border outline-none focus-visible:ring-2"
        >
          {keys.length ? (
            formatDisplayKeys(keys).map((k, i) => (
              <kbd
                key={`${k}-${i}`}
                className="border-muted-foreground/10 bg-background h-7 rounded-[6px] border px-2 font-mono text-sm leading-7"
              >
                {k}
              </kbd>
            ))
          ) : (
            <span className="text-muted-foreground text-[12px]">Listening… press keys</span>
          )}
        </div>

        <DialogFooter>
          <Button variant="outline" size="sm" onClick={onClose}>
            Cancel
          </Button>
          <Button size="sm" disabled={keys.length === 0 || saving} onClick={() => onSave(keys)}>
            Save
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export default function ShortcutsPage() {
  const { shortcuts, updateShortcut, resetShortcuts, isUpdating } = useShortcutCache();
  const categorySettings = useCategorySettings();
  const [recording, setRecording] = useState<Shortcut | null>(null);

  const handleSave = async (keys: string[]) => {
    if (!recording) return;
    try {
      await updateShortcut({ ...recording, keys });
      toast.success('Shortcut saved');
      setRecording(null);
    } catch {
      toast.error('Failed to save shortcut');
    }
  };

  const handleReset = async () => {
    try {
      await resetShortcuts();
      toast.success('Shortcuts reset to defaults');
    } catch {
      toast.error('Failed to reset shortcuts');
    }
  };

  return (
    <div className="grid gap-6">
      <SettingsCard
        title={m['pages.settings.shortcuts.title']()}
        description={m['pages.settings.shortcuts.description']()}
        footer={
          <div className="flex gap-4">
            <Button variant="outline" size="sm" onClick={handleReset} disabled={isUpdating}>
              Reset to defaults
            </Button>
          </div>
        }
      >
        <div className="grid max-w-3xl gap-6">
          {Object.entries(
            shortcuts.reduce<Record<string, Shortcut[]>>((acc, shortcut) => {
              const scope = shortcut.scope;
              if (!acc[scope]) acc[scope] = [];
              acc[scope].push(shortcut);
              return acc;
            }, {}),
          ).map(([scope, scopedShortcuts]) => (
            <div key={scope}>
              <h3 className="mb-4 text-lg font-semibold capitalize">
                {scope.split('-').join(' ')}
              </h3>
              <div className="grid grid-cols-1 gap-2 md:grid-cols-2">
                {scopedShortcuts.map((shortcut, index) => {
                  const categoryActionIndex: Record<string, number> = {
                    showImportant: 0,
                    showAllMail: 1,
                    showPersonal: 2,
                    showUpdates: 3,
                    showPromotions: 4,
                    showUnread: 5,
                  };

                  let label: string;

                  const safeMessage = (action: string): string => {
                    // Locale catalogs may not cover every action — fall back to a humanised
                    // version of the action key instead of throwing on `m[missing]()`.
                    const key = `pages.settings.shortcuts.actions.${action}`;
                    const fn = (m as Record<string, unknown>)[key];
                    if (typeof fn === 'function') {
                      try {
                        return (fn as () => string)();
                      } catch {
                        // fall through to humanised label
                      }
                    }
                    return action
                      .replace(/([A-Z])/g, ' $1')
                      .replace(/[-_]/g, ' ')
                      .replace(/\s+/g, ' ')
                      .trim()
                      .replace(/^./, (c) => c.toUpperCase());
                  };

                  if (shortcut.action in categoryActionIndex && categorySettings.length) {
                    const idx = categoryActionIndex[shortcut.action];
                    const cat = categorySettings[idx];
                    label = cat ? `Show ${cat.name}` : safeMessage(shortcut.action);
                  } else {
                    label = safeMessage(shortcut.action);
                  }

                  return (
                    <ShortcutItem
                      key={`${scope}-${index}`}
                      keys={shortcut.keys}
                      onEdit={() => setRecording(shortcut)}
                    >
                      {label}
                    </ShortcutItem>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      </SettingsCard>

      <HotkeyRecorderDialog
        shortcut={recording}
        onClose={() => setRecording(null)}
        onSave={handleSave}
        saving={isUpdating}
      />
    </div>
  );
}

function ShortcutItem({
  children,
  keys,
  onEdit,
}: {
  children: ReactNode;
  keys: string[];
  onEdit: () => void;
}) {
  const displayKeys = formatDisplayKeys(keys);

  return (
    <div
      className="bg-popover text-muted-foreground hover:bg-accent/50 flex cursor-pointer items-center justify-between gap-2 rounded-lg border p-2 text-sm"
      onClick={onEdit}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          onEdit();
        }
      }}
      role="button"
      tabIndex={0}
    >
      <span className="font-medium">{children}</span>
      <div className="flex select-none gap-1">
        {displayKeys.map((key) => (
          <kbd
            key={key}
            className="border-muted-foreground/10 bg-accent h-6 rounded-[6px] border px-1.5 font-mono text-xs leading-6"
          >
            {key}
          </kbd>
        ))}
      </div>
    </div>
  );
}
