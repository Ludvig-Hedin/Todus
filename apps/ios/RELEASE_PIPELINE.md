# Native Release Pipeline

Last updated: 2026-03-02

## Scope

This pipeline covers:

- iOS release validation + EAS build
- Android release validation + EAS build (same Expo app)
- macOS wrapper smoke validation (`apps/macos/main.mjs` syntax check)

Workflow file:

- `.github/workflows/native-release.yml`

## What Runs Automatically

On pull requests that touch native code:

1. `pnpm --filter @zero/ios run test:unit`
2. `pnpm --filter @zero/ios run bundle:ios`
3. `node --check apps/macos/main.mjs`

## Release Build Trigger (Manual)

Use GitHub Actions -> `Native Release Pipeline` -> `Run workflow`.

Inputs:

- `platform`: `ios` or `android`
- `profile`: `preview` or `production`
- `submit`: `true/false`

Build command used by the workflow:

```bash
pnpm dlx eas-cli build --platform <ios|android> --profile <preview|production> --non-interactive --no-wait
```

If `submit=true`, it also runs:

```bash
pnpm dlx eas-cli submit --platform <ios|android> --profile production --non-interactive
```

## Required GitHub Secrets

Minimum:

- `EXPO_TOKEN`

Optional (only for automated submit):

- iOS App Store Connect credentials required by EAS submit
- Android Play Console service account credentials required by EAS submit

If `EXPO_TOKEN` is missing, the workflow reports a skipped EAS release step.

## Manual Release Dependencies (Outside Repo)

- Apple signing setup and App Store Connect configuration
- Google Play Console service account and app setup
- Store listing/review and rollout actions

These remain manual because they depend on external account credentials and approvals.
