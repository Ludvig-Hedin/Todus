# Share Todus ASAP (iPhone + Mac)

## Fastest path for friends today

1. Deploy web + backend and share URL immediately:

```bash
pnpm deploy:frontend
pnpm deploy:backend
```

2. iPhone app via TestFlight (real app install, no Expo Go):

```bash
pnpm ios:build:production
pnpm --filter=@zero/ios submit:ios
```

Then in App Store Connect:

- Add Internal Testers first (fastest)
- Add External Testers next (Apple beta review required)

3. Mac usage right now:

- Fastest: share the same web URL (friends can install as Safari/Chrome app)
- Native wrapper exists in `apps/macos`, but signed/notarized distribution needs Apple signing setup

## Custom domain routing (Cloudflare)

Use two hostnames:

1. `todus.app` (or `app.todus.app`) -> frontend Worker `todus-production`
2. `api.todus.app` -> backend Worker `todus-server-v1-production`

Do not point your app domain to the old `zero` Worker.

Set these env vars in Cloudflare Worker environments:

- `VITE_PUBLIC_APP_URL=https://todus.app` (or your chosen app host)
- `VITE_PUBLIC_BACKEND_URL=https://api.todus.app`
- `BETTER_AUTH_URL=https://api.todus.app`
- `COOKIE_DOMAIN=todus.app`

## Why login can appear in browser

Google OAuth can leave embedded WebViews depending on provider flow and popup behavior.
This repo now keeps all normal HTTP/HTTPS navigation in-app, but if Google forces an external step,
that is provider behavior, not Supabase.

## Native iOS auth return requirements

To return from Google auth back into the app instead of staying in Safari:

1. iOS app must register URL scheme `todus://` (already set in `apps/apple/Todus/Todus.xcodeproj`).
2. Web login must send callback URL `todus://auth-callback` for native user agent (already set in `apps/mail/app/(auth)/login/login-client.tsx`).
3. Backend auth allowlist must include:
   - deployed app origin
   - deployed backend origin
   - `todus://auth-callback`
     (configured in `apps/server/src/lib/auth.ts`).
4. Redeploy backend and frontend after these changes:

```bash
pnpm deploy:backend
pnpm deploy:frontend
```
