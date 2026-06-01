# Scripts Guide

> Last updated: 2026-05-27. For the full command catalog, see [AGENT_CONTEXT.md §8](AGENT_CONTEXT.md#8-commands-youll-actually-run).

## Active App Commands

### iOS (`apps/ios/Todus`)
```bash
pnpm ios                        # Open Xcode project (lightest)
pnpm ios:simulator              # Build + boot the iOS simulator
pnpm ios:build:preview          # Preview .ipa
pnpm ios:build:production       # App Store / TestFlight .ipa
```

### macOS (`apps/macos/TodusMac`)
Native SwiftUI app (the old Electron flow is retired).
```bash
pnpm macos                          # Run the macOS app via SwiftPM filter
./scripts/build-mac-dmg.sh          # Archive → sign → upload DMG to Cloudflare R2
```

### Web (`apps/web`) + Backend (`apps/server`)
```bash
pnpm go                                 # docker DB + apps/web + backend
pnpm dev                                # apps/web + backend (DB already running)
pnpm web                                # alias for pnpm dev
pnpm --filter=@zero/web build           # build apps/web specifically
pnpm --filter=@zero/web deploy          # deploy apps/web to Cloudflare
pnpm deploy:backend                     # deploy apps/server to Cloudflare Workers
pnpm sentry:sourcemaps                  # upload frontend source maps
```

⚠️ The root `pnpm build:frontend` / `pnpm deploy:frontend` scripts still target the legacy `apps/mail` archive. Use the `--filter=@zero/web` variants above to ship the active frontend.

### Database (Drizzle ORM + Hyperdrive Postgres)
```bash
pnpm docker:db:up               # start local Postgres
pnpm docker:db:stop / down / clean
pnpm db:generate                # generate migration from schema diff
pnpm db:migrate                 # apply pending migrations
pnpm db:push                    # push schema directly (dev shortcut)
pnpm db:studio                  # Drizzle Studio GUI
```

### Parity Screenshots
```bash
pnpm parity:screenshots:check                   # presence check across web/ios/macos
pnpm parity:screenshots:sync                    # sync the screenshot log
pnpm parity:screenshots:capture:web             # Playwright capture for /settings/* etc.
pnpm parity:screenshots:capture:ios             # interactive iOS sim capture
pnpm parity:screenshots:capture:ios:auto        # deeplink-driven (no interaction)
pnpm parity:screenshots:capture:macos:auto      # native macOS capture
pnpm parity:screenshots:capture:android:auto    # Android emulator capture
```

### AI / Evals / Tests
```bash
pnpm test                       # vitest in packages/testing
pnpm test:watch / test:coverage / test:ui
pnpm test -- -t "test name"     # single test by name
pnpm test:ai                    # backend AI tests
pnpm eval / eval:dev / eval:ci  # backend AI evals
```

## Removed From Active Use

The old `native:*` scripts were removed from root `package.json`. Legacy app implementations are archived under `apps/archived/*` and `apps/mail/` and should not be used for active development.
