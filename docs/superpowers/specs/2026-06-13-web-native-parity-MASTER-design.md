# Web → Native Parity — Master Design

> Date: 2026-06-13 · Status: approved decomposition · Owner: Ludvig
> Companion specs live in this folder, one per workstream.
> Supersedes the stale `PARITY_CHECKLIST.md` / `CLAUDE_PARITY_CHECKLIST.md`
> (those describe an Expo-WebView / Electron / `apps/mail` architecture that no
> longer exists — ignore them).

## Goal

Bring `apps/web` to feature parity with the native SwiftUI iOS (`apps/ios/Todus`)
and macOS (`apps/macos/TodusMac`) apps. All three share one backend
(`apps/server`, tRPC + Cloudflare Workers).

## Audit summary (2026-06-13)

A capability-level audit (not file-exists) found `apps/web` is **~85% at parity**.
Mail, Tasks, Docs, Meetings, Billing, Sharing, and Auth backends are genuinely
complete and wired. The missing ~15% is concentrated in a few areas where the UI
*looks* present but is stubbed, dead, or broken:

### Tier 1 — looks present, actually doesn't work
| Gap | Evidence |
| --- | --- |
| Calendar is read-only — no event create/edit/delete UI; quick-add only makes tasks. Server mutations exist (`apps/server/src/trpc/routes/calendar.ts:473-642`) but no client calls them. | `apps/web/app/(routes)/mail/calendar/page.tsx`, `apps/web/components/calendar/calendar-grid.tsx` |
| AI chat cannot create tasks/events — `agent/tools.ts` has email tools only. | `apps/server/src/routes/agent/tools.ts:171-346` |
| Voice tool execution disabled — `clientTools` commented out; talk-only. | `apps/web/providers/voice-provider.tsx:62-87` |
| Voice transcript never rendered — `onMessage` only `console.log`s. | `apps/web/providers/voice-provider.tsx:123-126` |
| No web push at all — no service worker / PushManager / VAPID; backend has no push infra, no device-token table, no notification center/history. | `apps/web/public/manifest.json`, `apps/web/app/entry.client.tsx`; grep zero matches in `apps/server/src` |
| Signatures data-loss bug — per-account signatures save to `localStorage` only, never server-synced. | `apps/web/app/(routes)/settings/signatures/page.tsx:15-26` |

### Tier 2 — dead / stub controls
| Gap | Evidence |
| --- | --- |
| Shortcuts customization — edit UI fully commented out; `updateShortcut` is a TODO. | `apps/web/app/(routes)/settings/shortcuts/page.tsx` |
| Multi-calendar visibility toggles — page hardcodes `calendarId='primary'`; `settings/calendars` toggles are placeholder text. | `apps/web/app/(routes)/mail/calendar/page.tsx:156-159`, `settings/calendars/page.tsx` |
| Security 2FA — page has session list only, no 2FA enable/disable UI. | `apps/web/app/(routes)/settings/security/page.tsx` |
| Share-creation UI — backend full, but no UI to share a conversation; only list/revoke in settings. | `apps/server/src/trpc/routes/sharing.ts` |

### Tier 3 — minor / polish
Docs delete + search have no UI (backends exist) · password-reset UI missing
(backend exists) · email/password login+signup commented out · Apple web sign-in
flag-gated · onboarding lacks Gmail-connect step + home setup-checklist · group
chat is 5s polling not realtime.

### Out of scope (platform-inherent — NOT real gaps)
On-device MLX / Apple Intelligence inference, Apple Reminders two-way sync,
EventKit system calendar, home-screen widgets, tab-bar customization, Siri
intents, macOS hotkey/wake-word. None belong on web.

## Decomposition — 7 workstreams

Each workstream is shippable on its own and gets its own design spec + plan.

| # | Workstream | Closes | Touches | Risk | Spec |
| --- | --- | --- | --- | --- | --- |
| A | **Calendar write support** | event create/edit/delete UI ✅ (A1) · multi-calendar visibility toggles ✅ (A2, via `eventsMulti`; no server change needed after all) · remaining: create-on-specific-calendar picker + cross-connection editing (PAR-A2) | web (server ready) | Low | `2026-06-13-web-calendar-write-support-design.md` · plan `plans/2026-06-13-web-calendar-event-crud.md` |
| B | **AI actionability** | task tools `createTask`/`updateTask`/`completeTask`/`listTasks` ✅ (B1) · `createEvent` tool ✅ (B2) — both gated by now-enforced `aiCanWriteTasks`/`aiCanWriteCalendar` · verify mention-context injection ⏳ (PAR-B3) | server + web | Med | (master) |
| C | **Voice parity** | live transcript ✅ (shipped) + fixed misplaced `onMessage` · re-enable `clientTools` ⏳ (PAR-C — blocked on ElevenLabs dashboard config) | web | Med | (master) |
| D | **Notifications & web push** | device-token table + VAPID web-push sender (gated by existing toggles), service worker + permission flow, notification center/history, actionable notifications | server + web | High | TBD |
| E | **Settings completeness** | share-creation UI ✅ (shipped) · signatures server-sync ⏳ · shortcuts customization ⏳ · 2FA UI ⏳ | web (+ Better Auth) | Med | (master) |
| F | **Auth & onboarding polish** | password-reset UI, email/password login+signup, Apple web sign-in, onboarding Gmail step + setup checklist | web | Low | TBD |
| G | **Docs & realtime polish** | docs delete + search UI, group-chat realtime | web (+ server DO) | Low | TBD |

## Sequence

A → B → C → E → D → F → G.

Rationale: A is self-contained with backend ready (fast, visible win); B unblocks
C; signatures bug in E is a correctness issue pulled forward where convenient; D
is the largest epic and gets its own focused cycle; F/G are polish.

## Acceptance (master)

Parity is "done" when, for every Tier 1/2/3 item above, the web behavior matches
native behavior (or has a documented, intentional platform difference). Each
workstream spec defines its own acceptance criteria and the verification command
for the touched area.

## Process

Per workstream: design spec → user review → `writing-plans` → implement → verify →
commit. Update `CHANGELOG.md` and `FEATURES.md` as behavior changes. This master
doc tracks status across workstreams.
