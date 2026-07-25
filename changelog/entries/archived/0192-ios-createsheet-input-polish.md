---
id: 0192
title: "iOS CreateSheet Input Polish"
status: archived
category: Changed
release_date: 2026-04-04
source: CHANGELOG.md
---

## [2026-04-04] iOS CreateSheet Input Polish

- [Fix] Capped `PasteHandlingTextInput` at `maxHeight: 120` in `CreateSheet` — eliminates unbounded layout growth that caused lag and the sheet appearing too tall (`CreateSheet.swift`, `CaptureComposer.swift`)
- [Fix] Removed helper copy ("Write naturally. Todus will sort it.") — sheet is now compact like the AI chat input (`CreateSheet.swift`)
- [Fix] Fixed placeholder-below-cursor bug: `textViewDidBeginEditing` now calls `invalidateIntrinsicContentSize()` + `setContentOffset(.zero)` after clearing placeholder text (`CaptureComposer.swift`)
- [Fix] Keyboard positioning uses `max(keyboard.height + 8, 86)` instead of conditional — removes redundant layout pass when keyboard height changes (`CreateSheet.swift`)
