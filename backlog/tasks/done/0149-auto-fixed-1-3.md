---
id: 0149
title: "Auto-fixed (1)"
status: done
tags: [bug-hunt, code-review-backlog]
files: []
created: 2026-06-01
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-01 — Bug hunt (uncommitted + last 3 commits)

## Auto-fixed (1)

| File:line | Severity | What changed |
|-----------|----------|--------------|
| `apps/web/components/mail/reply-composer.tsx:92-101` | ⚠️ high (build) | Added `fromEmail?: string;` to the `handleSendEmail` `data` param type. The body reads `data.fromEmail` (lines 111/113) to honor the composer's From picker, but the inline param type omitted the field → `TS2339 Property 'fromEmail' does not exist`. Caller (`EmailComposer.onSendEmail`) already passes it, so this was a pure type gap, not a logic change. |
