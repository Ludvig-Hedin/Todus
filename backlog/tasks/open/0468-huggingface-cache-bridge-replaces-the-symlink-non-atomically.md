---
id: 0468
title: "HuggingFace cache bridge replaces the symlink non-atomically"
status: open
priority: P2
tags: [macos, todo-sweep, local-ai]
files: [apps/macos/TodusMac/Services/AI/Local/HuggingFaceCacheConnector.swift]
created: 2026-07-25
source: code TODO/FIXME sweep
---

`HuggingFaceCacheConnector.swift:227` — `bridgeIntoAppCacheIfPossible` is `nonisolated static` with no serialization, so two concurrent `refresh()` calls can interleave between `removeItem` and `createSymbolicLink`, leaving a missing or stale link. Symptom: MLX re-downloads multi-GB weights.

## Fix shape

The comment already states it: create the link at a temp path in the same directory, then `fm.replaceItemAt(target, withItemAt: tempLink)` for an atomic rename.
