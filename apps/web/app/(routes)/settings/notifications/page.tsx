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
import { zodResolver } from '@hookform/resolvers/zod';
import { Switch } from '@/components/ui/switch';
import { Button } from '@/components/ui/button';
import { useForm } from 'react-hook-form';
import { AlertCircle, Bell } from 'lucide-react';
import * as z from 'zod';

const formSchema = z.object({
  newMailNotifications: z.enum(['none', 'important', 'all']),
  marketingCommunications: z.boolean(),
});

// NOTE: the `newMailNotifications` and `marketingCommunications` preferences
// are NOT in `userSettingsSchema` on the backend yet — there is no persistence
// path for them. The previous version pretended to save via `setTimeout` and
// silently discarded user input; that's worse than not saving at all, so we
// now disable the save action and explicitly tell the user this section is
// preview-only. Wire to `trpc.settings.save` once the schema is extended.
export default function NotificationsPage() {
  const form = useForm<z.infer<typeof formSchema>>({
    resolver: zodResolver(formSchema),
    defaultValues: {
      newMailNotifications: 'all',
      marketingCommunications: false,
    },
  });

  return (
    <div className="grid gap-5">
      <SettingsCard
        title="Notifications"
        description="Choose what notifications you want to receive."
        footer={
          <div className="flex justify-between">
            <Button type="button" variant="outline" onClick={() => form.reset()}>
              Reset to Defaults
            </Button>
            <Button type="submit" form="notifications-form" disabled>
              Coming soon
            </Button>
          </div>
        }
      >
        <div
          role="status"
          className="mb-4 flex items-start gap-2 rounded-lg border border-amber-500/30 bg-amber-500/5 p-3 text-[13px] text-amber-700 dark:text-amber-400"
        >
          <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />
          <p>
            Notification preferences aren&apos;t saved yet — this section is preview-only until
            we ship the backend setting. Your choices below will reset on reload.
          </p>
        </div>
        <Form {...form}>
          <form
            id="notifications-form"
            onSubmit={(e) => e.preventDefault()}
            className="space-y-6"
          >
            <FormField
              control={form.control}
              name="newMailNotifications"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>New Mail Notifications</FormLabel>
                  <Select onValueChange={field.onChange} defaultValue={field.value}>
                    <FormControl>
                      <SelectTrigger className="w-[240px]">
                        <Bell className="mr-2 h-4 w-4" />
                        <SelectValue placeholder="Select notification level" />
                      </SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      <SelectItem value="none">None</SelectItem>
                      <SelectItem value="important">Important Only</SelectItem>
                      <SelectItem value="all">All Messages</SelectItem>
                    </SelectContent>
                  </Select>
                  <FormDescription>
                    Choose which messages you want to receive notifications for
                  </FormDescription>
                </FormItem>
              )}
            />
            <FormField
              control={form.control}
              name="marketingCommunications"
              render={({ field }) => (
                <FormItem className="flex items-center justify-between rounded-lg border p-4">
                  <div className="space-y-0.5">
                    <FormLabel className="text-base">Marketing Communications</FormLabel>
                    <FormDescription>Receive updates about new features</FormDescription>
                  </div>
                  <FormControl>
                    <Switch checked={field.value} onCheckedChange={field.onChange} />
                  </FormControl>
                </FormItem>
              )}
            />
          </form>
        </Form>
      </SettingsCard>
    </div>
  );
}
