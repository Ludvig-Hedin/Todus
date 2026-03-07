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

const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const screens = manifest.screens ?? [];
const webBaseUrl = (process.env.PARITY_WEB_BASE_URL ?? 'https://todus.app').replace(/\/$/, '');
const timeoutMs = Number(process.env.PARITY_MACOS_TIMEOUT_MS ?? 90_000);
const delayMs = Number(process.env.PARITY_MACOS_DELAY_MS ?? 1200);

function normalizedRoute(rawRoute) {
  return rawRoute
    .replace('<sample>', 'sample')
    .replace('/mail/inbox?threadId=sample', '/mail/inbox')
    .replace('/mail/inbox?search=sample', '/mail/inbox?search=sample');
}

let captured = 0;
let skipped = 0;
const failures = [];

for (const screen of screens) {
  const route = normalizedRoute(screen.webRoute ?? '/login');
  const appEntryUrl = `${webBaseUrl}${route.startsWith('/') ? route : `/${route}`}`;
  const targetPath = path.join(parityDir, `${screen.slug}__macos.png`);

  const run = spawnSync('pnpm', ['--filter', '@zero/macos', 'dev:macos'], {
    cwd: rootDir,
    encoding: 'utf8',
    timeout: timeoutMs,
    env: {
      ...process.env,
      EXPO_PUBLIC_WEB_URL: webBaseUrl,
      EXPO_PUBLIC_APP_ENTRY_URL: appEntryUrl,
      PARITY_CAPTURE_PATH: targetPath,
      PARITY_CAPTURE_DELAY_MS: String(delayMs),
      PARITY_CAPTURE_QUIT: '1',
    },
  });

  if (run.status === 0 && fs.existsSync(targetPath)) {
    captured += 1;
    console.log(`Captured ${screen.slug} -> ${path.basename(targetPath)}`);
  } else {
    skipped += 1;
    failures.push(`${screen.slug}: capture failed (${run.status ?? 'timeout'})`);
  }
}

console.log(`\nDone. Captured: ${captured}. Skipped: ${skipped}.`);
if (failures.length > 0) {
  console.log('\nNotes:');
  failures.forEach((failure) => console.log(`- ${failure}`));
}
