# Todus — Feature Test Plan

Per-feature test checklist for [FEATURES.md](FEATURES.md). Section numbers mirror that file (web=1, backend=2, iOS=3, macOS=4).

Scope: web (browser e2e), backend (Vitest + integration), iOS (XCTest + simulator), macOS (XCTest + parity screenshots). Uses existing infra only — no new frameworks added.

> Last updated: 2026-05-27.

## How to Run Tests

### Web (browser)
- **Preview MCP**: `preview_start`, `preview_click`, `preview_fill`, `preview_snapshot`, `preview_console_logs`, `preview_network`, `preview_screenshot`, `preview_resize`. Use for any browser-driven test in this doc.
- **Unit (Vitest)**: `pnpm test -- -t "<name>"` from repo root; suites live in [packages/testing](packages/testing).
- **Local stack**: `pnpm go` (Docker Postgres + `apps/web` + backend) or `pnpm web` (assumes Postgres already up). `apps/web` serves the full surface — marketing + auth + `/mail/*` + `/settings/*` — in one app. `pnpm mail` boots the legacy `apps/mail` archive (reference only, do not edit).

### Backend
- **Vitest**: `pnpm test`, `pnpm test:ai`, `pnpm eval`, `pnpm eval:dev`, `pnpm eval:ci`.
- **Local dev**: `pnpm go` (Postgres + worker).
- **Manual API**: `curl` against `http://localhost:8787` or trigger tRPC procedures through the web client.

### iOS
- **Simulator**: `pnpm ios:simulator` (interactive); `pnpm ios` (lighter app start).
- **Builds**: `pnpm ios:build:preview`, `pnpm ios:build:production`.
- **XCTest**: open [apps/ios/Todus/Todus.xcodeproj](apps/ios/Todus/Todus.xcodeproj) → `⌘U`.
- **Parity screenshots**: `pnpm parity:screenshots:capture:ios:auto`, `pnpm parity:screenshots:check`.
- **Deep link probe**: [scripts/parity/capture-ios-deeplink.mjs](scripts/parity/capture-ios-deeplink.mjs).

### macOS
- **Run**: `pnpm macos`.
- **XCTest**: open the macOS project → `⌘U`.
- **Parity screenshots**: `pnpm parity:screenshots:capture:macos:auto`, `pnpm parity:screenshots:check`.

---

## 1. Web Test Cases

Boot `apps/web` with `pnpm dev` (or `pnpm go` for the full local stack), attach Preview MCP via `preview_start`, then run each test below.

### 1.1 Marketing & Public Routes

Smoke test: each route returns 200, no console errors, key heading visible.

| Feature | Route | Steps | Expected | Tool |
| --- | --- | --- | --- | --- |
| Landing | `/` | `preview_start /` → `preview_snapshot` | Hero copy visible, no `console.error` | Preview MCP |
| Home | `/home` | navigate, snapshot | Heading + CTA visible | Preview MCP |
| About | `/about` | navigate, snapshot | About content rendered | Preview MCP |
| Pricing | `/pricing` | navigate, click monthly/annual toggle | Plans render; price updates on toggle | Preview MCP |
| Terms | `/terms` | navigate, snapshot | Terms text rendered | Preview MCP |
| Privacy | `/privacy` | navigate, snapshot | Privacy text rendered | Preview MCP |
| Downloads | `/downloads` | navigate, snapshot | App download links visible | Preview MCP |
| Contact | `/contact` | fill form, submit | `contact.submit` tRPC fires; success toast | Preview MCP + `preview_network` |
| Contributors | `/contributors` | navigate | List renders | Preview MCP |
| FAQ | `/faq` | navigate, expand accordion | Items expand | Preview MCP |
| HR | `/hr` | navigate | Careers page renders | Preview MCP |
| Blog index | `/blog` | navigate | Post list renders | Preview MCP |
| Blog post | `/blog/:slug` | navigate to valid slug | Post body renders | Preview MCP |
| Compare | `/compare/:competitor` | navigate to known competitor | Comparison table renders | Preview MCP |
| Shared conversation | `/share/:slug` | open with valid slug | Read-only chat renders | Preview MCP |
| Group invite | `/g/:token` | open with valid token | Join CTA visible | Preview MCP |

### 1.2 Auth

| Feature | Route | Steps | Expected | Tool |
| --- | --- | --- | --- | --- |
| Login page renders | `/login` | navigate | Form + provider buttons present | Preview MCP |
| Google sign in (happy) | `/login` | click "Sign in with Google" | Redirect to Google OAuth | `preview_network` |
| Apple sign in (happy) | `/login` | click "Sign in with Apple" | Redirect to Apple OAuth | `preview_network` |
| Email OTP send | `/login` | enter email, request OTP | `auth/email-otp/send-verification-otp` called; success state | Preview MCP |
| Email OTP verify (valid) | `/login` | enter valid OTP | Bearer cookie set; redirect to `/mail/inbox` | Preview MCP |
| Email OTP verify (invalid) | `/login` | enter wrong OTP | Error toast visible | Preview MCP |
| Email/password signup | `/signup` | fill form, submit | Verification email sent; success state | Preview MCP + `preview_network` |
| Signed-out access guard | `/mail/inbox` (no session) | navigate | Redirect to `/login` | Preview MCP |

### 1.3 Mail Shell — Folders

| Feature | Route | Steps | Expected | Tool |
| --- | --- | --- | --- | --- |
| Inbox | `/mail/inbox` | navigate (authed) | Thread list loads; `mail.listThreads` succeeds | Preview MCP + `preview_network` |
| Draft | `/mail/draft` | navigate | Drafts list loads | Preview MCP |
| Sent | `/mail/sent` | navigate | Sent thread list | Preview MCP |
| Archive | `/mail/archive` | navigate | Archive list | Preview MCP |
| Spam | `/mail/spam` | navigate; click "Empty spam" | `mail.deleteAllSpam` called; list empties | Preview MCP |
| Bin | `/mail/bin` | navigate | Trash list | Preview MCP |
| Snoozed | `/mail/snoozed` | navigate | Snoozed list | Preview MCP |
| Custom label | `/mail/:labelId` | navigate to existing label | Filtered list | Preview MCP |
| Custom label invalid | `/mail/nonexistent` | navigate | Redirect / fallback | Preview MCP |
| Folder switch latency | inbox→sent→archive | navigate 3 in a row | All load < 1s | Preview MCP |

### 1.4 Mail Thread Actions

| Action | Steps | Expected | Tool |
| --- | --- | --- | --- |
| Open thread | click row in inbox | `mail.get` returns thread; conversation renders | Preview MCP |
| Mark as read | open unread thread | `mail.markAsRead` called; row no longer bold | `preview_network` |
| Mark as unread | open then click "Mark unread" | `mail.markAsUnread` called | `preview_network` |
| Star | toggle star icon | `mail.toggleStar` called | `preview_network` |
| Bulk star | select multiple, "Star" | `mail.bulkStar` called | `preview_network` |
| Mark important | toggle important | `mail.toggleImportant` called | `preview_network` |
| Bulk archive | select, "Archive" | `mail.bulkArchive` called; rows leave list | Preview MCP |
| Bulk delete | select, "Delete" | `mail.bulkDelete` called | Preview MCP |
| Snooze | open snooze dialog, pick date | `mail.snoozeThreads` called; thread moves to snoozed | Preview MCP |
| Unsnooze | from snoozed folder, "Unsnooze" | `mail.unsnoozeThreads` called | `preview_network` |
| Apply label | label dropdown → pick label | `mail.modifyLabels` called | `preview_network` |
| Reply | open thread, type reply, send | `mail.send` called; new message in thread | Preview MCP |
| Forward | open thread, "Forward", fill recipients, send | `mail.send` called | Preview MCP |
| Unsend | send → immediately click "Undo" | `mail.unsend` called within window | Preview MCP |
| Get attachments | open thread with attachment | `mail.getMessageAttachments` called; chip visible | `preview_network` |
| Download raw | "Download original" | `mail.getRawEmail` called; file downloads | `preview_network` |

### 1.5 Compose

| Feature | Route | Steps | Expected | Tool |
| --- | --- | --- | --- | --- |
| Open composer | `/mail/compose` | navigate | Editor mounts | Preview MCP |
| Recipient autosuggest | type in "To" | `mail.suggestRecipients` called; dropdown shows | `preview_network` |
| Subject AI | click "AI subject" | `ai.generateEmailSubject` called; subject populated | `preview_network` |
| AI compose | click "AI draft", enter prompt | `ai.compose` called; body populated | `preview_network` |
| Save draft | type body, blur | `drafts.create`/`drafts.update` called | `preview_network` |
| List drafts | open drafts | `drafts.list` returns | `preview_network` |
| Delete draft | swipe / "Delete" on draft | `drafts.delete` called | `preview_network` |
| Schedule send | open "Schedule", pick datetime | KV `scheduled_emails` entry created; queued for later | Preview MCP + manual KV check |
| Send now | click "Send" | `mail.send` called; toast | `preview_network` |
| Template insert | click "Templates", pick one | Body fills with template content | Preview MCP |
| Image upload | drag image | Uploads; thumbnail visible | Preview MCP |
| `/` command palette | type `/` in editor | Command menu opens | Preview MCP |

### 1.6 AI Chat / Generative UI

| Feature | Route | Steps | Expected | Tool |
| --- | --- | --- | --- | --- |
| Open chat | `/mail/chat` or AI sidebar | navigate / toggle | Empty chat renders | Preview MCP |
| Send message | type, send | SSE stream from `/sse/:sessionId`; response streams | `preview_network` |
| Save conversation | trigger "Save" | `ai.saveConversation` called | `preview_network` |
| List conversations | open conversation list | `ai.listConversations` returns | `preview_network` |
| Load conversation | click prior conversation | `ai.getConversation` returns; renders | `preview_network` |
| Delete conversation | overflow → delete | `ai.deleteConversation` called | `preview_network` |
| Generative card — Email | trigger email-suggestion response | EmailCard renders inline | Preview MCP + `preview_snapshot` |
| Generative card — Task | trigger task-suggestion | TaskCard renders; "Add" creates task via `tasks.create` | Preview MCP |
| Generative card — Calendar event | trigger event-suggestion | CalendarEventCard renders; "Add" via `calendar.createEvent` | Preview MCP |
| Generative card — Code | trigger code response | CodeBlockCard renders with syntax highlight | Preview MCP |
| Generative card — URL preview | paste URL | URLPreviewCard unfurls | Preview MCP |
| Web search | "search the web for X" | `ai.webSearch` called (Perplexity); result returned | `preview_network` |
| Voice transcribe | upload audio | `ai.transcribeAudio` called | `preview_network` |
| Shared link | open `/share/:slug` | Read-only render of shared chat | Preview MCP |

### 1.7 Calendar

| Feature | Route | Steps | Expected | Tool |
| --- | --- | --- | --- | --- |
| Calendar view | `/mail/calendar` | navigate | Grid renders | Preview MCP |
| Load events | navigate to current week | `calendar.events` / `calendar.eventsMulti` called | `preview_network` |
| Create event | click slot, fill form, save | `calendar.createEvent` called | `preview_network` |
| Update event | drag/resize | `calendar.updateEvent` called | `preview_network` |
| Delete event | open event, delete | `calendar.deleteEvent` called | `preview_network` |
| Multi-account | enable 2 accounts | Events from both render | Preview MCP |

### 1.8 Tasks

| Feature | Steps | Expected | Tool |
| --- | --- | --- | --- |
| Tasks page | `/mail/tasks` | List renders via `tasks.list` | Preview MCP |
| Create task | input + enter | `tasks.create` called; row appears | `preview_network` |
| Update task | edit title, blur | `tasks.update` called | `preview_network` |
| Delete task | remove | `tasks.delete` called | `preview_network` |
| Reorder | drag | `tasks.reorder` called | `preview_network` |
| Folders | create / pick folder | `folders` router CRUD | `preview_network` |
| Summary | open summary | `tasks.summary` returns counts | `preview_network` |
| Add to folder | drag task → folder | `tasks.addItem` called | `preview_network` |
| Remove from folder | drag out | `tasks.removeItem` called | `preview_network` |
| List contents | open folder | `tasks.listContents` returns | `preview_network` |

### 1.9 Meetings

| Feature | Steps | Expected | Tool |
| --- | --- | --- | --- |
| List | `/mail/meetings` | `meet.listMeetings` returns | Preview MCP |
| Detail | open meeting | `meet.getMeeting` returns + transcript | Preview MCP |
| Schedule bot | click "Send bot" on event | `meet.scheduleBot` called | `preview_network` |
| Cancel bot | "Cancel bot" | `meet.cancelBot` called | `preview_network` |
| Generate summary | "Summarize" | `meet.generateSummary` called | `preview_network` |
| Ask question | type Q on transcript | `meet.askQuestion` called; answer streams | `preview_network` |
| Sync from calendar | "Sync now" | `meet.syncFromCalendar` called | `preview_network` |
| Configure integration | settings/meetings | `meet.upsertIntegration` called | `preview_network` |

### 1.10 Docs

| Feature | Steps | Expected | Tool |
| --- | --- | --- | --- |
| Docs list | `/mail/docs` | `docs.list` returns | Preview MCP |
| Open doc | click doc | `docs.get` returns; Tiptap mounts | Preview MCP |
| Edit | type, blur | `docs.update` called (debounced) | `preview_network` |
| Create | "New doc" | `docs.create` called | `preview_network` |
| Delete | overflow → delete | `docs.delete` called | `preview_network` |
| Search | type in search | `docs.search` called | `preview_network` |

### 1.11 Settings — Per Page

For each row: page renders, form submit hits the right tRPC procedure, persisted value survives reload.

| Page | Route | Procedure exercised | Tool |
| --- | --- | --- | --- |
| Index | `/settings` | render only | Preview MCP |
| General | `/settings/general` | `settings.save` | `preview_network` |
| Appearance | `/settings/appearance` | `settings.save` (theme); local storage | Preview MCP |
| Connections | `/settings/connections` | `connections.list`, `setDefault`, `updateColor`, `delete` | `preview_network` |
| Categories | `/settings/categories` | `categories.defaults` | `preview_network` |
| Labels | `/settings/labels` | `labels.create/update/delete/list` | `preview_network` |
| Signatures | `/settings/signatures` | `settings.save` | `preview_network` |
| Notifications | `/settings/notifications` | `settings.save` | `preview_network` |
| Privacy | `/settings/privacy` | `cookiePreferences.getPreferences`/`updatePreferences` | `preview_network` |
| Security | `/settings/security` | `sessions.list`, `revoke`, `revokeAll` | `preview_network` |
| Shortcuts | `/settings/shortcuts` | `shortcut.update` | `preview_network` |
| Sharing | `/settings/sharing` | `sharing.listMine`, `revoke` | `preview_network` |
| Meetings | `/settings/meetings` | `meet.upsertIntegration` | `preview_network` |
| AI | `/settings/ai` | `settings.save` | `preview_network` |
| Local models | `/settings/local-models` | `settings.save` | `preview_network` |
| Billing | `/settings/billing` | `subscription.getStatus`, `getPricingTable`, `getBillingPortalUrl` | `preview_network` |
| Calendars | `/settings/calendars` | `calendar.calendars` + `settings.save` | `preview_network` |
| Danger zone | `/settings/danger-zone` | `user.delete` (DO NOT auto-run; manual gated) | manual |
| About | `/settings/about` | render only | Preview MCP |
| Design system | `/settings/design-system` | render only; allowlist gate | Preview MCP |
| Catch-all | `/settings/foo` | renders fallback | Preview MCP |

### 1.12 Developer / Gated

| Feature | Steps | Expected | Tool |
| --- | --- | --- | --- |
| Allowlisted email sees /developer | sign in as allowlisted user, navigate | Page renders | Preview MCP |
| Non-allowlisted blocked | sign in as random user | Redirect / 404 | Preview MCP |
| Design system page allowlist | as above | Same gate behavior | Preview MCP |

### 1.13 Components — Spot Tests

| Component | Test | Tool |
| --- | --- | --- |
| Command palette (⌘K) | press shortcut → palette opens; type → filters | Preview MCP |
| Keyboard shortcuts dialog | open from settings | Modal renders | Preview MCP |
| AI sidebar toggle | click toggle | Sidebar slides in/out | Preview MCP |
| BIMI avatar | view email from BIMI-enabled sender | Logo renders (via `bimi.getByEmail`) | `preview_network` |
| Recipient autosuggest | type in To/Cc | Dropdown filters | Preview MCP |
| Snooze dialog | open dialog | Date picker works | Preview MCP |
| Share conversation modal | open from chat | Renders w/ link + copy | Preview MCP |
| Pricing dialog | open from billing CTA | Renders Autumn table | Preview MCP |
| Theme switcher | toggle dark/light | `html` class flips | `preview_inspect` |

### 1.14 mailto Handler

| Feature | Steps | Expected | Tool |
| --- | --- | --- | --- |
| Register mailto | visit registration page | Browser registers handler | manual |
| Open mailto link | click `mailto:foo@bar.com?subject=Hi` | App opens to `/mail/compose` w/ prefilled fields | manual |

---

## 2. Backend Test Cases

Run with `pnpm test`, `pnpm test:ai`, `pnpm eval` (Vitest in [packages/testing](packages/testing)). For end-to-end tRPC verification use the local stack (`pnpm go`).

### 2.1 Auth Endpoints

| Endpoint | Test | Expected | Tool |
| --- | --- | --- | --- |
| `GET /auth/me` (no session) | call without cookie | 401 or null user | Vitest + miniflare |
| `GET /auth/me` (valid session) | call with valid Bearer | Returns user JSON | Vitest |
| `GET /auth/mobile-token` | authed via cookie | Returns Bearer token | Vitest |
| `POST /auth/refresh-native-token` | refresh w/ valid token | New token returned | Vitest |
| `POST /auth/native-email-otp/verify` (valid) | send + verify | Bearer issued; verification row deleted | Vitest |
| `POST /auth/native-email-otp/verify` (invalid) | wrong code | 400; row not deleted | Vitest |
| `POST /auth/native-link-social` | link Google to existing account | New `account` row | Vitest |
| `/auth/*` (Better Auth) | sign-in social Google | OAuth redirect chain | Integration |
| `.well-known/oauth-authorization-server` | GET | Discovery JSON | Vitest |
| `.well-known/openid-configuration` | GET | OIDC JSON | Vitest |

### 2.2 tRPC — Per Procedure

One row per procedure. Tool: `pnpm test` (Vitest) using `serverTrpc().<procedure>(...)` direct caller, with seeded DB.

#### `assistant`
| Procedure | Test | Expected |
| --- | --- | --- |
| `getBriefing` | seeded user with thread | Returns briefing JSON |
| `getChangeFeed` | call twice → check `changedSinceLastTime` | Second call returns diff only |
| `getThreadContext` | with valid threadId | Context JSON |
| `getPersonContext` | with personEmail | Memory JSON |
| `getWorkstreamContext` | with workstreamKey | Workstream memory |
| `listOpenLoops` | seeded loops | Array returned |
| `listPreparedActions` | seeded actions | Array returned |
| `applyPreparedAction` | valid id | Action executes; row removed |
| `dismissPreparedAction` | valid id | Row dismissed |
| `dismissOpenLoop` | valid id | Loop dismissed |
| `snoozeOpenLoop` | id + snoozedUntil | `snoozedUntil` persisted |
| `generateDraft` | thread + prompt | Draft body returned |
| `recordFeedback` | id + feedback | `assistantFeedback` row inserted |

#### `ai`
| Procedure | Test | Expected |
| --- | --- | --- |
| `compose` | prompt + threadMessages | Returns generated body |
| `generateEmailSubject` | body | Returns subject string |
| `generateSearchQuery` | NL query | Returns Gmail-syntax query |
| `webSearch` | query | Returns Perplexity result (mock) |
| `transcribeAudio` | base64 audio | Returns text (mock OpenAI) |
| `listConversations` | seeded | Array (newest first) |
| `getConversation` | id | Conversation w/ messages |
| `saveConversation` | new payload | Row inserted/updated |
| `deleteConversation` | id | Row removed |

#### `mailAssistant`
| Procedure | Test | Expected |
| --- | --- | --- |
| `generateDraft` | thread + intent | Draft returned |
| `createEventFromSuggestion` | suggestion id | Calls calendar create; returns eventId |
| `createTaskFromSuggestion` | suggestion id | Task created |
| `getActivity` | threadId | Activity log |
| `logActivity` | event payload | Log row inserted |
| `getInboxNudges` | seeded inbox | Nudges array |
| `getThread` | threadId | Hydrated thread |

#### `brain`
| Procedure | Test | Expected |
| --- | --- | --- |
| `enableBrain` | connectionId | KV `subscribed_accounts` updated |
| `disableBrain` | connectionId | KV removed |
| `getState` | userId | State JSON |
| `generateSummary` | thread payload | Summary returned + `summary` row inserted |
| `getLabels` | userId | Label list |
| `updateLabels` | new labels | Persists |
| `getPrompts` | userId | Prompts (KV `prompts_storage`) |
| `updatePrompt` | type + content | KV updated |

#### `mail`
| Procedure | Test | Expected |
| --- | --- | --- |
| `listThreads` | folder=inbox | Paginated threads |
| `listThreadsMulti` | 2 connections | Merged results |
| `get` | threadId | Full thread |
| `send` | composed payload | Resend / Gmail send call; returns id |
| `unsend` | within window | Pending send cancelled |
| `delete` | threadId | Thread trashed |
| `deleteAllSpam` | seeded spam | Folder emptied |
| `forceSync` | connectionId | Triggers `SYNC_THREADS_WORKFLOW` |
| `softSync` | connectionId | Uses Gmail history API |
| `rewatchGmail` | connectionId | Re-registers watch |
| `suggestRecipients` | query | Match list |
| `listSenders` | connectionId | Aliases list |
| `getEmailAliases` | — | Aliases |
| `verifyEmail` | alias | Triggers Gmail verify |
| `getMessageAttachments` | messageId | Attachments JSON |
| `getRawEmail` | messageId | Raw RFC822 |
| `processEmailContent` | html body | Sanitized |
| `modifyLabels` | threadId + labels | Labels applied |
| `markAsRead` / `markAsUnread` / `toggleStar` / `bulkStar`/`bulkUnstar` / `markAsImportant` / `toggleImportant` / `bulkMarkImportant`/`bulkUnmarkImportant` / `bulkArchive` / `bulkDelete` / `bulkMute` | invoke w/ seed | State updated; correct provider API called |
| `snoozeThreads` | threads + returnAt | KV `snoozed_emails` entry |
| `unsnoozeThreads` | threads | KV entry removed |

#### `drafts`
`create`, `get`, `list`, `update`, `delete` — CRUD round-trip.

#### `templates`
`create`, `list`, `delete` — CRUD round-trip.

#### `connections`
| Procedure | Test | Expected |
| --- | --- | --- |
| `list` | seeded user | Connections array |
| `getDefault` | — | Default connection |
| `setDefault` | id | Default updated |
| `updateColor` | id + color | Persisted |
| `delete` | id | Cascade delete tokens |

#### `calendar`
`calendars`, `events`, `eventsMulti`, `createEvent`, `updateEvent`, `deleteEvent` — round-trip against Google Calendar mock.

#### `meet`
`listMeetings`, `getMeeting`, `createMeeting`/`create`, `deleteMeeting`, `scheduleBot`, `cancelBot`, `syncFromCalendar`, `getIntegration`, `upsertIntegration`, `generateSummary`, `askQuestion`.

#### `tasks`
`create`, `list`, `update`, `delete`, `sync`, `reorder`, `summary`, `listContents`, `addItem`, `removeItem` — CRUD + ordering.

#### `folders`
`create`, `list`, `update`, `delete` — folder CRUD with color/icon/position; exported alongside `tasksRouter` from [tasks.ts](apps/server/src/trpc/routes/tasks.ts).

#### `notes`
`create`, `list`, `update`, `delete`, `reorder`.

#### `docs`
`create`, `get`, `list`, `update`, `delete`, `search`.

#### `categories`
`defaults` — returns default categories.

#### `labels`
`create`, `list`, `update`, `delete`.

#### `groups`
`create`, `update`, `delete`, `get`, `getByInvite`, `join`, `leave`, `kickMember`, `regenerateInvite`, `listMine`, `sendMessage`, `listMessages` (cursor).

#### `sharing`
`create`, `update`, `get`, `listMine`, `revoke`.

#### `mentions`
`search` — @-mention candidate lookup.

#### `contact`
`submit` — public form; sends via Resend; rate-limited.

#### `user`
`delete` — cascades through connections, accounts, sessions, settings, hotkeys.

#### `settings`
`get`, `save` — round-trip JSON.

#### `subscription`
`getPricingTable`, `getStatus`, `attach`, `cancel`, `refresh`, `getBillingPortalUrl` — Autumn integration (mock).

#### `sessions`
`list`, `revoke`, `revokeAll` — session management.

#### `avatar`
`getByEmail` — avatar lookup.

#### `bimi`
`getByEmail`, `getByDomain` — BIMI logo fetch.

#### `shortcut`
`update` — hotkey persistence.

#### `logging`
`getSessionState`, `getSessionStats`, `clearSession`.

#### `cookiePreferences`
`getPreferences`, `updatePreferences`.

### 2.3 HTTP Endpoints (non-tRPC)

| Endpoint | Test | Expected |
| --- | --- | --- |
| `GET /health` | curl | `{ message: "Todus Server is Up!" }` |
| `GET /` | curl | Redirect to `VITE_PUBLIC_APP_URL` |
| `/sse/:sessionId` | open SSE w/ valid session | Receives heartbeat + AI deltas |
| `/mcp/*` | MCP client connect | Tool list returned |
| `POST /admin/run-migrations` (mode=apply) | admin-auth | Migrations applied; idempotent on rerun |
| `POST /admin/run-migrations` (mode=plan) | admin-auth | Plan only; no rows changed |
| `POST /monitoring/sentry` | post DSN payload | Forwarded; 200 |
| `POST /a8n/notify/:providerId` | post webhook | Routed; queued correctly |
| `POST /webhooks/recall` | post Recall payload (valid sig) | Inserts to `meetingMedia`/`meetingTranscript`; triggers brain |
| `POST /webhooks/recall` (invalid sig) | bad sig | 401 |
| `POST /webhooks/autumn` | post Autumn event | Subscription state updated |
| `/ai/chat` | authed POST w/ message | Streams response |
| `/ai/voice-ping` | GET | 200 |
| `/ai/voice-ws` | WS connect | Voice WS established |
| `/ai/voice/system-prompt` | GET authed | Returns prompt |
| `/ai/do/:action` | POST authed | DO invocation succeeds |
| `/ai/call` | Twilio webhook | Phone call routed |
| `/autumn/customers`, `/attach`, `/cancel`, `/check`, `/track`, `/billing_portal`, `/openBillingPortal`, `/entities`, `/components/pricing_table` | authed proxy calls | Autumn API responses returned |
| `/public/providers` | GET | List of enabled auth providers |

### 2.4 Workflows

| Workflow | Test | Expected |
| --- | --- | --- |
| `SyncThreadsWorkflow` (happy) | invoke w/ valid connectionId | Pages through Gmail; upserts threads; KV `gmail_history_id` updated |
| `SyncThreadsWorkflow` (partial failure) | mock API 500 on page 2 | Workflow retries via Cloudflare Workflows resume; eventual completion |
| `SyncThreadsWorkflow` (resume) | suspend mid-run | Resumes from last checkpoint |
| `SyncThreadsCoordinatorWorkflow` (fan-out) | user w/ 2 connections | Spawns 2 child workflows |

### 2.5 Queue Consumers

| Queue | Test | Expected |
| --- | --- | --- |
| `thread-queue` | enqueue thread payload | `mail0_thread` upserted (idempotent on rerun) |
| `thread-queue` (failure) | enqueue malformed | Dead-letter; no DB mutation |
| `subscribe-queue` | enqueue `{userId, connectionId, threadId}` | `brain.enableBrain` triggered; `assistantPreparedAction` rows added |
| `send-email-queue` | enqueue draft | Resend send call; status KV updated to `sent` |
| `send-email-queue` (Resend failure) | mock 5xx | Retry; status KV stays `pending` until threshold |

### 2.6 Scheduled Handler

| Test | Expected |
| --- | --- |
| Hourly cron polls `scheduled_emails` | Items with `send_at <= now` queued |
| Item not yet due | Stays in KV |
| Item with skewed clock | Randomized delay applied |

### 2.7 Database

| Test | Expected |
| --- | --- |
| Migrate apply on fresh DB | All 40 tables created |
| Migrate apply on existing DB | Idempotent; no errors |
| User cascade delete | Removing `user` cascades to connection/account/session/settings/hotkeys |
| `mail0_` prefix | Every table prefixed (verify via `\dt mail0_*`) |
| Schema → TS types | `pnpm db:generate` produces stable diff or none |

### 2.8 External Integrations (mock + contract)

| Service | Test | Tool |
| --- | --- | --- |
| Resend | mock fetch, send + retry path | Vitest |
| Recall.ai | webhook signature verification + bot lifecycle | Vitest + fixture |
| Autumn | proxy call shape + webhook event types | Vitest |
| OpenAI | Whisper transcription mock | Vitest |
| Anthropic | message endpoint mock | Vitest |
| Perplexity | sonar model call mock | Vitest |
| Gmail | history.list, threads.list, messages.modify mocks | Vitest |
| Microsoft Graph | mail folder fetch mock | Vitest |
| Twilio | webhook POST shape | Vitest |
| ElevenLabs | TTS / voice synthesis mock | Vitest |

---

## 3. iOS Test Cases

Open [apps/ios/Todus/Todus.xcodeproj](apps/ios/Todus/Todus.xcodeproj). Run XCTest via `⌘U`. Use `pnpm ios:simulator` for manual UI verification.

### 3.1 Auth

| Feature | Steps | Expected |
| --- | --- | --- |
| Apple Sign In | tap "Continue with Apple" → consent | Bearer in Keychain; `AuthSessionStore` reflects signed-in |
| Google Sign In | tap "Continue with Google" → ASWebAuth → `todus://auth-callback?token=...` | Bearer in Keychain |
| Email OTP send | enter email, request code | Backend `/auth/native-email-otp/...` called |
| Email OTP verify (valid) | enter code | Bearer in Keychain; tabs render |
| Email OTP verify (invalid) | wrong code | Error message |
| Sign out | settings → log out | Keychain cleared; `AuthView` shown |
| Bearer persists across launches | sign in, force-quit, relaunch | Still signed in |

### 3.2 Onboarding

| Step | View | Expected |
| --- | --- | --- |
| Startup splash | App entry | Branding shown briefly |
| Notifications permission | NotificationsOnboardingView (App/) | APNS prompt; preference saved |
| Gmail connect | GmailOnboardingView | OAuth flow → connection created |
| Default mail setup | DefaultMailOnboardingView | Set as default mail handler |
| Tab bar setup | [TabBarOnboardingView](apps/ios/Todus/Todus/Features/Settings/TabBarOnboardingView.swift) | User picks tabs; saved |

### 3.3 Tabs

| Tab | Expected |
| --- | --- |
| Home | [HomeView](apps/ios/Todus/Todus/Features/Home/HomeView.swift) renders briefing |
| Tasks | [TasksTabView](apps/ios/Todus/Todus/Features/Tasks/TasksTabView.swift) renders inbox |
| Email | [EmailInboxView](apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift) renders threads |
| Calendar | [CalendarContainerView](apps/ios/Todus/Todus/Features/Calendar/CalendarContainerView.swift) renders grid |
| More sheet | tap More | Meetings/Docs/etc. appear |
| Customization persists | reorder, restart | Order kept |
| AI (search role) | tap AI chip | Chat opens |
| Create | tap + | CreateSheet opens |

### 3.4 Mail

| Feature | Steps | Expected |
| --- | --- | --- |
| Inbox list | open Email tab | Threads load via `EmailService` |
| Open thread | tap row | [EmailThreadView](apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift) renders |
| Swipe action: archive | swipe right | Thread archived via backend |
| Swipe action: delete | swipe left | Thread trashed |
| Reply | tap reply | [EmailComposeView](apps/ios/Todus/Todus/Features/Email/EmailComposeView.swift) opens prefilled |
| New compose | tap compose | Empty composer |
| AI draft | tap "AI" in composer | [EmailAIDraftSheet](apps/ios/Todus/Todus/Features/Email/EmailAIDraftSheet.swift) opens; draft generates |
| Connect Gmail | settings → connect | [EmailConnectView](apps/ios/Todus/Todus/Features/Email/EmailConnectView.swift) flow |
| Folder switch | tap folder | List updates |
| Search | global search | Email results returned |

### 3.5 AI / Assistant

| Feature | Steps | Expected |
| --- | --- | --- |
| Chat send | type, send | Streams via `AIChatService` |
| Group chat | open group | Multi-participant view |
| Shared conversation deep link | open `todus://share?slug=...` | `SharedConversationView` opens |
| Sources picker | tap sources | [AISourcesView](apps/ios/Todus/Todus/Features/AI/AISourcesView.swift) opens |
| Attachment picker | tap attach | [AIAttachmentSheet](apps/ios/Todus/Todus/Features/AI/AIAttachmentSheet.swift) opens |
| Markdown rendering | message with `**bold**` etc. | Renders correctly |
| Model picker | settings → model | Switches active model |
| Local model inference (Apple FM) | enable Apple FM, send | Inference local |
| Local model inference (MLX) | enable MLX model, send | Inference local |

### 3.6 Calendar

| Feature | Steps | Expected |
| --- | --- | --- |
| Permission denied state | deny | [CalendarPermissionView](apps/ios/Todus/Todus/Features/Calendar/CalendarPermissionView.swift) prompt |
| Month view | switch | [CalendarMonthView](apps/ios/Todus/Todus/Features/Calendar/CalendarMonthView.swift) renders |
| Year view | switch | [CalendarYearView](apps/ios/Todus/Todus/Features/Calendar/CalendarYearView.swift) renders |
| Multi-day | switch | [CalendarMultiDayView](apps/ios/Todus/Todus/Features/Calendar/CalendarMultiDayView.swift) renders |
| Time grid | switch | [CalendarTimeGridView](apps/ios/Todus/Todus/Features/Calendar/CalendarTimeGridView.swift) renders |
| List | switch | [CalendarListView](apps/ios/Todus/Todus/Features/Calendar/CalendarListView.swift) renders |
| Source picker | tap | [CalendarSourcePickerView](apps/ios/Todus/Todus/Features/Calendar/CalendarSourcePickerView.swift) opens |
| Multi-account events | enable both | Apple + Google merge |
| Tasks in calendar | task with due date | Appears in calendar |

### 3.7 Tasks

| Feature | Steps | Expected |
| --- | --- | --- |
| Capture | type in [CaptureComposer](apps/ios/Todus/Todus/Features/Tasks/CaptureComposer.swift) | Task created; remote-first parse |
| Inbox | open | [InboxView](apps/ios/Todus/Todus/Features/Tasks/InboxView.swift) renders |
| List mode | toggle | [TaskTableView](apps/ios/Todus/Todus/Features/Tasks/TaskTableView.swift) renders |
| Board mode | toggle | [BoardView](apps/ios/Todus/Todus/Features/Tasks/BoardView.swift) renders |
| Detail | tap row | [TaskDetailSheet](apps/ios/Todus/Todus/Features/Tasks/TaskDetailSheet.swift) opens |
| Reminders sync | enable in settings | Tasks appear in Apple Reminders bidirectionally |
| Folder pick | move to folder | [FolderPickerSheet](apps/ios/Todus/Todus/Features/Folders/FolderPickerSheet.swift) opens |
| Compound intent | "remind me X and Y" | Two tasks created via `CompoundIntentParser` |

### 3.8 Docs

| Feature | Steps | Expected |
| --- | --- | --- |
| List | open Docs | [DocsListView](apps/ios/Todus/Todus/Features/Docs/DocsListView.swift) renders |
| Open doc | tap doc | [DocsWebView](apps/ios/Todus/Todus/Features/Docs/DocsWebView.swift) loads Tiptap |
| Edit | type | Auto-saves via `DocsService` |
| Create | tap + | New doc opens |

### 3.9 Meetings

| Feature | Steps | Expected |
| --- | --- | --- |
| List | open Meetings | [MeetingsListView](apps/ios/Todus/Todus/Features/Meetings/MeetingsListView.swift) |
| Detail | tap row | [MeetingDetailView](apps/ios/Todus/Todus/Features/Meetings/MeetingDetailView.swift) shows transcript + AI summary |

### 3.10 Voice

| Feature | Steps | Expected |
| --- | --- | --- |
| Open voice modal | tap voice button | [VoiceChatModalView](apps/ios/Todus/Todus/Features/Voice/VoiceChatModalView.swift) opens; Gemini Live session starts |
| Mic permission | first time | iOS prompt; service handles deny |
| Mic mutex | start, try second | `VoiceMicLock` prevents concurrent |
| Audio playback | speak | TTS response plays via `AudioPlayerManager` |
| Tool invocation | "create a task" via voice | `VoiceToolRegistry` triggers; task created |

### 3.11 Settings (iOS)

| Page | Test | Expected |
| --- | --- | --- |
| Root | [SettingsView](apps/ios/Todus/Todus/Features/Settings/SettingsView.swift) | Account info renders |
| Billing | [BillingSettingsView](apps/ios/Todus/Todus/Features/Settings/BillingSettingsView.swift) | Plan + Autumn portal link |
| Calendar accounts | [CalendarAccountsView](apps/ios/Todus/Todus/Features/Settings/CalendarAccountsView.swift) | Connected calendars list |
| Email automation | [EmailAutomationPolicyView](apps/ios/Todus/Todus/Features/Settings/EmailAutomationPolicyView.swift) | Rule editor |
| Empty Gmail | [EmptyGmailOnboardingView](apps/ios/Todus/Todus/Features/Settings/EmptyGmailOnboardingView.swift) | Setup guide |
| Local models | [LocalModelsView](apps/ios/Todus/Todus/Features/Settings/LocalModelsView.swift) | Catalog + downloads |
| Reminders setup | [RemindersSetupView](apps/ios/Todus/Todus/Features/Settings/RemindersSetupView.swift) | Toggle bidirectional sync |
| Signatures | [SignaturesView](apps/ios/Todus/Todus/Features/Settings/SignaturesView.swift) | CRUD signatures |
| Tab bar customization | [TabBarCustomizationView](apps/ios/Todus/Todus/Features/Settings/TabBarCustomizationView.swift) | Drag reorder; persists |
| Voice assistant | [VoiceAssistantSettingsView](apps/ios/Todus/Todus/Features/Settings/VoiceAssistantSettingsView.swift) | Prefs save |
| Design system | [DesignSystemView](apps/ios/Todus/Todus/Features/DesignSystem/DesignSystemView.swift) | Allowlist gate; tokens render |

### 3.12 Local AI / MLX

| Feature | Steps | Expected |
| --- | --- | --- |
| Catalog | open Local models | List of models w/ size |
| Download | tap download | `ModelDownloadService` fetches from HF; progress reported |
| Activate | tap activate | `LocalModelStateStore` updates active model |
| Inference | run prompt | `MLXInferenceService` returns result |
| Apple FM fallback | enable Apple FM | `AppleFoundationModelService` used when supported |

### 3.13 Deep Links

| URL | Expected handler |
| --- | --- |
| `todus://` | App launches default tab |
| `todus://auth-callback?token=...` | `AuthSessionStore.handleAuthCallback` |
| `todus://share?slug=...` | `SharedConversationView` deep nav |
| `todus://link-callback` | Generic link callback handled |

Test via [scripts/parity/capture-ios-deeplink.mjs](scripts/parity/capture-ios-deeplink.mjs).

### 3.14 Push Notifications

| Test | Expected |
| --- | --- |
| APNS register | Token sent to backend |
| Receive notification | Banner shown |
| Tap notification | Deep link routes to correct screen |
| Digest batching | Multiple within window grouped via `NotificationDigestService` |
| Notification center | [NotificationCenterView](apps/ios/Todus/Todus/Features/Notifications/NotificationCenterView.swift) shows history |

### 3.15 Extensions

| Extension | Test |
| --- | --- |
| Notification Service Extension | Encrypted APNS payload decrypted + modified |
| Share Extension | Share text → opens app w/ pre-filled compose / task |
| Widget | Timeline renders via [WidgetUpdateManager](apps/ios/Todus/Todus/Services/Widgets/WidgetUpdateManager.swift) |

### 3.16 Parity Screenshots

| Command | Validates |
| --- | --- |
| `pnpm parity:screenshots:capture:ios:auto` | Captures all tracked iOS surfaces |
| `pnpm parity:screenshots:check` | Diff vs baseline; flag regressions |

---

## 4. macOS Test Cases

Open the macOS project. Run XCTest via `⌘U`. Run app via `pnpm macos`.

### 4.1 Sidebar Navigation

| Feature | Steps | Expected |
| --- | --- | --- |
| Sidebar renders | launch | [MacSidebarView](apps/macos/TodusMac/App/MacSidebarView.swift) shows all sections |
| Expand Email | click chevron | Inbox/Drafts/Sent/Archive/Snoozed/Spam/Trash visible |
| Collapse Email | click again | Sub-folders hidden |
| Expand Calendar | click chevron | Calendar sources visible |
| Compact sidebar | toggle | Sidebar narrows |
| Unread badges (Tasks) | with unread tasks | Badge count correct |
| Unread badges (Email) | with unread mail | Badge count correct |
| Log out | click | Auth cleared; [MacAuthView](apps/macos/TodusMac/App/MacAuthView.swift) shown |

### 4.2 Multi-Window

| Feature | Steps | Expected |
| --- | --- | --- |
| Detach compose | new compose → "Open in window" (or `⌘N`) | Compose opens in own window |
| Settings as window | open Settings | Separate window (or pane) |
| Close window leaves main | close detached compose | Main window remains |

### 4.3 Mail

| Feature | Steps | Expected |
| --- | --- | --- |
| Inbox | sidebar → Email → Inbox | [MacEmailInboxView](apps/macos/TodusMac/Views/Email/MacEmailInboxView.swift) renders |
| Thread | click row | [MacEmailThreadView](apps/macos/TodusMac/Views/Email/MacEmailThreadView.swift) renders |
| Compose | toolbar | [MacEmailComposeView](apps/macos/TodusMac/Views/Email/MacEmailComposeView.swift) opens |
| Markdown body editor | type in compose | [MacMarkdownBodyEditor](apps/macos/TodusMac/Views/Email/MacMarkdownBodyEditor.swift) handles formatting |
| Folder change | sidebar | List updates |

### 4.4 AI / Assistant

| Feature | Steps | Expected |
| --- | --- | --- |
| Assistant panel | toggle [AssistantButton](apps/macos/TodusMac/App/AssistantButton.swift) | [MacAssistantPanel](apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift) docks to side |
| Chat send | type, send | Streams via `MacAIChatService` |
| Group chat | open | [MacGroupChatView](apps/macos/TodusMac/Views/AI/MacGroupChatView.swift) renders |
| Share modal | open share | [MacShareConversationPanel](apps/macos/TodusMac/Views/AI/MacShareConversationPanel.swift) |
| Shared conv view | open shared link | [MacSharedConversationView](apps/macos/TodusMac/Views/AI/MacSharedConversationView.swift) |
| Sources | open | [MacAISourcesView](apps/macos/TodusMac/Views/AI/MacAISourcesView.swift) |

### 4.5 Calendar

| Feature | Steps | Expected |
| --- | --- | --- |
| Calendar | sidebar | [MacCalendarView](apps/macos/TodusMac/Views/Calendar/MacCalendarView.swift) renders |
| Time grid | view mode | [CalendarTimeGridView](apps/macos/TodusMac/Views/Calendar/CalendarTimeGridView.swift) renders |
| Event edit | double-click event | [MacEventEditSheet](apps/macos/TodusMac/Views/Calendar/MacEventEditSheet.swift) opens |
| Source picker | toolbar | [MacCalendarSourcePicker](apps/macos/TodusMac/Views/Calendar/MacCalendarSourcePicker.swift) opens |
| Trackpad nav | two-finger swipe | [CalendarTrackpadNavigation](apps/macos/TodusMac/Views/Calendar/CalendarTrackpadNavigation.swift) advances date |

### 4.6 Tasks / Docs / Meetings / Folders / Home

| Area | View | Test |
| --- | --- | --- |
| Tasks | [MacTasksView](apps/macos/TodusMac/Views/Tasks/MacTasksView.swift) | Same flow as iOS; shared logic |
| Docs | [MacDocsView](apps/macos/TodusMac/Views/Docs/MacDocsView.swift) + [MacDocEditorPane](apps/macos/TodusMac/Views/Docs/MacDocEditorPane.swift) | Open / edit / autosave |
| Meetings | [MacMeetingsView](apps/macos/TodusMac/Views/Meetings/MacMeetingsView.swift) + [MacMeetingDetailView](apps/macos/TodusMac/Views/Meetings/MacMeetingDetailView.swift) | List + detail + transcript |
| Folders | [MacFolderDetailView](apps/macos/TodusMac/Views/Folders/MacFolderDetailView.swift) | CRUD |
| Home | [MacHomeView](apps/macos/TodusMac/Views/Home/MacHomeView.swift) | Briefing renders |

### 4.7 Search / Notifications / Create

| Area | View | Test |
| --- | --- | --- |
| Global search | [MacSearchView](apps/macos/TodusMac/Views/Search/MacSearchView.swift) | ⌘F opens; results return |
| Notifications center | [MacNotificationCenterView](apps/macos/TodusMac/Views/Notifications/MacNotificationCenterView.swift) | History renders |
| Create sheet | [MacCreateSheet](apps/macos/TodusMac/Views/Create/MacCreateSheet.swift) | ⌘N opens; routes correctly |

### 4.8 Voice (macOS-Unique)

| Feature | Steps | Expected |
| --- | --- | --- |
| Voice panel | toggle | [MacVoiceChatPanel](apps/macos/TodusMac/Views/Voice/MacVoiceChatPanel.swift) docks |
| Status window | start voice session | [VoiceStatusWindow](apps/macos/TodusMac/Views/Voice/VoiceStatusWindow.swift) floats |
| Global hotkey | press configured hotkey from any app | Voice session starts via `HotkeyService` |
| Wake word | speak wake phrase | `WakeWordService` triggers session |
| Audio routing | multiple inputs | `AudioInputBroker` arbitrates |

### 4.9 Settings (macOS)

| Page | View | Test |
| --- | --- | --- |
| Root | [MacSettingsView](apps/macos/TodusMac/Views/Settings/MacSettingsView.swift) | Account renders |
| AI | [MacAISettingsView](apps/macos/TodusMac/Views/Settings/MacAISettingsView.swift) | Prefs save |
| Local models | [MacLocalModelsView](apps/macos/TodusMac/Views/Settings/MacLocalModelsView.swift) | Ollama detected; HF cache reused |
| Calendar accounts | [MacCalendarAccountsList](apps/macos/TodusMac/Views/Settings/MacCalendarAccountsList.swift) | Connected calendars |
| Design system | [MacDesignSystemView](apps/macos/TodusMac/Views/Settings/MacDesignSystemView.swift) | Allowlist gate; tokens render |

### 4.10 Auth & Onboarding (macOS)

| Step | View | Expected |
| --- | --- | --- |
| Sign in | [MacAuthView](apps/macos/TodusMac/App/MacAuthView.swift) | Provider flows work |
| Onboarding | [MacOnboardingViews](apps/macos/TodusMac/App/MacOnboardingViews.swift) | Step through; persists |

### 4.11 Local AI (macOS-Unique)

| Feature | Test | Expected |
| --- | --- | --- |
| Ollama detect | start Ollama locally | [OllamaConnector](apps/macos/TodusMac/Services/AI/Local/OllamaConnector.swift) reports running |
| Ollama inference | send prompt w/ Ollama model | [OllamaInferenceService](apps/macos/TodusMac/Services/AI/Local/OllamaInferenceService.swift) responds |
| HF cache reuse | model previously downloaded | [HuggingFaceCacheConnector](apps/macos/TodusMac/Services/AI/Local/HuggingFaceCacheConnector.swift) reuses; no re-download |

### 4.12 Custom Scroll & Native Bridges

| Feature | Test | Expected |
| --- | --- | --- |
| Custom scroll style | scroll long list | [MacScrollStyle](apps/macos/TodusMac/DesignSystem/MacScrollStyle.swift) applied |
| Email text field | focus + type | [MacEmailTextField](apps/macos/TodusMac/App/MacEmailTextField.swift) handles natively |

### 4.13 Parity Screenshots

`pnpm parity:screenshots:capture:macos:auto` + `pnpm parity:screenshots:check`.

---

## 5. Cross-Platform Parity Tests

| Test | Steps | Expected |
| --- | --- | --- |
| Parity screenshots | `pnpm parity:screenshots:check` | Tracked surfaces match baselines (see [parity_screenshots/SCREENSHOT_LOG.md](parity_screenshots/SCREENSHOT_LOG.md)) |
| Bearer token portability | sign in on web, copy Bearer, use on iOS | Same user data accessible |
| Settings sync | change theme on web, re-open iOS | `settings.get` returns same JSON |
| Mail sync parity | `mail.forceSync` from any surface | New threads visible on all surfaces after workflow completes |
| Connection list parity | add Gmail on iOS, refresh on web | Connection appears |
| AI conversation parity | save chat on web, open on iOS | Same content via `ai.getConversation` |
| Shared link parity | create share on web, open on iOS | `SharedConversationView` renders |

---

## 6. Coverage Gaps & Manual QA

Items existing infra cannot fully automate — flag for manual QA each release.

| Area | Why manual | Manual procedure |
| --- | --- | --- |
| Voice / audio capture | Mic + speaker; OS permission dialogs | Manually run voice flow on each platform |
| Push notification delivery | Requires APNS routing | Send test push from backend; observe device |
| In-app purchase (StoreKit) | Apple sandbox env | Sandbox account; purchase + restore flow |
| Paid Autumn billing | Live payment provider | Stripe test mode if available; verify webhook ingestion |
| OAuth consent screens | Third-party UI | Manual click-through |
| BIMI logo fetch | External DNS / DMARC dependency | Spot-check known BIMI-enabled sender |
| Recall.ai bot in real meeting | Requires Google/Zoom meeting | Spot-check on staging |
| Local LLM correctness | Output quality non-deterministic | Eyeball outputs on representative prompts |
| Multi-window behavior | macOS WindowGroup nuances | Manual detach/close cycle |
| Trackpad gestures | Requires hardware | Manual gesture pass |
| Global hotkey | OS-level event | Manual press from third-party app |
| Wake word detection | Audio environment dependent | Quiet + noisy env smoke tests |
| Email send via real Gmail/Outlook | Quota / spam risk | Use dedicated test mailbox |
| Schedule send arrival time | Hourly cron precision | Schedule, wait, verify arrival |
| Snooze return | Hourly cron | Snooze, wait, verify return |

---

## 7. Execution Order (recommended)

1. **Backend unit + integration** — cheapest failure mode; catches contract breakage early.
   - `pnpm test`, `pnpm test:ai`, `pnpm eval`.
2. **Web smoke tests** — `preview_start` + per-route navigate + `preview_console_logs` check.
3. **Web e2e top flows** — sign in, send email, change a setting, send AI chat message.
4. **iOS XCTest** — open Xcode → `⌘U`.
5. **macOS XCTest** — open Xcode → `⌘U`.
6. **Parity screenshot diff** — `pnpm parity:screenshots:check`.
7. **Manual QA gaps** — items from §6.

A "ship-ready" run should clear steps 1–6 and have a fresh §6 manual pass within the last 24 hours.
