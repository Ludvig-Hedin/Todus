---
id: 0297
title: "iOS UX pass: retire default-mail onboarding, tighten Tasks header, smarter briefing, thread-fetch timeouts"
status: archived
category: Changed
release_date: 2026-05-21
source: CHANGELOG.md
---

## [2026-05-21] iOS UX pass: retire default-mail onboarding, tighten Tasks header, smarter briefing, thread-fetch timeouts

- **Onboarding** — Removed the "Make Todus your mail app" step (`apps/ios/Todus/Todus/App/RootView.swift`). iOS still has no public API to set a default mail app, so the step couldn't function; onboarding total is now 3 steps. The `DefaultMailOnboardingView.swift` file is left in place (dead code) plus the `hasConfiguredDefaultMailPrompt` flag stays as a no-op stored preference so migration/sign-out reset paths keep compiling.
- **Tasks header** — Removed the green "All clear" header chip; tightened search-bar vertical padding (4→2pt); raised the inset between the pinned search bar and view content from 6→18pt across all four view modes (List / Board / Table / Dates) so spacing is consistent at the 16–24px target. Smart-sort bucket headers (e.g. "No date") are now rendered as inline list rows instead of `Section` headers, so they scroll with content instead of sticking to the top.
- **Tasks Board** — Wrapped `BoardView` in a `GeometryReader` and pinned each column to the available scroll height. Horizontal `ScrollView`s don't propagate vertical bounds to `.frame(maxHeight: .infinity)` content, which previously made columns vertical-center inside the viewport — producing a huge blank gap above the column headers.
- **Home Assistant Briefing — fewer false positives** — Receipts from senders that don't look automated (e.g. `support@openrouter.ai`) were being classified as `needs_reply`, producing bogus "URGENT REPLY" cards for $2 invoices. Tightened `classifyThreadKind` so strong receipt phrases ("tax invoice", "amount paid", "your purchase", "transaction details", "subscription renewed", …) always classify as `receipt` regardless of sender automation status. Expanded `NOREPLY_SENDER_PATTERN` to include `billing@`, `payments@`, `receipts@`, `invoices@`, `subscriptions@`, `orders@`, `accounts@`, `mailer-daemon`, `postmaster`. `replyNeeded` and `deadline_risk` loops are now gated by `!isNonConversational` so receipts / notifications / marketing / verification threads never produce urgent-reply loops.
- **Home Assistant Briefing — visual** — Fixed-width (72pt) badge pills on the briefing feed rows so the row title text starts at the same x-offset regardless of badge label length, plus a subtle stroke outline on the badge for legibility.
- **Email thread load timeouts** — `mail.get` server route now races the `getThread` shard fetch against a 15s timeout and surfaces `INTERNAL_SERVER_ERROR` instead of letting the request hang to the Cloudflare outer limit. iOS `EmailService.loadThread` adds a parallel 20s watchdog that cancels the in-flight request and surfaces typed error messages ("Thread is taking too long to load. Pull to retry." / "You're offline." / "Mail service is unavailable.") instead of a generic "Failed to load thread.". Eliminates the ≈90s "loading forever" experience when a shard or Gmail subrequest stalls.
