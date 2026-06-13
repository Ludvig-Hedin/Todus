/**
 * Calendar accounts settings page.
 *
 * Web-side companion to the iOS / macOS Calendar Accounts list. Lists the
 * connected calendar sources the user has access to, lets them toggle each
 * one, and links into the Connections page to add a new account.
 *
 * Note: Apple Calendar / Apple Reminders are native-only — this page surfaces
 * connected Google calendars when present and falls back to a guidance card.
 */

import { CalendarDays, Link as LinkIcon, Plus } from 'lucide-react';
import { SettingsCard } from '@/components/settings/settings-card';
import { Button } from '@/components/ui/button';
import { Switch } from '@/components/ui/switch';
import { Link } from 'react-router';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useTRPC } from '@/providers/query-provider';
import { useSettings } from '@/hooks/use-settings';
import { useCalendarVisibility } from '@/lib/calendar-visibility';
import { m } from '@/paraglide/messages';
import { toast } from 'sonner';

export default function CalendarsSettingsPage() {
  const { data } = useSettings();
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const { mutateAsync: saveUserSettings } = useMutation(trpc.settings.save.mutationOptions());
  const { data: calendarsData } = useQuery(
    trpc.calendar.calendars.queryOptions(undefined, { staleTime: 1000 * 60 * 10 }),
  );
  const calendars = calendarsData?.calendars ?? [];
  const { isHidden, toggle: toggleCalendar } = useCalendarVisibility();

  const hideAppleSide = (data?.settings as any)?.hideAppleSideGmailDuplicates ?? true;

  const setHideAppleSide = async (value: boolean) => {
    if (!data?.settings) return;
    const snapshot = data.settings;
    queryClient.setQueryData(trpc.settings.get.queryKey(), (updater) => {
      if (!updater) return;
      return { settings: { ...updater.settings, hideAppleSideGmailDuplicates: value } };
    });
    try {
      await saveUserSettings({ ...snapshot, hideAppleSideGmailDuplicates: value } as any);
    } catch {
      toast.error(m['common.settings.failedToSave']());
      queryClient.setQueryData(trpc.settings.get.queryKey(), (updater) => {
        if (!updater) return;
        return { settings: snapshot };
      });
    }
  };

  return (
    <div className="grid gap-5">
      <SettingsCard
        title="Calendar Accounts"
        description="Calendars surfaced inside Todus. Apple Calendar and Reminders are managed in the native iOS and macOS apps."
        action={
          <Button asChild variant="secondary" size="sm">
            <Link to="/settings/connections">
              <Plus className="mr-1.5 h-3.5 w-3.5" />
              Add account
            </Link>
          </Button>
        }
      >
        {calendars.length > 0 ? (
          <div className="flex flex-col gap-1">
            {calendars.map((cal) => {
              const visible = !isHidden(cal.id);
              return (
                <div
                  key={cal.id}
                  className="flex items-center justify-between rounded-lg border p-3 shadow-sm"
                >
                  <div className="flex min-w-0 items-center gap-2.5">
                    <span
                      className="h-3.5 w-3.5 shrink-0 rounded-[4px] border"
                      style={{ backgroundColor: cal.color, borderColor: cal.color }}
                      aria-hidden
                    />
                    <span className="truncate text-sm font-medium">{cal.name}</span>
                    {cal.primary ? (
                      <span className="text-muted-foreground bg-muted/60 rounded-full px-1.5 py-0.5 text-[10px]">
                        Primary
                      </span>
                    ) : null}
                  </div>
                  <Switch checked={visible} onCheckedChange={() => toggleCalendar(cal.id)} />
                </div>
              );
            })}
          </div>
        ) : (
          <div className="border-border/60 rounded-md border border-dashed px-4 py-8 text-center">
            <CalendarDays className="text-muted-foreground/50 mx-auto h-8 w-8" />
            <p className="text-muted-foreground mt-2 text-sm">
              Connect a Google account from the Connections page to surface its calendars here.
            </p>
            <p className="text-muted-foreground mt-1 text-xs">
              Per-calendar toggles and colors will appear once at least one account is connected.
            </p>
            <Button asChild variant="ghost" size="sm" className="mt-3">
              <Link to="/settings/connections">
                <LinkIcon className="mr-1.5 h-3.5 w-3.5" />
                Open Connections
              </Link>
            </Button>
          </div>
        )}
      </SettingsCard>

      <SettingsCard
        title="Sync preferences"
        description="Avoid duplicate events when the same Google account is also configured in iOS / macOS Apple Calendar."
      >
        <div className="flex max-w-xl flex-row items-center justify-between rounded-lg border p-3 shadow-sm">
          <div className="space-y-0.5 pr-4">
            <p className="text-sm font-medium leading-none">Hide Apple-side Gmail duplicates</p>
            <p className="text-muted-foreground text-xs">
              Prefer the connected Gmail copy when the same account also syncs through iOS.
            </p>
          </div>
          <Switch checked={hideAppleSide} onCheckedChange={setHideAppleSide} />
        </div>
      </SettingsCard>
    </div>
  );
}
