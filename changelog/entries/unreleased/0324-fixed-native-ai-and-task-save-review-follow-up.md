---
id: 0324
title: "Fixed — native AI and task-save review follow-up"
status: unreleased
category: Fixed
release_date: 2026-07-24
source: CHANGELOG.md
---

### Fixed — native AI and task-save review follow-up, 2026-07-24

- iOS task creation and task-detail editing now keep drafts, attachments, and sheets open when SwiftData persistence fails. Removed attachment files are deleted only after the task update commits.
- Kept the one-time cloud-processing disclosure before the first AI message or voice session.
- Native iOS/macOS AI chat now exposes the read-only second-brain tools `getPersonContext`, `getWorkstreamContext`, and `getOpenLoops`; backend limits are integer-normalized before database queries.
