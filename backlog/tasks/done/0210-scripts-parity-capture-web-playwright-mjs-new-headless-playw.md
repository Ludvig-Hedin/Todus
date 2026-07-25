---
id: 0210
title: "scripts/parity/capture-web-playwright.mjs (new): headless Playwright capture using the install vendo"
status: done
tags: [task-md, sprint]
files: [scripts/parity/capture-web-playwright.mjs, packages/testing/e2e/auth.setup.ts]
created: 2026-05-24
source: TASK.md
---

> Source context: TASK.md → Task 16 — Design System screenshot regression suite (2026-05-24) — IN PROGRESS (infra DONE)

- `scripts/parity/capture-web-playwright.mjs` (new): headless Playwright capture using the install vendored at `packages/testing` (no new dep). Injects Better-Auth cookies from `PLAYWRIGHT_SESSION_TOKEN` / `PLAYWRIGHT_SESSION_DATA` (same pattern as `packages/testing/e2e/auth.setup.ts`). Detects redirects for gated screens and refuses to overwrite the baseline with the redirect target. Full-page screenshot is the default for `surface: design-system` (the DS page scrolls past one viewport). Wired into `pnpm parity:screenshots:capture:web`.
