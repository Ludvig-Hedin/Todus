---
id: 0080
title: "BH-0601-3 — legacyCalendarEvent.id switched from composite (apple:/google:) to raw providerEventId. SwiftUI li"
status: open
priority: P3
tags: [bug-hunt, code-review-backlog]
files: []
created: 2026-06-01
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-01 — Bug hunt (uncommitted + last 3 commits) → Needs attention (not auto-fixed)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| BH-0601-3 | macOS calendar | `apps/macos/TodusMac/Services/Calendar/UnifiedCalendarService.swift:24` | 🟡 medium | `legacyCalendarEvent.id` switched from composite (`apple:`/`google:`) to raw `providerEventId`. SwiftUI lists key on `id`; if an Apple and Google event ever share a provider id, duplicate `Identifiable` ids drop/duplicate rows. Cross-provider collision is unlikely (matches iOS) but unguarded. | Keep a composite id for list identity; expose `providerEventId` separately for EKEventStore lookups. |
