---
id: 0470
title: "iOS AI chat thumbs up/down goes nowhere"
status: open
priority: P4
tags: [ios, todo-sweep, ai]
files: [apps/ios/Todus/Todus/Features/AI/AIChatView.swift]
created: 2026-07-25
source: code TODO/FIXME sweep
---

`AIChatView.swift:2575` — `TODO(P4): Wire thumbs up/down to a chat-feedback endpoint.` The control renders and reacts locally but no feedback leaves the device.

## Fix shape

Add a feedback procedure on the AI router and post `{ conversationId, messageId, rating }`, or hide the control until there is somewhere to send it.
