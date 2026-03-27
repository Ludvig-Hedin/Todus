import { SettingsCard } from '@/components/settings/settings-card';
import { m } from '@/paraglide/messages';
import { Lock, ShieldCheck } from 'lucide-react';

/**
 * Security settings page — features are not yet implemented on the backend,
 * so we show a clear "coming soon" state rather than non-functional toggles
 * that could mislead users into thinking they've enabled security features.
 */
export default function SecurityPage() {
  return (
    <div className="grid gap-6">
      <SettingsCard
        title={m['pages.settings.security.title']()}
        description={m['pages.settings.security.description']()}
      >
        <div className="flex flex-col items-center justify-center py-8 text-center">
          <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-muted">
            <ShieldCheck className="h-6 w-6 text-muted-foreground" />
          </div>
          <h3 className="text-base font-semibold">Security features coming soon</h3>
          <p className="mt-1.5 max-w-sm text-[13px] text-muted-foreground">
            Two-factor authentication, login notifications, and account management
            options are being developed and will be available in an upcoming release.
          </p>
        </div>
      </SettingsCard>
    </div>
  );
}
