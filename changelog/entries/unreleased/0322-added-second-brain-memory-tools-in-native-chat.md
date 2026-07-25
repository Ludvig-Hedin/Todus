---
id: 0322
title: "Added — second-brain memory tools in native chat"
status: unreleased
category: Added
release_date: 2026-07-23
source: CHANGELOG.md
---

### Added — second-brain memory tools in native chat, 2026-07-23

- iOS/macOS AI chat (`POST /api/ai/chat`) now exposes the three read-only second-brain memory tools previously available only to the web chat. Native clients proxy execution to `POST /api/ai/do/<tool>` with Bearer auth and return the JSON result to the model.
