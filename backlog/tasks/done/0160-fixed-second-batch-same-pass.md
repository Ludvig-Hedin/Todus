---
id: 0160
title: "Fixed — second batch (same pass)"
status: done
tags: [code-review-backlog]
files: [bimi-avatar.tsx, lib/sender-avatar.ts, trpc/routes/avatar.ts]
created: 2026-06-13
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Backlog resolution pass — 2026-06-13 (whole-repo)

## Fixed — second batch (same pass)

- **Web B-014 (privacy)** — `bimi-avatar.tsx` now gates ALL third-party favicon fetches (local builder AND the backend `fallbackUrls`, which also carry clearbit/icon.horse/DDG/Gravatar URLs the browser fetches) behind the existing `externalImages` setting; keeps own Google contact photo + inlined sanitized BIMI SVG.
- **Server B-015 (privacy)** — `lib/sender-avatar.ts` short-circuits before any anonymous third-party request when `externalImages` is off; `trpc/routes/avatar.ts` loads + passes the setting. (KV cache still deferred — no general-purpose KV binding; `// TODO(B-015)` left.)
- **Web B-040** — tasks placeholder de-bilingualized to neutral English.
- **iOS EM-8** — Copy message text / Copy as quote now copy the full `message.body` rendered to plain text (new `htmlToPlainText`), not the snippet.
- **iOS B-037** — stale-refresh log now includes dropped/kept counts (telemetry); strict `<` kept.
- **iOS B-034** — documented the intentional `hideTabBar` asymmetry (MainTabView resets per tab switch).
- **macOS QA-0608-2** — per-message reply/forward quotes the clicked message (`selectedComposeMessage`), not always the latest.
- **macOS QA-0608-4** — partial-enrichment failures no longer shrink the folder cache (`EnrichmentResult` + `mergeSurvivors`).
- **macOS MAC-3** — `loadThreads` cache/live/spinner/error gated by a monotonic `loadGeneration` token.
