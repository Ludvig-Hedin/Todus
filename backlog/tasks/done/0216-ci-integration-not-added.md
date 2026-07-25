---
id: 0216
title: "CI integration not added."
status: done
tags: [task-md, sprint]
files: [.github/workflows/ci.yml, apps/web/app/globals.css, apps/ios/Todus/Todus/DesignSystem/AppTheme.swift, apps/macos/TodusMac/DesignSystem/MacTheme.swift]
created: 2026-05-24
source: TASK.md
---

> Source context: TASK.md → Task 16 — Design System screenshot regression suite (2026-05-24) — IN PROGRESS (infra DONE)

- **CI integration not added.** `.github/workflows/ci.yml` is `oxlint`-only today. Recommended (deferred to user): add a job that runs `pnpm parity:screenshots:check -- --surface design-system` on PRs touching `apps/web/app/globals.css`, `apps/ios/Todus/Todus/DesignSystem/AppTheme.swift`, `apps/macos/TodusMac/DesignSystem/MacTheme.swift`, or the three DS viewer files. Optional: capture web baselines in CI if we add a CI-only allowlisted seed user.
