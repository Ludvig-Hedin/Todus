# Todus macOS — Status Tracker

## Current Phase: Shell Scaffold Complete

Native macOS shell scaffolding is now in place under `apps/macos` as a standalone SwiftUI app.

---

## Prerequisites
- [ ] iOS app compiles and runs on TestFlight
- [ ] Unified auth working on iOS
- [ ] Email tab functional on iOS
- [ ] Navigation stable on iOS

---

## Build Status

| Component | Status | Notes |
|-----------|--------|-------|
| macOS target added | ✅ Complete | Standalone XcodeGen project in `apps/macos` |
| NavigationSplitView layout | ✅ Complete | Sidebar-based shell scaffold |
| Toolbar adaptation | ✅ Complete | Custom SwiftUI content header |
| CalendarKit macOS | ⬜ Not started | May need replacement |
| Platform conditionals | ⬜ Not started | `#if os(macOS)` where needed |
| Compiles on macOS | ✅ Done | `xcodebuild -project apps/macos/TodusMac.xcodeproj -scheme TodusMac -destination 'platform=macOS' build` succeeds after fixing root-view selection shadowing and current settings/assistant compile issues |

## Feature Parity

| Feature | iOS | macOS | Notes |
|---------|-----|-------|-------|
| Tasks | ✅ | 🟨 Shell only | Placeholder view only |
| Calendar | ✅ | 🟨 Shell only | Placeholder view only |
| Email | ✅ | 🟨 Shell only | Placeholder view only |
| AI Chat | ✅ | 🟨 Entry only | Assistant sheet placeholder |
| Home | ✅ | 🟨 Shell only | Placeholder view only |
| Auth | ✅ | ⬜ | Not connected on macOS yet |
| Settings | ✅ | 🟨 Placeholder | Modal placeholder only |
| AI profile settings | ✅ | 🟨 Synced | Shared `Context about you` + `Custom instructions` fields now sync through backend `userSettings` and feed all macOS AI prompts |

## macOS-Specific Features

| Feature | Status | Notes |
|---------|--------|-------|
| Keyboard shortcuts | ⬜ Not started | |
| Menu bar | ⬜ Not started | |
| Multi-window | ⬜ Not started | Single window only in this pass |
| Drag and drop | ⬜ Not started | |
| Touch Bar | ⬜ Not started | If applicable |

---

## Blockers

| Issue | Impact | Resolution |
|-------|--------|------------|
| None currently | — | macOS CLI build verification now passes after the latest settings and assistant-panel cleanup |

---

## Build Notes

- April 3, 2026: tightened macOS button hit targets and pointer affordances on the shared header, sidebar, task, and calendar controls without changing the drawn UI.
- April 3, 2026: shipped a focused Home/Tasks/Email UX remediation pass on macOS. Home now distinguishes loading from empty states and shows partial-setup guidance plus actionable empty cards; Tasks now exposes the active sort label, explains view purpose more clearly, and calls out when completed tasks stay in List; Email now shows mailbox context inside the pane, clarifies search status, de-emphasizes assistant nudges, and places a short message preview ahead of the AI card in thread detail.
- April 3, 2026: applied a small macOS UX clarity pass without changing the shell structure: the bell surface is now framed as a `Daily Brief`, auth/restoring copy better explains the synced workspace state, search copy better communicates jump/navigation behavior, and create/search are slightly more visually prominent than secondary toolbar actions.
- April 3, 2026: added macOS first-run onboarding after auth for Gmail, calendar access, and launch-page selection. Each step is skippable, persists in `MacAppServices`, and the app now lands users in the main shell with a clearer startup destination.
- April 3, 2026: regenerated the macOS `AppIcon.appiconset` from the iOS 1024 px master so the Dock icon uses the same padding as iOS and the logo no longer reads as cropped.
- March 30, 2026: removed the explicit `AppIcon.icns` plist/resource wiring so the macOS app now uses the asset catalog `AppIcon` target directly, matching the iOS artwork and avoiding the cropped launcher icon.
- March 30, 2026: wired the shared AI profile settings into the macOS settings sheet and assistant prompt pipeline so `Context about you` and `Custom instructions` are now persisted through backend settings.
- March 30, 2026: wired the mini calendar sidebar tap through to the calendar view's selected date so tapping a day now jumps the main calendar to that date instead of only opening the calendar section.
- March 30, 2026: aligned the macOS settings Apple Calendar and Apple Reminders icons with the iOS BrandIcons implementation so the connected-services rows render with the correct proportions.

---

## Last Updated: 2026-04-03
