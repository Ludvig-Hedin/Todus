---
id: 0321
title: "Fixed — iOS AI chat sheet composer/layout"
status: unreleased
category: Fixed
release_date: 2026-07-23
source: CHANGELOG.md
---

### Fixed — iOS AI chat sheet composer/layout, 2026-07-23

- AI chat sheet (`AIChatView`): removed the model/Gmail/Calendar status pills and the shuffle button from the empty state to de-clutter; the send button now reads as an intentional quiet button when empty (neutral fill + muted glyph) instead of a washed-out disabled accent; added bottom breathing room under the composer in the collapsed state; and focusing the input now expands the sheet from `.medium` to `.large` so the composer's button row clears the keyboard instead of hiding behind it (multi-line input grows upward, not down). Sheet detents are now owned by `AIChatView` rather than each call site.
- Chat history sheet search bar is now legible: added a gradient scrim that fades the list rows out behind the pinned pill, a drop shadow, and a stronger border (it previously blended into the scrolling rows).
