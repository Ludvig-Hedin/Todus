---
id: 0259
title: "Fix — iOS CodeRabbit review follow-up"
status: archived
category: Fixed
release_date: 2026-04-26
source: CHANGELOG.md
---

## [2026-04-26] Fix — iOS CodeRabbit review follow-up

- [Fix] **The tracked per-user Xcode scheme file is removed from version control.** `apps/ios/Todus/Todus.xcodeproj/xcuserdata/.../xcschememanagement.plist` is no longer tracked, matching the existing `xcuserdata/` ignore rule and avoiding user-specific scheme churn in the repo.
- [Fix] **Folder/item duplication and stale-filter bugs are closed on iOS.** Task board/table now recompute when `restrictToInbox` changes, folder pickers filter out already-added email/event items, and `TaskCaptureService.addItemToFolder(...)` now skips duplicate folder bookmarks before incrementing cached counts.
- [Fix] **Several native reliability issues are hardened.** The compose sheet now defers attachment file deletion until send succeeds, avatar-cache writes are flushed on background, widget refreshes use a bounded completed-task fetch with DST-safe day math, AI undo/retry flows always report completion, assistant-summary retry state stays visible, and the voice session no longer leaks audio resources if the user disconnects during startup.
- [Fix] **The native voice model now uses Google’s currently documented Live API identifier.** iOS `VoiceModelCatalog` now uses `gemini-live-2.5-flash-native-audio`, which matches current Google Cloud Live API docs instead of the invalid `gemini-3.1-flash-live-preview` value.
- [Verification] **Targeted iOS simulator build passed after the fixes.** `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` completed successfully; remaining output was warnings only.
- [Files] `apps/ios/Todus/Todus.xcodeproj/project.pbxproj`, `apps/ios/Todus/project.yml`, `apps/ios/Todus/TodosApp.swift`, `apps/ios/Todus/Todus/Features/AI/AIChatMessage.swift`, `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`, `apps/ios/Todus/Todus/Features/AI/AIAttachmentSheet.swift`, `apps/ios/Todus/Todus/Features/Calendar/CalendarListView.swift`, `apps/ios/Todus/Todus/Features/Calendar/CalendarTabView.swift`, `apps/ios/Todus/Todus/Features/Email/EmailComposeView.swift`, `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift`, `apps/ios/Todus/Todus/Features/Email/SenderAvatarView.swift`, `apps/ios/Todus/Todus/Features/Folders/*`, `apps/ios/Todus/Todus/Features/Home/HomeView.swift`, `apps/ios/Todus/Todus/Features/Tasks/{BoardView.swift,TaskTableView.swift,TasksTabView.swift}`, `apps/ios/Todus/Todus/Features/Voice/VoiceChatViewModel.swift`, `apps/ios/Todus/Todus/Services/{AI/API/Drafts/Notifications/Tasks/Voice/Widgets}/*`, `CHANGELOG.md`, `apps/ios/Todus/TASK.md`
