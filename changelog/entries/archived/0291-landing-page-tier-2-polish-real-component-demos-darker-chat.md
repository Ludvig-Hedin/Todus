---
id: 0291
title: "Landing page tier-2 polish: real-component demos, darker chat panel, native section removed"
status: archived
category: Removed
release_date: 2026-05-21
source: CHANGELOG.md
---

## [2026-05-21] Landing page tier-2 polish: real-component demos, darker chat panel, native section removed

User feedback on the first landing-page expansion: the inline CSS mockups looked nested-card-y and off-brand, the AI chat panel was too light, the native-app section's copy ("Built native, not wrapped. Real Swift apps...") read like AI marketing speak. This pass:

- **`NativeAppSection` removed.** Deleted from `components/home/product-sections.tsx` exports and from `HomeContent.tsx`. The downloads page (`/downloads`) already covers platforms.
- **Feature demos rewritten to mirror the real app.** `product-sections.tsx` now copies the visual blueprint of the real components (`apps/web/components/calendar/calendar-grid.tsx`, `apps/web/app/(routes)/mail/tasks/page.tsx`, `apps/web/app/(routes)/mail/meetings/page.tsx`, `apps/web/components/docs/`). Single outer frame per demo (no nested cards). iOS blue `#007AFF`, system reds `#FF453A`, greens `#30D158`, yellows `#FFD60A` — matches the real app's accent palette. Each demo has scroll-triggered staggered reveals (event blocks fade in column-by-column, task cards drop in, meeting rows slide from the left, checklist items pop sequentially). Adds a live "now" line on the calendar demo.
- **Plain copy.** Replaced marketing speak. "Built native, not wrapped" → removed entirely. "Turn email into action" → "Pull tasks out of email. Drop them where they go." "Meetings, recorded and recapped" → "Meetings get transcribed and summarized." Removed "AI-generated" claims that the demos don't actually prove.
- **AI Chat section darkened.** In `HomeContent.tsx`: the inner chat panel `bg-[#252525]` → `bg-[#0E0E0E]` with `border border-white/[0.06]` + soft shadow. Pinned-conversations panel `bg-zinc-900 opacity-30` → `bg-[#0A0A0A] opacity-40` + hairline border. Chip backgrounds `bg-[#303030]` → `bg-[#181818]`. Edge fade gradients `neutral-800` → `#0E0E0E` so the row blends into the panel instead of standing off it.
