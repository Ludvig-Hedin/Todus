---
id: 0318
title: "Fixed — iOS: UX-audit remediation wave (25 findings)"
status: unreleased
category: Fixed
release_date: 2026-07-21
source: CHANGELOG.md
---

### Fixed — iOS: UX-audit remediation wave (25 findings), 2026-07-21

Full audit + fixes: `docs/audits/ios-ux-audit-2026-07-21.md`. Highlights (user-facing):

- **Guest trust (TD-01, P1):** guests no longer see a false "Session expired — Sign in again" banner; 401s only raise it when a real session existed (`TodosAPIClient`, `AuthService.hasSessionToExpire`). Banner stack now reserves a top slot instead of overlapping the nav row (TD-25).
- **Dynamic Type (TD-02, P1):** new `scaledFont` helper in `AppTheme`; ~341 fixed-size fonts migrated across Tasks/Home/Create/Email/AI surfaces — text now tracks the user's type size (sim-verified at AX-XL). 9pt chips raised to 11pt.
- **Data safety (TD-03/06/08/09/13/21):** sign-out and guest sign-in warn when unsynced tasks would be deleted; notification "Complete" action routes through `setStatus` so it syncs; AI enrichment no longer clobbers a manual rename; folder mutation queue persists across kills (no more resurrecting deleted folders); deleted SwiftData models filtered from cached render arrays; folder rename no longer transiently reverts mid-sync.
- **Input safety (TD-04/10):** create-sheet drafts survive scrim dismissal; AI profile settings save on swipe-dismiss too.
- **Permissions (TD-05):** creating a task no longer fires the system notification prompt after the user skipped it in onboarding.
- **Email (TD-07/19):** background/poll refresh no longer wipes active search results; archive gets an Undo toast (inbox + sender drill-in) via new `ToastOverlay` action support + `EmailService.unarchiveThreads`.
- **Accessibility (TD-11/12/14/16/18/20/22):** Reduce Motion gates on all repeat-forever animations; ~25 icon-only buttons labeled; tap-only rows exposed as buttons to VoiceOver; toasts announced via `AccessibilityNotification`; create sheet is a proper VO modal with escape; `mutedText` contrast raised; onboarding truncation fixed; 44pt hit targets on Home section links; overdue chips get a glyph + spoken "Overdue"; task rows expose complete/snooze/move as VO actions.
- **Perf:** folder-picker search no longer refetches per keystroke; calendar now-line ticks via `TimelineView` without relayouting the whole grid; global search computes results once per query (backlog PERF-2/3/4 resolved).
- **Misc:** Settings entry added to the More tab (TD-24); AI 401 copy humanized, no longer tells users to log out (TD-15).

Deferred: dead `Features/Tasks/CustomTabBar.swift` deletion (TD-23); macOS copy of the 401 jargon string; `design: .rounded/.monospaced` fonts (3 sites) not scalable via helper yet.
