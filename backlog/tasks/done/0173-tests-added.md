---
id: 0173
title: "Tests added"
status: done
tags: [macos, qa, code-review-backlog]
files: [apps/macos/TodusMacTests/EmailDecodeToleranceTests.swift, apps/macos/scripts/run-email-decode-tests.sh, scripts/email-decode-tests/main.swift, EmailModels.swift]
created: 2026-06-13
source: CODE_REVIEW_BACKLOG.md
---

> Source context: macOS QA pass — 2026-06-13 — email loading / thread-open / hangs

## Tests added

- `apps/macos/TodusMacTests/EmailDecodeToleranceTests.swift` — XCTest (real types via `@testable import Todus`) covering sender/message/thread decode tolerance + the one-bad-message regression.
- `apps/macos/scripts/run-email-decode-tests.sh` + `scripts/email-decode-tests/main.swift` — Xcode-free runner that compiles the **real** `EmailModels.swift` and runs the decode regressions (11/11 green). Use this until the XCTest target is wired (see blocker below).
