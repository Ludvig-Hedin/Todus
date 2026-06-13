# Deployment

> How each surface ships. Derived from `wrangler.jsonc` (both apps), `.github/workflows/`, `scripts/`, `docker-compose*.yaml`. Last verified: 2026-06-13.

## Web (`apps/web`)

```bash
pnpm --filter=@zero/web build     # react-router build → build/client/
pnpm --filter=@zero/web deploy    # wrangler deploy
```

- Cloudflare Worker `name: todus`; envs `todus-local` / `todus-staging` / `todus-production`. SPA assets served from `build/client/`.
- Domains (`todus.app`, `staging.todus.app`) are attached in the Cloudflare dashboard — there is **no `routes` key** in `wrangler.jsonc`.
- ⚠️ **Do not use** root `pnpm build:frontend` / `pnpm deploy:frontend` — they still target the legacy `@zero/mail` archive. Both apps deploy to the same Worker name, so the live result is whichever ran last.

## Backend (`apps/server`)

```bash
pnpm deploy:backend               # wrangler deploy --env production
# staging: the apps/server "deploy:staging" script
```

- Worker `name: todus-server-v1`; `api.todus.app` (prod), `sapi.todus.app` (staging) — domains dashboard-attached.
- No CI deploy job exists — backend + web deploys are **manual CLI**.

## Database migrations

- Local/dev: `pnpm db:generate` → review → `pnpm db:migrate` (or `db:push`). See [database.md](database.md).
- Production: **`db-migrate-production.yml`** GitHub Action — triggers on push to `main` touching `apps/server/src/db/migrations/**` or `drizzle.config.ts`, or `workflow_dispatch`. Runs `pnpm run -C apps/server db:migrate` against `secrets.PRODUCTION_DATABASE_URL` (direct Postgres origin, not the Hyperdrive binding). `cancel-in-progress: false`.

## macOS (DMG → R2)

```bash
./scripts/build-mac-dmg.sh        # archive → export → codesign verify → create-dmg → upload to R2
```

- Reads `MARKETING_VERSION` from `TodusMac.xcodeproj`, archives/exports `TodusMac` (Release, `ExportOptions.plist`), builds the DMG via `create-dmg`, uploads with `npx wrangler r2 object put todus-releases/mac/Todus-<version>.dmg`.
- ⚠️ **No notarization/stapling** step (signs but does not run `notarytool`/`stapler`). Run **manually** — not wired to any pnpm script or CI. After upload, update the download URL in `apps/web/app/(full-width)/downloads.tsx`.

## iOS / TestFlight

- iOS scripts (`scripts/ios/`) only **open** the Xcode project or run a **compile smoke check** (`build-native-device.sh` uses `CODE_SIGNING_ALLOWED=NO`, so it does *not* produce a shippable signed build). `pnpm ios:build:production` runs that smoke build.
- **There is no automated TestFlight/App Store upload path.** Submission is **manual via Xcode Organizer**.
- The committed App Store Connect API key (`AuthKey_ZJC3UFF6WX.p8`) is **not** referenced by any workflow or script — see the security note below.

## CI/CD (`.github/workflows/`)

| Workflow | Trigger | Does |
|---|---|---|
| `ci.yml` (`autofix.ci`) | PR | `pnpm install` + `oxlint --deny-warnings`. Lint gate only — no build/test/typecheck. |
| `gitleaks.yml` | PR | Secret scan on PR diffs (forward-looking only — does **not** scan already-committed files). |
| `db-migrate-production.yml` | push to `main` (migrations) / dispatch | Run Drizzle migrations on prod. |
| `lingo-dev.yml` | push to `staging` / dispatch | lingo.dev localization → opens a translations PR. |
| `close-conflicted-prs.yml` | daily cron | Close PRs with ≥3-day merge conflicts. |
| `close-stale-issues.yml` | daily cron | Close issues stale ≥3 days (PRs exempt). |
| `native-release.yml` | PR on `apps/ios/**`/`apps/macos/**`; dispatch | ⚠️ **Broken / legacy.** QA + EAS steps target the dead Expo/RN stack (`@zero/ios` only exists in `apps/archived/archived-rn`; `apps/ios|macos/package.json` are empty; `apps/macos/main.mjs` is the old wrapper). Does not exercise the current native Swift apps. |

## Self-hosting

`docker-compose.db.yaml` is the **local dev** stack (Postgres 17 `:5433`, valkey, upstash-proxy). `docker-compose.prod.yaml` is a **stale Next.js-era self-host artifact** (`NEXT_PUBLIC_*` env, Next-style app image) — it does **not** match the real Cloudflare Workers runtime; treat it as outdated. See [`../SELF_HOSTING.md`](../SELF_HOSTING.md).

## ⚠️ Security — committed signing key

`AuthKey_ZJC3UFF6WX.p8` (an Apple **App Store Connect API private key**, key ID `ZJC3UFF6WX`) is **committed to git and not in `.gitignore`** (a copy also exists under `.claude/worktrees/`). `gitleaks.yml` did not catch it because that workflow scans only new PR diffs. No automation consumes it. **Recommended remediation (owner action):** revoke key `ZJC3UFF6WX` in App Store Connect → Users and Access → Integrations → App Store Connect API, generate a replacement, add `*.p8` to `.gitignore`, `git rm --cached` the file, and purge it from history. Do the same review for `reference/soma/AuthKey_SR63GGCR3C.p8`.
