---
id: 0024
title: "MAC-1 — Test target is defined in project.yml but not runnable yet: xcodebuild test fails resolving MLX's Cmlx"
status: open
priority: P2
tags: [macos, code-review, qa, code-review-backlog]
files: [project.yml, scripts/run-email-decode-tests.sh]
created: 2026-06-13
source: CODE_REVIEW_BACKLOG.md
---

> Source context: macOS QA pass — 2026-06-13 — email loading / thread-open / hangs → Needs human review (deferred)

| ID | Area | Where | Sev | Problem | Suggested fix |
|----|------|-------|-----|---------|---------------|
| MAC-1 | Test infra | `project.yml` `TodusMacTests` | 🟠 high | Test target is defined in `project.yml` but **not runnable** yet: `xcodebuild test` fails resolving MLX's `Cmlx`/`_NumericsShims` C modules in the `@testable` test-host rebuild (regular `build` is fine). Also: a bare `xcodegen generate` rewrites ~285 lines of the committed `project.pbxproj` (drift), so it wasn't regenerated this pass. | Wire MLX C-module search paths for the testable build (or split email models into an SPM lib target with no MLX dep that the test target imports), then regenerate the project intentionally and commit the pbxproj. Interim: `scripts/run-email-decode-tests.sh`. |
