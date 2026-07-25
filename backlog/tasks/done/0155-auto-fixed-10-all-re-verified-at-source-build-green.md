---
id: 0155
title: "Auto-fixed (10) — all re-verified at source, build green"
status: done
tags: [macos, qa, code-review-backlog]
files: []
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-08 — QA pass (macOS app, pre-TestFlight)

## Auto-fixed (10) — all re-verified at source, build green

| File:line | Severity | What changed |
|-----------|----------|--------------|
| `apps/macos/.../Services/Email/EmailService.swift:1130` (`sendEmail`) | 🔴 **critical** | Decoded `SendResponse` but never checked `success`; backend returns HTTP 200 `{success:false,error}` for undo-send / scheduled-send failures → compose closed + autosaved draft cleared as "sent" while the mail was **lost**. Now `guard response.success else { surface error; return false }`; `SendResponse` gained `error`. |
| `apps/macos/.../Services/Drafts/MacDraftService.swift:125` (`send`) | 🔴 **critical** | Same silent-failure on the **attachment** send path (decoded `EmptyResult`, ignored `success`). Now decodes `SendResult{success,error}` and `throw`s on `success == false` so the compose sheet stays open and surfaces the error. |
| `apps/macos/.../Services/AI/MacAIChatService.swift:1405` (`saveCurrentConversation`) | 🟠 high | Always minted a fresh `UUID()` + inserted → every autosave / clearHistory / loadConversation for the **same** live chat appended a duplicate history row (and defeated server merge-by-id, so dupes synced). Now updates the existing entry in place when `currentConversationID` matches. |
| `apps/macos/.../App/MacOnboardingViews.swift:126` (`MacGmailOnboardingView.connect`) | 🟠 high | Called `signInWithGoogle()` directly → an Apple/OTP-signed-in user clicking "Connect Gmail" had their **session overwritten** by a Google sign-in (account hijack) instead of linking. Now uses the link-aware `EmailService.connectGmail(authService:)` (links when authed, signs in only when signed out), mirroring iOS. |
| `apps/macos/.../Views/Docs/MacDocEditorPane.swift:394` (`load`) | 🟠 high | `lastText` was only set in `onContentChange`, so a flush before the editor's first change (open-then-close, or doc switch) wrote `contentText` as a single space — or the **previous** doc's text — silently corrupting server search/preview text. Now seeds `lastText = d.contentText ?? ""` on load. |
| `apps/macos/.../Views/Email/MacEmailInboxView.swift:590` (row context menu) | 🟠 high | Archiving/deleting the **currently-open** thread via the list context menu didn't clear `selectedThreadId` → the detail pane kept rendering a thread no longer in the list; reply/archive/delete from that stale pane acted on a gone thread. Now clears selection when the acted-on thread is open (matches the header close button). |
| `apps/macos/.../Services/AI/MacAIChatService.swift:1344` (`appendError`) | 🟡 med | A mid-stream network drop **overwrote** already-streamed assistant tokens with `⚠️ …`, discarding the partial answer the user was reading. Now appends the error on a new line, preserving streamed text. |
| `apps/macos/.../App/MacRootView.swift:490` (launch silent-refresh `.task`) | 🟡 med | The on-launch `attemptSilentRefresh()` task ran once on appear — before the sibling bootstrap task's `await restorePersistedSession()` set `hasBootstrappedAuthState`/`isAuthenticated` — so its guard always failed and it **never ran**. Re-keyed `.task(id: hasBootstrappedAuthState)` so it re-fires once bootstrap completes. |
| `apps/macos/.../Views/Calendar/MacCalendarView.swift:568` (`dayView`) | 🔵 low | Day view filtered timed events by start-day equality, so a multi-day event that **began earlier** vanished from the day it continued into (week view already used overlap). Now overlap (`start < endOfDay && end > startOfDay`) for timed events; all-day pills keep start-day keying to match the week grid. |
| `apps/macos/.../Views/Email/MacEmailComposeView.swift:664` (`tokenizeRecipients`) | 🔵 low | Split on `,` only, so pasting `a@x.com b@y.com` or `a@x.com; b@y.com` became one invalid mega-token that blocked send. Now splits on commas, semicolons, and whitespace/newlines. |
