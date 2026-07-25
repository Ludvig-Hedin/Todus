# User tasks

Work **only the owner can do**, because it lives outside this repository: environment
variables on a host, third-party dashboards, Apple/Google console steps, signing,
account creation, live-credential verification.

Agents file tasks here and read them for context. Agents do **not** tick the boxes.

## Layout

```
user-tasks/
  tasks/open/   NNNN-<slug>.md
  tasks/done/   NNNN-<slug>.md
```

Own 4-digit sequence, independent of `backlog/`.

## Front matter

```yaml
---
id: 0010
title: "Confirm the X key is revoked"
status: open            # open | done
priority: P1            # P0–P4
area: security          # auth · billing · infra · security · qa · ops · legal · apps ·
                        # integrations · analytics · seo · support · misc
source: "CODE_REVIEW_BACKLOG.md — release review 2026-07-24"
created: 2026-07-25
---
```

## Writing the body

Checkboxes, and **exact**: name the variable *and where it lives* (which host's project
env vs which backend), the dashboard, the account, the command. "Set the API key" is not
a task; "set `VITE_PUBLIC_ELEVENLABS_AGENT_ID` in the Cloudflare Workers env for
`@zero/web`" is.

Rule for agents: **never tick a box from a presence check when the claim is about
behaviour.** A variable being *set* is not a webhook being *delivered*, and a key file
being absent locally is not a key being *revoked*.

## Commands

```bash
bun user-tasks:check                 # next free id + collisions + unchecked-box counts
bun user-tasks:check --json
bun user-tasks:check --write-readme  # regenerate the table below
```

## Open tasks

<!-- agent-ops:index:start -->

| id | priority | area | title | open boxes |
| --- | --- | --- | --- | --- |
| 0001 | P0 | security | [Confirm Apple key ZJC3UFF6WX is revoked in App Store Connect](tasks/open/0001-confirm-apple-key-zjc3uff6wx-is-revoked-in-app-store-connect.md) | 5 |
| 0002 | P0 | ops | [Deploy apps/server before the next native release](tasks/open/0002-deploy-apps-server-before-the-next-native-release.md) | 3 |
| 0003 | P1 | integrations | [Activate ElevenLabs voice client tools (dashboard + env)](tasks/open/0003-activate-elevenlabs-voice-client-tools-dashboard-env.md) | 4 |
| 0004 | P1 | infra | [Provide the public R2 URL for the Mac DMG download](tasks/open/0004-provide-the-public-r2-url-for-the-mac-dmg-download.md) | 3 |
| 0005 | P1 | auth | [Create the native Google OAuth client and redirect URIs](tasks/open/0005-create-the-native-google-oauth-client-and-redirect-uris.md) | 4 |
| 0006 | P1 | infra | [Set the backend and native environment values for the target deploy](tasks/open/0006-set-the-backend-and-native-environment-values-for-the-target.md) | 4 |
| 0007 | P1 | apps | [Upload the iOS and macOS internal archives and verify testers can sign in](tasks/open/0007-upload-the-ios-and-macos-internal-archives-and-verify-tester.md) | 3 |
| 0008 | P2 | analytics | [Provide production analytics, Intercom and Sentry keys](tasks/open/0008-provide-production-analytics-intercom-and-sentry-keys.md) | 4 |
| 0009 | P3 | apps | [Set up the Android signing keystore and Play Console tracks](tasks/open/0009-set-up-the-android-signing-keystore-and-play-console-tracks.md) | 3 |

### Do first — P0 blockers

- **0001** — [Confirm Apple key ZJC3UFF6WX is revoked in App Store Connect](tasks/open/0001-confirm-apple-key-zjc3uff6wx-is-revoked-in-app-store-connect.md) (5 open box(es))
- **0002** — [Deploy apps/server before the next native release](tasks/open/0002-deploy-apps-server-before-the-next-native-release.md) (3 open box(es))

<!-- agent-ops:index:end -->
