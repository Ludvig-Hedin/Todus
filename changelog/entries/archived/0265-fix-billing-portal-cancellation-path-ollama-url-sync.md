---
id: 0265
title: "Fix — billing portal cancellation path + Ollama URL sync"
status: archived
category: Fixed
release_date: 2026-04-26
source: CHANGELOG.md
---

## [2026-04-26] Fix — billing portal cancellation path + Ollama URL sync

- [Fix] **Web + mail billing settings no longer guess the Pro SKU when canceling.** Paid users now open the hosted billing portal for cancellation and billing management, which works for both monthly and annual Pro without relying on normalized `plan === 'pro'` state.
- [Fix] **Billing plan copy now matches the current product surface.** The shared web/mail settings pages only advertise the active `free` and `pro` tiers.
- [Fix] **Saved Ollama endpoints load correctly in settings.** The AI settings URL input now resyncs from async user settings after load, so existing custom `ollamaBaseUrl` values are shown instead of the localhost fallback and are not accidentally overwritten on save.
- [Files] `apps/web/app/(routes)/settings/billing/page.tsx`, `apps/mail/app/(routes)/settings/billing/page.tsx`, `apps/web/app/(routes)/settings/ai/page.tsx`, `apps/mail/app/(routes)/settings/ai/page.tsx`, `CHANGELOG.md`
