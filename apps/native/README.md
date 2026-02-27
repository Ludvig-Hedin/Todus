# Zero Native (React Native iOS + macOS)

Cross-platform native shell for the Zero/Todus product using React Native + react-native-macos.

## What this app does

- Uses native navigation/auth/session shell.
- Loads active web product routes in RN WebView for high-fidelity parity.
- Supports provider discovery and OAuth handoff through staging backend.
- Persists native session metadata, theme preference, and last visited path.

## Key scripts

From repo root:

```bash
pnpm native:start
pnpm native:ios
pnpm native:macos
pnpm native:ios:compile
pnpm native:macos:compile
```

Direct package commands:

```bash
pnpm --filter @zero/native typecheck
pnpm --filter @zero/native test --watch=false
pnpm --filter @zero/native ios:build:compile
pnpm --filter @zero/native macos:build:compile
```

## Environment

Set these for staging/local targets:

```bash
ZERO_PUBLIC_WEB_URL=https://todus.app
ZERO_PUBLIC_BACKEND_URL=https://api.todus.app
ZERO_PUBLIC_APP_ENTRY_PATH=/mail/inbox
# Must match whatever is in your browser's address bar + /mail/inbox
ZERO_PUBLIC_AUTH_CALLBACK_URL=https://todus.app/mail/inbox
ZERO_PUBLIC_APP_NAME=Todus
```

## Notes

- Compile scripts run with code signing disabled for deterministic local compile validation.
- Signed/internal distribution is tracked in `MANUAL_INPUTS_GUIDE.md`.
