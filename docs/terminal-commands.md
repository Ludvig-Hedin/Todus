# Todus Terminal Commands

All commands below are run from:

```bash
cd /Users/ludvighedin/Programming/personal/mail
```

## First-time setup

```bash
pnpm install
pnpm nizzy env
pnpm nizzy sync
pnpm docker:db:up
pnpm db:push
```

## Start local web + backend

```bash
pnpm dev
```

## Start only iOS app (Expo)

```bash
pnpm ios
```

## Open iOS simulator directly

```bash
pnpm ios:simulator
```

## Start macOS WebView app (Electron)

```bash
pnpm macos
```

## Deploy your web frontend + backend to Cloudflare

```bash
pnpm deploy:frontend
pnpm deploy:backend
```

## Build iOS for TestFlight

```bash
pnpm ios:build:production
```

## Submit iOS build to App Store Connect / TestFlight

```bash
pnpm --filter=@zero/ios submit:ios
```

## Optional: internal iOS preview build

```bash
pnpm ios:build:preview
```

## Stop local DB

```bash
pnpm docker:db:down
```
