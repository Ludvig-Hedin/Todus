---
id: 0424
title: "PG-011 completed by adding native Autumn billing integration and settings UX parity (apps/ios/src/sh"
status: done
tags: [task-md, sprint]
files: [apps/ios/src/shared/integrations/autumn.ts, apps/ios/app/(app)/settings/billing.tsx]
created: 2026-03-01
source: TASK.md
---

> Source context: TASK.md → Session Notes (2026-03-01)

- `PG-011` completed by adding native Autumn billing integration and settings UX parity (`apps/ios/src/shared/integrations/autumn.ts`, `apps/ios/app/(app)/settings/billing.tsx`, route wiring in settings index/layout). Dub parity remains server-driven via existing backend `dubAnalytics` auth plugin; native uses the same better-auth social sign-in endpoint flow.
