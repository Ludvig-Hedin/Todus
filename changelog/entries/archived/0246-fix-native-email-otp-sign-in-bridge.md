---
id: 0246
title: "Fix — Native Email OTP sign-in bridge"
status: archived
category: Fixed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Fix — Native Email OTP sign-in bridge

- [Fix] **Backend:** Added `POST /api/auth/native-email-otp/verify` for iOS/macOS. It validates the existing Better Auth `sign-in` OTP record, creates a native session token, and returns structured JSON errors instead of the opaque empty-body 500 seen from `/api/auth/sign-in/email-otp`.
- [Fix] **Backend:** The native OTP bridge now selects only core auth columns from `mail0_user`, so production logins do not fail if newer app-only user columns have not been migrated yet.
- [Fix] **iOS + macOS:** Shared native `AuthService` now verifies email OTP against the native bridge and captures the returned session ID alongside the raw session token.
- **Files:** `apps/server/src/main.ts`, `packages/swift-auth/Sources/TodusAuth/AuthService.swift`
