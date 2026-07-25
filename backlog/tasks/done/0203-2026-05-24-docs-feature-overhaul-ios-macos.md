---
id: 0203
title: "✅ 2026-05-24 — Docs feature overhaul (iOS + macOS)"
status: done
tags: [task-md, sprint]
files: [docs/superpowers/specs/2026-05-24-docs-feature-overhaul-design.md, docs/superpowers/plans/2026-05-24-docs-feature-overhaul.md]
created: 2026-05-24
source: TASK.md
---

> Source context: TASK.md

## ✅ 2026-05-24 — Docs feature overhaul (iOS + macOS)

- iOS: fixed tap-doesn't-open + create-doesn't-navigate bugs on iPhone (`NavigationStack(path:)` + remove conflicting outer NavigationStack in `MainTabView`).
- iOS: native title TextField + autosave + save indicator + autofocus on new docs; search + Recent + Starred sections in list; info sheet, share, copy title.
- macOS: persistent sidebar (HSplitView never collapses), right pane swaps list↔editor; Cmd+N; sidebar selected state; sort menu (Most recent / Alphabetical / Starred first) persisted; richer doc cards with hover/selected states; skeleton loading.
- Cross-platform: unified "New document" copy, aligned autosave debounce to 500ms.
- Pre-existing bug-fixes to unblock build verification: SettingsView EdgeInsets arg order + 11-chain type-checker timeout split with AnyView.
- Bug hunt + inconsistency hunter ran. 5 pre-existing docs bugs logged to `CODE_REVIEW_BACKLOG.md`.
- Spec: `docs/superpowers/specs/2026-05-24-docs-feature-overhaul-design.md`
- Plan: `docs/superpowers/plans/2026-05-24-docs-feature-overhaul.md`
- **Deferred (follow-up project):** bundling the Tiptap editor into iOS for offline/native parity with macOS.
