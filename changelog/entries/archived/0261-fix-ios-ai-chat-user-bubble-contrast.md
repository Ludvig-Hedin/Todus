---
id: 0261
title: "Fix — iOS AI chat user bubble contrast"
status: archived
category: Fixed
release_date: 2026-04-26
source: CHANGELOG.md
---

## [2026-04-26] Fix — iOS AI chat user bubble contrast

- [Fix] **The user message bubble in the native AI sheet now has clear, restrained separation in both appearances.** User bubbles no longer reuse the generic card fill that was too close to the assistant sheet background; they now use a dedicated dynamic fill tuned to a very light gray in light mode and a very dark gray in dark mode.
- [User-facing] **User turns are readable at a glance again without looking loud.** The bubble remains subtle, but it now holds the same visual role in dark mode that it already should in light mode.
- [Files] `apps/ios/Todus/Todus/DesignSystem/AppTheme.swift`, `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`, `CHANGELOG.md`, `apps/ios/Todus/TASK.md`
