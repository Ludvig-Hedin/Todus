---
id: 0246
title: "DONE 2026-04-29 review follow-up for mail pagination + NLP regressions: shard mail pagination now us"
status: done
tags: [task-md, sprint]
files: []
created: 2026-04-29
source: TASK.md
---

> Source context: TASK.md → Current Review Fixes

- `DONE` **2026-04-29 review follow-up for mail pagination + NLP regressions:** shard mail pagination now uses a composite `(latestReceivedOn, id)` cursor end-to-end instead of a timestamp-only boundary, web task quick-add no longer treats bare trailing numbers as times without a date marker, and the iOS/macOS compound-intent splitters now only break on `and` / `och` when the next clause starts like a fresh action. macOS intent classification also checks email verbs before event keywords to avoid opening calendar flows for phrases like `maila honom presentationen innan`. During verification, the web compound parser was also aligned with native follow-up-word handling so `sedan`/`sen` and ASCII variants like `i forvag` / `efterat` resolve dates without leaking those markers into the final title.
