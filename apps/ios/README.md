# Todus iOS WebView App

This app wraps your deployed mail web app in a native iOS shell.

## Quick start

```bash
cd /Users/ludvighedin/Programming/personal/mail/apps/ios
pnpm start
```

For iPhone simulator:

```bash
pnpm ios
```

## Configuration

- Default web base URL: `https://zero-production.ludvighedin15.workers.dev`
- Default backend URL: `https://zero-server-v1-production.ludvighedin15.workers.dev`
- Default app entry URL: `https://zero-production.ludvighedin15.workers.dev/mail/inbox`
- Override URLs:

```bash
EXPO_PUBLIC_WEB_URL=https://your-domain.com pnpm ios
EXPO_PUBLIC_BACKEND_URL=https://your-backend.workers.dev pnpm ios
EXPO_PUBLIC_APP_ENTRY_URL=https://your-domain.com/mail/inbox pnpm ios
```

Bundle identifier is set in `app.config.ts`:

- iOS: `com.ludvighedin.todus`

Change this before App Store/TestFlight submission if needed.

## TestFlight flow

1. Install EAS CLI once:

```bash
pnpm dlx eas-cli@latest --version
```

2. Login and connect project:

```bash
pnpm dlx eas-cli@latest login
pnpm dlx eas-cli@latest init --idempotent
```

3. Build for internal testing:

```bash
pnpm build:ios:preview
```

4. Build for App Store/TestFlight:

```bash
pnpm build:ios:production
pnpm submit:ios
```

## Notes

- External links are opened in Safari.
- In-app loading and retry states are handled in `App.tsx`.
