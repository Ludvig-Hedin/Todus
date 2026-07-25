---
id: 0163
title: "Fix — Native email mailbox clarity and responsiveness pass"
status: archived
category: Fixed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] Fix — Native email mailbox clarity and responsiveness pass

### iOS (`apps/ios/Todus`)

- **Connection-state gating:** The inbox now distinguishes `checking connection` from `not connected`, so the Gmail connect surface no longer flashes before the initial connection check completes.
- **Folder-specific empty states:** Empty mailboxes now use folder-aware copy such as `No drafts`, `Nothing sent yet`, and `Trash is empty`, each with a short explanation of what belongs there.
- **Verification:** `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` succeeds after the inbox-state changes.

### macOS (`apps/macos`)

- **Instant folder switching:** The macOS email service now hydrates each mailbox from an in-memory per-folder cache before refreshing, so switching between Inbox, Drafts, Sent, and the secondary folders no longer waits on a cold reload.
- **Connection-state gating:** The macOS email page now shows a loading state while checking Gmail connectivity instead of briefly rendering the connect prompt during startup.
- **Sender avatars:** The inbox list and thread detail now use the same avatar-resolution pipeline as iOS, preferring contact/domain imagery before falling back to deterministic initials.
- **Folder-specific empty states:** Empty mailbox messaging is now specific to the selected folder instead of the generic `No emails` copy.
- **Verification:** The changed email files compile during the macOS build, but the full target still fails because of pre-existing unrelated errors in `apps/macos/TodusMac/Views/Tasks/MacTasksView.swift`.
