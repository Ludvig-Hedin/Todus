---
id: 0305
title: "Accessibility / UX — legacy unreleased batch"
status: unreleased
category: Changed
source: CHANGELOG.md
---

### Accessibility / UX

- **Billing credits display scale (iOS + macOS + web)** — credits now shown at 10× their internal dollar value so plans read as round, sensible numbers: Free **75**, Pro **150** (was Free 75 / Pro 15, which made the paid tier look smaller). Display-only `creditsDisplayScale`/`CREDITS_DISPLAY_SCALE = 10` applied in `formatCredits` so the usage meter matches the plan copy; actual billing/limits unchanged. Server truth: `model-pricing.ts` (Free 7.5, Pro 15). (`BillingSettingsView.swift`, `MacSettingsView.swift`, web `billing/page.tsx`)
- **iOS VoiceOver labels** — added accessibility labels to icon-only controls: AI chat voice + settings buttons, GroupChat send, CalendarAccounts visibility toggle + default-calendar star, and the Billing usage `ProgressView` (label + % value).
- **iOS keyboard handling** — Signatures editor gained a "Done" keyboard toolbar (was a trap on a List); compose recipient fields (To/Cc/Bcc) advance focus on return; global search submits on return and dismisses the keyboard on scroll.
