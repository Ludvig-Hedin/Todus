high‑level product + execution plan to follow.

Think in phases, each shippable, building toward a real SaaS.

1. Core assumptions ￼

- Source of truth app: Todus repo (Next.js, Node, Postgres, Better Auth).

- Primary user auth: Google OAuth (existing), plus optional email/password later.

- Infra:

 ▫ Dev: local Docker Postgres + ‎`pnpm dev`.

 ▫ Prod: one public URL (e.g. Vercel for frontend + a Node/DB host, or a single VPS).

- Convex: used for app-level state (subscriptions, feature flags, analytics, device sessions), not email storage (that stays in Postgres / R2 as in Todus).

Phase 1 — Baseline: “Hosted Todus” as a single-tenant SaaS ￼

Goal: A stable, hosted Todus instance reachable from anywhere, with clean environments.

Deliverables

- Dev environment

 ▫ Local: ‎`http://localhost:3000`, Docker Postgres, .env via ‎`pnpm nizzy env`.

 ▫ Staging: ‎`https://staging.Todus.yourdomain.com` with isolated DB + OAuth config.

- Prod environment

 ▫ ‎`https://app.Todus.yourdomain.com` (or similar).

 ▫ Shared Postgres instance for all users.

 ▫ Durable Objects / R2 configured as in README for email sync.

- Auth & accounts

 ▫ Google OAuth working end‑to‑end in both staging + prod.

 ▫ “My account” page surfaces:

 ⁃ connected email providers,

 ⁃ sync status,

 ⁃ basic profile (name, photo, email).

- Basic multi-user

 ▫ Multiple Google accounts can sign up and use the same hosted instance.

 ▫ Separation by user ID in DB confirmed.

 ▫ Rate limits and safe defaults for sync.

Key tasks

- Pick hosting (Vercel + managed Postgres, or VPS + Docker Compose).

- Wire up ‎`NEXT_PUBLIC_*` and OAuth redirect URIs for all envs.

- Create clear ‎`.env` patterns: ‎`.env.development`, ‎`.env.staging`, ‎`.env.production`.

- Smoke test core flows:

 ▫ sign in,

 ▫ connect Gmail,

 ▫ read + send email.

Success criteria

- Anyone with a Google account can sign in at prod URL and use inbox.

- No environment-specific hacks; Electron/iOS can later just open the URL.

Phase 2 — Mac MVP: Electron webview wrapper ￼

Goal: A downloadable Mac app that’s basically a browser locked to your hosted Todus.

Deliverables

- Electron app project in its own folder/repo.

- App opens a single window pointing to:

 ▫ Dev: ‎`http://localhost:3000`

 ▫ Staging/Prod: ‎`https://app.Todus.yourdomain.com`

- Basic native feel

 ▫ App icon, name, menu items.

 ▫ Remember last window size/position.

- Distribution

 ▫ Signed/notarized ‎`.dmg` / ‎`.app` for macOS.

 ▫ Internal build flow documented (e.g. ‎`pnpm dist` + Apple dev steps).

Key tasks

- Add build-time env switch: dev vs prod Todus URL.

- Handle deep links / URLs:

 ▫ mailto links open inside the webview or handoff to Todus.

- Session management:

 ▫ Confirm Google OAuth and cookies work inside Electron (no weird popup issues).

- Error handling:

 ▫ Offline screen when Todus backend is unreachable.

 ▫ “Retry” / “Open in browser” actions.

Success criteria

- You can install the .app on a clean Mac.

- Sign in with Google, use inbox, compose, etc, same as web.

- No critical UX blockers (scrolling, shortcuts, CMD+Q).

Phase 3 — Minimal iOS app: Expo + WebView -> TestFlight ￼

Goal: Ship a TestFlight iOS app that loads the same hosted Todus via WebView.

Deliverables

- Expo app project (managed workflow).

- Landing screen = full‑screen WebView to ‎`https://app.Todus.yourdomain.com`.

- Environment modes

 ▫ Dev: simulator hitting local/staging backend.

 ▫ Prod: TestFlight build hitting prod backend.

- Auth

 ▫ Google OAuth works inside WebView.

 ▫ Redirect URIs configured for mobile (no broken flows).

- App Store Connect setup

 ▫ Bundle ID, icons, description, basic privacy info.

 ▫ At least one TestFlight build approved.

Key tasks

- Domain must be HTTPS + stable.

- Tighten Todus’s responsive UI for small screens (mobile breakpoints).

- Mobile-specific tweaks:

 ▫ make sure navigation, buttons, and compose view are usable on iPhone.

- Instrument basic analytics:

 ▫ page load errors,

 ▫ sign-in success rate (via Convex or other).

Success criteria

- Testers can install via TestFlight.

- Can log in, read, and send email without major layout issues.

- App survives background/foreground switches gracefully.

Phase 4 — SaaS backbone: Convex for meta, billing, and plans ￼

Goal: Layer in “real SaaS” capabilities without touching core email storage.

What Convex owns

- User meta: user profile, onboarding progress, feature flags.

- Billing state: subscription tiers, status, trial period.

- Device sessions: which user has which devices (iOS / Mac / Web).

- Telemetry: events like “connected first inbox”, “sent first email”.

Deliverables

- Convex project created with:

 ▫ ‎`users` table linked by Todus user ID.

 ▫ ‎`subscriptions` table: plan, status, renewal date, Stripe customer ID.

 ▫ ‎`features` / flags: enabling experimental features per user.

- Stripe (or similar) integration:

 ▫ pricing page on web.

 ▫ webhook into Convex to keep subscription state in sync.

- Gating logic in Todus UI:

 ▫ feature visibility / limits based on Convex data.

 ▫ example: max number of connected inboxes by plan.

Key tasks

- Design “user identity mapping”:

 ▫ Todus’s internal user ID ↔ Convex user ID ↔ Stripe customer.

- Add an API layer in Todus that reads Convex state for:

 ▫ current plan,

 ▫ capabilities / quotas.

- Basic admin dashboard (internal only):

 ▫ list users, their plans, and rough usage.

Success criteria

- New user can:

 ▫ sign up via Google,

 ▫ start trial/free plan,

 ▫ upgrade to paid,

 ▫ see plan reflected in UI.

- Downgrades / cancellations reflected within Convex and UI.

Phase 5 — Native Mac app (SwiftUI + WebView shell) ￼

Goal: Replace Electron with a thinner, more native SwiftUI app that still uses the hosted Todus UI as the main surface.

Deliverables

- macOS app in Swift/SwiftUI:

 ▫ top-level window with WebView (WKWebView).

 ▫ native menu bar, keyboard shortcuts, dock badge for unread count.

- Deeper integration

 ▫ basic system notifications for new emails.

 ▫ “Open at login” option.

- Use the same backend + URL as all other clients.

Key tasks

- Decide how to fetch unread counts:

 ▫ Polling API from Todus backend, or dedicated lightweight endpoint.

- Decide how to show new mail:

 ▫ Local notifications triggered by that endpoint.

- Add deep link support:

 ▫ clicking links like ‎`Todus://thread/{id}` opens specific thread in app.

Success criteria

- SwiftUI app can fully replace Electron for daily use.

- Notifications and dock badges feel reliable.

- Apple notarization + distribution pipeline exists (outside Mac App Store or in, your choice).

Phase 6 — Native iOS 2.0: Expo React Native UI (real mobile client) ￼

Goal: Move from “WebView wrapper” to a proper native-ish iOS UI that calls Todus’s backend APIs directly.

Deliverables

- API layer on the backend:

 ▫ stable, documented REST/GraphQL endpoints for:

 ⁃ list threads,

 ⁃ list messages,

 ⁃ send email,

 ⁃ mark read / archive / labels.

- Shared TS client SDK:

 ▫ used by Next.js frontend and the Expo app.

- Expo app UI:

 ▫ native inbox list.

 ▫ thread view.

 ▫ compose screen.

 ▫ basic offline/poor network handling.

- Auth & session

 ▫ reuse Google OAuth tokens / sessions via secure JWT or cookies from backend.

 ▫ handle token refresh gracefully.

Key tasks

- API design & versioning with mobile in mind.

- Authentication strategy:

 ▫ either OAuth in WebView just for login → store tokens for native calls,

 ▫ or direct OAuth flow embedded in native.

- Push notifications for new mail:

 ▫ backend hook → APNs via Expo push or your own service.

Success criteria

- iOS app feels like a real mobile email client, not a web wrapper.

- Core flows (read/sort/search/compose) feel fast on cellular.

- API is stable enough that future clients (Android, more desktop) can reuse it.

Phase 7 — Polish, scalability, and “real SaaS” hardening ￼

Goal: Everything feels boringly reliable and sellable.

Deliverables

- Monitoring + alerting for:

 ▫ sync failures,

 ▫ OAuth errors,

 ▫ email send failures.

- Rate limiting and abuse protection.

- Clear onboarding:

 ▫ landing page,

 ▫ 1–2 minute setup flow (connect Gmail, choose defaults, done).

- Docs:

 ▫ “How to self-host Todus” using your SaaS as reference.

 ▫ “How to add another inbox”.

 ▫ “Privacy & security” explaining data flows.

Key tasks

- Instrument critical paths with logging/metrics.

- SLOs: response time targets for API, sync latency.

- Tidy up UX inconsistencies across Web, Mac, iOS.

Success criteria

- New user can:

 ▫ discover product → sign up → connect inbox → use it across Web/Mac/iOS in <10 minutes.

- You can go a month without touching servers because monitoring + limits are solid.

That’s the spine. turn each Phase into tasks: set up hosting + Electron wrapper so you can feel it running “for real” before getting fancy.
