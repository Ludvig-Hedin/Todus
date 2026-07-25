---
id: 0095
title: "apps/server/src/main.ts:1010 — send-email-queue catch deletes statusKV + payloadKV after a send failure withou"
status: open
priority: P1
tags: [code-review, code-review-backlog]
files: []
created: 2026-05-27
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-27 — Multi-skill review of cross-platform local diff → Needs human review (5)

| File:line | Severity | Problem | Suggested fix |
|-----------|----------|---------|---------------|
| `apps/server/src/main.ts:1010` | 🔴 critical | `send-email-queue` catch deletes `statusKV` + `payloadKV` after a send failure without rethrowing. Cloudflare Queues then acks the message and the payload is gone — a transient error (network blip, Gmail rate limit, DO hiccup) silently drops a scheduled email the user thinks was sent. | Distinguish permanent vs transient errors; rethrow on transient so the queue retries, only delete on a final / non-retryable failure. |
