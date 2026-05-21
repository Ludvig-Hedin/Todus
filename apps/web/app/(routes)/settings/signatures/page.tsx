import { useSettings } from '@/hooks/use-settings';
import { useConnections } from '@/hooks/use-connections';
import { useTRPC } from '@/providers/query-provider';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Textarea } from '@/components/ui/textarea';
import { Section, RowList, ToggleRow } from '@/components/settings/primitives';
import { m } from '@/paraglide/messages';
import { toast } from 'sonner';
import { Mail } from 'lucide-react';
import { useCallback, useEffect, useState } from 'react';

const SIGNATURE_KEY_PREFIX = 'web_signature_';

function loadSignature(connectionId: string): string {
  if (typeof window === 'undefined') return '';
  return window.localStorage.getItem(`${SIGNATURE_KEY_PREFIX}${connectionId}`) ?? '';
}

function saveSignature(connectionId: string, value: string) {
  if (typeof window === 'undefined') return;
  try {
    window.localStorage.setItem(`${SIGNATURE_KEY_PREFIX}${connectionId}`, value);
  } catch {
    // ignore quota / privacy mode
  }
}

export default function SignaturesPage() {
  const { data, refetch } = useSettings();
  const { data: connectionsData } = useConnections();
  const connections = connectionsData?.connections ?? [];
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
    <div className="space-y-10">
      <Section
        title={m['pages.settings.signatures.title']()}
        description={m['pages.settings.signatures.description']()}
      >
        <RowList>
          <ToggleRow
            label={m['pages.settings.general.zeroSignature']()}
            description={m['pages.settings.general.zeroSignatureDescription']()}
            checked={todusSignature}
            onChange={handleToggle}
          />
        </RowList>
      </Section>

      <Section
        title="Per-account signatures"
        description="Appended to new messages from each account. Saved locally on this device."
      >
        {connections.length === 0 ? (
          <div className="border-border/60 rounded-md border border-dashed px-4 py-6 text-center">
            <Mail className="text-muted-foreground/50 mx-auto h-8 w-8" />
            <p className="text-muted-foreground mt-2 text-sm">No connected accounts</p>
            <p className="text-muted-foreground text-xs">
              Connect an account from Connections to set its signature.
            </p>
          </div>
        ) : (
          <div className="space-y-3">
            {connections.map((connection) => (
              <SignatureEditor
                key={connection.id}
                connectionId={connection.id}
                email={connection.email}
                name={connection.name}
                picture={connection.picture}
              />
            ))}
          </div>
        )}
      </Section>
    </div>
  );
}

function SignatureEditor({
  connectionId,
  email,
  name,
  picture,
}: {
  connectionId: string;
  email: string;
  name?: string | null;
  picture?: string | null;
}) {
  const [value, setValue] = useState('');

  useEffect(() => {
    setValue(loadSignature(connectionId));
  }, [connectionId]);

  const persist = useCallback(
    (next: string) => {
      setValue(next);
      saveSignature(connectionId, next);
    },
    [connectionId],
  );

  return (
    <div className="border-border/60 space-y-2 rounded-lg border px-3 py-3">
      <div className="flex items-center gap-2.5">
        {picture ? (
          <img src={picture} alt="" className="h-7 w-7 shrink-0 rounded-full object-cover" />
        ) : (
          <div className="bg-primary/10 flex h-7 w-7 shrink-0 items-center justify-center rounded-full">
            <Mail className="h-3.5 w-3.5" />
          </div>
        )}
        <div className="min-w-0">
          {name && <p className="truncate text-sm font-medium leading-tight">{name}</p>}
          <p className="text-muted-foreground truncate text-xs leading-tight">{email}</p>
        </div>
      </div>
      <Textarea
        value={value}
        onChange={(event) => persist(event.target.value)}
        placeholder={`e.g. Best,\n${name ?? email.split('@')[0]}`}
        className="min-h-[88px] resize-y text-sm"
      />
    </div>
  );
}
