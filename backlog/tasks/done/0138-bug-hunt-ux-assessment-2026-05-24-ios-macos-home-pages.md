---
id: 0138
title: "Bug Hunt + UX Assessment — 2026-05-24 (iOS + macOS Home pages)"
status: done
tags: [ios, macos, bug-hunt, ux, code-review-backlog]
files: []
created: 2026-05-20
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-20 — iOS Mobile App Bug Hunt

## Bug Hunt + UX Assessment — 2026-05-24 (iOS + macOS Home pages)

_Closed by the 2026-06-13 backlog resolution pass (`CODE_REVIEW_BACKLOG.md` → "No open code defects remain": every code-defect item was fixed, built, tested and committed in passes 1-6). Re-open if this finding is still reproducible._


### Auto-fixed (3 issues)
- `apps/macos/TodusMac/Views/Home/MacHomeView.swift:52` — `isEmailRefreshing` missing `|| isReconciling`; "Updating" badge was absent during post-forceSync reconciliation on macOS while iOS showed it correctly
- `apps/macos/TodusMac/Views/Home/MacHomeView.swift:1281` — email timestamp hardcoded as `hour().minute()` showing "14:32" even for week-old threads; replaced with `emailTimeLabel()` helper (same logic as iOS: "5m ago" / "Yesterday" / "Apr 23")
- `apps/macos/TodusMac/Views/Home/MacHomeView.swift:280-284` — `emailSectionSubtitle` unreachable branch (`total <= shown` always true since `shown = min(5,total)`); dead branch removed

### Needs human review (4 issues)
- `apps/macos/TodusMac/Views/Home/MacHomeView.swift:902` — `meetingsSection` commented out in `scheduleSidebar`; iOS renders it. Re-enable once desktop layout is confirmed. TODO comment added.
- `apps/macos/TodusMac/Views/Home/MacHomeView.swift:565,601,640` — `assistantPriorityStrip`, `assistantQueueColumn`, `macBriefingRowCard` are dead code from old three-column briefing UI. Safe to delete. TODO comments added.
- `apps/ios/Todus/Todus/Features/Home/HomeView.swift:411` — `heroStatChips` computed but never rendered (planned hero chip UI was removed). TODO comment added.
- `apps/macos/TodusMac/Views/Home/MacHomeView.swift:52` (**NOTE: fixed**) but also verify `isEventsRefreshing` only checks `todaysEvents` (line 48) while iOS checks `upcomingEvents` — may be intentional given macOS splits sections.
