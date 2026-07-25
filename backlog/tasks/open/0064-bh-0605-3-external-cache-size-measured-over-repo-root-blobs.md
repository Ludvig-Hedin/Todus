---
id: 0064
title: "BH-0605-3 — External-cache size measured over repo root (blobs/ + snapshots/) while the weight check scans onl"
status: open
priority: P4
tags: [ios, macos, bug-hunt, code-review-backlog]
files: [HuggingFaceCacheConnector.swift]
created: 2026-06-05
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-05 — Bug hunt (iOS + macOS changed files) → Needs attention (not auto-fixed — TODO added in code where noted)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| BH-0605-3 | macOS local AI | `HuggingFaceCacheConnector.swift` `collectExternalCache` | 🔵 low | External-cache size measured over repo root (`blobs/` + `snapshots/`) while the weight check scans only `snapshots/` → size can ~2× inflate when snapshots aren't symlinks into blobs; a weight present only in stale `blobs/` is listed yet fails to bridge. | `directorySize` over `snapshots/` (symlink-resolved), not the repo root. |
