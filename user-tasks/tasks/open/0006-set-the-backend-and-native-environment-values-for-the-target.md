---
id: 0006
title: "Set the backend and native environment values for the target deploy"
status: open
priority: P1
area: infra
source: "MANUAL_INPUTS_GUIDE.md §2 checklist (unchecked)"
created: 2026-07-25
---

Two unchecked checklist lines: "Better Auth and server env values updated" and "native env values set for local/internal builds".

- [ ] Set the Better Auth + provider secrets on the server deploy environment (`apps/server/wrangler.jsonc` bindings / Cloudflare secrets — never commit them)
- [ ] Set the backend URL the native apps point at for the build you are producing
- [ ] Confirm `VITE_PUBLIC_BACKEND_URL` is set for the `@zero/web` deploy
- [ ] Record which environment each value was set in (production vs staging) — a value set in the wrong project reads as "done" but is not
