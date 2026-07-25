---
id: 0003
title: "iOS/Mac Wrapper and Todus Branding Updates"
status: archived
category: Changed
release_date: 2026-02-21
source: CHANGELOG.md
---

## [2026-02-21] iOS/Mac Wrapper and Todus Branding Updates

### Added

- Added `/docs/terminal-commands.md` with end-to-end startup/build/deploy commands
- Added `/docs/share-asap.md` with fastest distribution path for friends (web + TestFlight)

### Changed

- iOS wrapper now keeps HTTP/HTTPS navigation in-app and starts at `/mail/inbox`
- iOS wrapper now uses safe area/inset behavior to reduce clipped content at top/bottom
- Added env-driven app name support:
  - `VITE_PUBLIC_APP_NAME` (web branding)
  - `EXPO_PUBLIC_APP_NAME` (iOS/macOS wrapper title/loading text)
- Updated visible branding on login/onboarding/navigation/footer/manifest from Zero to Todus in key user-facing surfaces

### Notes

- OAuth browser handoff can still happen depending on Google provider behavior; this is not Supabase-specific in this stack
