---
id: 0311
title: "Fixed — iOS triple audit (UX assessment + UX polish + bug hunt)"
status: unreleased
category: Fixed
release_date: 2026-07-07
source: CHANGELOG.md
---

### Fixed — iOS triple audit (UX assessment + UX polish + bug hunt), 2026-07-07

Full-app pass over `apps/ios/Todus`: 12 parallel finder agents (UX assessment, polish, bug hunt) produced ~75 verified findings; ~60 were fixed, the rest deferred with `TODO(bug-hunt)` markers (see `CODE_REVIEW_BACKLOG.md`). Simulator build green. Highlights:

**Correctness / data integrity**
- Settings → AI Permissions toggles now bind to the live `AIChatService`, so disabling e.g. "Read Email" takes effect on the next request instead of after an app relaunch (privacy fix; also resolves the fresh-install "Send Email" default mismatch across three surfaces).
- Voice assistant no longer reports "Done" when updating/deleting a task that doesn't exist (voice path now checks the same result the text path does).
- Email notification "Archive" action actually archives the thread (previously it just opened the app to the thread) and clears the delivered notification.
- Folder sync no longer duplicates folders created on web/macOS: dictionaries were keyed by uppercase `uuidString` but looked up with lowercase server ids — every sync missed and re-inserted. Same fix un-broke folder count/summary cards and folder-contents task resolution.
- Offline task deletions are retained and replayed on reconnect instead of being dropped (server no longer resurrects deleted tasks).
- Removing a task attachment now defers the disk delete until Save succeeds — Cancel no longer leaves the persisted task pointing at a deleted file; Cancel also cleans up files imported during the session.
- Creating a folder whose name matches an existing one (case-insensitive) now surfaces an inline "already exists" error instead of playing a success haptic, dismissing, and silently dropping the chosen color/icon.
- Month view renders multi-day events on every covered day (was start-day only); Google all-day events no longer paint one extra day (exclusive→inclusive end conversion); recurring events no longer share a single SwiftUI identity per occurrence (fixes collapsed/mis-anchored rows; EventKit lookups still work via suffix-stripped ids).
- Inbox search no longer re-filters server search results against the local subject/from/snippet blob — body-only matches from Gmail no longer vanish as "0 results".
- Per-message Reply/Forward from a message's context menu now targets that message instead of always the newest one in the thread.
- Reply subject no longer double-prefixes ("Re: RE: …"); recipient tokenizer now actually splits space-separated addresses as documented (display-name `<addr>` form preserved).
- Task list/board/table/calendar views no longer miss in-place multi-device sync updates (change digest now includes an order-independent term, not just count + max updatedAt).
- Billing "resets on" date parses again (JS fractional-second ISO timestamps); local-model recommendations respect free disk, not just RAM; quick-capture NLP no longer marks every result "low confidence" (Supabase gating bug); AI card date-only values render and flag overdue correctly; NoteCard "blue" is actually blue; AI generative-UI specs have a recursion depth guard; inline compose card flushes its pending autosave on disappear; AVSpeech "Stop" pill resets when speech finishes and stops on scroll-away.
- Voice session can't be resurrected to "listening" by a tool call that finishes after Stop; GeminiLive WebSocket references are now lock-guarded (data race); drafts stuck mid-send are no longer auto-resent (duplicate-email risk — idempotency-key follow-up in backlog); calendar swipe-back gesture no longer arms on the root view (intermittent frozen calendar); meetings "This Week" bucket is correct across year boundaries; `deleteAccount` sends the CSRF-required `Origin` header.

**UX**
- Gmail-first users who declined Apple Calendar access are no longer locked out of the Calendar tab — Google events render without EventKit permission.
- Tapping a calendar time slot pre-fills that time in the create sheet (was silently discarded, defaulting to "now").
- Task capture now confirms with a "Task added to Inbox/⟨folder⟩" toast (plus "Event added" / "Added N items") — a dateless capture was previously invisible from Home. The unreachable "You're caught up." Home state now renders when the briefing has zero items.
- CreateSheet Auto mode shows a live "Creates task/event/email" indicator; the folder control shows "Auto" when AI routing is active; email mode explains the disabled Send ("Add a recipient to send").
- Onboarding: welcome tour no longer promises the removed tab-customization step; progress pill works for guests; guests skip the Gmail step they can't use; one spinner per tapped sign-in action; "Open your email app" opens the inbox (Gmail/Outlook/Spark/Mail via `LSApplicationQueriesSchemes`) instead of a blank compose window; startup-card a11y hints aligned with reality.
- Email: persistent star indicator in list rows; swipe action reads "Unstar" when starred; attachment cards are explicitly informational ("Preview not available yet"); compose warns attachments aren't sent yet; global search "See all" carries the query into the destination tab; calendar-only queries no longer flash "No results" mid-debounce; empty-state category chips respond to tap; AI chat empty state shows the model + Gmail/Calendar access pills.
- No-op "Customize Tab Bar" and legacy "Docs (Web)" entries hidden behind the developer allowlist until wired.
- States & feedback: Docs WebView failures show error + Retry (was silent blank); doc-detail fetch failures show Retry (was infinite spinner); docs list "Last refreshed" footer; calendar list load-more spinner; meetings empty-state sync spinner; meeting Q&A dismisses keyboard on send, notes "Answers aren't saved", and confirms summary/schedule/ask success; folder detail distinguishes "couldn't load" from "empty" and resets a stale type filter; AddToFolderSheet's email picker self-loads; board delete, local-model weight delete, and "Log out all other devices" gained confirmation dialogs; active local model shows an "Active" badge.
- Consistency: haptics added across table checkbox, board card actions, FABs, calendar event blocks/copy, signature save/select, calendar account toggles, meetings sync, folder moves, thread star; 44pt hit targets for board quick-add and calendar nav; Home "This Week" badge counts items (not day groups); Meetings header uses a sync icon (not "+") and guards double-tap; Home email rows expose unread to VoiceOver; capture composer keeps the caret in place on bullet auto-format; Tasks header overdue/today chips are passive stats (they never filtered).
- Dead code removed: `EmailAIDraftSheet.swift`, `OnboardingAuthSheet.swift` (its working `openEmailInbox()` ported into `AuthView` first).
