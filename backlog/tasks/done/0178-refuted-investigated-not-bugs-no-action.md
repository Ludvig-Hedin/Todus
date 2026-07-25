---
id: 0178
title: "Refuted — investigated, NOT bugs (no action)"
status: done
tags: [ios, bug-hunt, code-review-backlog]
files: []
created: 2026-06-14
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Bug Hunt — 2026-06-14 (iOS main user-flow surfaces)

## Refuted — investigated, NOT bugs (no action)

- `Features/Tasks/TaskDetailSheet.swift:120` (camera picker) — claimed off-main `@State` mutation. False: `UIImagePickerControllerDelegate` callbacks fire on the main thread; `appendAttachments` runs on main.
- `Services/Tasks/TaskCaptureService.swift:122` (`try? context.fetch` in rollback) — error-swallow is intentional & documented; the just-saved mutations are already persisted at `:106`, and a failed fetch only skips an optional rollback (tasks keep their visible `.failed` state, not phantom data).
- `Features/Calendar/CalendarTabView.swift:500` (`loadEvents`) and `:553` (`loadMoreListEvents`) — claimed off-main `@State` mutation. Both are called from main-actor contexts (`.task`, `.onChange`); Swift concurrency violations are compile-time, and the app builds, so no runtime isolation violation exists. (Adding explicit `@MainActor` would be redundant.)
- `Features/Voice/VoiceChatViewModel.swift:135` (trailing-event state resurrection) — already guarded by `if case .failed = connectionState { return }` at the top of `handleEvent`. (Overlaps the broader, still-open `CR-0613-7` TODO; left as-is.)
- `Navigation/MainTabView.swift:87` (capture-failure dismiss timer) — idiomatic cancel-and-replace `Task` on the main actor; `guard !Task.isCancelled` + `try?` handle cancellation correctly.
- `App/AppServices.swift:806` (`Task { @MainActor … }` after `Task.yield()`) — class is `@MainActor`; the closure is explicitly `@MainActor`; mutated properties have no `didSet`. Correct as written.

---
