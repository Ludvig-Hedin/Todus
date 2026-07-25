---
id: 0005
title: "Create the native Google OAuth client and redirect URIs"
status: open
priority: P1
area: auth
source: "MANUAL_INPUTS_GUIDE.md §2 checklist (unchecked)"
created: 2026-07-25
---

Unchecked in the manual-inputs checklist. Native Google sign-in uses `ASWebAuthenticationSession` → backend OAuth → `/api/auth/mobile-token` → `todus://auth-callback`, so the OAuth client has to allow both the backend origin and the deep-link callback.

- [ ] Create/confirm the Google OAuth client for the native redirect strategy in Google Cloud Console
- [ ] Add the authorised redirect URIs and JavaScript origins for the environment you are wiring (production `todus.app` / `api.todus.app`, or the staging hosts if staging is still in use)
- [ ] Confirm every origin you added is also listed in `trustedOrigins` in `apps/server/src/lib/auth.ts` — that list is hardcoded and does not read from env
- [ ] Sign in with Google from a device build and confirm the callback lands

Note: `MANUAL_INPUTS_GUIDE.md` still describes the retired `apps/native` Expo app; use it for the Google/Apple console steps only, not for repo paths.
