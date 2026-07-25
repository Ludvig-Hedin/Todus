---
id: 0469
title: "todus://share deep link has no presenter on macOS"
status: open
priority: P2
tags: [macos, todo-sweep, sharing]
files: [apps/macos/TodusMac/Views/AI/MacSharedConversationView.swift]
created: 2026-07-25
source: code TODO/FIXME sweep
---

`MacSharedConversationView.swift:5` — `TODO(integration)`. `TodusMacApp.dispatchValidatedURL` broadcasts `Notification.Name.todusOpenSharedConversation` for `todus://share?slug=...`, but nothing observes it, so opening a shared-conversation link on macOS does nothing. The comment carries the exact `MacRootView` wiring.

## Fix shape

Apply the wiring sketched in the comment (`@State pendingShareSlug` + `.onReceive` + `.sheet`), then delete the TODO block.
