import { SettingsCard } from '@/components/settings/settings-card';
import { useSettings } from '@/hooks/use-settings';
import { useTRPC } from '@/providers/query-provider';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Switch } from '@/components/ui/switch';
import { m } from '@/paraglide/messages';
import { toast } from 'sonner';

export default function SignaturesPage() {
  const { data, refetch } = useSettings();
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const { mutateAsync: saveUserSettings } = useMutation(trpc.settings.save.mutationOptions());

  const todusSignature = data?.settings?.todusSignature ?? true;

  const handleToggle = async (checked: boolean) => {
    const saved = data?.settings ? { ...data.settings } : undefined;
    try {
      queryClient.setQueryData(trpc.settings.get.queryKey(), (updater) => {
        if (!updater) return;
        return { settings: { ...updater.settings, todusSignature: checked } };
      });
      await saveUserSettings({ ...data?.settings, todusSignature: checked });
      await refetch();
      toast.success(m['common.settings.saved']());
    } catch {
      toast.error(m['common.settings.failedToSave']());
      queryClient.setQueryData(trpc.settings.get.queryKey(), (updater) => {
        if (!updater) return;
        return saved ? { settings: { ...updater.settings, ...saved } } : updater;
      });
    }
  };

  return (
    <div className="grid gap-6">
      <SettingsCard
        title={m['pages.settings.signatures.title']()}
        description={m['pages.settings.signatures.description']()}
      >
        <div className="flex max-w-xl flex-row items-center justify-between rounded-lg border px-4 py-3">
          <div className="space-y-0.5">
            <p className="text-sm font-medium">{m['pages.settings.general.zeroSignature']()}</p>
            <p className="text-sm text-muted-foreground">{m['pages.settings.general.zeroSignatureDescription']()}</p>
          </div>
          <Switch checked={todusSignature} onCheckedChange={handleToggle} />
        </div>
      </SettingsCard>
    </div>
  );
}
