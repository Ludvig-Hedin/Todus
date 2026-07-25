---
id: 0041
title: "Needs attention (not auto-fixed — verified real, deferred as higher-risk/product calls)"
status: open
priority: P4
tags: [macos, qa, code-review-backlog]
files: []
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-08 — QA pass (macOS app, pre-TestFlight)

> Section overview — the individual findings from this section are separate items.

## Needs attention (not auto-fixed — verified real, deferred as higher-risk/product calls)

> Cleared as NOT bugs (verified): smart-sort buckets agree on overdue/today + handle empty input; local-model picker gates on `runtime.isReady` (no silent hang); `processToolCalls` is dead code (live path `executeSingleToolCall` has cancellation gates before every side effect incl. `send_email`); GroupChat polling calls `stopPolling()` first (no double-timer); `ModelContainer` init has a 3-tier fallback + recoverable error UI (no blank window); deep-link handlers reject malformed/unknown hosts; no force-unwrap/`try!`/`as!` crash on the launch/onboarding path; compose double-send guarded by `isSending`/`isSendingAttachments`; pagination dedupes by id. The `HuggingFaceCacheConnector.swift:227` non-atomic-symlink TODO is pre-existing (tracked as BH-0605-2).

---
