#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { createInterface } from 'node:readline/promises';
import { stdin as input, stdout as output } from 'node:process';
import { spawnSync } from 'node:child_process';

const rootDir = process.cwd();
const parityDir = path.join(rootDir, 'parity_screenshots');
const manifestPath = path.join(parityDir, 'manifest.json');

if (!fs.existsSync(manifestPath)) {
  console.error('Missing parity_screenshots/manifest.json');
  process.exit(1);
}

const xcrunCheck = spawnSync('xcrun', ['simctl', 'list', 'devices', 'booted'], {
  encoding: 'utf8',
});
if (xcrunCheck.status !== 0 || !xcrunCheck.stdout.includes('Booted')) {
  console.error('No booted iOS simulator found. Boot a simulator and run again.');
  process.exit(1);
}

const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const screens = manifest.screens ?? [];

if (screens.length === 0) {
  console.log('No screens in manifest.');
  process.exit(0);
}

const rl = createInterface({ input, output });

let captured = 0;
let skipped = 0;

console.log(
  `Interactive iOS capture started for ${screens.length} screens. Commands: [Enter]=capture, s=skip, q=quit`,
);

for (const screen of screens) {
  const slug = screen.slug;
  const route = screen.webRoute ?? '';
  const target = path.join(parityDir, `${slug}__ios.png`);
  const exists = fs.existsSync(target);
  const prompt = exists
    ? `\n${slug} (${route}) already exists. [Enter]=recapture, s=skip, q=quit: `
    : `\n${slug} (${route}) [Enter]=capture, s=skip, q=quit: `;

  // eslint-disable-next-line no-await-in-loop
  const answer = (await rl.question(prompt)).trim().toLowerCase();
  if (answer === 'q') {
    break;
  }
  if (answer === 's') {
    skipped += 1;
    continue;
  }

  const shot = spawnSync('xcrun', ['simctl', 'io', 'booted', 'screenshot', target], {
    encoding: 'utf8',
  });
  if (shot.status === 0) {
    captured += 1;
    console.log(`Captured ${path.basename(target)}`);
  } else {
    skipped += 1;
    console.error(`Failed ${slug}: ${shot.stderr || shot.stdout}`);
  }
}

rl.close();

console.log(`\nDone. Captured: ${captured}. Skipped: ${skipped}.`);
