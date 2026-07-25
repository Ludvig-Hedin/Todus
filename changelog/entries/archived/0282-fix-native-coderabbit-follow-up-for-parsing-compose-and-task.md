---
id: 0282
title: "Fix — native CodeRabbit follow-up for parsing, compose, and task UI"
status: archived
category: Fixed
release_date: 2026-04-27
source: CHANGELOG.md
---

## [2026-04-27] Fix — native CodeRabbit follow-up for parsing, compose, and task UI

- [Fix] **iOS and macOS local task parsing now avoid false-positive bare-number times and Unicode range drift.** `LocalTaskParsingService` only applies `tailTimeRegex` when a date keyword was already detected, stops at the first matching relative-date marker, and computes/removes consumed ranges against the original trimmed string so case-folding edge cases do not corrupt title cleanup.
- [Fix] **Compound intent parsing now respects the caller timezone and resolves Swedish relative-reference words consistently.** Both native `CompoundIntentParser` implementations use a timezone-configured `Calendar` for anchor offsets, remove the `i förväg` overlap from `containsSoonReference`, and strip the same before/after tokens they detect from final titles.
- [Fix] **Native compose/task UX regressions are closed.** iOS compound email creation now forwards the computed attachments into the compose seed, macOS reply and reply-all autosave keys no longer collide, macOS send validation now checks `to`/`cc`/`bcc`, and completed-task restore saves outside the animation block.
- [Verification] **Native app builds passed locally, and parser coverage was expanded.** `xcodebuild build` succeeded for both `apps/ios/Todus/Todus.xcodeproj` and `apps/macos/TodusMac.xcodeproj`; the new parser tests were added for the bare-tail-number regression, first relative-marker precedence, and `i förväg` compound parsing semantics, but the `TodusTests` target is currently blocked by an existing missing-`Info.plist` test-target configuration on this branch.
- [Files] `apps/ios/Todus/Todus/Features/Home/HomeView.swift`, `apps/ios/Todus/Todus/Navigation/CreateSheet.swift`, `apps/ios/Todus/Todus/Services/Parsing/{CompoundIntentParser.swift,LocalTaskParsingService.swift}`, `apps/ios/Todus/TodusTests/LocalTaskParsingServiceTests.swift`, `apps/macos/TodusMac/Services/Tasks/{CompoundIntentParser.swift,LocalTaskParsingService.swift}`, `apps/macos/TodusMac/Views/Email/MacEmailComposeView.swift`, `apps/macos/TodusMac/Views/Tasks/MacTasksView.swift`, `CHANGELOG.md`, `TASK.md`
