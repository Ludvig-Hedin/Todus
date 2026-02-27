# Todus iOS App

Native React Native (Expo Router) mail client for iOS.

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

- Default web URL: `https://todus.app`
- Default backend URL: `https://api.todus.app`
- Default app entry URL: `https://todus.app/mail/inbox`
- Default app name: `Todus`
- Override URLs:

```bash
EXPO_PUBLIC_WEB_URL=https://todus.app pnpm ios
EXPO_PUBLIC_BACKEND_URL=https://api.todus.app pnpm ios
EXPO_PUBLIC_APP_NAME=Todus pnpm ios
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

- OAuth login opens Google consent screen directly in a WebView (no intermediate web login page).
- Bearer token stored in iOS Keychain via `expo-secure-store`.
- TRPC queries use Bearer auth header for API calls.
