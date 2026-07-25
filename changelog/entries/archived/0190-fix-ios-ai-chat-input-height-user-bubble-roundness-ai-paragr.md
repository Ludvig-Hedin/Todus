---
id: 0190
title: "Fix — iOS AI chat: input height, user bubble roundness, AI paragraph spacing"
status: archived
category: Fixed
release_date: 2026-04-04
source: CHANGELOG.md
---

## [2026-04-04] Fix — iOS AI chat: input height, user bubble roundness, AI paragraph spacing

- **Input height reduced:** Tightened padding in `chatInputBox` — text field top/bottom padding reduced, button row bottom padding reduced, pill row padding reduced. Input is now more compact.
- **User bubbles more round:** Increased corner radius from 16 → 20 and reduced vertical padding from 12 → 10. Single-line messages now appear capsule/pill-shaped (cornerRadius ≈ height/2).
- **AI paragraph spacing:** Added 6pt `paragraphSpacing` via `NSParagraphStyle` to the markdown `AttributedString`. SwiftUI's `Text` has no default gap between CommonMark paragraphs, making AI responses appear as a single blob. This preserves heading-specific paragraph styles via `enumerateAttribute`.

**Files:** `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`
