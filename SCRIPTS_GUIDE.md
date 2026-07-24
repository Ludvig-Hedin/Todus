# Scripts Guide

> Last updated: 2026-05-27. For the full command catalog, see [AGENT_CONTEXT.md §8](AGENT_CONTEXT.md#8-commands-youll-actually-run).

## Active App Commands

### iOS (`apps/ios/Todus`)
```bash
bun ios                        # Open Xcode project (lightest)
bun ios:simulator              # Build + boot the iOS simulator
bun ios:build:preview          # Preview .ipa
bun ios:build:production       # App Store / TestFlight .ipa
```

### macOS (`apps/macos/TodusMac`)
Native SwiftUI app (the old Electron flow is retired).
```bash
bun macos                          # Run the macOS app via SwiftPM filter
./scripts/build-mac-dmg.sh          # Archive → sign → upload DMG to Cloudflare R2
```

### Web (`apps/web`) + Backend (`apps/server`)
```bash
bun go                                 # docker DB + apps/web + backend
bun dev                                # apps/web + backend (DB already running)
bun web                                # alias for bun dev
bun run --filter=@zero/web build           # build apps/web specifically
bun run --filter=@zero/web deploy          # deploy apps/web to Cloudflare
bun deploy:backend                     # deploy apps/server to Cloudflare Workers
bun sentry:sourcemaps                  # upload frontend source maps
```

⚠️ The root `bun build:frontend` / `bun deploy:frontend` scripts still target the legacy `apps/mail` archive. Use the `--filter=@zero/web` variants above to ship the active frontend.

### Database (Drizzle ORM + Hyperdrive Postgres)
```bash
bun docker:db:up               # start local Postgres
bun docker:db:stop / down / clean
bun db:generate                # generate migration from schema diff
bun db:migrate                 # apply pending migrations
bun db:push                    # push schema directly (dev shortcut)
bun db:studio                  # Drizzle Studio GUI
```

### Parity Screenshots
```bash
bun parity:screenshots:check                   # presence check across web/ios/macos
bun parity:screenshots:sync                    # sync the screenshot log
bun parity:screenshots:capture:web             # Playwright capture for /settings/* etc.
bun parity:screenshots:capture:ios             # interactive iOS sim capture
bun parity:screenshots:capture:ios:auto        # deeplink-driven (no interaction)
bun parity:screenshots:capture:macos:auto      # native macOS capture
bun parity:screenshots:capture:android:auto    # Android emulator capture
```

### AI / Evals / Tests
```bash
bun run test                       # vitest in packages/testing
bun test:watch / test:coverage / test:ui
bun run test -- -t "test name"     # single test by name
bun test:ai                    # backend AI tests
bun eval / eval:dev / eval:ci  # backend AI evals
```

## Removed From Active Use

The old `native:*` scripts were removed from root `package.json`. Legacy app implementations are archived under `apps/archived/*` and `apps/mail/` and should not be used for active development.
