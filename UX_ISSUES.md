# UX Issues Tracker

Generated from UX assessment of iOS, macOS, and Web apps.
Last updated: 2026-03-31

---

## HIGH Priority

### [H1] Web Calendar: Misleading "Calendar" label — shows tasks only, not events
**Platforms:** Web
**File:** `apps/web/app/(routes)/mail/calendar/page.tsx`
**Problem:** The Calendar page shows tasks plotted by due date but is labeled as "Calendar". The "Connect Google Calendar" notice implies real integration exists when it doesn't.
**Fix:** Page title changed to "Tasks by Date" with inline "Calendar events coming soon" badge. Misleading "Connect Google Calendar" link replaced with static informational notice.
**Status:** ✅ DONE

---

### [H2] iOS Settings: Extremely long, one-page settings wall
**Platforms:** iOS
**File:** `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`
**Problem:** 20+ settings items in one scrollable list. "Email & AI" section conflated unrelated settings (swipe gestures next to AI task permissions).
**Fix:** Split "Email & AI" into separate "Email" and "AI Assistant" sections.
**Status:** ✅ DONE

---

### [H3] iOS Settings: Active Sessions horizontal-scroll table unusable on mobile
**Platforms:** iOS
**File:** `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`
**Problem:** Session data shown in a horizontal-scrolling table inside a vertical List — cramped and hard to use on iPhone.
**Fix:** Replaced with vertical session cards: device icon, name, "This device" badge for current session, location + last-updated labels, Log out button on non-current sessions only.
**Status:** ✅ DONE

---

## MEDIUM Priority

### [M1] macOS: Non-functional sidebar Quick Filters (Tasks section)
**Platforms:** macOS
**File:** `apps/macos/TodusMac/App/MacSidebarView.swift`
**Problem:** "Quick Filters" (All Tasks, Today, Upcoming, Completed) appeared in sidebar footer but had nil action closures — clicking did nothing.
**Fix:** Removed the non-functional filter section. `tasksFooter` now returns `EmptyView()`. MacTasksView has its own filter toolbar.
**Status:** ✅ DONE

---

### [M2] macOS: Hardcoded email labels & calendar sources in sidebar
**Platforms:** macOS
**File:** `apps/macos/TodusMac/App/MacSidebarView.swift`
**Problem:** "Important / Work / Personal" email labels and "Personal / Work / Holidays" calendar sources were hardcoded static UI not connected to real data.
**Fix:** Removed `emailFooter` label list and `calendarFooter` source list. Deleted unused `LabelRow` and `FilterRow` private structs.
**Status:** ✅ DONE

---

### [M3] macOS: Non-functional toolbar filter menus (Email + Tasks)
**Platforms:** macOS
**File:** `apps/macos/TodusMac/App/MacRootView.swift`
**Problem:** Toolbar filter menus for email (All Mail, Unread, Flagged, With Attachments) and tasks (All, Today, Upcoming, Completed) had empty `{}` action closures.
**Fix:** Removed both non-functional filter menus. Context toolbar now shows only the functional "Mark All Read" button for email section.
**Status:** ✅ DONE

---

### [M4] Web: Two competing AI chat interfaces
**Platforms:** Web
**Files:** `apps/web/config/navigation.ts`
**Problem:** `/mail/chat` route and the AI sidebar were separate implementations. Users might find one and not the other.
**Fix:** Chat removed from sidebar navigation (FAB-only). Navigation config comment: "AI Chat is FAB-only, not a sidebar nav item."
**Status:** ✅ DONE

---

### [M5] macOS Settings: "Email & AI" section conflates unrelated settings
**Platforms:** macOS
**File:** `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`
**Problem:** Same issue as iOS — email preferences and AI permissions in one section.
**Fix:** Already split into separate `emailPreferencesSection` and `aiAssistantSection` — verified, no change needed.
**Status:** ✅ DONE (pre-existing)

---

## LOW Priority

### [L1] iOS: Email inbox empty state is passive — no loading skeleton
**Platforms:** iOS
**File:** `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`
**Problem:** No distinction between loading, truly empty, and error states.
**Fix:** Added `loadingState` branch with deterministic skeleton rows (`.redacted(reason: .placeholder)`). Body now branches: no-connection → loading skeleton (first load) → empty state → thread list.
**Status:** ✅ DONE

---

### [L2] macOS: Bell icon shows "No new notifications" placeholder
**Platforms:** macOS
**File:** `apps/macos/TodusMac/App/MacRootView.swift`
**Problem:** Notification bell always showed "No new notifications." — dead-end UI with no action.
**Fix:** Removed bell icon and its associated `showNotifications` state.
**Status:** ✅ DONE

---

### [L3] Web: Search lacks quick-create actions (macOS has them, web doesn't)
**Platforms:** Web
**File:** `apps/web/app/(routes)/mail/search/page.tsx`
**Problem:** macOS search has quick-create shortcuts (task/email). Web search had no actions in the empty state.
**Fix:** Initial empty state now shows "Quick Actions" panel: inline task-create input (type + Enter to create, with loading spinner and error toast) + "Compose new email" button navigating to `/mail/compose`.
**Status:** ✅ DONE

---

## Structural (Future Work)

### [S1] Web Calendar: Implement real calendar integration
Real time-grid view with Google Calendar events. Backend Calendar API needed first.

### [S2] Guided onboarding for web and macOS
First-run screen like iOS GmailOnboardingView/RemindersOnboardingView.

### [S3] iOS Settings: Full navigation-based restructure
Split into sub-pages via NavigationLink (Account, Connections, Appearance, Email, AI, Notifications, Security, About).

### [S4] Email folder parity: Add Archive/Snoozed/Spam/Trash to iOS and macOS
Currently only web surfaces these folders.

### [S5] Voice input on web
Port iOS voice chat capabilities to web.
