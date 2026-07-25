---
id: 0166
title: "Fixed — sixth batch (MAC-1, after a deeper root-cause fix)"
status: done
tags: [macos, code-review-backlog]
files: [project.yml, EmailModels.swift, Domain/EmailThreadResponse.swift]
created: 2026-06-13
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Backlog resolution pass — 2026-06-13 (whole-repo)

## Fixed — sixth batch (MAC-1, after a deeper root-cause fix)

- **MAC-1** — TodusMacTests now runs in Xcode/CI. Root cause turned out deeper than "regen risk": `project.yml` had **no `packages:` section**, so the MLX SPM packages (added via the Xcode UI) were missing from it and every `xcodegen generate` silently dropped them (19→4 MLX refs) and broke the app's `Cmlx`/`_NumericsShims` resolution. Fix: (1) declared `mlx-swift-examples` (2.29.1) in `project.yml` + linked `MLXLLM`/`MLXLMCommon` on the app target — the project is now **regen-safe**; (2) made `EmailModels.swift` Foundation-only (`AppLogger` → `#if DEBUG print`) and moved `GetThreadResponse`/`FailableDecodable`/`EmailThreadDetail` into a Foundation-only `Domain/EmailThreadResponse.swift`; (3) made `TodusMacTests` a standalone host-less logic bundle compiling those two files directly (no `@testable`/MLX host) + a dedicated `TodusMacTests` scheme that builds only the test target. Verified: macOS app `BUILD SUCCEEDED` (MLX refs back to 19), `xcodebuild test -scheme TodusMacTests` → **11/11 pass**.
