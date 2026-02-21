# Zero macOS WebView App

This is a lightweight Electron wrapper around your deployed Zero frontend.

## Run

```bash
cd /Users/ludvighedin/Programming/personal/mail/apps/macos
pnpm dev
```

## Defaults

- Web: `https://zero-production.ludvighedin15.workers.dev`
- Backend/Auth: `https://zero-server-v1-production.ludvighedin15.workers.dev`
- Entry: `/mail/inbox`

## Override

```bash
EXPO_PUBLIC_WEB_URL=https://your-domain.com pnpm dev
EXPO_PUBLIC_BACKEND_URL=https://your-backend.workers.dev pnpm dev
EXPO_PUBLIC_APP_ENTRY_URL=https://your-domain.com/mail/inbox pnpm dev
```
