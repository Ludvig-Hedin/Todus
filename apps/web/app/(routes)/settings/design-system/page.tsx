/**
 * Design System viewer (web).
 *
 * Cross-platform sister to `Features/DesignSystem/DesignSystemView.swift`
 * (iOS) and `Views/Settings/MacDesignSystemView.swift` (macOS). Renders every
 * surface-level token + component variant the app ships so we can dogfood
 * drift between platforms.
 *
 * Gated to `VITE_TODUS_ALLOWLISTED_EMAILS` so it never leaks to teammates
 * with stray developer-mode toggles. Non-allowlisted accounts get redirected
 * to `/settings/general` at the loader.
 */

import { redirect } from 'react-router';
import { useEffect, useState } from 'react';

import { SettingsCard } from '@/components/settings/settings-card';
import { authProxy } from '@/lib/auth-proxy';
import { isAllowlisted } from '@/lib/developer-access';
import { cn } from '@/lib/utils';

import { Button } from '@/components/ui/button';
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion';
import { TooltipProvider } from '@/components/ui/tooltip';

import {
  CATEGORY_LABELS,
  CATEGORY_ORDER,
  COMPONENT_MANIFEST,
  MANIFEST_FILE_PATH,
  type ComponentCategory,
  type ComponentEntry,
} from './_components-manifest';

import type { Route } from './+types/page';

// Mirror of ACCENT_COLORS in apps/web/app/(routes)/settings/appearance/page.tsx.
// Kept locally so this page does not import from a sibling route file (Vite
// route chunking treats those imports as inter-route coupling).
type AccentColor = {
  key: string;
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

/**
 * Tokens we render in the Colors section. Order mirrors the iOS surface
 * hierarchy so reviewers can scan left-to-right and spot drift fast.
 */
const COLOR_TOKENS: ReadonlyArray<string> = [
  '--background',
  '--foreground',
  '--card',
  '--card-foreground',
  '--popover',
  '--popover-foreground',
  '--primary',
  '--primary-foreground',
  '--secondary',
  '--secondary-foreground',
  '--muted',
  '--muted-foreground',
  '--accent',
  '--accent-foreground',
  '--destructive',
  '--destructive-foreground',
  '--border',
  '--input',
  '--ring',
  '--sidebar-background',
  '--sidebar-foreground',
  '--sidebar-primary',
  '--sidebar-accent',
  '--sidebar-border',
  '--panel',
];

const STATIC_COLOR_TOKENS: ReadonlyArray<string> = [
  '--darkBackground',
  '--lightBackground',
  '--offsetDark',
  '--offsetLight',
  '--panelDark',
  '--panelLight',
  '--iconDark',
  '--iconLight',
  '--logout',
  '--mainBlue',
  '--subtleWhite',
  '--subtleBlack',
  '--skyBlue',
  '--shinyGray',
];

const RADIUS_CHIPS: ReadonlyArray<{ token: string; px: string; usage: string }> = [
  { token: '--radius-xs', px: '7px', usage: 'Chip / pill micro' },
  { token: '--radius-sm', px: '12px', usage: 'Compact controls' },
  { token: '--radius-md', px: '14px', usage: 'Default controls' },
  { token: '--radius-lg', px: '16px', usage: 'Rows / list items' },
  { token: '--radius-xl', px: '18px', usage: 'Cards' },
  { token: '--radius-2xl', px: '24px', usage: 'Composer / sheet' },
];

const SPACING_CHIPS: ReadonlyArray<{ label: string; px: number; rem: string }> = [
  { label: '1', px: 4, rem: '0.25rem' },
  { label: '2', px: 8, rem: '0.5rem' },
  { label: '3', px: 12, rem: '0.75rem' },
  { label: '4', px: 16, rem: '1rem' },
  { label: '6', px: 24, rem: '1.5rem' },
  { label: '8', px: 32, rem: '2rem' },
];

const TYPOGRAPHY_SAMPLES: ReadonlyArray<{
  scale: string;
  className: string;
  letterSpacingNote: string;
}> = [
  { scale: 'text-xs', className: 'text-xs', letterSpacingNote: '-0.006em (body small)' },
  { scale: 'text-sm', className: 'text-sm', letterSpacingNote: '-0.006em (body small)' },
  { scale: 'text-base', className: 'text-base', letterSpacingNote: '-0.014em (body)' },
  { scale: 'text-lg', className: 'text-lg', letterSpacingNote: '-0.014em (body)' },
  { scale: 'text-xl', className: 'text-xl font-semibold', letterSpacingNote: '-0.02em (heading)' },
  {
    scale: 'text-2xl',
    className: 'text-2xl font-semibold',
    letterSpacingNote: '-0.02em (heading)',
  },
  {
    scale: 'text-3xl',
    className: 'text-3xl font-semibold',
    letterSpacingNote: '-0.02em (heading)',
  },
];

const SHADOW_SAMPLES: ReadonlyArray<{ token: string; className: string }> = [
  { token: 'shadow-sm', className: 'shadow-sm' },
  { token: 'shadow-md', className: 'shadow-md' },
  { token: 'shadow-lg', className: 'shadow-lg' },
  { token: 'shadow-xl', className: 'shadow-xl' },
];

const MOTION_DEMOS: ReadonlyArray<{
  label: string;
  durationVar: string;
  ms: string;
}> = [
  { label: 'Fast', durationVar: 'var(--motion-duration-fast)', ms: '150ms' },
  { label: 'Base', durationVar: 'var(--motion-duration-base)', ms: '250ms' },
  { label: 'Slow', durationVar: 'var(--motion-duration-slow)', ms: '350ms' },
];

export async function clientLoader({ request }: Route.ClientLoaderArgs) {
  const session = await authProxy.api.getSession({ headers: request.headers });

  if (!session) {
    throw redirect('/login');
  }

  if (!isAllowlisted(session.user?.email)) {
    throw redirect('/settings/general');
  }

  return null;
}

export default function DesignSystemSettingsPage() {
  return (
    <div className="grid gap-6">
      <SettingsCard
        title="Design System"
        description="Live, dogfood-only viewer for color, type, radius, spacing, motion, and component variants. Mirror of the iOS / macOS Design System screens — drift between platforms should show up here first."
      >
        <p className="text-muted-foreground text-[13px]">
          Edit tokens at{' '}
          <code className="bg-muted rounded px-1 py-0.5 font-mono text-[12px]">
            apps/web/app/globals.css
          </code>{' '}
          (see &ldquo;How to change&rdquo; at the bottom).
        </p>
      </SettingsCard>

      <ColorTokensSection />
      <StaticColorsSection />
      <AccentPaletteSection />
      <TypographySection />
      <RadiusSection />
      <SpacingSection />
      <ShadowsSection />
      <MotionSection />
      <ComponentGallerySection />
      <HowToChangeSection />
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* Sections                                                                    */
/* -------------------------------------------------------------------------- */

function ColorTokensSection() {
  return (
    <SettingsCard
      title="Colors"
      description="Theme tokens that flip between light + dark. Hex shown is what the browser computed for the current theme — toggle Appearance to compare modes."
    >
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
        {COLOR_TOKENS.map((token) => (
          <TokenSwatch key={token} token={token} />
        ))}
      </div>
    </SettingsCard>
  );
}

function StaticColorsSection() {
  return (
    <SettingsCard
      title="Static colors"
      description="Brand and product constants that do not flip between light + dark. Use sparingly — most surfaces should reference the theme tokens above."
    >
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
        {STATIC_COLOR_TOKENS.map((token) => (
          <TokenSwatch key={token} token={token} />
        ))}
      </div>
    </SettingsCard>
  );
}

function AccentPaletteSection() {
  return (
    <SettingsCard
      title="Accent palette"
      description="Same 6-color ramp the iOS + macOS accent picker exposes. Edit in Appearance settings."
    >
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
        {ACCENT_COLORS.map((accent) => (
          <div
            key={accent.key}
            className="border-border/60 bg-card rounded-lg border p-3 shadow-sm"
          >
            <div className="flex items-center gap-3">
              <span
                className="h-10 w-10 rounded-full border border-black/5 shadow-inner"
                style={{ backgroundColor: accent.light }}
                aria-hidden
              />
              <div className="flex flex-col">
                <span className="text-sm font-medium">{accent.label}</span>
                <span className="text-muted-foreground font-mono text-[11px]">
                  {accent.light.toLowerCase()}
                </span>
              </div>
            </div>
            <div className="mt-3 flex items-center gap-2">
              <span
                className="h-6 w-full rounded-md border border-black/5"
                style={{ backgroundColor: accent.dark }}
                aria-hidden
              />
              <span className="text-muted-foreground font-mono text-[11px]">
                {accent.dark.toLowerCase()}
              </span>
            </div>
          </div>
        ))}
      </div>
    </SettingsCard>
  );
}

function TypographySection() {
  return (
    <SettingsCard
      title="Typography"
      description="Geist Variable sans across the Tailwind scale. Headings use -0.02em tracking, body -0.014em, small labels -0.006em — set in globals.css base layer."
    >
      <div className="space-y-3">
        {TYPOGRAPHY_SAMPLES.map((sample) => (
          <div
            key={sample.scale}
            className="border-border/60 flex flex-col gap-1 border-b pb-3 last:border-0 last:pb-0 sm:flex-row sm:items-baseline sm:justify-between"
          >
            <div className="flex-1">
              <p className={cn(sample.className, 'truncate')}>The quick brown fox</p>
            </div>
            <div className="text-muted-foreground flex shrink-0 items-center gap-3 font-mono text-[11px] sm:justify-end">
              <span className="rounded-md bg-muted px-1.5 py-0.5">{sample.scale}</span>
              <span>{sample.letterSpacingNote}</span>
            </div>
          </div>
        ))}
      </div>
    </SettingsCard>
  );
}

function RadiusSection() {
  return (
    <SettingsCard
      title="Radius"
      description="6-tier scale that mirrors iOS Radius.chip/compact/control/row/card/composer. Plus the literal rounded-full for circular controls."
    >
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
        {RADIUS_CHIPS.map((chip) => (
          <div
            key={chip.token}
            className="border-border/60 bg-card flex items-center gap-3 rounded-lg border p-3"
          >
            <div
              className="bg-muted-foreground/15 border-border/60 h-12 w-12 shrink-0 border"
              style={{ borderRadius: `var(${chip.token})` }}
              aria-hidden
            />
            <div className="flex min-w-0 flex-col">
              <code className="truncate font-mono text-[11px]">{chip.token}</code>
              <span className="text-muted-foreground text-[11px]">{chip.px}</span>
              <span className="text-muted-foreground text-[11px]">{chip.usage}</span>
            </div>
          </div>
        ))}
        <div className="border-border/60 bg-card flex items-center gap-3 rounded-lg border p-3">
          <div
            className="bg-muted-foreground/15 border-border/60 h-12 w-12 shrink-0 rounded-full border"
            aria-hidden
          />
          <div className="flex min-w-0 flex-col">
            <code className="truncate font-mono text-[11px]">rounded-full</code>
            <span className="text-muted-foreground text-[11px]">circle / pill</span>
            <span className="text-muted-foreground text-[11px]">Buttons, avatars</span>
          </div>
        </div>
      </div>
    </SettingsCard>
  );
}

function SpacingSection() {
  return (
    <SettingsCard
      title="Spacing"
      description="4-pt rhythm that all components hang off of. iOS / macOS use the same scale."
    >
      <div className="flex flex-wrap items-end gap-4">
        {SPACING_CHIPS.map((spacing) => (
          <div key={spacing.label} className="flex flex-col items-center gap-2">
            <div
              className="bg-foreground/80 rounded-sm"
              style={{ width: `${spacing.px}px`, height: `${spacing.px}px` }}
              aria-hidden
            />
            <div className="flex flex-col items-center">
              <code className="font-mono text-[11px]">{spacing.label}</code>
              <span className="text-muted-foreground text-[10px]">{spacing.px}px</span>
              <span className="text-muted-foreground text-[10px]">{spacing.rem}</span>
            </div>
          </div>
        ))}
      </div>
    </SettingsCard>
  );
}

function ShadowsSection() {
  return (
    <SettingsCard
      title="Shadows"
      description="Tailwind defaults. Reserve shadow-xl for modals / popouts that need real elevation against the background."
    >
      <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
        {SHADOW_SAMPLES.map((shadow) => (
          <div
            key={shadow.token}
            className={cn(
              'bg-card flex h-24 flex-col items-center justify-center gap-2 rounded-xl',
              shadow.className,
            )}
          >
            <code className="font-mono text-[12px]">{shadow.token}</code>
          </div>
        ))}
      </div>
    </SettingsCard>
  );
}

function MotionSection() {
  return (
    <SettingsCard
      title="Motion"
      description="Tap each button to animate the chip with the corresponding duration token. Tokens live in globals.css :root."
    >
      <MotionDemo />
    </SettingsCard>
  );
}

function MotionDemo() {
  const [activeDuration, setActiveDuration] = useState<string>(MOTION_DEMOS[1].durationVar);
  const [pulse, setPulse] = useState(false);

  function trigger(durationVar: string) {
    setActiveDuration(durationVar);
    setPulse(false);
    // Force a reflow so consecutive clicks re-trigger the transition reliably.
    requestAnimationFrame(() => setPulse(true));
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap gap-2">
        {MOTION_DEMOS.map((demo) => (
          <Button
            key={demo.label}
            type="button"
            variant="outline"
            size="sm"
            onClick={() => trigger(demo.durationVar)}
          >
            {demo.label}
            <span className="text-muted-foreground ml-1.5 font-mono text-[11px]">{demo.ms}</span>
          </Button>
        ))}
      </div>
      <div className="bg-muted/40 relative h-14 overflow-hidden rounded-lg p-2">
        <div
          className="bg-primary h-10 w-10 rounded-md"
          style={{
            transform: pulse ? 'translateX(calc(100% * 5))' : 'translateX(0)',
            transitionProperty: 'transform',
            transitionDuration: activeDuration,
            transitionTimingFunction: 'var(--motion-easing-standard)',
          }}
        />
      </div>
      <p className="text-muted-foreground text-[11px]">
        Standard easing:{' '}
        <code className="font-mono">cubic-bezier(0.2, 0, 0, 1)</code> — used for everything except
        large sheet enter/exit, which switches to{' '}
        <code className="font-mono">cubic-bezier(0.16, 1, 0.3, 1)</code>.
      </p>
    </div>
  );
}

function ComponentGallerySection() {
  // Group entries by category. The empty-category branches stay collapsed so
  // adding a new category just means adding entries to the manifest.
  const grouped = new Map<ComponentCategory, ComponentEntry[]>();
  for (const entry of COMPONENT_MANIFEST) {
    const bucket = grouped.get(entry.category) ?? [];
    bucket.push(entry);
    grouped.set(entry.category, bucket);
  }

  return (
    <SettingsCard
      title="Component gallery"
      description="Every variant of the shipped shadcn/ui primitives. If a component renders inconsistently here, it will render inconsistently in the app."
    >
      <TooltipProvider delayDuration={120}>
        <div className="space-y-10">
          {CATEGORY_ORDER.map((category) => {
            const entries = grouped.get(category);
            if (!entries || entries.length === 0) return null;
            return (
              <CategorySection
                key={category}
                title={CATEGORY_LABELS[category]}
                entries={entries}
              />
            );
          })}
          <AddNewComponentCallout />
        </div>
      </TooltipProvider>
    </SettingsCard>
  );
}

function CategorySection({
  title,
  entries,
}: {
  title: string;
  entries: ComponentEntry[];
}) {
  return (
    <section className="space-y-5">
      <h2 className="text-muted-foreground text-[11px] font-semibold uppercase tracking-wider">
        {title}
      </h2>
      <div className="space-y-6">
        {entries.map((entry) => (
          <GalleryEntry key={`${entry.category}-${entry.name}`} entry={entry} />
        ))}
      </div>
    </section>
  );
}

function GalleryEntry({ entry }: { entry: ComponentEntry }) {
  return (
    <div className="border-border/60 border-b pb-5 last:border-0 last:pb-0">
      <div className="mb-3 flex flex-wrap items-baseline justify-between gap-2">
        <h3 className="text-sm font-medium">{entry.name}</h3>
        <code className="text-muted-foreground font-mono text-[11px]">{entry.file}</code>
      </div>
      <div className="flex flex-wrap items-center gap-3">
        {entry.variants
          ? entry.variants.map((variant) => (
              <div key={variant.name} className="flex flex-col items-start gap-1">
                {variant.render()}
                <span className="text-muted-foreground font-mono text-[10px]">
                  {variant.name}
                </span>
              </div>
            ))
          : entry.render?.()}
      </div>
      {entry.notes ? (
        <p className="text-muted-foreground mt-3 text-[11px]">{entry.notes}</p>
      ) : null}
    </div>
  );
}

function AddNewComponentCallout() {
  return (
    <div className="border-border/60 bg-muted/30 rounded-lg border border-dashed p-4">
      <h3 className="text-sm font-medium">Add a new component</h3>
      <p className="text-muted-foreground mt-1 text-[12px]">
        When a new shadcn/ui primitive lands under{' '}
        <code className="font-mono">components/ui/</code>, add an entry to{' '}
        <code className="bg-muted rounded px-1 py-0.5 font-mono text-[11px]">
          {MANIFEST_FILE_PATH}
        </code>
        . The viewer maps over the manifest grouped by category, so a new entry is all it takes.
      </p>
    </div>
  );
}

function HowToChangeSection() {
  return (
    <SettingsCard
      title="How to change"
      description="Where each token lives so the next person doesn't have to grep."
    >
      <Accordion type="multiple" className="w-full">
        <AccordionItem value="colors">
          <AccordionTrigger>Color tokens</AccordionTrigger>
          <AccordionContent>
            <p className="text-muted-foreground text-sm">
              Theme tokens live in{' '}
              <code className="bg-muted rounded px-1 py-0.5 font-mono text-[12px]">
                apps/web/app/globals.css
              </code>{' '}
              under the <code className="font-mono">:root</code> (light) and{' '}
              <code className="font-mono">.dark</code> blocks. Tailwind v4 exposure happens in the
              <code className="font-mono">@theme inline</code> block immediately below.
            </p>
          </AccordionContent>
        </AccordionItem>

        <AccordionItem value="radius">
          <AccordionTrigger>Radius scale</AccordionTrigger>
          <AccordionContent>
            <p className="text-muted-foreground text-sm">
              <code className="font-mono">--radius</code>, <code className="font-mono">--radius-xs</code>{' '}
              and <code className="font-mono">--radius-2xl</code> in <code className="font-mono">globals.css</code>.{' '}
              <code className="font-mono">--radius-sm/md/lg</code> are derived via the existing calc
              chain inside <code className="font-mono">@theme inline</code>.
            </p>
          </AccordionContent>
        </AccordionItem>

        <AccordionItem value="motion">
          <AccordionTrigger>Motion tokens</AccordionTrigger>
          <AccordionContent>
            <p className="text-muted-foreground text-sm">
              <code className="font-mono">--motion-duration-fast/base/slow</code> +{' '}
              <code className="font-mono">--motion-easing-standard/emphasized</code> in{' '}
              <code className="font-mono">globals.css :root</code>. Surfaced to Tailwind via{' '}
              <code className="font-mono">--default-transition-duration</code> /{' '}
              <code className="font-mono">--default-transition-timing-function</code>.
            </p>
            <p className="text-muted-foreground mt-2 text-sm">
              Use them in JSX as <code className="font-mono">duration-(--motion-duration-fast)</code>
              and <code className="font-mono">ease-(--motion-easing-standard)</code>.
            </p>
          </AccordionContent>
        </AccordionItem>

        <AccordionItem value="components">
          <AccordionTrigger>Component primitives</AccordionTrigger>
          <AccordionContent>
            <p className="text-muted-foreground text-sm">
              shadcn/ui primitives live under{' '}
              <code className="font-mono">apps/web/components/ui/</code>. The most-edited files for
              motion + radius parity are <code className="font-mono">button.tsx</code>,{' '}
              <code className="font-mono">input.tsx</code>, <code className="font-mono">dialog.tsx</code>,{' '}
              <code className="font-mono">sheet.tsx</code>, <code className="font-mono">dropdown-menu.tsx</code>,
              and <code className="font-mono">sidebar.tsx</code>.
            </p>
          </AccordionContent>
        </AccordionItem>

        <AccordionItem value="allowlist">
          <AccordionTrigger>Allowlist + visibility</AccordionTrigger>
          <AccordionContent>
            <p className="text-muted-foreground text-sm">
              This page (and its nav entry) is gated by{' '}
              <code className="font-mono">apps/web/lib/developer-access.ts</code>, which reads{' '}
              <code className="font-mono">VITE_TODUS_ALLOWLISTED_EMAILS</code> (comma-separated,
              lowercased). Mirrors the iOS / macOS{' '}
              <code className="font-mono">TODUS_ALLOWLISTED_EMAILS</code> Swift gate.
            </p>
          </AccordionContent>
        </AccordionItem>
      </Accordion>
    </SettingsCard>
  );
}

/* -------------------------------------------------------------------------- */
/* Helpers                                                                     */
/* -------------------------------------------------------------------------- */

function TokenSwatch({ token }: { token: string }) {
  const [computed, setComputed] = useState<string>('');

  useEffect(() => {
    if (typeof document === 'undefined') return;

    function read() {
      const value = getComputedStyle(document.documentElement)
        .getPropertyValue(token)
        .trim();
      setComputed(value || '—');
    }

    read();

    // Re-read whenever the theme toggles. next-themes flips the .dark class on
    // <html>, so a MutationObserver on documentElement.class catches it.
    const observer = new MutationObserver(read);
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ['class'] });
    return () => observer.disconnect();
  }, [token]);

  return (
    <div className="border-border/60 bg-card flex items-center gap-3 rounded-lg border p-2.5">
      <span
        className="border-border/60 h-9 w-9 shrink-0 rounded-md border"
        style={{ backgroundColor: `var(${token})` }}
        aria-hidden
      />
      <div className="flex min-w-0 flex-col">
        <code className="truncate font-mono text-[11px]">{token}</code>
        <span className="text-muted-foreground truncate font-mono text-[11px]">
          {computed || '—'}
        </span>
      </div>
    </div>
  );
}

/**
 * Lets React Router treat the loader as runtime even though it has no data.
 * Mirrors the export contract used by the other settings pages.
 */
export function HydrateFallback() {
  return null;
}
