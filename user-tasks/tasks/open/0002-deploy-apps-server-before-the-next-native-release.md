---
id: 0002
title: "Deploy apps/server before the next native release"
status: open
priority: P0
area: ops
source: "TASK.md — 2026-07-08 iOS follow-up; CODE_REVIEW_BACKLOG.md — operator prerequisites"
created: 2026-07-25
---

Several shipped client behaviours only work once the current backend is live. Until the deploy happens the iOS/macOS builds silently fall back to the old server behaviour.

Waiting on this deploy:

- `mail.send` `clientSendId` idempotency key — until deployed, zod strips the unknown key and retries can double-send
- second-brain memory tool limit normalisation on `POST /api/ai/do/*`
- every server change from the 2026-06-13 review passes 1–4

- [ ] `bun deploy:backend` (from the repo root, with Cloudflare auth for the account that owns the Worker)
- [ ] Confirm the deploy in the Cloudflare dashboard (Workers → deployment timestamp)
- [ ] Smoke-test a send from iOS and confirm no duplicate arrives on retry

Deploy the server **before** shipping a native build, not after.
