---
id: 0155
title: "AI — Second-brain briefing, open loops, and prepared work"
status: archived
category: Changed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] AI — Second-brain briefing, open loops, and prepared work

### Backend (`apps/server`)

- **Second-brain assistant domain:** Added a new `assistant` router that turns mail/meeting/task context into durable assistant state instead of one-off thread heuristics.
- **Open-loop ledger:** Added persisted assistant open loops for needs-reply, waiting-on, deadline-risk, meeting follow-up, decision-needed, draft-ready, and research-needed states.
- **Prepared actions:** Added persisted prepared actions for reply drafts, task creation, event creation, follow-ups, and research so the assistant can queue work for approval.
- **Structured memory:** Added people-memory and workstream-memory tables so the assistant can remember relationship context, recent communication, unresolved asks, and workstream status.
- **Briefing API:** Added `assistant.getBriefing`, `assistant.listOpenLoops`, `assistant.getThreadContext`, `assistant.getPersonContext`, `assistant.getWorkstreamContext`, `assistant.listPreparedActions`, `assistant.generateDraft`, `assistant.applyPreparedAction`, `assistant.snoozeOpenLoop`, `assistant.dismissOpenLoop`, `assistant.recordFeedback`, and `assistant.getChangeFeed`.
- **Compatibility:** Kept existing `mailAssistant.*` APIs intact while allowing the new thread/inbox surfaces to read from the broader assistant state.

### Web (`apps/mail`)

- **Home becomes a briefing surface:** Home now shows assistant priorities, Needs You, Waiting On, Prepared work, and recent changes before the generic dashboard sections.
- **Inbox becomes queue-oriented:** Mail assistant nudges now come from grouped open-loop queues instead of looser thread-only nudges.
- **Thread context upgraded:** The thread assistant card now uses `assistant.getThreadContext`, showing recommendation, waiting state, changed-since-last-open, related people context, linked work, and prepared actions.
- **Assistant settings expanded:** Settings now expose briefing-engine controls, Home briefing visibility, waiting-on tracking, people memory, batch approvals, workday hours, and excluded sender/topic patterns in addition to the existing summary/draft/auto-send controls.

### iOS (`apps/ios/Todus`)

- **Home briefing parity:** Home now conditionally loads and shows the assistant briefing sections when the briefing engine is enabled.
- **Thread context parity:** Email thread assistant surfaces now use the richer second-brain context shape with recommendation, people context, changed-since-last-open, and prepared-draft awareness.
- **Settings parity:** The AI settings page now exposes the second-brain operating model, including briefing controls, waiting-on tracking, people memory, batch approvals, workday timing, and noise filtering.

### macOS (`apps/macos`)

- **Home briefing parity:** macOS Home now respects the same briefing-engine gating and shows the same prepared-work framing as web/iOS.
- **Settings parity:** macOS settings now expose the new assistant operating model and workday/noise-filter controls.
- **Target graph stabilization:** Added `AppLogger.swift` back into the macOS Xcode target and fixed follow-on compile issues in meetings/tasks/assistant-panel paths discovered during the second-brain verification build.

### Verification

- `pnpm exec tsc -p apps/mail/tsconfig.json --noEmit` filtered to the changed assistant files produced no matches for [mail-display.tsx](/Users/ludvighedin/Programming/personal/mail/apps/mail/components/mail/mail-display.tsx), [mail.tsx](/Users/ludvighedin/Programming/personal/mail/apps/mail/components/mail/mail.tsx), [home/page.tsx](</Users/ludvighedin/Programming/personal/mail/apps/mail/app/(routes)/mail/home/page.tsx>), and [settings/general/page.tsx](</Users/ludvighedin/Programming/personal/mail/apps/mail/app/(routes)/settings/general/page.tsx>).
- `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator build CODE_SIGNING_ALLOWED=NO` [Passed]
- `xcodebuild -project apps/macos/TodusMac.xcodeproj -scheme TodusMac -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO` [Passed]
