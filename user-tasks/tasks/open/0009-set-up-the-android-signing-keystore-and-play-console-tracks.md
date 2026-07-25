---
id: 0009
title: "Set up the Android signing keystore and Play Console tracks"
status: open
priority: P3
area: apps
source: "TASK.md — Manual Inputs Required"
created: 2026-07-25
---

Listed as required manual input. Note that Android is not one of the four active apps in `APPS_ARCHITECTURE.md` — the root `bun android` script still exists, but there is no maintained Android client in `apps/`.

- [ ] Decide whether Android is still in scope at all
- [ ] If yes: create the signing keystore, store it outside the repo, and set up the Play Console tracks
- [ ] If no: close this task and remove the `android` script from the root `package.json` (that removal is a code change — file it in `backlog/`)
