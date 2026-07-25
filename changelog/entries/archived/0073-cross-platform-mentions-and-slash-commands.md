---
id: 0073
title: "Cross-platform mentions and slash commands"
status: archived
category: Changed
release_date: 2026-03-28
source: CHANGELOG.md
---

## [2026-03-28] Cross-platform mentions and slash commands

### New Features

- **Shared mention model**: Added shared `MentionKind` / `MentionRef` types in `packages/shared` so web, server, and iOS use the same structured mention payload.
- **Server mention search**: Added `mentions.search` tRPC route for task, thread, and person lookup with grouped results and stable IDs. Event mentions remain feature-gated on web until a web provider exists.
- **AI mention context**: `/ai/chat` and the web agent route now accept optional `mentions` arrays and inject compact structured mention context into the current user turn before model execution.
- **Web TipTap mentions and slash commands**: The active shared editor hook now supports `@` mentions, `/` commands, human-readable mention chips, and per-surface command ordering for email compose and AI chat.
- **Web submit serialization**: Email compose now strips mention metadata to readable text before send; AI chat extracts mention refs separately and submits them as structured context.
- **iOS rich input**: Added a reusable `UITextView`-backed rich composer input with shared slash command definitions, inline mention highlighting, and reuse across task capture, email compose, and AI chat.
- **iOS mention-aware AI requests**: Native AI chat now collects mention refs and includes them in the backend payload alongside the visible user message.

### Architectural Notes

- **Shared slash semantics**: iOS task capture now derives slash actions from the same shared command model used by the new rich input surfaces instead of maintaining a one-off command list.
- **Compose signature command**: Email compose now supports `/signature` using the currently active native signature.

### Verification

- `pnpm --filter @zero/mail exec tsc --noEmit --pretty false` narrowed to the edited mail files reports no errors.
- `pnpm --filter @zero/server exec tsc --noEmit --pretty false` narrowed to the edited server files reports one pre-existing unrelated overload error in `apps/server/src/routes/agent/index.ts`.
- `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -configuration Debug -sdk iphonesimulator -derivedDataPath /tmp/todus-codex-derived-data build CODE_SIGNING_ALLOWED=NO` was started to validate the edited Swift files in an isolated build directory.
