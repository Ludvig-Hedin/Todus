import { useTRPC } from '@/providers/query-provider';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useSettings } from '@/hooks/use-settings';
import { Check } from 'lucide-react';
import { Section, RowList, SelectRow } from '@/components/settings/primitives';
import { m } from '@/paraglide/messages';
import { useTheme } from 'next-themes';
import { useEffect } from 'react';
import { toast } from 'sonner';
import { cn } from '@/lib/utils';

type AccentColor = {
  key: 'blue' | 'indigo' | 'teal' | 'green' | 'orange' | 'rose';
  label: string;
  light: string;
  dark: string;
};

const ACCENT_COLORS: ReadonlyArray<AccentColor> = [
  { key: 'blue', label: 'Blue', light: '#3873d9', dark: '#4d80e0' },
  { key: 'indigo', label: 'Indigo', light: '#5952c7', dark: '#7a78e6' },
  { key: 'teal', label: 'Teal', light: '#2e858c', dark: '#52aeb8' },
  { key: 'green', label: 'Green', light: '#408c52', dark: '#62b873' },
  { key: 'orange', label: 'Orange', light: '#c77a2e', dark: '#e69a4d' },
  { key: 'rose', label: 'Rose', light: '#b84759', dark: '#e06b7a' },
];

const DEFAULT_VIEW_OPTIONS = [
  { value: 'list', label: 'List' },
  { value: 'board', label: 'Board' },
  { value: 'table', label: 'Table' },
  { value: 'calendar', label: 'Dates' },
] as const;

type Theme = 'dark' | 'light' | 'system';

export default function AppearancePage() {
  const { data } = useSettings();
  const { theme, systemTheme, resolvedTheme, setTheme } = useTheme();
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const { mutateAsync: saveUserSettings } = useMutation(trpc.settings.save.mutationOptions());

  const accentColor = (data?.settings?.accentColor ?? 'blue') as AccentColor['key'];
  const defaultView = data?.settings?.defaultTaskView ?? 'list';

  // Mirror the chosen accent into a CSS custom property so the rest of the app
  // can opt in via `var(--accent-color)`. Matches macOS MacTheme.accentColor(for:).
  useEffect(() => {
    if (typeof document === 'undefined') return;
    const palette = ACCENT_COLORS.find((c) => c.key === accentColor) ?? ACCENT_COLORS[0];
    document.documentElement.style.setProperty('--accent-color', palette.light);
    document.documentElement.style.setProperty('--accent-color-dark', palette.dark);
  }, [accentColor]);

  const patchSetting = async <K extends 'accentColor' | 'defaultTaskView' | 'colorTheme'>(
    key: K,
    value: K extends 'accentColor' ? AccentColor['key'] : string,
  ) => {
    if (!data?.settings) return;
    const snapshot = data.settings;
    queryClient.setQueryData(trpc.settings.get.queryKey(), (updater) => {
      if (!updater) return;
      return { settings: { ...updater.settings, [key]: value } };
    });
    try {
      await saveUserSettings({ ...snapshot, [key]: value } as any);
    } catch {
      toast.error(m['common.settings.failedToSave']());
      queryClient.setQueryData(trpc.settings.get.queryKey(), (updater) => {
        if (!updater) return;
        return { settings: { ...updater.settings, [key]: snapshot[key] } };
      });
    }
  };

  async function handleThemeChange(newTheme: Theme) {
    let nextResolvedTheme: string = newTheme;
    if (newTheme === 'system' && systemTheme) {
      nextResolvedTheme = systemTheme;
    }
    const update = () => {
      setTheme(newTheme);
      void patchSetting('colorTheme' as const, newTheme as never);
    };
    if (document.startViewTransition && nextResolvedTheme !== resolvedTheme) {
      document.documentElement.style.viewTransitionName = 'theme-transition';
      await document.startViewTransition(update).finished;
      document.documentElement.style.viewTransitionName = '';
    } else {
      update();
    }
  }

  if (!data?.settings) return null;

  return (
    <div className="space-y-10">
      <Section
        title={m['pages.settings.appearance.title']()}
        description="Theme, accent, and default task layout. Syncs to iOS and macOS."
      >
        <RowList>
          <SelectRow
            label="Theme"
            value={(theme as Theme) ?? 'system'}
            options={[
              { value: 'light', label: 'Light' },
              { value: 'system', label: 'System' },
              { value: 'dark', label: 'Dark' },
            ]}
            onChange={(value) => handleThemeChange(value as Theme)}
            width={160}
          />
          <div className="flex items-center justify-between gap-4 py-2.5">
            <div className="min-w-0 flex-1">
              <p className="text-sm">Accent</p>
              <p className="text-muted-foreground text-xs">Tints buttons, badges, and links.</p>
            </div>
            <div className="flex items-center gap-2">
              {ACCENT_COLORS.map((color) => {
                const isSelected = color.key === accentColor;
                return (
                  <button
                    key={color.key}
                    type="button"
                    onClick={() => patchSetting('accentColor', color.key)}
                    title={color.label}
                    className={cn(
                      'relative flex h-6 w-6 items-center justify-center rounded-full transition-transform',
                      isSelected ? 'scale-110 ring-2 ring-offset-2 ring-offset-background' : 'hover:scale-105',
                    )}
                    aria-label={color.label}
                    style={{ backgroundColor: color.light, ['--tw-ring-color' as never]: color.light }}
                  >
                    {isSelected && <Check className="h-3 w-3 text-white" strokeWidth={3} />}
                  </button>
                );
              })}
            </div>
          </div>
          <SelectRow
            label="Default view"
            description="Which task layout to show by default."
            value={defaultView}
            options={[...DEFAULT_VIEW_OPTIONS]}
            onChange={(value) => patchSetting('defaultTaskView', value as never)}
            width={140}
          />
        </RowList>
      </Section>
    </div>
  );
}
