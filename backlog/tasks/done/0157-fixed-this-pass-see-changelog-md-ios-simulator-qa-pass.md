---
id: 0157
title: "✅ Fixed this pass (see `CHANGELOG.md` → \"iOS Simulator QA pass\")"
status: done
tags: [ios, qa, code-review-backlog]
files: []
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-08 — iOS Simulator QA pass

## ✅ Fixed this pass (see `CHANGELOG.md` → "iOS Simulator QA pass")

- **Round 1** (committed `e2ee191f`): silent capture-failure banner, multi-recipient email entry, Tasks empty-state copy, Home section-icon a11y, GroupChat clobber guard.
- **Round 2**: IOS-0608-1 (offline capture no longer deleted — `URLError`/`backendNotConfigured` keep `.localOnly`, re-sync on reconnect), IOS-0608-3 (optimistic star + rollback), IOS-0608-4 (AI tab context seeded from restored tab), IOS-0608-5 (More-tab dark background `#1c1c1e`), IOS-0608-6 (share-sheet foreground-active scene, both call sites), IOS-0608-8 (CreateSheet To/Cc/Bcc placeholders no longer blue). **Email perf**: cached date formatters (`EmailModels.parseDate`, `EmailThreadView` receipt chip), **security**: email-HTML CSP gained `form-action 'none'; base-uri 'none'`. **Tests added**: `EmailServiceTests` (toggleStar optimistic/rollback + `parseDate` formats), `SupabaseSyncServiceTests` (offline/unconfigured keep-local vs reject-fail).
