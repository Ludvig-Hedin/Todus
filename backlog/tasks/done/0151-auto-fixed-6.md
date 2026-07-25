---
id: 0151
title: "Auto-fixed (6)"
status: done
tags: [ios, macos, bug-hunt, code-review-backlog]
files: []
created: 2026-06-05
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-05 — Bug hunt (iOS + macOS changed files)

## Auto-fixed (6)

| File:line | Severity | What changed |
|-----------|----------|--------------|
| `apps/ios/.../Features/Docs/DocsListView.swift:307` (`docRow`) | 🔴 high (crash) | Recursion over server-controlled `parentId` chains had no cycle/depth guard → stack-overflow crash on a cyclic (A→B→A) or self-parent doc. Added `visited: Set<String>` + `depth < 32` guard; cyclic/over-depth nodes render without recursing. |
| `apps/ios/.../Features/Calendar/CalendarViewController.swift:285` (`createNewEvent`) | 🟡 med (latent crash) | `calendar.date(byAdding:)` (`Date?`) was assigned to the implicitly-unwrapped `EKEvent.endDate`; a nil would later trap in `EKWrapper`'s `DateInterval(start:end:)`. Added `guard let endDate else { return nil }`. |
| `apps/ios/.../Features/Calendar/CalendarViewController.swift:178` (`initializeStore`) | 🟡 med (UX) | Post-authorization fresh store didn't invalidate the pre-grant cache → days fetched before access was granted stayed blank until an `EKEventStoreChanged` or day swipe. Now clears `cachedEvents`/`inFlightDates` before `reloadData()`. |
| `apps/ios/.../Services/Notifications/NotificationService.swift:287` (`clearAll`) | 🟡 med (UX) | `clearAll()` removed notifications but not the app-icon badge set by the due-today digest → stale due-count badge on the icon. Added `center.setBadgeCount(0)`. |
| `apps/ios/.../Features/Home/HomeView.swift:1818` (`loadHomeData`) | 🟡 med (race) | Briefing auto-load (fires from `.task`, scenePhase-active, refresh tick) lacked the `!isLoadingAssistantBriefing` guard that `retryBriefing()` has → could stack parallel briefing fetches. Added the guard. |
| `apps/ios/.../Features/Settings/BillingSettingsView.swift:301` (`progressTint`) | 🔵 low (consistency) | `progressTint` read `aiUsagePercent` without the `.isFinite` guard every other consumer in the file uses; a NaN/±inf could pick a misleading tint. Added guard. |
