---
id: 0228
title: "DONE Duplicate file resolved — App/LocalModelStateStore.swift (51L stub) collided with Services/AI/L"
status: done
tags: [task-md, sprint]
files: [App/LocalModelStateStore.swift, Services/AI/Local/LocalModelStateStore.swift, LocalModelStateStore_DEPRECATED.swift]
created: 2026-05-17
source: TASK.md
---

> Source context: TASK.md → Current iOS Parity + Hardening Sprint (2026-05-17)

- `DONE` **Duplicate file resolved** — `App/LocalModelStateStore.swift` (51L stub) collided with `Services/AI/Local/LocalModelStateStore.swift` (188L real impl, used by `ModelDownloadService` + `MLXInferenceService`). Renamed stub to `LocalModelStateStore_DEPRECATED.swift` and emptied class definition; safe to delete in next cleanup.
