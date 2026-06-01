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

// CLI flags
//   --surface <name>     Only check screens with `surface === <name>` in manifest
//   --platform <name>    Only check this platform
//   --strict-presence    Default; fails if any expected file is missing
//   --allow-missing      Reports but does not fail on missing files
const args = process.argv.slice(2);
function flag(name) {
  const idx = args.indexOf(name);
  if (idx === -1) return undefined;
  return args[idx + 1];
}
const surfaceFilter = flag('--surface');
const platformFilter = flag('--platform');
const allowMissing = args.includes('--allow-missing');

const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const allPlatforms = manifest.platforms ?? ['web', 'ios', 'android', 'macos'];
const platforms = platformFilter ? allPlatforms.filter((p) => p === platformFilter) : allPlatforms;
const screens = (manifest.screens ?? []).filter((s) =>
  surfaceFilter ? s.surface === surfaceFilter : true,
);

if (screens.length === 0) {
  console.log(`No screens match filter (surface=${surfaceFilter ?? '*'}).`);
  process.exit(0);
}

if (platforms.length === 0) {
  console.log(`No platforms match filter (platform=${platformFilter ?? '*'}).`);
  process.exit(0);
}

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

const filterLabel = [
  surfaceFilter ? `surface=${surfaceFilter}` : null,
  platformFilter ? `platform=${platformFilter}` : null,
]
  .filter(Boolean)
  .join(' ');

console.log(
  `Screenshots coverage${filterLabel ? ` (${filterLabel})` : ''}: ${foundCount}/${expectedCount} (${coverage}%)`,
);

if (missing.length > 0) {
  console.log('\nMissing files:');
  for (const file of missing) {
    console.log(`- ${file}`);
  }
  if (!allowMissing) {
    process.exit(1);
  }
  console.log('\n(--allow-missing set; not exiting non-zero.)');
  process.exit(0);
}

console.log('\nAll required screenshots are present.');
