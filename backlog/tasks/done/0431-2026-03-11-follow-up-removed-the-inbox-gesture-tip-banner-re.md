---
id: 0431
title: "2026-03-11 follow-up: removed the inbox gesture tip banner, replaced the inbox compose + with a penc"
status: done
tags: [task-md, sprint]
files: [apps/ios/app/(app)/(mail)/[folder].tsx, apps/ios/src/shared/theme/ThemeContext.tsx, apps/ios/src/features/mail/SenderAvatar.tsx]
created: 2026-03-01
source: TASK.md
---

> Source context: TASK.md → Session Notes (2026-03-01)

- 2026-03-11 follow-up: removed the inbox gesture tip banner, replaced the inbox compose `+` with a pencil icon, neutralized the remaining blue/slate tint in the native mail surface tokens, and switched sender avatar fallbacks to domain-logo lookups with `fallback=false` so missing logos drop to initials instead of the generic person placeholder. User-facing change in `apps/ios/app/(app)/(mail)/[folder].tsx`, `apps/ios/src/shared/theme/ThemeContext.tsx`, and `apps/ios/src/features/mail/SenderAvatar.tsx`.
