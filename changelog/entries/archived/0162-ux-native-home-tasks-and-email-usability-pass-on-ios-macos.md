---
id: 0162
title: "UX — Native home, tasks, and email usability pass on iOS + macOS"
status: archived
category: Changed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] UX — Native home, tasks, and email usability pass on iOS + macOS

### iOS (`apps/ios/Todus`)

- **Home:** The Home dashboard now distinguishes loading from empty states for events and email, surfaces a compact partial-setup card when Gmail or Calendar still needs connection, adds explicit section actions (`Open` / `View all`), and visually demotes `Other Spaces` so today-focused content reads first.
- **Tasks:** Task search and sort now apply consistently across List, Board, Table, and `By Date`; the mode helper text explains what each layout is for; Board and Table explicitly hide completed work outside List; board columns now have clearer empty states; and due dates are more visually prominent inside board cards.
- **Email:** The inbox now shows a persistent mailbox cue with quick-switch chips for primary folders, clarifies search state (`Filtering loaded...` vs `Searching...`), compresses assistant nudges, and keeps the thread list primary. Thread detail now shows a short message preview before AI summary/actions and consolidates the main thread actions into one top cluster.
- **Verification:** `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -destination 'generic/platform=iOS Simulator' build` succeeds after the UX pass.

### macOS (`apps/macos`)

- **Home:** Added distinct loading cards for events/tasks/email, a compact partial-setup banner when Gmail or Calendar is still disconnected, and actionable empty states with direct next-step buttons for Calendar, Tasks, and Inbox.
- **Tasks:** The toolbar now shows the active sort label alongside the sort icon, explains the purpose of the current view mode more clearly, adds a visible note when completed tasks stay in List, and upgrades the empty state with an explicit create/clear-search action.
- **Email:** The inbox now shows the current mailbox context inside the pane, de-emphasizes assistant nudges relative to the thread list, clarifies search status, improves the empty detail guidance, and moves the AI card below a short message preview in thread detail so reading comes first.
- **Verification:** `xcodebuild -project apps/macos/TodusMac.xcodeproj -scheme TodusMac -destination 'platform=macOS' build` succeeds after the UX pass.
