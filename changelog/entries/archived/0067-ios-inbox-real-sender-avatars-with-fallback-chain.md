---
id: 0067
title: "iOS Inbox — Real Sender Avatars with Fallback Chain"
status: archived
category: Changed
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] iOS Inbox — Real Sender Avatars with Fallback Chain

### Feature

- **`SenderAvatarView`**: New SwiftUI component that resolves real sender avatars via the existing backend `avatar.getByEmail` tRPC endpoint (Google People API → domain favicon → fallbacks → initials).
- **`AvatarCache`**: `@Observable` singleton that deduplicates in-flight requests and caches results for the session. Views re-render automatically when a cache entry arrives.
- **Waterfall fallback**: `AsyncImage` tries URLs in priority order; advances to next on load failure, ending at initials + deterministic color circle if all fail.
- **Subdomain handling**: Handled by the backend — `auth.supabase.com` resolves to the Supabase root-domain logo.

### Files

- `apps/ios/Todus/Todus/Features/Email/SenderAvatarView.swift` (**new** — add to Xcode project)
- `apps/ios/Todus/Todus/Features/Email/EmailRowView.swift` — replaced inline initials avatar with `SenderAvatarView`
