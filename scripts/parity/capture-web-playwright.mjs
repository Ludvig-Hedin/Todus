#!/usr/bin/env node

/**
 * Web screenshot capture for parity baselines.
 *
 * Uses the Playwright install already vendored at `packages/testing` — no new
 * dependency added at the root. Run from repo root:
 *
 *   bun parity:screenshots:capture:web
 *
 * Env vars
 *   PARITY_WEB_BASE_URL          Base URL of running app. Default http://localhost:3000
 *   PARITY_WEB_VIEWPORT_WIDTH    Default 1440
 *   PARITY_WEB_VIEWPORT_HEIGHT   Default 900
 *   PARITY_WEB_SETTLE_MS         Wait after navigation (default 1500)
 *   PARITY_WEB_FULL_PAGE         "1" to capture full-page (default for surface=design-system)
 *
 * Auth (the Design System page is allowlisted; without a session you'll be
 * redirected away). Reuses the existing pattern in
 * `packages/testing/e2e/auth.setup.ts`:
 *
 *   PLAYWRIGHT_SESSION_TOKEN     Better-Auth session token cookie value
 *   PLAYWRIGHT_SESSION_DATA      Better-Auth session data cookie value (b64)
 *
 * If those are unset, the script still runs but captures the public surfaces
 * only and logs a warning for gated screens.
 *
 * CLI
 *   --surface <name>             Filter manifest to one surface
 *   --slug <name>                Filter to a single slug
 *   --full-page                  Force full-page screenshot for all screens
 */

import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const rootDir = process.cwd();
const parityDir = path.join(rootDir, 'parity_screenshots');
const manifestPath = path.join(parityDir, 'manifest.json');

if (!fs.existsSync(manifestPath)) {
  console.error('Missing parity_screenshots/manifest.json');
  process.exit(1);
}

// Resolve Playwright from the testing package so we don't need a root dep.
const require = createRequire(
  path.join(rootDir, 'packages/testing/package.json'),
);
let chromium;
try {
  ({ chromium } = require('@playwright/test'));
} catch (err) {
  console.error(
    'Failed to load @playwright/test from packages/testing. Run `bun install` first.',
  );
  console.error(String(err));
  process.exit(1);
}

const args = process.argv.slice(2);
function flag(name) {
  const idx = args.indexOf(name);
  if (idx === -1) return undefined;
  return args[idx + 1];
}
const surfaceFilter = flag('--surface');
const slugFilter = flag('--slug');
const forceFullPage = args.includes('--full-page');

const baseUrl = (process.env.PARITY_WEB_BASE_URL ?? 'http://localhost:3000').replace(/\/$/, '');
const viewportWidth = Number(process.env.PARITY_WEB_VIEWPORT_WIDTH ?? 1440);
const viewportHeight = Number(process.env.PARITY_WEB_VIEWPORT_HEIGHT ?? 900);
const settleMs = Number(process.env.PARITY_WEB_SETTLE_MS ?? 1500);

const sessionToken = process.env.PLAYWRIGHT_SESSION_TOKEN;
const sessionData = process.env.PLAYWRIGHT_SESSION_DATA;
const hasAuth = Boolean(sessionToken && sessionData);

const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
let screens = manifest.screens ?? [];
if (surfaceFilter) screens = screens.filter((s) => s.surface === surfaceFilter);
if (slugFilter) screens = screens.filter((s) => s.slug === slugFilter);

if (screens.length === 0) {
  console.log('No screens match filter.');
  process.exit(0);
}

function resolveRoute(rawRoute) {
  if (!rawRoute) return '/';
  return rawRoute
    .replace('<sample>', 'sample')
    // Preserve fragments; the browser navigates to them and we scroll to the
    // target element explicitly (see scroll-into-view logic below).
    ;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

const cookieDomain = new URL(baseUrl).hostname;

async function main() {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: viewportWidth, height: viewportHeight },
    deviceScaleFactor: 2,
  });

  if (hasAuth) {
    await context.addCookies([
      {
        name: 'better-auth-dev.session_token',
        value: sessionToken,
        domain: cookieDomain,
        path: '/',
        httpOnly: true,
        secure: cookieDomain !== 'localhost',
        sameSite: 'Lax',
      },
      {
        name: 'better-auth-dev.session_data',
        value: sessionData,
        domain: cookieDomain,
        path: '/',
        httpOnly: true,
        secure: cookieDomain !== 'localhost',
        sameSite: 'Lax',
      },
    ]);
    console.log(`Auth cookies injected for ${cookieDomain}.`);
  } else {
    console.warn(
      'PLAYWRIGHT_SESSION_TOKEN / PLAYWRIGHT_SESSION_DATA unset. ' +
        'Gated screens (Settings, Design System, Mail*) will not render correctly.',
    );
  }

  const page = await context.newPage();

  let captured = 0;
  let skipped = 0;
  const failures = [];

  for (const screen of screens) {
    if (screen.gated && !hasAuth) {
      skipped += 1;
      failures.push(`${screen.slug}: gated, no auth session injected`);
      continue;
    }

    const route = resolveRoute(screen.webRoute);
    const url = `${baseUrl}${route.startsWith('/') ? route : `/${route}`}`;
    const target = path.join(parityDir, `${screen.slug}__web.png`);

    try {
      await page.goto(url, { waitUntil: 'networkidle', timeout: 30_000 });
    } catch {
      // networkidle can time out on long-lived connections; fall back to dom.
      try {
        await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30_000 });
      } catch (err2) {
        skipped += 1;
        failures.push(`${screen.slug}: navigation failed (${(err2 && err2.message) || err2})`);
        continue;
      }
    }

    // If the loader redirected (e.g. allowlist check), record that as a skip
    // for gated surfaces so we don't silently overwrite the baseline with the
    // redirect target.
    const finalUrl = page.url();
    if (
      screen.gated &&
      !finalUrl.includes(screen.webRoute?.split('#')[0] ?? screen.webRoute ?? '')
    ) {
      skipped += 1;
      failures.push(
        `${screen.slug}: redirected to ${finalUrl} (allowlist did not match the signed-in account)`,
      );
      continue;
    }

    // For DS sections that use a hash fragment, scroll the section into view.
    const hashIdx = (screen.webRoute ?? '').indexOf('#');
    if (hashIdx !== -1) {
      const id = (screen.webRoute ?? '').slice(hashIdx + 1);
      try {
        await page.evaluate((targetId) => {
          const el = document.getElementById(targetId);
          if (el) el.scrollIntoView({ behavior: 'instant', block: 'start' });
        }, id);
      } catch {
        // best effort — fall back to full page anyway
      }
    }

    await sleep(settleMs);

    const fullPage = forceFullPage || screen.surface === 'design-system';
    try {
      await page.screenshot({ path: target, fullPage });
      captured += 1;
      console.log(`Captured ${screen.slug} -> ${path.basename(target)}`);
    } catch (err) {
      skipped += 1;
      failures.push(`${screen.slug}: screenshot failed (${(err && err.message) || err})`);
    }
  }

  await browser.close();

  console.log(`\nDone. Captured: ${captured}. Skipped: ${skipped}.`);
  if (failures.length > 0) {
    console.log('\nNotes:');
    failures.forEach((failure) => console.log(`- ${failure}`));
  }

  if (failures.length > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
