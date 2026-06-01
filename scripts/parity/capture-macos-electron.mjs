#!/usr/bin/env node

/**
 * macOS screenshot capture for the **native** SwiftUI shell at
 * `apps/macos/TodusMac` (the Electron wrapper this script originally targeted
 * is retired — see `apps/macos/README.md`).
 *
 * Strategy:
 *   1. Build + launch the native app via `xcodebuild` (`TodusMac` scheme,
 *      `platform=macOS`) if it isn't already running, OR rely on the app
 *      being already open (faster on iteration).
 *   2. For each screen in the manifest:
 *      - If `macosNavigation` is set, the script logs the manual nav steps
 *        and (when --interactive) waits for the user to press Enter.
 *      - Otherwise the script captures the frontmost window via
 *        `screencapture -o -l <windowId>` (no shadow, just the window).
 *   3. Write to `parity_screenshots/<Slug>__macos.png`.
 *
 * The native app does NOT support cross-screen deep linking yet, so the
 * deterministic `--auto` path only works for surfaces the app launches
 * directly into. For the Design System sheet specifically, the test runs
 * with `--surface design-system` and uses AppleScript to walk
 * Settings → Developer → Design System (allowlisted account required).
 *
 * Env vars
 *   PARITY_MACOS_APP_PATH    Path to built TodusMac.app. If unset, the script
 *                            invokes `xcodebuild` to build into derived data
 *                            and resolves the binary from there.
 *   PARITY_MACOS_DELAY_MS    Pause between nav step and capture (default 1500)
 *
 * CLI
 *   --surface <name>         Filter manifest screens
 *   --interactive            Pause before each capture so user can stage the UI
 *   --skip-build             Don't run xcodebuild; assume app is already
 *                            installed/launched
 */

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

const args = process.argv.slice(2);
function flag(name) {
  const idx = args.indexOf(name);
  if (idx === -1) return undefined;
  return args[idx + 1];
}
const surfaceFilter = flag('--surface');
const interactive = args.includes('--interactive');
const skipBuild = args.includes('--skip-build');

const delayMs = Number(process.env.PARITY_MACOS_DELAY_MS ?? 1500);

const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const screens = (manifest.screens ?? []).filter((s) =>
  surfaceFilter ? s.surface === surfaceFilter : true,
);

if (screens.length === 0) {
  console.log(`No screens match filter (surface=${surfaceFilter ?? '*'}).`);
  process.exit(0);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function run(cmd, argv, options = {}) {
  return spawnSync(cmd, argv, { encoding: 'utf8', ...options });
}

// ----- build / launch -----

if (!skipBuild) {
  console.log('Building TodusMac (this is a no-op if up to date)…');
  const build = run(
    'xcodebuild',
    [
      '-project',
      'apps/macos/TodusMac.xcodeproj',
      '-scheme',
      'TodusMac',
      '-destination',
      'platform=macOS',
      '-configuration',
      'Debug',
      'build',
    ],
    { cwd: rootDir, stdio: 'inherit' },
  );
  if (build.status !== 0) {
    console.error('xcodebuild failed. Re-run with --skip-build if you have a working build.');
    process.exit(1);
  }
}

// Resolve TodusMac.app path so we can `open` it.
let appPath = process.env.PARITY_MACOS_APP_PATH;
if (!appPath) {
  const settings = run('xcodebuild', [
    '-project',
    'apps/macos/TodusMac.xcodeproj',
    '-scheme',
    'TodusMac',
    '-showBuildSettings',
    '-configuration',
    'Debug',
    '-json',
  ]);
  if (settings.status === 0) {
    try {
      const parsed = JSON.parse(settings.stdout);
      const built = parsed.find?.((entry) => entry.buildSettings?.BUILT_PRODUCTS_DIR);
      const productsDir = built?.buildSettings?.BUILT_PRODUCTS_DIR;
      if (productsDir) {
        appPath = path.join(productsDir, 'TodusMac.app');
      }
    } catch {
      // fall through; we'll error below
    }
  }
}

if (!appPath || !fs.existsSync(appPath)) {
  console.error(
    'Could not resolve TodusMac.app path. Set PARITY_MACOS_APP_PATH to the built .app, ' +
      'or build the app once in Xcode first.',
  );
  process.exit(1);
}

console.log(`Using app: ${appPath}`);
run('open', [appPath]);
await sleep(2000);

// ----- per-screen capture -----

let captured = 0;
let skipped = 0;
const failures = [];

// AppleScript to find the frontmost TodusMac window id (works for the main
// window AND for the Settings sheet — both belong to the same app process).
const FRONT_WINDOW_AS = `
tell application "System Events"
  tell process "TodusMac"
    set frontmost to true
    delay 0.3
    if (count of windows) = 0 then return ""
    set winId to id of front window
    return winId as string
  end tell
end tell
`;

function frontWindowId() {
  const res = run('osascript', ['-e', FRONT_WINDOW_AS]);
  if (res.status !== 0) return undefined;
  const id = res.stdout.trim();
  return id || undefined;
}

async function captureSlug(slug) {
  const target = path.join(parityDir, `${slug}__macos.png`);
  await sleep(delayMs);

  const winId = frontWindowId();
  if (winId) {
    const cap = run('screencapture', ['-o', '-x', '-l', winId, target]);
    if (cap.status === 0 && fs.existsSync(target)) return true;
  }

  // Fallback: capture main display
  const fallback = run('screencapture', ['-o', '-x', target]);
  return fallback.status === 0 && fs.existsSync(target);
}

async function promptContinue(message) {
  if (!interactive) return;
  process.stdout.write(`${message}\n  press Enter to capture > `);
  await new Promise((resolve) => {
    process.stdin.resume();
    process.stdin.once('data', () => {
      process.stdin.pause();
      resolve();
    });
  });
}

for (const screen of screens) {
  if (screen.macosNavigation) {
    console.log(`\n[${screen.slug}] manual nav required: ${screen.macosNavigation}`);
  } else {
    console.log(`\n[${screen.slug}] capturing front window`);
  }

  await promptContinue('Stage the UI on screen.');

  const ok = await captureSlug(screen.slug);
  if (ok) {
    captured += 1;
    console.log(`  -> ${screen.slug}__macos.png`);
  } else {
    skipped += 1;
    failures.push(`${screen.slug}: capture failed`);
  }
}

console.log(`\nDone. Captured: ${captured}. Skipped: ${skipped}.`);
if (failures.length > 0) {
  console.log('\nNotes:');
  failures.forEach((failure) => console.log(`- ${failure}`));
}
