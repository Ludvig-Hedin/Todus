---
id: 0115
title: "Polish — iOS AI assistant input bar refinements"
status: archived
category: Changed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Polish — iOS AI assistant input bar refinements

Five targeted UX improvements to the iOS AI chat input area:

- **Tighter button sizing**: Standardized all action buttons (waveform, mic, send) to consistent 34×34 outer frames with 6pt spacing (was mixed 36/30 with 4/8pt spacing)
- **Tap-outside to blur**: Tapping anywhere in the chat area now resigns keyboard focus (previously only dismissed attachment picker)
- **Top-right toolbar breathing room**: Reduced HStack spacing to 16pt and added 2pt trailing padding on ellipsis for less cramped feel
- **Hidden send button when empty**: Send button now hidden (not just faded) when input is empty; appears with scale+opacity transition when content is typed or file attached
- **File-only send**: Users can attach and send files/images without any text; auto-generates "View the attached file" prompt when sending attachments alone

**Files changed:**

- `apps/ios/Todus/Todus/Features/AI/AIChatView.swift` — All five changes in inputSection, chatInputBox, toolbarContent, sendMessage(), ChatVoiceInputButton
