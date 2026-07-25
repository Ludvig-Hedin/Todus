---
id: 0132
title: "Auto-fixed (2)"
status: done
tags: [macos, bug-hunt, code-review-backlog]
files: []
created: 2026-05-20
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-20 — Bug Hunt: macOS app main user flows

## Auto-fixed (2)

| File:line | Severity | What changed |
|-----------|----------|--------------|
| `apps/macos/TodusMac/Views/Email/MacEmailComposeView.swift:380` | error | Reply All never auto-expanded Cc/Bcc when `draft.cc` was empty. The branch `if cc.isEmpty && nav != "Reply All" {} else if !cc.isEmpty { show }` had an empty if-body, so the `navigationTitle == "Reply All"` check was dead. Replaced with `if navigationTitle == "Reply All" || !draft.cc.isEmpty { showCcBcc = true }`. |
| `apps/macos/TodusMac/App/MacOnboardingViews.swift:200` | error | Reminders onboarding treated `.writeOnly` as denied, but `MacAppServices.requestRemindersPermissionIfNeeded()` (line 736) accepts `.writeOnly` as authorized. Users granting write-only access saw "Permission was not granted" while underlying sync would have worked. Moved `.writeOnly` into the authorized branch. |
