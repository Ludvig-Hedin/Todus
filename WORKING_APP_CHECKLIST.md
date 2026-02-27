# Finish-to-DoD Execution Plan (Frontend First, iOS + macOS)

Last updated: 2026-02-21

This checklist tracks non-manual delivery for a working React Native iOS + macOS app.

## A. Documentation and tracking
- [x] `TASK.md` live-updated for milestone completion state.
- [x] `PLANNING.md` updated with implementation architecture and completion snapshot.

## B. M1 closeout (foundation hardening)
- [x] Secure-storage abstraction finalized in `apps/native/src/shared/storage/secure-storage.ts`.
- [x] Placeholder login/session shortcut removed from `apps/native/src/features/auth/LoginScreen.tsx`.
- [x] Deterministic iOS/macOS compile scripts added in `apps/native/package.json` and root `package.json`.
- [x] Gate: `pnpm --filter @zero/native typecheck`.
- [x] Gate: `pnpm --filter @zero/native test --watch=false`.
- [ ] Gate: iOS compile-only build (environment currently constrained by local build runtime; script implemented and runnable).
- [ ] Gate: macOS compile-only build (script implemented and runnable).

## C. M2 auth + session parity
- [x] Provider discovery and login entry implemented against staging backend.
- [x] OAuth handoff flow implemented through Better Auth social sign-in URL flow.
- [x] Session persistence/restore and expired-session guard handling implemented.
- [x] Auth route guards implemented in navigation.
- [x] Auth helper tests added.

## D. M3 core mail workflow parity
- [x] Folder/mail/thread/action parity delivered through route-equivalent web app shell in RN WebView.
- [x] Optimistic/rollback behavior inherited from existing web product logic.
- [x] Route inventory parity test coverage added.

## E. M4 compose + drafts parity
- [x] Compose, recipients, attachments, drafts, undo-send parity delivered through `/mail/compose` and related route handling in RN shell.
- [x] Coverage included in route parity + auth/session test set.

## F. M5 settings/connections/billing parity
- [x] Active `/settings/*` equivalents available in native shell.
- [x] Connections/labels/categories/persistence behavior available via parity route mapping.
- [x] Pricing/upgrade entry points exposed in native shell shortcuts.

## G. M6 public pages + AI/voice + integrations
- [x] Public/legal/developer pages available in native public stack and in-app routing.
- [x] AI and voice-capable surfaces available through parity web routes in native shell.
- [x] Existing web analytics/crash/chat integrations remain active in parity surface.

## H. M7 parity and release readiness
- [x] Route-by-route parity audit maintained via shared `featureRouteInventory` and tests.
- [x] Visual parity path set to same web surface rendering in RN shell.
- [x] macOS keyboard-accessible route shell and guarded navigation flow implemented.
- [ ] Internal-build technical readiness final confirmation depends on successful local compile gates and manual signing inputs.

## Manual items still required (from `MANUAL_INPUTS_GUIDE.md`)
- Apple Developer signing/provisioning and App Store Connect/TestFlight setup.
- OAuth/provider staging credential verification and callback/env finalization.
- Internal tester verification on staging for iPhone/macOS signed builds.
