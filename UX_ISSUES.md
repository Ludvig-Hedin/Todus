# UX Issues Tracker

Generated from UX assessment of iOS, macOS, and Web apps.
Last updated: 2026-03-31

---

## HIGH Priority

### [H1] Web Calendar: Misleading "Calendar" label — shows tasks only, not events
**Platforms:** Web
**File:** `apps/web/app/(routes)/mail/calendar/page.tsx`
**Problem:** The Calendar page shows tasks plotted by due date but is labeled as "Calendar". The "Connect Google Calendar" notice implies real integration exists when it doesn't.
**Fix:** Add honest messaging: page title shows "Tasks by Date", banner explains calendar events coming soon.
**Status:** ✅ DONE

---

### [H2] iOS Settings: Extremely long, one-page settings wall
**Platforms:** iOS
**File:** `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`
**Problem:** 20+ settings items in one scrollable list. "Email & AI" section conflates unrelated settings (swipe gestures next to AI task permissions).
**Fix:** Split "Email & AI" into separate "Email" and "AI Assistant" sections.
**Status:** ✅ DONE

---

### [H3] iOS Settings: Active Sessions horizontal-scroll table unusable on mobile
**Platforms:** iOS
**File:** `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`
**Problem:** Session data shown in a horizontal-scrolling table inside a vertical List — cramped and hard to use.
**Fix:** Replace with vertical session cards.
**Status:** ✅ DONE

---

## MEDIUM Priority

### [M1] macOS: Non-functional sidebar Quick Filters (Tasks section)
**Platforms:** macOS
**File:** `apps/macos/TodusMac/App/MacSidebarView.swift`
**Problem:** "Quick Filters" (All Tasks, Today, Upcoming, Completed) appear in sidebar footer but have nil action closures — clicking does nothing.
**Fix:** Remove the non-functional filter section (MacTasksView already has its own filter toolbar).
**Status:** ✅ DONE

---

### [M2] macOS: Hardcoded email labels & calendar sources in sidebar
**Platforms:** macOS
**File:** `apps/macos/TodusMac/App/MacSidebarView.swift`
**Problem:** "Important / Work / Personal" email labels and "Personal / Work / Holidays" calendar sources are hardcoded static UI not connected to real data.
**Fix:** Remove these placeholder sections.
**Status:** ✅ DONE

---

### [M3] macOS: Non-functional toolbar filter menus (Email + Tasks)
**Platforms:** macOS
**File:** `apps/macos/TodusMac/App/MacRootView.swift`
**Problem:** Toolbar filter menus for email (All Mail, Unread, Flagged, With Attachments) and tasks (All, Today, Upcoming, Completed) have empty `{}` action closures.
**Fix:** Remove non-functional filter menus from toolbar.
**Status:** ✅ DONE

---

### [M4] Web: Two competing AI chat interfaces
**Platforms:** Web
**Files:** `apps/web/app/(routes)/mail/chat/page.tsx`, `apps/web/components/ui/ai-sidebar.tsx`
**Problem:** `/mail/chat` route and the AI sidebar are separate implementations. Users may find one and not the other. The Chat nav item routes to the full-page version while the AI button opens the sidebar.
**Fix:** Remove `/mail/chat` nav item from sidebar, keep the AI sidebar as the only interface. Add Chat link that opens AI sidebar instead.
**Status:** ✅ DONE

---

### [M5] macOS Settings: "Email & AI" section conflates unrelated settings
**Platforms:** macOS
**File:** `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`
**Problem:** Same issue as iOS — email preferences and AI permissions mixed in one section.
**Fix:** Split into separate "Email" and "AI Assistant" sections.
**Status:** ✅ DONE

---

### [M6] Home dashboard: No distinction between "not connected" vs "no data"
**Platforms:** All
**Problem:** "No events today" shows even when calendar is not connected. Individual empty states don't guide connection.
**Fix:** Show "Connect calendar to see events" when not connected, vs "No events today" when connected but empty.
**Status:** ✅ DONE

---

## LOW Priority

### [L1] iOS: Email inbox empty state is passive
**Platforms:** iOS
**File:** `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`
**Problem:** No distinction between loading, truly empty, and error states. "Tap Refresh" is vague.
**Fix:** Differentiate loading skeleton vs empty vs error with clearer messaging.
**Status:** ✅ DONE

---

### [L2] macOS: Bell icon shows "No new notifications" placeholder
**Platforms:** macOS
**File:** `apps/macos/TodusMac/App/MacRootView.swift`
**Problem:** Notification bell always shows "No new notifications." — it's a dead-end UI.
**Fix:** Hide bell icon until notifications are implemented, or remove the popover.
**Status:** ✅ DONE

---

### [L3] Web: Search lacks quick-create actions (macOS has them, web doesn't)
**Platforms:** Web
**File:** `apps/web/app/(routes)/mail/search/page.tsx`
**Problem:** macOS search has quick-create shortcuts (task/email/event from results). Web search has no actions.
**Fix:** Add quick-action buttons below search results.
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
