---
id: 0104
title: "Redesign — Unified Create Sheet (merged CaptureComposer into CreateSheet)"
status: archived
category: Changed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Redesign — Unified Create Sheet (merged CaptureComposer into CreateSheet)

**Problem:** Two competing input systems (CaptureComposer in tasks tab + CreateSheet global overlay) overlapped visually. CaptureComposer sat under the tab bar and was unusable. CreateSheet lacked attachments, voice, and slash commands.

**Solution:** Removed CaptureComposer from tasks tab entirely. Merged all its features into CreateSheet:

- Attachments (photo picker, camera, file picker) with inline thumbnails
- Voice transcription (VoiceInputButton)
- Slash commands (/due-today, /due-tomorrow, /due-next-week, /in-one-hour)
- Image paste handling (PasteHandlingTextInput)
- Keyboard-aware positioning

**Visual improvements:**

- Scrim opacity 0.10 → 0.45 (clearly distinguishable modal overlay)
- Text input 28pt → 16pt (compact, not oversized)
- Default type always "Auto" (AI decides) regardless of which tab
- Tight, clean toolbar with folder/date/voice/send in a single row

**Files:**

- `CreateSheet.swift` — Major rewrite with all merged features
- `TasksTabView.swift` — Removed CaptureComposer and keyboard observer
- `MainTabView.swift` — Removed defaultType parameter and method
- `CaptureComposer.swift` — Removed CaptureComposer struct; kept shared types (RichComposerInput, PasteHandlingTextInput, CameraPicker)
