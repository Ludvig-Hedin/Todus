---
id: 0443
title: "Parity Gap Tasks (2026-03-01)"
status: done
tags: [task-md, sprint]
files: [apps/ios/app/(auth)/signup.tsx, apps/ios/app/(auth)/_layout.tsx, apps/ios/TEST_PLAN_PARITY.md]
created: 2026-03-01
source: TASK.md
---

> Source context: TASK.md

> Section overview — individual items from this section are separate files.

## Parity Gap Tasks (2026-03-01)

| ID     | Task                                                                                                                                      | Status | Notes                                                                                                                                                                          |
| ------ | ----------------------------------------------------------------------------------------------------------------------------------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| PG-001 | Implement native public route set parity (`/`, `/home`, `/about`, `/terms`, `/pricing`, `/privacy`, `/contributors`, `/developer`, `/hr`) | DONE   | Completed historically; these public WebView wrapper routes were later deprecated/removed in `N8-05` as part of native wrapper-flow cleanup                                    |
| PG-002 | Add native `/signup` parity flow                                                                                                          | DONE   | Added native auth signup route/screen in `apps/ios/app/(auth)/signup.tsx` and wired it in `apps/ios/app/(auth)/_layout.tsx`                                                    |
| PG-003 | Complete native mail shell parity for `/mail/:folder`                                                                                     | DONE   | Category tabs + bulk selection + command palette/search entry points now implemented in native mail shell                                                                      |
| PG-004 | Implement `/mail/create` and `/mail/under-construction/:path` parity behaviors                                                            | DONE   | Native create redirect now forwards web-style prefill params to compose; under-construction fallback now matches web behavior                                                  |
| PG-005 | Rebuild native compose parity (`/mail/compose`)                                                                                           | DONE   | Compose parity shipped with rich text, attachments, drafts, reply/reply-all/forward, undo-send, schedule send, and templates                                                   |
| PG-006 | Add native mailto parity (`/api/mailto-handler`)                                                                                          | DONE   | Native `/api/mailto-handler` parses mailto payloads, attempts draft creation, and opens compose with fallback params + `draftId` when available                                |
| PG-007 | Complete settings parity for missing sections                                                                                             | DONE   | Native forms added for `/settings/categories`, `/settings/notifications`, `/settings/privacy`, `/settings/security`, `/settings/shortcuts`, `/settings/danger-zone`            |
| PG-008 | Upgrade native existing settings sections from partial to full parity                                                                     | DONE   | `/settings/general`, `/settings/appearance`, `/settings/connections`, `/settings/labels` upgraded with parity-focused forms/actions                                            |
| PG-009 | Implement labels/categories CRUD + assignment parity in native                                                                            | DONE   | Labels CRUD + color selection and category default/order/filter editing implemented                                                                                            |
| PG-010 | Implement native AI assistant and voice parity                                                                                            | DONE   | Native assistant now has practical parity for iOS workflows: streaming chat, dictation + transcription, playback, auto-read, hands-free loop, and auth-bypass-safe fallback UX |
| PG-011 | Implement native integrations parity: PostHog + Dub + Sentry + Autumn                                                                     | DONE   | Autumn billing customer/checkout/portal native integration added; Dub attribution stays server-side through existing better-auth plugin used by native auth flow               |
| PG-012 | Establish screenshot-driven visual regression proof in `/parity_screenshots/`                                                             | DONE   | Naming convention + manifest + diff log + verifier are implemented, and required iOS-scope coverage passes (`web` + `ios`: `46/46`)                                            |
| PG-013 | Build parity-focused automated tests (unit/integration/E2E)                                                                               | DONE   | Added Autumn integration tests to iOS unit suite and documented RC E2E/manual parity workflow script in `apps/ios/TEST_PLAN_PARITY.md`                                         |
| PG-014 | Resolve macOS architecture blocker                                                                                                        | DONE   | De-scoped from this stream because current migration goal is iOS-native parity (`apps/ios`); macOS architecture work is tracked separately outside this iOS backlog            |
