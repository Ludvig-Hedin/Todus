---
id: 0308
title: "DONE Native Email OTP sign-in bridge: iOS/macOS now verify OTP codes through /api/auth/native-email"
status: done
tags: [task-md, sprint]
files: []
created: unknown
source: TASK.md
---

> Source context: TASK.md → Current Web/Server Fix Batch

- `DONE` Native Email OTP sign-in bridge: iOS/macOS now verify OTP codes through `/api/auth/native-email-otp/verify`, which validates the existing Better Auth OTP record, creates a raw native session token, and returns structured JSON so the shared native auth service can complete the existing refresh-token flow without hitting the opaque Better Auth 500. Follow-up: the bridge selects only core auth columns from `mail0_user` so production does not require newer app-only user columns to exist before login works.
