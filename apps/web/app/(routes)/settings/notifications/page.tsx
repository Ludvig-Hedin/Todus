import { useTRPC } from '@/providers/query-provider';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useSettings } from '@/hooks/use-settings';
import { Section, RowList, ToggleRow } from '@/components/settings/primitives';
import { PushNotificationsSection } from '@/components/settings/push-notifications-section';
import { toast } from 'sonner';
import { m } from '@/paraglide/messages';

export default function NotificationsPage() {
  const { data } = useSettings();
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const { mutateAsync: saveUserSettings } = useMutation(
    trpc.settings.save.mutationOptions({
      // Re-fetch authoritative settings after each save so the cache
      // converges on the server's normalized/clamped result and racing
      // patches reconcile against truth.
      onSettled: () =>
        queryClient.invalidateQueries({ queryKey: trpc.settings.get.queryKey() }),
    }),
  );

  const settings = data?.settings;

  const patch = async (changes: Record<string, unknown>) => {
    const settingsKey = trpc.settings.get.queryKey();
    const before = queryClient.getQueryData<{ settings: Record<string, unknown> }>(settingsKey);
    if (!before?.settings) return;

    queryClient.setQueryData(settingsKey, (updater: { settings: Record<string, unknown> } | undefined) => {
      if (!updater) return updater;
      return { settings: { ...updater.settings, ...changes } };
    });

    try {
      // Send *only* the changed keys. The server merges them onto the
      // authoritative server-side settings — spreading the entire client
      // cache would round-trip server-managed / read-only fields and risk
      // clobbering changes from another device that landed between our
      // initial read and this save.
      await saveUserSettings(changes as any);
    } catch {
      toast.error(m['common.settings.failedToSave']());
      // Rollback only the keys this patch touched — re-reading the cache and
      // restoring `before` would also undo any unrelated patch that succeeded
      // between this call's optimistic write and its rejection.
      queryClient.setQueryData(settingsKey, (updater: { settings: Record<string, unknown> } | undefined) => {
        if (!updater) return updater;
        const restored: Record<string, unknown> = { ...updater.settings };
        for (const key of Object.keys(changes)) {
          restored[key] = before.settings[key];
        }
        return { settings: restored };
      });
    }
  };

  if (!settings) return null;

  return (
    <div className="space-y-10">
      <Section
        title="Notifications"
        description="Control reminders for tasks and calendar events. Syncs to iOS and macOS."
      >
        <RowList>
          <ToggleRow
            label="Task due reminders"
            description="Notify when tasks are due or overdue."
            checked={(settings.taskRemindersEnabled as boolean | undefined) ?? true}
            onChange={(v) => patch({ taskRemindersEnabled: v })}
          />
          <ToggleRow
            label="Calendar reminders"
            description="Notify before upcoming calendar events."
            checked={(settings.calendarRemindersEnabled as boolean | undefined) ?? true}
            onChange={(v) => patch({ calendarRemindersEnabled: v })}
          />
        </RowList>
      </Section>

      <PushNotificationsSection />
    </div>
  );
}
