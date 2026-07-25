---
id: 0275
title: "DONE Apple Reminders brand icon (2026-04): AppleRemindersLogo on iOS + macOS now uses Canvas with th"
status: done
tags: [task-md, sprint]
files: []
created: unknown
source: TASK.md
---

> Source context: TASK.md → macOS UI

- `DONE` **Apple Reminders brand icon (2026-04):** `AppleRemindersLogo` on iOS + macOS now uses `Canvas` with the official 1024×1024 Reminders light geometry (grey bars + blue/red/orange rings with white centers); macOS `AppIconContainer` matches iOS fixed inner `width`+`height` and `clipShape` so artwork never overflows the white rounded square. All call sites use `AppleRemindersIconView` only (onboarding, Settings, Tasks connect).
