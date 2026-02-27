# Todus macOS WebView App

This is a lightweight Electron wrapper around your deployed Todus frontend.

## Run

```bash
cd /Users/ludvighedin/Programming/personal/mail/apps/macos
pnpm dev
```

## Defaults

- Web: `https://todus-production.ludvighedin15.workers.dev`
- Backend/Auth: `https://todus-server-v1-production.ludvighedin15.workers.dev`
- Entry: `/mail/inbox`
- App name: `Todus`

## Override

```bash
EXPO_PUBLIC_WEB_URL=https://your-domain.com pnpm dev
EXPO_PUBLIC_BACKEND_URL=https://your-backend.workers.dev pnpm dev
EXPO_PUBLIC_APP_ENTRY_URL=https://your-domain.com/mail/inbox pnpm dev
EXPO_PUBLIC_APP_NAME=YourAppName pnpm dev
```
