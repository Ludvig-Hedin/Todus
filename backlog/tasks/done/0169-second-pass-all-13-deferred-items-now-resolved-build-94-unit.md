---
id: 0169
title: "Second pass — ALL 13 deferred items now resolved (build + 94 unit tests green)"
status: done
tags: [ios, bug-hunt, code-review-backlog]
files: [apps/server/src/trpc/routes/calendar.ts, Todus.xcodeproj/project.pbxproj]
created: 2026-06-13
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Bug Hunt — 2026-06-13 — full iOS app (`/bug-hunt`)

## Second pass — ALL 13 deferred items now resolved (build + 94 unit tests green)

The "deferred" items below were re-evaluated and resolved in the same session: 10 fixed in code, 3 verified to be non-bugs (no change needed).

| ID | Area | Resolution |
|----|------|-----------|
| BH-0613-1 | Calendar (multi-account) | ✅ FIXED. Backend `calendar.calendars` already accepted `connectionId` (resolves target connection, user-scoped — no IDOR); added `accessRole` echo to its response (`apps/server/src/trpc/routes/calendar.ts`). Client `GoogleCalendarService` now passes `connectionId: conn.id` and decodes/uses the real `accessRole` (was hardcoded `"reader"`). |
| BH-0613-2 | Calendar | ✅ FIXED. Added `calendarId` to `CalendarEvent` (set from `EKCalendar.calendarIdentifier`); `UnifiedCalendarService` builds `apple:{calId}` instead of `apple:unknown`. |
| BH-0613-3 | Calendar | ✅ FIXED. `MultiDayPageView` column filter now uses an overlap test (`start < dayEnd && end > dayStart`) so cross-midnight events appear on each covered day. (EventKit's predicate already returns overlapping events, so no extra leading window pad needed.) |
| BH-0613-4 | Calendar | ✅ FIXED. `loadMoreListEvents` dedupes appended events by id; the bottom trigger only re-fires when the list grows, so empty pages no longer loop. |
| BH-0613-5 | Calendar | ✅ VERIFIED NOT A BUG. `didUpdate` is correct: new events set `editedEvent = self` (line 300) → `originalEvent === editingEvent` true → opens editor; existing events use `makeEditable()` clone → `editedEvent` points at the original → saves directly. |
| BH-0613-6 | Navigation | ✅ FIXED (UX bug removed). The live `MainTabView` uses a fixed native tab bar and does not consume `tabBarTabs`, so the customization **onboarding step was a no-op** — removed it from the `RootView` chain + pending flags. The native bar (good UX) is kept; the customization components remain for if/when the dynamic tab bar is finished (out of scope: high-regression rebuild of core nav). |
| BH-0613-7 | Settings | ✅ FIXED. Consolidated to a single source of truth: `AppServices.accentPreference.didSet` now mirrors to the server-synced `ios_accent_color` key and pushes `accentColor` to the server; both the Preferences and Appearance pickers drive `accentPreference`; removed the duplicate `accentColorKey` state + redundant onChange. (Visible app re-tinting via `.tint` remains a separate product decision — the footer already says some surfaces adopt the accent in a later release.) |
| BH-0613-8 | Dead code | ✅ NOT A USER-FACING BUG. `MoreSheetView`/`DefaultMailOnboardingView`/`EmailAIDraftSheet` are never instantiated → zero runtime/UI effect. Left in place; deleting would require hand-editing `Todus.xcodeproj/project.pbxproj` (high risk, no user benefit). |
| BH-0613-9 | Email | ✅ FIXED. `SenderAvatarView` snapshots candidate URLs into `@State` (`resolvedCandidates`), adopted on first populate + growth only — `recordSuccess` reordering the cache no longer shifts `urlIndex` onto a different URL (flicker gone). |
| BH-0613-10 | App | ✅ FIXED. `RootView` snapshots the *set* of pending onboarding indices and computes the step as the position of the first still-pending flag — counts up monotonically even when a later step auto-skips first. |
| BH-0613-11 | Voice | ✅ FIXED. `VoiceChatViewModel.handleEvent` ignores all events once `connectionState` is `.failed`, so a trailing provider event can't resurrect a torn-down session. |
| BH-0613-12 | AI | ✅ FIXED (`addSavedPrompt` now dedupes by id / move-to-top). `aiCanSendEmail` verified NOT a bug — consistent with its two sibling flags and idempotent. |
| BH-0613-13 | Calendar | ✅ FIXED. now-indicator dot accounts for the 0.5pt inter-column separators; `CalendarYearView` event dots index the full day-span (guard-capped) so multi-day events dot every covered day. |

---
