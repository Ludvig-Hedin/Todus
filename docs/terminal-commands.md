# Todus Terminal Commands

All commands below are run from:

```bash
cd /Users/ludvighedin/Programming/personal/mail
```

## First-time setup

```bash
bun install
bun nizzy env
bun nizzy sync
bun docker:db:up
bun db:push
```

## Start local web + backend

```bash
bun dev
```

## Start only iOS app (Expo)

```bash
bun ios
```

## Open iOS simulator directly

```bash
bun ios:simulator
```

## Start macOS WebView app (Electron)

```bash
bun macos
```

## Deploy your web frontend + backend to Cloudflare
Run from repo root (and do NOT append inline `# ...` text after the command, since that can be forwarded as real CLI args).

```bash
bun run build:frontend

# NOTE: `wrangler` is not installed globally in this repo.
# Use `bun run --filter=... exec wrangler ...` to run the correct local CLI version.

# Deploy staging
bun run --filter=@zero/server exec wrangler deploy -e staging
bun run --filter=@zero/mail exec wrangler deploy -e staging

# Deploy production
bun run --filter=@zero/server exec wrangler deploy -e production
bun run --filter=@zero/mail exec wrangler deploy -e production
```

## Build iOS for TestFlight

```bash
bun ios:build:production
```

## Submit iOS build to App Store Connect / TestFlight

```bash
bun run --filter=@zero/ios submit:ios
```

## Optional: internal iOS preview build

```bash
bun ios:build:preview
```

## Stop local DB

```bash
bun docker:db:down
```
