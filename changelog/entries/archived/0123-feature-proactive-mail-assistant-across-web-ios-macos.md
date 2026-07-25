---
id: 0123
title: "Feature — Proactive Mail Assistant across web + iOS + macOS"
status: archived
category: Added
release_date: 2026-03-31
source: CHANGELOG.md
---

## [2026-03-31] Feature — Proactive Mail Assistant across web + iOS + macOS

### Backend — shared assistant layer + settings policy

- Added `mailAssistant` tRPC router with per-thread recommendations (`getThread`), inbox nudges (`getInboxNudges`), manual apply actions (`createTaskFromSuggestion`, `createEventFromSuggestion`), draft generation (`generateDraft`), and assistant activity logging (`logActivity`, `getActivity`).
- Added shared `assistantAutomationPolicy` settings schema with defaults for summaries, task/event suggestions, smart nudges, auto-drafts, and the opt-in auto-send experiment.
- Settings now deep-merge the nested assistant policy so older settings payloads stay backward-compatible.
- Draft generation reuses the existing compose pipeline and thread context; assistant activity is stored in KV for lightweight audit history without a schema migration.

### Web — proactive thread + inbox UX

- Replaced the passive summary block with a visible `Mail Assistant` card in thread view: summary, action-item detection, risk/confidence badges, suggested tasks/events, reply draft action, research entry point, and copy/refresh controls.
- Added inline per-message assistant actions for task creation, event creation, assistant handoff, and research.
- Added inbox-level assistant nudges above the thread list so users see reply-needed / meeting-request / follow-up / draft-ready prompts before opening a thread.
- Added mail assistant controls to General Settings with recommended defaults, nested policy toggles, quiet hours, and allowed auto-send scenarios.

### iOS

- Added native assistant models plus email-service calls for thread recommendations, inbox nudges, task/event creation, and assistant draft generation.
- Email thread now shows a top-level assistant card with summarize, extract-task, create-event, draft-reply, ask-assistant, and research actions.
- Email inbox now surfaces compact assistant nudges above the thread list.
- AI Assistant settings now include mail-assistant automation toggles and persist them through shared backend settings.

### macOS

- Added native assistant models plus email-service calls for thread recommendations, inbox nudges, task/event creation, and assistant draft generation.
- macOS thread sheets now show a visible assistant card and inline assistant controls.
- macOS inbox now surfaces assistant nudges above the thread list.
- macOS settings now expose the assistant automation toggles and recommended preset.

**User-facing:** Mail now behaves more like an assistant than a passive inbox. Users can summarize threads, extract tasks, create events, draft replies, and act on proactive nudges across web, iOS, and macOS.

**Files:** `apps/server/src/lib/schemas.ts`, `apps/server/src/trpc/routes/settings.ts`, `apps/server/src/trpc/routes/mail-assistant.ts` (new), `apps/server/src/trpc/index.ts`, `apps/mail/components/mail/mail-display.tsx`, `apps/mail/components/mail/mail.tsx`, `apps/mail/app/(routes)/settings/general/page.tsx`, `apps/ios/Todus/Todus/Domain/MailAssistantModels.swift` (new), `apps/ios/Todus/Todus/App/AppServices.swift`, `apps/ios/Todus/Todus/Navigation/MainTabView.swift`, `apps/ios/Todus/Todus/Services/Email/EmailService.swift`, `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift`, `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`, `apps/ios/Todus/Todus/Features/Email/EmailComposeView.swift`, `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`, `apps/macos/TodusMac/Domain/MailAssistantModels.swift` (new), `apps/macos/TodusMac/App/MacAppServices.swift`, `apps/macos/TodusMac/App/MacRootView.swift`, `apps/macos/TodusMac/Services/Email/EmailService.swift`, `apps/macos/TodusMac/Views/Email/MacEmailThreadView.swift`, `apps/macos/TodusMac/Views/Email/MacEmailInboxView.swift`, `apps/macos/TodusMac/Views/Email/MacEmailComposeView.swift`, `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`, `TASK.md`
