---
id: 0179
title: "Fixed this pass (highlights by surface)"
status: done
tags: [ios, ux, code-review-backlog]
files: []
created: 2026-06-15
source: CODE_REVIEW_BACKLOG.md
---

> Source context: iOS UX hardening pass — 2026-06-15 (whole-app, main user-flow surfaces)

## Fixed this pass (highlights by surface)

- **Auth/onboarding** — email-validation error no longer flashes mid-typing (gated on blur); "Send code" always visible-but-disabled; email field a11y label/hint; OTP digit-only paste filter; 60s resend cooldown; user-friendly backend error copy (no Supabase/SMTP leakage); Gmail-check loading state + haptic; bell-icon a11y; WelcomeTour "Skip" → "Skip tour". (RootView reinstall "bug" confirmed a non-issue — `&&` already skips the card when authenticated.)
- **Email** — compose `To`-invalid indicator + send-fail haptic + attachment-remove confirm + CC/BCC hint; inbox folder-dropdown affordance on iOS 26, search-term truncation, pagination double-tap guard; thread task/event/copy haptics; row/receipt truncation help.
- **Tasks** — TaskDetailSheet save now surfaces errors + keeps sheet open on failure; **bulk-capture truncation banner** (`lastTruncatedCount`/`lastTruncatedAt` → MainTabView, mirrors rollback banner); attachment-delete confirms; dynamic snooze labels; a11y on parse-state/folder chip/board title; checkbox copy.
- **Create sheet** — duplicate-send guard (`isSending`); `To` required for email type; attachment-delete confirm.
- **Folders** — a11y labels on add/menu; MoveToFolder shows current folder + disables no-op Inbox + inline create-error; AddToFolder "Add X to [folder]"; save haptic; empty-state copy.
- **Calendar** — explicit read-only-event message; clearer reconnect-Gmail scope copy; Today/nav/list/copy haptics; refresh indicator over non-empty events; nav-chevron a11y; proactive full-access permission copy.
- **AI + Voice** — **voice-connect failure now shows an error card + Retry for all users** (was dev-only); `isDisconnecting` "Closing…" state; muted mic icon; tool-call success confirmation; copy-card haptic; sources count header; disabled-state dimming; `+`/attachment a11y labels.
- **Home/Search** — **BH-0614-1 fixed** (stale-briefing reconcile); 350ms search-nav flicker removed; person row tappable → compose; "See all N" rows; Docs no longer dev-gated; destructive-dismiss confirm + haptics.
- **Settings** — signature swipe-delete confirm; billing error-alert + `forceRefreshFromAutumn` after cancel; disconnect-button label + 44pt target; tab-bar customization surfaced in Settings; calendar toggle labels; duplicate-pattern feedback; voice-settings nav-title consistency; tab-bar-customization background token.
- **Docs/Meetings/Notifications** — faster new-doc autofocus + blur-save; docs search-task cancel; meetings sync button + row truncation help; Q&A send spinner + a11y; notification row haptic + truncation help.
