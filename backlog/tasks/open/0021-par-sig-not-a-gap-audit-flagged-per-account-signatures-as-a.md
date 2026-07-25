---
id: 0021
title: "PAR-SIG (not a gap) — Audit flagged per-account signatures as a web localStorage \"data-loss bug\". On re-check"
status: open
priority: P3
tags: [web, code-review-backlog]
files: [apps/web/.../settings/signatures/page.tsx, apps/macos/.../MacSignatureStore.swift]
created: 2026-06-13
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Web → Native parity — deferred sub-items (2026-06-13)

| ID | Area | Where | Problem | Suggested fix |
|----|------|-------|---------|---------------|
| PAR-SIG (not a gap) | Signatures | `apps/web/.../settings/signatures/page.tsx`, `apps/macos/.../MacSignatureStore.swift` | Audit flagged per-account signatures as a web localStorage "data-loss bug". On re-check this is **at parity**: macOS also stores them locally (UserDefaults). Both are local-per-device by design. | No action — fixing web to server-sync would *diverge* from native. Revisit only if cross-device signatures become a product goal (would need a server table + native changes). |
