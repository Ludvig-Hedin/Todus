---
id: 0320
title: "Fixed — cross-platform performance and reliability pass"
status: unreleased
category: Fixed
release_date: 2026-07-22
source: CHANGELOG.md
---

### Fixed — cross-platform performance and reliability pass, 2026-07-22

- **Web:** lazy-loads the AI sidebar, removes the full icon registry from mail rows, replaces 47 MB of onboarding GIFs with 4.7 MB of MP4 assets rendered one step at a time, and fixes an invalid minified CodeMirror selection selector. Failed mail-list and thread loads now show a retry state instead of an empty inbox or endless skeleton.
- **Write safety:** non-idempotent TanStack mutations no longer retry globally, Gmail webhook/queue failures are retried instead of acknowledged, and scheduled-email KV retention now covers the requested send time.
- **iOS:** transient HTTP, rate-limit, server, and malformed-response failures keep captured tasks locally for retry; only explicit semantic 4xx rejections can mark a capture failed.
- **macOS:** task/folder offline queues now survive termination, partial acknowledgements preserve remaining work, and each account opens an isolated local store and mutation journal before rendering or syncing. Guest mode uses its own store; the ownerless legacy store is retained but never opened, assigned, or deleted. Slow store activation revalidates the live account before installation.
- **Native auth:** native local storage now binds to the verified backend user ID. A new sign-in clears cached profile identity before validating the callback, so missing provider metadata cannot inherit the previous account's scope.
- **Public routes:** anonymous Autumn customer bootstrap is treated as an empty billing state, removing the expected-but-noisy 401 on logged-out pages while billing mutations remain protected.
- Audit and verification evidence: `docs/audits/performance-reliability-audit-2026-07-22.md` and `qa-reports/qa-report-localhost-2026-07-22.md`.
