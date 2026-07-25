---
id: 0145
title: "Investigated, not bugs (false positives from re-review pass)"
status: done
tags: [code-review, code-review-backlog]
files: [apps/web/hooks/use-settings.ts]
created: 2026-05-27
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-27 — Multi-skill review of cross-platform local diff

## Investigated, not bugs (false positives from re-review pass)

- `apps/web/app/(routes)/settings/notifications/page.tsx:17` — `claude-review` warned that `useSettings` may not write to `trpc.settings.get`. Verified in `apps/web/hooks/use-settings.ts`: `useSettings` is `useQuery(trpc.settings.get.queryOptions(...))`, same key. Optimistic write lands on the right cache.
- `apps/macos/TodusMac/Views/Settings/MacLocalModelsView.swift:205` — A curated MLX model the user downloaded in-app could appear in both Installed and Connected (HuggingFace). Confirmed acceptable: Installed shows the curated catalog entry with full controls, HF section shows raw on-disk entries; product team to decide whether to dedupe (architectural).

---
