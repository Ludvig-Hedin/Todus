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

const appScheme = process.env.PARITY_ANDROID_SCHEME ?? 'todus';
const appPackage = process.env.PARITY_ANDROID_PACKAGE ?? 'com.ludvighedin.todus';
const settleMs = Number(process.env.PARITY_ANDROID_SETTLE_MS ?? 1500);
const deviceId = process.env.PARITY_ANDROID_DEVICE?.trim() ?? '';

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

function run(command, args, options = {}) {
  return spawnSync(command, args, { ...options });
}

function adbArgs(args) {
  return deviceId ? ['-s', deviceId, ...args] : args;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

const devices = run('adb', ['devices'], { encoding: 'utf8' });
if (devices.status !== 0) {
  console.error('Failed to run adb. Is Android SDK/adb installed?');
  process.exit(1);
}

const onlineDevices = devices.stdout
  .split('\n')
  .slice(1)
  .map((line) => line.trim())
  .filter((line) => line.endsWith('\tdevice'));

if (onlineDevices.length === 0) {
  console.error('No online Android device/emulator found.');
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
  const target = path.join(parityDir, `${screen.slug}__android.png`);

  const openResult = run(
    'adb',
    adbArgs([
      'shell',
      'am',
      'start',
      '-W',
      '-a',
      'android.intent.action.VIEW',
      '-d',
      deepLink,
      '-p',
      appPackage,
    ]),
    { encoding: 'utf8' },
  );
  if (openResult.status !== 0) {
    skipped += 1;
    failures.push(`${screen.slug}: failed to open ${deepLink}`);
    continue;
  }

  // eslint-disable-next-line no-await-in-loop
  await sleep(settleMs);

  const screenshotResult = run('adb', adbArgs(['exec-out', 'screencap', '-p']));
  if (screenshotResult.status === 0 && screenshotResult.stdout) {
    fs.writeFileSync(target, screenshotResult.stdout);
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
