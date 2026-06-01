#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const rootDir = process.cwd();
const parityDir = path.join(rootDir, 'parity_screenshots');
const manifestPath = path.join(parityDir, 'manifest.json');

if (!fs.existsSync(manifestPath)) {
  console.error('Missing parity_screenshots/manifest.json');
  process.exit(1);
}

// CLI: --surface <name>    Only capture screens with surface === <name>
const args = process.argv.slice(2);
function flag(name) {
  const idx = args.indexOf(name);
  if (idx === -1) return undefined;
  return args[idx + 1];
}
const surfaceFilter = flag('--surface');

const appScheme = process.env.PARITY_IOS_SCHEME ?? 'todus';
// `Number("foo")` is `NaN`, and `setTimeout(_, NaN)` coerces to 0 — a
// non-numeric `PARITY_IOS_SETTLE_MS` would skip the settle delay silently
// and screenshot a mid-transition UI. Guard with `Number.isFinite`.
const settleMsRaw = Number(process.env.PARITY_IOS_SETTLE_MS);
const settleMs = Number.isFinite(settleMsRaw) && settleMsRaw >= 0 ? settleMsRaw : 1200;

const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const allScreens = manifest.screens ?? [];
const screens = surfaceFilter
  ? allScreens.filter((s) => s.surface === surfaceFilter)
  : allScreens;

if (screens.length === 0) {
  console.log(`No screens match filter (surface=${surfaceFilter ?? '*'}).`);
  process.exit(0);
}

// Route mapping. Manifest entries may include `iosDeepLink` to override the
// derived route directly (e.g. for sheet-style surfaces or developer-gated
// screens that don't have a 1:1 web route). When set, that wins.
const routeBySlug = {
  Login: '/login',
  Signup: '/signup',
  MailInbox: '/inbox',
  MailSent: '/sent',
  MailDraft: '/draft',
  MailArchive: '/archive',
  MailBin: '/bin',
  MailSpam: '/spam',
  MailSnoozed: '/snoozed',
  MailThreadDetail: '/thread/sample-thread',
  MailCompose: '/compose',
  MailSearch: '/search',
  SettingsGeneral: '/settings/general',
  SettingsAppearance: '/settings/appearance',
  SettingsConnections: '/settings/connections',
  SettingsLabels: '/settings/labels',
  SettingsCategories: '/settings/categories',
  SettingsNotifications: '/settings/notifications',
  SettingsPrivacy: '/settings/privacy',
  SettingsSecurity: '/settings/security',
  SettingsShortcuts: '/settings/shortcuts',
  SettingsDangerZone: '/settings/danger-zone',
  NotFound: '/missing-route-for-not-found',
  // DesignSystem*: the iOS app does NOT yet implement a settings deep-link
  // handler (see `.onOpenURL` in `apps/ios/Todus/Todus/App/TodosApp.swift` —
  // only `auth-callback`, `link-callback`, `share`, `mailto` are routed). The
  // deep-link auto path therefore can't navigate into the DS view; use the
  // `pnpm parity:screenshots:capture:ios` interactive flow instead, or wire a
  // `todus://settings/<name>` handler in TodosApp.swift to unblock automation.
};

// Slugs we deliberately refuse to capture via deep link until the iOS app
// gains a settings router. Skipping is safer than capturing whatever the
// simulator happens to be showing.
const slugsRequiringInteractiveCapture = new Set([
  'DesignSystem',
  'DesignSystemColors',
  'DesignSystemTypography',
  'DesignSystemRadius',
  'DesignSystemSpacing',
  'DesignSystemComponents',
  'DesignSystemMotion',
]);

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function run(command, args) {
  return spawnSync(command, args, { encoding: 'utf8' });
}

const booted = run('xcrun', ['simctl', 'list', 'devices', 'booted']);
if (booted.status !== 0 || !booted.stdout.includes('Booted')) {
  console.error('No booted iOS simulator found.');
  process.exit(1);
}

let captured = 0;
let skipped = 0;
const failures = [];

for (const screen of screens) {
  if (slugsRequiringInteractiveCapture.has(screen.slug)) {
    skipped += 1;
    failures.push(
      `${screen.slug}: iOS deep-link router has no /settings/* handler — use \`pnpm parity:screenshots:capture:ios\` (interactive) instead`,
    );
    continue;
  }

  const route = screen.iosDeepLink ?? routeBySlug[screen.slug];
  if (!route) {
    skipped += 1;
    failures.push(`${screen.slug}: missing route mapping`);
    continue;
  }

  // Allow manifest to supply a fully-qualified deep link (e.g. todus://...).
  // Strip a leading slash so `${scheme}://${route}` doesn't become
  // `todus:///login` (triple slash = empty host) which iOS `.onOpenURL`
  // parses with a different host/path split than `todus://login`.
  const deepLink = route.includes('://')
    ? route
    : `${appScheme}://${route.replace(/^\/+/, '')}`;
  const target = path.join(parityDir, `${screen.slug}__ios.png`);

  const openResult = run('xcrun', ['simctl', 'openurl', 'booted', deepLink]);
  if (openResult.status !== 0) {
    skipped += 1;
    failures.push(`${screen.slug}: failed to open ${deepLink}`);
    continue;
  }

  // eslint-disable-next-line no-await-in-loop
  await sleep(settleMs);

  const shot = run('xcrun', ['simctl', 'io', 'booted', 'screenshot', target]);
  if (shot.status === 0) {
    captured += 1;
    console.log(`Captured ${screen.slug} -> ${path.basename(target)}`);
  } else {
    skipped += 1;
    failures.push(`${screen.slug}: screenshot failed`);
  }
}

console.log(`\nDone. Captured: ${captured}. Skipped: ${skipped}.`);
if (failures.length > 0) {
  console.log('\nNotes:');
  failures.forEach((failure) => console.log(`- ${failure}`));
}
