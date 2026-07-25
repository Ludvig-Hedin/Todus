---
id: 0073
title: "Needs attention (not auto-fixed)"
status: open
priority: P3
tags: [ios, bug-hunt, code-review-backlog]
files: []
created: 2026-06-01
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-01 — Bug hunt (iOS screenshots: bg color / alignment / thread-load)

> Section overview — the individual findings from this section are separate items.

## Needs attention (not auto-fixed)

> Cleared false positives (verified NOT bugs): (1) `EmailInboxView.swift:858` People unread-count badge uses `Color(UIColor.systemBlue)` — a color sub-agent suggested `AppTheme.accentBlue`, but `EmailRowView.swift:57` shows the inbox unread dot was **deliberately** moved off `accentBlue` (= `Color.primary` = black, invisible) to `systemBlue`; both use systemBlue → already consistent. (2) `AvatarCache.bootstrap()` IS wired (`RootView.swift:139`) — the deferred-disk-hydration refactor is safe. (3) People view DOES refresh on new mail (`.onChange(of: emailService.threads)` → `recomputeFilteredThreads` → `recomputeSenderGroupsIfPeopleMode`, `EmailInboxView.swift:337`). (4) Backend `mail.send` accepts the new `headers`/`isForward`/`originalMessage` (`apps/server/src/trpc/routes/mail.ts:857-864`) — the reply-threading + forward changes won't break sends.

---
