---
id: 0154
title: "2026-06-08 — QA pass (macOS app, pre-TestFlight)"
status: done
tags: [macos, qa, code-review-backlog]
files: []
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

# 2026-06-08 — QA pass (macOS app, pre-TestFlight)

_Closed by the 2026-06-13 backlog resolution pass (`CODE_REVIEW_BACKLOG.md` → "No open code defects remain": every code-defect item was fixed, built, tested and committed in passes 1-6). Re-open if this finding is still reproducible._


Scope: native macOS app `apps/macos/TodusMac`. Build = clean `xcodebuild` (Debug, macOS, arch=arm64) — **BUILD SUCCEEDED** before and after fixes. 3 parallel sub-agents by surface (launch/auth/root, email, calendar/tasks/docs/AI); every finding re-verified against source before any edit. App launched in-app for runtime validation (auth gate, light/dark). No automated UI auth path exists on macOS, so logged-in flows were validated by code trace + a real persisted session where available.
