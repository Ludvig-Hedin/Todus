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

const appScheme = process.env.PARITY_IOS_SCHEME ?? 'todus';
const settleMs = Number(process.env.PARITY_IOS_SETTLE_MS ?? 1200);

const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const screens = manifest.screens ?? [];

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
};

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
  const route = routeBySlug[screen.slug];
  if (!route) {
    skipped += 1;
    failures.push(`${screen.slug}: missing route mapping`);
    continue;
  }

  const deepLink = `${appScheme}://${route}`;
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
