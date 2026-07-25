---
id: 0207
title: "scripts/parity/capture-ios-deeplink.mjs: added --surface filter and support for manifest-supplied io"
status: done
tags: [task-md, sprint]
files: [scripts/parity/capture-ios-deeplink.mjs, apps/ios/Todus/Todus/App/TodosApp.swift]
created: 2026-05-24
source: TASK.md
---

> Source context: TASK.md → Task 16 — Design System screenshot regression suite (2026-05-24) — IN PROGRESS (infra DONE)

- `scripts/parity/capture-ios-deeplink.mjs`: added `--surface` filter and support for manifest-supplied `iosDeepLink` overrides. **The DesignSystem* slugs are explicitly skipped by this script** because the iOS app has no `/settings/*` deep-link handler today (see `apps/ios/Todus/Todus/App/TodosApp.swift` `.onOpenURL` — only `auth-callback`, `link-callback`, `share`, `mailto` are routed). The script now exits a clear failure rather than capturing whatever the simulator happens to be showing. Use the interactive capture flow for DS slugs.
