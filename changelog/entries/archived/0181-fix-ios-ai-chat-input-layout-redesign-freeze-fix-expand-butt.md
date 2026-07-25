---
id: 0181
title: "Fix — iOS AI chat input: layout redesign, freeze fix, expand button"
status: archived
category: Fixed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] Fix — iOS AI chat input: layout redesign, freeze fix, expand button

- Redesigned chat input to two-row layout: full-width text field on top, button row below. Eliminates the squeezed text field issue and aligns text to the left edge.
- Fixed 9+ second freeze caused by a GeometryReader layout cycle — the old single-row HStack toggled `inputAtMaxHeight` which changed text field width → height → retrigger → infinite loop. New layout isolates text and buttons into separate VStack rows.
- Fixed transcribe button freezing the UI by moving `AVAudioSession.setActive` off the main actor with `Task.detached` in `VoiceController.beginAudioSession()`.
- Fixed full-screen compose sheet causing a 5-second hang by delaying keyboard focus until after the sheet presentation animation finishes (~350ms).
- Full-screen expand button is now only shown when the text input has reached its maximum height (≥118pt), with consistent 30×30 sizing matching other buttons.
- Reduced excessive vertical padding in the input box.

**Files:** `apps/ios/Todus/Todus/Features/Voice/VoiceInputButton.swift`, `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`
