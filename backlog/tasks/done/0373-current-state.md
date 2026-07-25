---
id: 0373
title: "Current State"
status: done
tags: [task-md, sprint]
files: []
created: 2026-05-17
source: TASK.md
---

> Source context: TASK.md

> Section overview — individual items from this section are separate files.

## Current State

The old M1-M7 milestones represent the historical WebView-shell phase and are complete.

The active goal is a **truly native iOS app in `apps/ios`** that reaches feature + behavior parity with `apps/mail` while using native navigation/layout patterns.

As of **2026-05-17**, `apps/macos/TodusMac` has also had a comprehensive hardening + iOS parity pass (Email compose/thread, Calendar in-app editing, Notifications categories/actions/routing, Tasks recurrence/checklist/attachments, cross-entity Search, Share deep link). Full integration `xcodebuild` for the macOS target is green. See `## macOS hardening + parity sweep (DONE) (2026-05-17)` above and the parity matrix in `PARITY_CHECKLIST.md` section 7.

Auth/login is currently owned by another agent stream and is excluded from this stream unless explicitly reassigned.
