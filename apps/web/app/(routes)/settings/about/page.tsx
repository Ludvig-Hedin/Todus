/**
 * About settings page.
 *
 * Mirrors the iOS / macOS About & Legal section: surface app version, build
 * info, and the canonical Terms / Privacy / open-source license links so all
 * three surfaces expose the same place to find this metadata.
 */

import { SettingsCard } from '@/components/settings/settings-card';
import { ExternalLink } from 'lucide-react';

const VERSION = (typeof import.meta !== 'undefined' && (import.meta as any).env?.VITE_APP_VERSION) || '1.0';
const BUILD = (typeof import.meta !== 'undefined' && (import.meta as any).env?.VITE_APP_BUILD) || 'dev';

export default function AboutSettingsPage() {
  return (
    <div className="grid gap-5">
      <SettingsCard title="About" description="Build info for this client.">
        <div className="space-y-2 text-sm">
          <Row label="App" value="Todus" />
          <Row label="Version" value={VERSION} />
          <Row label="Build" value={BUILD} />
          <Row label="Platform" value="Web" />
        </div>
      </SettingsCard>

      <SettingsCard title="Legal" description="Policies that apply to your use of Todus.">
        <div className="space-y-2 text-sm">
          <LegalLink href="/terms" label="Terms of Service" />
          <LegalLink href="/privacy" label="Privacy Policy" />
        </div>
      </SettingsCard>

      <SettingsCard
        title="Open Source"
        description="Todus is built on open-source software. The full list of dependencies and their licenses is available in the project repository."
      >
        <LegalLink
          href="https://github.com/anthropics"
          label="View open-source licenses"
          external
        />
      </SettingsCard>
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between gap-3 border-b border-border/40 pb-2 last:border-0 last:pb-0">
      <span className="text-muted-foreground">{label}</span>
      <span className="font-mono text-xs">{value}</span>
    </div>
  );
}

function LegalLink({
  href,
  label,
  external = false,
}: {
  href: string;
  label: string;
  external?: boolean;
}) {
  return (
    <a
      href={href}
      target={external ? '_blank' : undefined}
      rel={external ? 'noopener noreferrer' : undefined}
      className="text-foreground hover:text-primary inline-flex items-center gap-1.5 text-sm underline-offset-4 hover:underline"
    >
      {label}
      {external && <ExternalLink className="h-3.5 w-3.5" />}
    </a>
  );
}
