---
id: 0205
title: "Feature — Home proactive AI suggestions (iOS + macOS)"
status: archived
category: Added
release_date: 2026-04-24
source: CHANGELOG.md
---

## [2026-04-24] Feature — Home proactive AI suggestions (iOS + macOS)

- [Feature] Home shows a **Suggestions for you** strip powered by existing open-loop nudges (`EmailService.loadAssistantNudges` / assistant inbox nudges): short explainer, horizontal cards, tap opens the thread or Mail when no thread id.
- [UX] macOS: section respects Focus Mode (`mac_focus_mode_enabled`) and matches the editorial card styling; iOS: section after the greeting, before the briefing block.
- [Fix] macOS: replaced invalid `MacTheme.spacing10` references with `spacing8` so the target compiles.
