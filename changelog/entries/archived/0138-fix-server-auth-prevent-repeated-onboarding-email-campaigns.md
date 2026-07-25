---
id: 0138
title: "Fix — server auth: prevent repeated onboarding email campaigns"
status: archived
category: Fixed
release_date: 2026-03-31
source: CHANGELOG.md
---

## [2026-03-31] Fix — server auth: prevent repeated onboarding email campaigns

- Persist the `welcomeEmailSent` guard before dispatching onboarding campaigns so a partial Resend failure can no longer replay the entire sequence on the next login.
- Made onboarding campaign dispatch best-effort per email so one failed scheduled message does not block the rest of the sequence or reopen the send gate.

**User-facing:** New and returning users should stop receiving repeated "Welcome", "Todus Pro is here", and related onboarding emails on every login.

**Files:** `apps/server/src/lib/auth.ts`, `TASK.md`
