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

## Why login can appear in browser

Google OAuth can leave embedded WebViews depending on provider flow and popup behavior.
This repo now keeps all normal HTTP/HTTPS navigation in-app, but if Google forces an external step,
that is provider behavior, not Supabase.
