---
id: 0217
title: "Fix — iOS AI chat composer focus (keyboard / + button)"
status: archived
category: Fixed
release_date: 2026-04-24
source: CHANGELOG.md
---

## [2026-04-24] Fix — iOS AI chat composer focus (keyboard / + button)

- [Fix] Removed a `ScrollView` `simultaneousGesture` that resigned the keyboard on every tap; that gesture also hit-tested the bottom `safeAreaInset` input row, so taps on the text field, padding, or the + button dismissed the keyboard and interfered with double-tap-to-copy on messages.
- [Fix] The full-screen clear tap layer now only appears for the attachment picker (not while the field is focused); the input box uses a `simultaneousGesture` tap to request focus without stealing the UITextView’s first touch.
- [Fix] The + attachment source popover can be dismissed by tapping outside it: a dimming scrim is applied in `.overlay` above the message/empty content _before_ `.safeAreaInset`, so it receives taps (unlike a `ZStack` layer behind the chat) and does not cover the input bar or popover.
- **Files:** `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`
