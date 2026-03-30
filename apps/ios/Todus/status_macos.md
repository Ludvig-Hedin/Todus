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

- March 30, 2026: removed the explicit `AppIcon.icns` plist/resource wiring so the macOS app now uses the asset catalog `AppIcon` target directly, matching the iOS artwork and avoiding the cropped launcher icon.
- March 30, 2026: wired the mini calendar sidebar tap through to the calendar view's selected date so tapping a day now jumps the main calendar to that date instead of only opening the calendar section.
- March 30, 2026: aligned the macOS settings Apple Calendar and Apple Reminders icons with the iOS BrandIcons implementation so the connected-services rows render with the correct proportions.

---

## Last Updated: 2026-03-30
