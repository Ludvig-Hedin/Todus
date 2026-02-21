# Zero iOS WebView App

This app wraps the deployed Zero web app in a native iOS shell.

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

- Default URL: `https://0.email`
- Override URL:

```bash
EXPO_PUBLIC_WEB_URL=https://your-domain.com pnpm ios
```

Bundle identifier is set in `app.config.ts`:

- iOS: `com.ludvighedin.zero`

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
