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
Run from repo root (and do NOT append inline `# ...` text after the command, since that can be forwarded as real CLI args).

```bash
pnpm run build:frontend

# NOTE: `wrangler` is not installed globally in this repo.
# Use `pnpm --filter=... exec wrangler ...` to run the correct local CLI version.

# Deploy staging
pnpm --filter=@zero/server exec wrangler deploy -e staging
pnpm --filter=@zero/mail exec wrangler deploy -e staging

# Deploy production
pnpm --filter=@zero/server exec wrangler deploy -e production
pnpm --filter=@zero/mail exec wrangler deploy -e production
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
