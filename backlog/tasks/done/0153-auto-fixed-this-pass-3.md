---
id: 0153
title: "Auto-fixed this pass (3)"
status: done
tags: [ios, bug-hunt, code-review-backlog]
files: []
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Bug Hunt — 2026-06-08 — iOS email surface (`/bug-hunt`)

## Auto-fixed this pass (3)

| File:line | Severity | What changed |
|-----------|----------|--------------|
| `Features/Email/EmailThreadView.swift:126` + `EmailComposeView.swift:113` | 🔴 **critical (data loss)** | **Forward sent only the snippet.** Forward passed `lastMessage.plainText` — which decodes from the `title`/snippet field (`EmailModels.swift:85`), not the body — so forwarding silently truncated the email to a one-line preview. Added `isForward`/`originalMessage` params to the compose init and route Forward through them with the **full** `lastMessage.body`; the backend appends it (`google.ts:1236`). Verified end-to-end against the server handler. |
| `Services/Email/EmailService.swift:309,394-410` (`performLoadThreads`) | 🟠 high | **Superseded-load state race.** The `defer` gen-gated only the spinner; the `threads`/`errorMessage`/`hasConnection` writes were ungated, so a slow superseded load could paint a stale error banner over a newer successful inbox. Added `guard loadGeneration == myGen else { return }` before state application and gated every `catch` write on `myGen`. |
| `Services/Email/EmailService.swift:1548` (`invalidateThreadDetail`) | 🟡 med | **Stale thread detail after list mutation.** `markAsRead`/`markAsUnread`/`toggleStar` updated `threads` but not `threadDetailCache`, so opening a just-read/just-starred thread showed the pre-mutation state until the cache TTL expired. Added a shared `invalidateThreadDetail(ids:)` and call it from those mutations. |
