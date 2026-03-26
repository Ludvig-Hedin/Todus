# Todus macOS — Status Tracker

## Current Phase: Not Started

macOS development begins after iOS MVP is stable and on TestFlight.

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
| macOS target added | ⬜ Not started | |
| NavigationSplitView layout | ⬜ Not started | Sidebar-based nav for macOS |
| Toolbar adaptation | ⬜ Not started | Replace tab bar with toolbar |
| CalendarKit macOS | ⬜ Not started | May need replacement |
| Platform conditionals | ⬜ Not started | `#if os(macOS)` where needed |
| Compiles on macOS | ⬜ Not started | |

## Feature Parity

| Feature | iOS | macOS | Notes |
|---------|-----|-------|-------|
| Tasks | ✅ | ⬜ | |
| Calendar | ✅ | ⬜ | CalendarKit is iOS-only |
| Email | ✅ | ⬜ | |
| AI Chat | ✅ | ⬜ | |
| Home | ✅ | ⬜ | |
| Auth | ✅ | ⬜ | Apple Sign In works on macOS |
| Settings | ✅ | ⬜ | |

## macOS-Specific Features

| Feature | Status | Notes |
|---------|--------|-------|
| Keyboard shortcuts | ⬜ Not started | |
| Menu bar | ⬜ Not started | |
| Multi-window | ⬜ Not started | |
| Drag and drop | ⬜ Not started | |
| Touch Bar | ⬜ Not started | If applicable |

---

## Blockers

| Issue | Impact | Resolution |
|-------|--------|------------|
| iOS MVP not complete | Can't start macOS | Complete iOS phases 0-6 first |

---

## Last Updated: 2026-03-26
