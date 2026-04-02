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
**Fix:** Full 4-state branching: no-connection → loading skeleton (first load) → **error state** (exclamationmark.triangle, error message, Try Again button) → empty state (folder icon + title + optional subtitle) → thread list. Empty state further branches: search-empty ("No results for X", Clear Search) vs folder-empty (Refresh). Fixed `searchBar.onSubmit` missing `folder:` parameter bug.
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

## Structural

### [S1] Web Calendar: Implement real calendar integration
**Status:** ✅ DONE
- **Backend**: New `calendarRouter` at `apps/server/src/trpc/routes/calendar.ts` — `events` query calls Google Calendar API v3 using `OAuth2Client` (auto-refresh) + `fetch`. Returns events with title, startTime, endTime, allDay, color, location, description, htmlLink. Handles 403 (missing `calendar.readonly` scope) by returning `{ events: [], scopeMissing: true }` instead of throwing.
- **Scope**: Added `https://www.googleapis.com/auth/calendar.readonly` to Google driver's `getScope()` — new auth flows get it automatically.
- **Web**: Calendar page now fetches `trpc.calendar.events` for the displayed month range. Right panel shows real events (colored left border, time, location) above tasks. Week overview shows blue dots on days with events. If `scopeMissing = true`, a "Connect Google Calendar" banner with a re-auth button appears. Page title reverted from "Tasks by Date" back to "Calendar" now that real events are shown.

**Files:** `apps/server/src/trpc/routes/calendar.ts`, `apps/server/src/trpc/index.ts`, `apps/server/src/lib/driver/google.ts`, `apps/web/app/(routes)/mail/calendar/page.tsx`

---

### [S2] Guided onboarding for web and macOS
**Status:** ✅ DONE (pre-existing)
- macOS: `MacHomeView` already has `getStartedSection` — shows three action cards (Create task / Connect Gmail / Check calendar) when user has no data. Gmail connection is prompted inline in the email view via `connectPrompt`.
- iOS: `GmailOnboardingView` + `RemindersOnboardingView` gate the main tab bar on first run.

---

### [S3] iOS Settings: Full navigation-based restructure
**Status:** ✅ DONE
- `activeSessionsSection` replaced by `sessionsNavigationSection` — a single NavigationLink row with a session-count badge. Full session management moved to `SessionsSettingsView` (loads its own data, handles revoke/revoke-all, signs out if current session revoked).
- `aiAssistantSection` (with two large inline TextEditors) replaced by `aiAssistantNavigationSection` — a NavigationLink row. AI settings moved to `AIAssistantSettingsView` with proper section headers and footers. `saveSharedAIProfile()` called on `.onDisappear`.
- `preferencesAndAppearanceSection` replaced by `preferencesSection` + "Appearance" NavigationLink. Appearance moved to `AppearanceSettingsView` with a vertical list layout (swatch + title + subtitle + checkmark) instead of the cramped three-column picker.
- Main settings page now has 8 clean sections — no more large inline editors or wide layout components.

**Files:** `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`

---

### [S4] Email folder parity: Add Archive/Snoozed/Spam/Trash to iOS and macOS
**Status:** ✅ DONE
- **macOS**: Added `archive`, `snoozed`, `spam`, `bin` cases to `EmailSection` enum in `MacRootView.swift`. Each has a title and SF Symbol. Sidebar shows primary folders (Inbox/Drafts/Sent) above a divider, secondary folders below. `SidebarChildItemButton` updated to accept optional `systemImage` parameter. `MacEmailInboxView(folder: section.rawValue)` already passes the folder string to the backend.
- **iOS**: Added `EmailFolder` private enum to `EmailInboxView.swift` with all 7 folders (inbox/drafts/sent/archive/snoozed/spam/bin). Header title now taps to open a `Menu` picker showing primary and secondary folders with icons. Folder changes trigger thread reload. Empty state shows folder-specific icon and title.

**Files:** `apps/macos/TodusMac/App/MacRootView.swift`, `apps/macos/TodusMac/App/MacSidebarView.swift`, `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`

---

### [S5] Voice input on web
**Status:** ✅ DONE (pre-existing)
`VoiceButton` component exists at `apps/web/components/voice-button.tsx` and is rendered inside the AI chat panel (`apps/web/components/create/ai-chat.tsx`). Uses ElevenLabs with email thread context awareness.

---

### [C2] Web Home: Distinguish "not connected" from "no data" empty states
**Status:** ✅ DONE
- **Calendar section**: Now queries `trpc.calendar.events` for today's range. Shows real events with colored left border, time, and location. If `scopeMissing = true` (token lacks `calendar.readonly`), shows a re-auth button. If no events: "No events today". No longer shows a misleading static "Connect Google Calendar" CTA regardless of connection state.
- **Email section**: Now checks `threadsQuery.isError` (backend throws `NOT_FOUND` when no Gmail connection is linked). On error → "Connect Gmail" CTA linking to `/settings/connections`. On success with empty list → "Your inbox is empty".

**Files:** `apps/web/app/(routes)/mail/home/page.tsx`
