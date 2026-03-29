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
| Compiles on macOS | 🟨 Pending local license | `xcodebuild` blocked until Xcode license is accepted |

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
| Xcode license not accepted locally | Blocks CLI build verification | Run `sudo xcodebuild -license` once, then build the `TodusMac` scheme |

---

## Last Updated: 2026-03-29
