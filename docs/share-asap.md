# Share Todus ASAP (iPhone + Mac)

## Fastest path for friends today

1. Deploy web + backend and share URL immediately:

```bash
pnpm deploy:frontend
pnpm deploy:backend
```

2. iPhone app via TestFlight:

```bash
pnpm ios:build:production
pnpm --filter=@zero/ios submit:ios
```

Then in App Store Connect:
- add Internal Testers first
- add External Testers next (beta review required)

3. Mac usage right now:
- share the same web URL immediately
- optional desktop wrapper: `apps/macos`

## Active app structure

- iPhone native app: `apps/ios`
- Desktop webview wrapper: `apps/macos`
- Legacy/duplicate apps: `apps/archived/*` (reference only)

## Native iOS auth return requirements

To return from Google auth back into app instead of staying in browser:

1. iOS app URL scheme `todus://` must be configured in `apps/ios/app.config.ts`.
2. Web login should use callback `todus://auth-callback` for native flows.
3. Backend trusted origins/redirect allowlist must include `todus://auth-callback`.
4. Redeploy backend + frontend after auth config changes:

```bash
pnpm deploy:backend
pnpm deploy:frontend
```
