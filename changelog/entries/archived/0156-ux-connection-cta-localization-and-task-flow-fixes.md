---
id: 0156
title: "UX — Connection CTA, localization, and task flow fixes"
status: archived
category: Fixed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] UX — Connection CTA, localization, and task flow fixes

### iOS (`apps/ios/Todus`)

- **Attachment thumbnails:** Task attachment thumbnails now load off the main actor before updating the SwiftUI image state, preventing visible UI stalls while thumbnails are generated.
- **Task folder creation failure feedback:** Task detail sheet now surfaces a visible error when inline folder creation fails instead of silently doing nothing.

### macOS (`apps/macos`)

- **Assistant connection accuracy:** The assistant panel now treats email connectivity as `emailService.hasConnection` instead of inferring it from loaded threads, so connect prompts reflect the real auth state.
- **Email connect recovery:** The assistant panel’s `Connect Email` actions now open Internet Accounts in System Settings and fall back to a helpful alert if the deep link cannot be opened.
- **Service-specific CTA matching:** Assistant connection banners now only appear for explicit calendar/email disconnection phrases, avoiding false positives from generic “not connected” wording.
- **Tasks empty state action:** The macOS tasks empty state now always invokes a required create callback instead of silently no-oping.

### Web (`apps/mail`, `apps/web`)

- **Assistant email CTA matching:** The web AI compose chat now uses stricter email-connection phrase detection before showing the connect-email CTA.
- **Sidebar dialog accessibility:** The compose dialog now exposes descriptive screen-reader-only title and description text instead of empty Radix dialog labels.
- **Meetings auth redirect:** The meetings loader now constructs the login redirect with `URL` normalization so `VITE_PUBLIC_APP_URL` cannot produce double slashes.
- **Locale coverage:** Requested Catalan, German, Persian, French, Hindi, Japanese, Latvian, Dutch formatting, Polish, Portuguese, Russian, Turkish, Arabic, Hungarian, and Korean locale fixes were applied across `apps/mail/messages` and `apps/web/messages`.
