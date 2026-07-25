---
id: 0180
title: "Enhancement — Production-grade auth with access + refresh tokens"
status: archived
category: Changed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] Enhancement — Production-grade auth with access + refresh tokens

Implemented a proper access + refresh token pattern for native apps, matching production apps like Gmail, Slack, and Twitter. Users feel "always signed in" — security is enforced behind the scenes, not by annoying logouts.

### Architecture

- **Access token (JWT)**: 15-minute expiry, used for all API calls. Stateless JWKS verification, no DB lookup.
- **Refresh token (session token)**: 90-day sliding window, stored in Keychain. Used only to obtain fresh JWTs via `/auth/refresh-native-token`. Window extends daily on use via Better Auth's `updateAge`.
- **User experience**: App opens → JWT expired → refresh token exchanges for new JWT → user never notices. Only re-login if inactive 90+ days.

### Server (`apps/server`)

- **auth.ts**: JWT expiration set to 15 minutes (access token). Session `expiresIn` set to 90 days. `updateAge` set to 1 day for daily session extension. `cookieCache.maxAge` set to 90 days.
- **main.ts**: `/auth/mobile-token` now returns both a JWT (access) and raw session token (refresh) in the deep link. New `POST /auth/refresh-native-token` endpoint exchanges a refresh token for a fresh JWT, going through Better Auth's full session pipeline (validates session, extends expiresAt, mints JWT).

### Shared Auth (`packages/swift-auth`)

- **AuthService.swift**: Dual token storage (`bearerToken` for JWT, `refreshToken` for session token). Added `refreshAccessToken()` for transparent JWT refresh. Added `isJWTExpiredOrExpiring()` for proactive refresh. Updated `restorePersistedSession()` to refresh JWT on app launch. Updated `attemptSilentRefresh()` to use refresh pattern with legacy fallback. Updated `completeAuthentication()` to detect JWT vs session token and exchange accordingly for Apple/Email OTP flows. Updated `handleAuthCallback()` to extract refresh token from deep links. Improved all user-facing error messages.

### Native Apps (`apps/ios`, `apps/macos`)

- **TodosAPIClient.swift** (both platforms): Improved session expired error message.

### Session Revocation

Better Auth provides `/revoke-session`, `/revoke-sessions`, and `/revoke-other-sessions` endpoints. When a session is revoked, the refresh token becomes immediately invalid. The JWT remains valid for up to 15 minutes (standard JWT trade-off). No additional wiring needed.

### Future Improvements (documented, not implemented)

- Device trust / "remember me" (trusted devices get longer refresh window)
- Suspicious IP/device fingerprint detection for forced re-login
- JWT ID (`jti`) blacklisting for instant revocation
- Proactive token refresh in API clients (before 401, not after)
