---
id: 0206
title: "UX — pointer cursor for interactive controls (web + macOS)"
status: archived
category: Changed
release_date: 2026-04-24
source: CHANGELOG.md
---

## [2026-04-24] UX — pointer cursor for interactive controls (web + macOS)

- [UX] Web (`apps/web`, `apps/mail`): base styles now set `cursor: pointer` for native `checkbox` / `radio` / `file` / `range` inputs and for labels that wrap a checkbox or radio; existing rules already covered `button`, links, and ARIA roles.
- [UX] macOS: added `macClickablePointer()` (`PointerStyle.link`) and applied it across toolbars, settings, email/meetings/create flows, the AI panel, and other plain-style buttons; regenerated `TodusMac.xcodeproj` so `MacClickablePointer.swift` is included in the target.
