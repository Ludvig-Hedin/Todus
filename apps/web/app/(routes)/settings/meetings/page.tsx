/**
 * Meetings settings — recording, AI recaps, and storage preferences.
 *
 * Design: Follows the existing SettingsCard pattern with transparent cards,
 * border-border/60 dividers, and compact toggle rows. Form items use the
 * app's standard spacing (space-y-4 between items, max-w-sm for inputs).
 * Toggle rows use rounded-lg border with p-3 — consistent with other
 * settings pages (appearance, notifications).
 */
import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormLabel,
  FormDescription,
} from '@/components/ui/form';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { SettingsCard } from '@/components/settings/settings-card';
import { useMutation, useQuery } from '@tanstack/react-query';
import { zodResolver } from '@hookform/resolvers/zod';
import { useTRPC } from '@/providers/query-provider';
import { useEffect, useMemo, useState } from 'react';
import { Switch } from '@/components/ui/switch';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { useForm } from 'react-hook-form';
import { Loader2 } from 'lucide-react';
import { toast } from 'sonner';
import * as z from 'zod';

const meetingsSettingsSchema = z.object({
  isEnabled: z.boolean(),
  autoJoin: z.boolean(),
  botName: z.string().min(1).max(50),
  joinEarlyMinutes: z.number().int().min(0).max(10),
  autoGenerateSummary: z.boolean(),
  summaryLanguage: z.string().min(2).max(5),
  excludeAllDay: z.boolean(),
  minimumDurationMinutes: z.number().int().min(0).max(120),
  autoDeleteDays: z.number().int().min(0).max(365),
});

type MeetingsSettings = z.infer<typeof meetingsSettingsSchema>;

const SUMMARY_LANGUAGES = [
  { value: 'en', label: 'English' },
  { value: 'es', label: 'Spanish' },
  { value: 'fr', label: 'French' },
  { value: 'de', label: 'German' },
  { value: 'pt', label: 'Portuguese' },
  { value: 'it', label: 'Italian' },
  { value: 'nl', label: 'Dutch' },
  { value: 'sv', label: 'Swedish' },
  { value: 'no', label: 'Norwegian' },
  { value: 'da', label: 'Danish' },
  { value: 'ja', label: 'Japanese' },
  { value: 'ko', label: 'Korean' },
  { value: 'zh', label: 'Chinese' },
  { value: 'ar', label: 'Arabic' },
  { value: 'hi', label: 'Hindi' },
];

const AUTO_DELETE_OPTIONS = [
  { value: 0, label: 'Never' },
  { value: 7, label: '7 days' },
  { value: 14, label: '14 days' },
  { value: 30, label: '30 days' },
  { value: 60, label: '60 days' },
  { value: 90, label: '90 days' },
  { value: 180, label: '6 months' },
  { value: 365, label: '1 year' },
];

const DEFAULT_MEETINGS_SETTINGS: MeetingsSettings = {
  isEnabled: true,
  autoJoin: true,
  botName: 'Notetaker',
  joinEarlyMinutes: 1,
  autoGenerateSummary: true,
  summaryLanguage: 'en',
  excludeAllDay: true,
  minimumDurationMinutes: 5,
  autoDeleteDays: 0,
};

export default function MeetingsSettingsPage() {
  const [isSaving, setIsSaving] = useState(false);
  const trpc = useTRPC();

  const { data, isLoading } = useQuery(trpc.meet.getIntegration.queryOptions());
  const { mutateAsync: saveSettings } = useMutation(
    trpc.meet.upsertIntegration.mutationOptions(),
  );

  const form = useForm<MeetingsSettings>({
    resolver: zodResolver(meetingsSettingsSchema as any),
    defaultValues: DEFAULT_MEETINGS_SETTINGS,
  });

  const serverValues = useMemo<MeetingsSettings | null>(() => {
    if (!data?.integration) return null;
    const i = data.integration;
    return {
      isEnabled: i.isEnabled,
      autoJoin: i.autoJoin,
      botName: i.botName,
      joinEarlyMinutes: i.joinEarlyMinutes,
      autoGenerateSummary: i.autoGenerateSummary ?? true,
      summaryLanguage: i.summaryLanguage ?? 'en',
      excludeAllDay: i.excludeAllDay ?? true,
      minimumDurationMinutes: i.minimumDurationMinutes ?? 5,
      autoDeleteDays: i.autoDeleteDays ?? 0,
    };
  }, [data?.integration]);

  useEffect(() => {
    if (serverValues) form.reset(serverValues);
  }, [form, serverValues]);

  async function onSubmit(values: MeetingsSettings) {
    setIsSaving(true);
    try {
      await saveSettings(values);
      toast.success('Settings saved');
    } catch {
      toast.error('Failed to save settings');
    } finally {
      setIsSaving(false);
    }
  }

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-20">
        <Loader2 className="text-muted-foreground/50 h-4 w-4 animate-spin" />
      </div>
    );
  }

  return (
    <Form {...form}>
      <form
        id="meetings-settings-form"
        onSubmit={form.handleSubmit(onSubmit)}
        className="grid gap-6"
      >
        {/* ── Recording ────────────────────────────────────────────────── */}
        <SettingsCard
          title="Recording"
          description="Control how meetings are recorded."
          footer={
            <div className="flex items-center justify-between">
              <div>
                {form.formState.isDirty && (
                  <span className="text-[12px] font-medium text-amber-500/80">
                    Unsaved changes
                  </span>
                )}
              </div>
              <div className="flex items-center gap-2">
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  className="h-7 text-xs text-muted-foreground"
                  onClick={() => form.reset(serverValues ?? DEFAULT_MEETINGS_SETTINGS)}
                >
                  Reset
                </Button>
                <Button
                  type="submit"
                  size="sm"
                  className="h-7 text-xs"
                  disabled={isSaving}
                >
                  {isSaving ? 'Saving…' : 'Save'}
                </Button>
              </div>
            </div>
          }
        >
          <div className="space-y-4">
            {/* Enable recording */}
            <ToggleRow
              control={form.control}
              name="isEnabled"
              label="Enable recording"
              description="Record and transcribe your Google Meet meetings"
            />

            {/* Auto-record */}
            <ToggleRow
              control={form.control}
              name="autoJoin"
              label="Auto-record"
              description="Automatically record all synced meetings"
            />

            {/* Recorder name */}
            <FormField
              control={form.control}
              name="botName"
              render={({ field }) => (
                <FormItem className="max-w-sm">
                  <FormLabel className="text-[13px]">Recorder name</FormLabel>
                  <FormControl>
                    <Input
                      {...field}
                      placeholder="Notetaker"
                      className="h-8 text-[13px]"
                    />
                  </FormControl>
                  <FormDescription className="text-[11px]">
                    Shown when the recorder joins a meeting
                  </FormDescription>
                </FormItem>
              )}
            />

            {/* Join early */}
            <FormField
              control={form.control}
              name="joinEarlyMinutes"
              render={({ field }) => (
                <FormItem className="max-w-[180px]">
                  <FormLabel className="text-[13px]">Join early</FormLabel>
                  <Select
                    onValueChange={(v) => field.onChange(Number(v))}
                    value={String(field.value)}
                  >
                    <FormControl>
                      <SelectTrigger className="h-8 text-[13px]">
                        <SelectValue />
                      </SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      <SelectItem value="0">On time</SelectItem>
                      <SelectItem value="1">1 min early</SelectItem>
                      <SelectItem value="2">2 min early</SelectItem>
                      <SelectItem value="3">3 min early</SelectItem>
                      <SelectItem value="5">5 min early</SelectItem>
                      <SelectItem value="10">10 min early</SelectItem>
                    </SelectContent>
                  </Select>
                </FormItem>
              )}
            />

            {/* Skip all-day events */}
            <ToggleRow
              control={form.control}
              name="excludeAllDay"
              label="Skip all-day events"
              description="Don't record all-day calendar events"
            />

            {/* Minimum duration */}
            <FormField
              control={form.control}
              name="minimumDurationMinutes"
              render={({ field }) => (
                <FormItem className="max-w-[180px]">
                  <FormLabel className="text-[13px]">Minimum duration</FormLabel>
                  <Select
                    onValueChange={(v) => field.onChange(Number(v))}
                    value={String(field.value)}
                  >
                    <FormControl>
                      <SelectTrigger className="h-8 text-[13px]">
                        <SelectValue />
                      </SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      <SelectItem value="0">No minimum</SelectItem>
                      <SelectItem value="5">5 minutes</SelectItem>
                      <SelectItem value="10">10 minutes</SelectItem>
                      <SelectItem value="15">15 minutes</SelectItem>
                      <SelectItem value="30">30 minutes</SelectItem>
                    </SelectContent>
                  </Select>
                  <FormDescription className="text-[11px]">
                    Skip meetings shorter than this
                  </FormDescription>
                </FormItem>
              )}
            />
          </div>
        </SettingsCard>

        {/* ── AI Recaps ────────────────────────────────────────────────── */}
        <SettingsCard
          title="AI Recaps"
          description="Configure automatic summaries."
        >
          <div className="space-y-4">
            <ToggleRow
              control={form.control}
              name="autoGenerateSummary"
              label="Auto-generate recaps"
              description="Create an AI recap when recording is processed"
            />

            <FormField
              control={form.control}
              name="summaryLanguage"
              render={({ field }) => (
                <FormItem className="max-w-[180px]">
                  <FormLabel className="text-[13px]">Recap language</FormLabel>
                  <Select onValueChange={field.onChange} value={field.value}>
                    <FormControl>
                      <SelectTrigger className="h-8 text-[13px]">
                        <SelectValue />
                      </SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      {SUMMARY_LANGUAGES.map((lang) => (
                        <SelectItem key={lang.value} value={lang.value}>
                          {lang.label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </FormItem>
              )}
            />
          </div>
        </SettingsCard>

        {/* ── Storage ──────────────────────────────────────────────────── */}
        <SettingsCard
          title="Storage"
          description="Manage recording retention."
        >
          <div className="space-y-4">
            <FormField
              control={form.control}
              name="autoDeleteDays"
              render={({ field }) => (
                <FormItem className="max-w-[200px]">
                  <FormLabel className="text-[13px]">Auto-delete recordings</FormLabel>
                  <Select
                    onValueChange={(v) => field.onChange(Number(v))}
                    value={String(field.value)}
                  >
                    <FormControl>
                      <SelectTrigger className="h-8 text-[13px]">
                        <SelectValue />
                      </SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      {AUTO_DELETE_OPTIONS.map((opt) => (
                        <SelectItem key={opt.value} value={String(opt.value)}>
                          {opt.label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <FormDescription className="text-[11px]">
                    Recaps and transcripts are kept
                  </FormDescription>
                </FormItem>
              )}
            />
          </div>
        </SettingsCard>
      </form>
    </Form>
  );
}

/* ── Toggle row — reusable compact switch row ────────────────────────────── */

function ToggleRow({
  control,
  name,
  label,
  description,
}: {
  control: any;
  name: keyof MeetingsSettings;
  label: string;
  description: string;
}) {
  return (
    <FormField
      control={control}
      name={name}
      render={({ field }) => (
        <FormItem className="flex max-w-xl items-center justify-between rounded-lg border border-border/60 p-3">
          <div className="space-y-0.5">
            <FormLabel className="text-[13px] font-medium">{label}</FormLabel>
            <FormDescription className="text-[11px]">{description}</FormDescription>
          </div>
          <FormControl>
            <Switch checked={field.value as boolean} onCheckedChange={field.onChange} />
          </FormControl>
        </FormItem>
      )}
    />
  );
}
