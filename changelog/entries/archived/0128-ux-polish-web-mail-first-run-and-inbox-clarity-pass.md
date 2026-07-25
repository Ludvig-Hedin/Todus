---
id: 0128
title: "UX Polish — web mail first-run and inbox clarity pass"
status: archived
category: Changed
release_date: 2026-03-31
source: CHANGELOG.md
---

## [2026-03-31] UX Polish — web mail first-run and inbox clarity pass

- Reworked the first-run flow in `apps/mail` so onboarding no longer competes with inbox connection setup. The inbox tour now waits until the user has at least one connected account.
- Replaced the blocking connect-email modal with a dismissible setup card, so users can orient themselves or navigate to settings without being trapped in a modal on first load.
- Clarified primary inbox controls: the main search affordance now reads as `Search or filter mail`, the category dropdown is labeled `Filter inbox`, active filter counts use consistent wording, and the inbox/People toggle now explains what the People view does.
- Improved thread-list discoverability by keeping row actions lightly visible instead of fully hidden until hover, and upgraded empty states with clearer, action-oriented copy.
- Simplified thread-header hierarchy by making `Reply all` the obvious primary action and moving notes into secondary actions, while also making the AI entry point more concrete through updated tooltip/call-to-action language.
- Tightened onboarding copy to focus on immediate email tasks instead of vague marketing or future-looking messaging.

**User-facing:** First-time users get a calmer setup flow, inbox controls are easier to understand within a few seconds, and the main email actions are more obvious.

**Files:** `apps/mail/components/onboarding.tsx`, `apps/mail/components/connection/connection-wrapper.tsx`, `apps/mail/components/mail/mail.tsx`, `apps/mail/components/mail/mail-list.tsx`, `apps/mail/components/mail/thread-display.tsx`, `apps/mail/components/mail/note-panel.tsx`, `apps/mail/components/ai-toggle-button.tsx`, `TASK.md`
