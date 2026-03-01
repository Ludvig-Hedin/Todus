#!/usr/bin/env node

import path from 'node:path';
import fs from 'node:fs';

const rootDir = process.cwd();
const parityDir = path.join(rootDir, 'parity_screenshots');
const manifestPath = path.join(parityDir, 'manifest.json');

if (!fs.existsSync(manifestPath)) {
  console.error('Missing parity_screenshots/manifest.json');
  process.exit(1);
}

const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const platforms = manifest.platforms ?? ['web', 'ios', 'android', 'macos'];
const screens = manifest.screens ?? [];

const missing = [];
let foundCount = 0;
let expectedCount = 0;

for (const screen of screens) {
  for (const platform of platforms) {
    const fileName = `${screen.slug}__${platform}.png`;
    const filePath = path.join(parityDir, fileName);
    expectedCount += 1;

    if (fs.existsSync(filePath)) {
      foundCount += 1;
    } else {
      missing.push(fileName);
    }
  }
}

const coverage = expectedCount === 0 ? 100 : Math.round((foundCount / expectedCount) * 100);

console.log(`Screenshots coverage: ${foundCount}/${expectedCount} (${coverage}%)`);

if (missing.length > 0) {
  console.log('\nMissing files:');
  for (const file of missing) {
    console.log(`- ${file}`);
  }
  process.exit(1);
}

console.log('\nAll required screenshots are present.');
