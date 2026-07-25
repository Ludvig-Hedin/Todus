---
id: 0247
title: "DONE CodeRabbit follow-up for native parsing/compose/task regressions (2026-04-27): iOS + macOS loca"
status: done
tags: [task-md, sprint]
files: []
created: 2026-04-27
source: TASK.md
---

> Source context: TASK.md → Current Native Review Follow-up

- `DONE` **CodeRabbit follow-up for native parsing/compose/task regressions (2026-04-27):** iOS + macOS local parsers now gate bare tail-number times on an actual date marker, stop on the first relative-date token, and remove matched spans from the original string to avoid Unicode case-folding range drift. Compound intent parsing now applies anchor offsets in the requested timezone and treats `i förväg` only as a before-reference. iOS compound email creation now preserves attachments, macOS reply/reply-all drafts use distinct autosave keys, CC/BCC participate in send validation, and restoring a completed macOS task saves outside the animation closure.
