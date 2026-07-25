---
id: 0157
title: "UX — Native onboarding and task clarity pass on iOS + macOS"
status: archived
category: Changed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] UX — Native onboarding and task clarity pass on iOS + macOS

### iOS (`apps/ios/Todus`)

- **Onboarding copy refresh:** Auth, Gmail, Reminders, and tab-bar onboarding now share one product promise, explain the benefit of each step more directly, and use lower-friction skip copy that tells users they can finish setup later in Settings.
- **Onboarding feedback states:** Gmail and Reminders onboarding now surface inline helper/error messaging so failed connection or denied-permission states are understandable instead of silent.
- **Tasks discoverability:** The Tasks page now exposes a local `Add Task` action in the header, removes the old standalone current-view chip, and uses labeled mode toggles instead of icon-only buttons.
- **Tasks clarity:** Non-list task modes now explicitly tell users that completed tasks stay in List, list empty-state copy points to the real creation path, and task-row metadata has a clearer hierarchy with due date/status emphasized over folder noise.
- **Board scrolling:** The board view now scrolls vertically and horizontally as separate axes instead of allowing free-form canvas panning.

### macOS (`apps/macos`)

- **Onboarding copy refresh:** Auth, Gmail, Calendar, and startup onboarding now use the same workspace framing as iOS, clearer outcome-based skip copy, and inline guidance that reduces setup anxiety.
- **Permission feedback:** Calendar onboarding now keeps the user on the step when access is denied and explains the Settings recovery path instead of silently advancing.
- **Startup preference polish:** Startup-view onboarding now presents Home as the recommended default and keeps the skip path aligned with that recommendation.
- **Tasks discoverability:** The Tasks page now includes a local `Add Task` action, labeled view toggles, a clearer completed-visibility note outside List, and stronger empty-state guidance.
- **Task editing parity:** macOS task detail editing now supports changing the task folder, and list/board rows communicate clickability more clearly with lighter metadata and a trailing chevron.

### Verification Details

- `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -configuration Debug -destination 'generic/platform=iOS' build` [Resolved]
- `xcodebuild -project apps/macos/TodusMac.xcodeproj -scheme TodusMac -configuration Debug build` [Blocking] existing unrelated compile failure in [EmailModels.swift](/Users/ludvighedin/Programming/personal/mail/apps/macos/TodusMac/Domain/EmailModels.swift) referencing missing `AppLogger`.
