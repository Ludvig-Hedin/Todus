---
id: 0465
title: "Group chat is polling-based; realtime needs a Durable Object room"
status: open
priority: P3
tags: [server, web, macos, todo-sweep, realtime]
files: [apps/server/src/trpc/routes/groups.ts, apps/web/components/ui/group-chat-view.tsx, apps/macos/TodusMac/Views/AI/MacGroupChatView.swift]
created: 2026-07-25
source: code TODO/FIXME sweep
---

Three matching `TODO(realtime)` comments describe the same missing piece: group chat refetches on a 5s poll because there is no Durable Object room to broadcast into.

```
apps/server/src/trpc/routes/groups.ts:71   // TODO(realtime): When Durable Object rooms are added for group chat, move this
apps/server/src/trpc/routes/groups.ts:348  // TODO(realtime): switch to Durable Object WebSocket broadcast here
apps/web/components/ui/group-chat-view.tsx:43
apps/macos/TodusMac/Views/AI/MacGroupChatView.swift:7
```

## Fix shape

Add a `GroupRoom` Durable Object (the codebase already runs `ZeroAgent`/`ZeroDB`/`ShardRegistry`), broadcast on message insert, and swap both clients from poll to WebSocket. Server and both clients must land together.
