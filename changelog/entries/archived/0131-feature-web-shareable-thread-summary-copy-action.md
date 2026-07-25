---
id: 0131
title: "Feature — web: shareable thread summary copy action"
status: archived
category: Added
release_date: 2026-03-31
source: CHANGELOG.md
---

## [2026-03-31] Feature — web: shareable thread summary copy action

- Added a one-click `Copy summary` action to the thread summary card in `apps/mail/components/mail/mail-display.tsx`.
- The copied payload includes the thread subject, the AI summary, and a short Todus attribution footer so it can be pasted into email or Slack as a branded handoff.
- Added PostHog tracking for successful shares via `Thread Summary Shared`.

**User-facing:** Users can now turn an AI summary into a reusable share artifact without leaving the thread view.

**Files:** `apps/mail/components/mail/mail-display.tsx`, `TASK.md`
