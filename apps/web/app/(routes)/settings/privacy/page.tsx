import { Form, FormField } from '@/components/ui/form';
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip';
import { Section, RowList, ToggleRow } from '@/components/settings/primitives';
import { userSettingsSchema } from '@zero/server/schemas';
import { ScrollArea } from '@/components/ui/scroll-area';
import { zodResolver } from '@hookform/resolvers/zod';
import { useTRPC } from '@/providers/query-provider';
import { useMutation } from '@tanstack/react-query';
import { useSettings } from '@/hooks/use-settings';
import { Button } from '@/components/ui/button';
import { useState, useEffect } from 'react';
import { useForm } from 'react-hook-form';
import { m } from '@/paraglide/messages';
import { XIcon } from 'lucide-react';
import { toast } from 'sonner';
import * as z from 'zod';

export default function PrivacyPage() {
  const [isSaving, setIsSaving] = useState(false);
  const { data, refetch } = useSettings();
  const trpc = useTRPC();
  const { mutateAsync: saveUserSettings } = useMutation(trpc.settings.save.mutationOptions());

  const form = useForm<z.infer<typeof userSettingsSchema>>({
    resolver: zodResolver(userSettingsSchema),
  });

  const externalImages = data?.settings.externalImages;
  useEffect(() => {
    if (data) {
      form.reset({
        ...data.settings,
        trustedSenders: data.settings.trustedSenders,
        externalImages: !!data.settings.externalImages,
      });
    }
  }, [form, data]);

  async function onSubmit(values: z.infer<typeof userSettingsSchema>) {
    if (data) {
      setIsSaving(true);
      toast.promise(
        saveUserSettings({
          ...data.settings,
          ...values,
        }),
        {
          success: m['common.settings.saved'](),
          error: m['common.settings.failedToSave'](),
          finally: async () => {
            await refetch();
            setIsSaving(false);
          },
        },
      );
    }
  }

  return (
    <div className="space-y-10">
      <Section
        title={m['pages.settings.privacy.title']()}
        description={m['pages.settings.privacy.description']()}
        action={
          <Button
            size="sm"
            className="h-8"
            onClick={() => form.handleSubmit(onSubmit)()}
            disabled={isSaving || !form.formState.isDirty}
          >
            {isSaving ? m['common.actions.saving']() : 'Save'}
          </Button>
        }
      >
        <Form {...form}>
          <form id="privacy-form" onSubmit={form.handleSubmit(onSubmit)}>
            <RowList>
              <FormField
                control={form.control}
                name="externalImages"
                render={({ field }) => (
                  <ToggleRow
                    label={m['pages.settings.privacy.externalImages']()}
                    description={m['pages.settings.privacy.externalImagesDescription']()}
                    checked={!!field.value}
                    onChange={field.onChange}
                  />
                )}
              />
            </RowList>

            <FormField
              control={form.control}
              name="trustedSenders"
              render={({ field }) =>
                (field.value?.length || 0) > 0 && !externalImages ? (
                  <div className="border-border/60 mt-4 rounded-lg border p-3">
                    <p className="text-sm font-medium">
                      {m['pages.settings.privacy.trustedSenders']()}
                    </p>
                    <p className="text-muted-foreground mt-0.5 text-xs">
                      {m['pages.settings.privacy.trustedSendersDescription']()}
                    </p>
                    <ScrollArea className="mt-2 max-h-32 pr-3">
                      {field.value?.map((senderEmail) => (
                        <div
                          className="flex items-center justify-between py-1 text-sm"
                          key={senderEmail}
                        >
                          <span>{senderEmail}</span>
                          <Tooltip>
                            <TooltipTrigger asChild>
                              <button
                                type="button"
                                onClick={() =>
                                  field.onChange(field.value?.filter((e) => e !== senderEmail))
                                }
                              >
                                <XIcon className="text-muted-foreground h-4 w-4 transition hover:opacity-80" />
                              </button>
                            </TooltipTrigger>
                            <TooltipContent>{m['common.actions.remove']()}</TooltipContent>
                          </Tooltip>
                        </div>
                      ))}
                    </ScrollArea>
                  </div>
                ) : (
                  <></>
                )
              }
            />
          </form>
        </Form>
      </Section>
    </div>
  );
}
