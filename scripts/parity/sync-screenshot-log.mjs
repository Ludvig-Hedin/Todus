#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const rootDir = process.cwd();
const parityDir = path.join(rootDir, 'parity_screenshots');
const manifestPath = path.join(parityDir, 'manifest.json');
const logPath = path.join(parityDir, 'SCREENSHOT_LOG.md');

if (!fs.existsSync(manifestPath)) {
  console.error('Missing parity_screenshots/manifest.json');
  process.exit(1);
}

const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const platforms = manifest.platforms ?? ['web', 'ios', 'android', 'macos'];
const screens = manifest.screens ?? [];

const hasPlatform = (platform) => platforms.includes(platform);
const statusFor = (slug, platform) => {
  const filePath = path.join(parityDir, `${slug}__${platform}.png`);
  return fs.existsSync(filePath) ? 'Y' : 'N';
};

const today = new Date().toISOString().slice(0, 10);

const header = [
  '# Screenshot Diff Log',
  '',
  `Last updated: ${today}`,
  '',
  'Use this file to record visual comparison notes after screenshots are captured.',
  '',
  'Legend:',
  '',
  '- `Y` = captured',
  '- `N` = missing',
  '',
  '| Screen | Web | iOS | Android | macOS | Diff Notes | Accepted |',
  '| ------ | --- | --- | ------- | ----- | ---------- | -------- |',
];

const rows = screens.map((screen) => {
  const slug = screen.slug;
  const web = hasPlatform('web') ? statusFor(slug, 'web') : '-';
  const ios = hasPlatform('ios') ? statusFor(slug, 'ios') : '-';
  const android = hasPlatform('android') ? statusFor(slug, 'android') : '-';
  const macos = hasPlatform('macos') ? statusFor(slug, 'macos') : '-';
  return `| ${slug} | ${web} | ${ios} | ${android} | ${macos} |  |  |`;
});

fs.writeFileSync(logPath, [...header, ...rows, ''].join('\n'));
console.log(`Synced screenshot log for ${screens.length} screens: ${logPath}`);
