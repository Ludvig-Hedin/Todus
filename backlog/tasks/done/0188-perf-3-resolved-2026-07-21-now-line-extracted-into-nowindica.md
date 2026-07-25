---
id: 0188
title: "PERF-3 — Resolved 2026-07-21 — now-line extracted into NowIndicatorView with TimelineView(.periodic) aligned t"
status: done
tags: [ios, performance, code-review-backlog]
files: [Features/Calendar/CalendarTimeGridView.swift]
created: 2026-07-11
source: CODE_REVIEW_BACKLOG.md
---

> Source context: iOS performance pass — deferred findings, 2026-07-11

| ID | File | Issue | Fix direction | Why deferred |
|----|------|-------|---------------|--------------|
| ~~PERF-3~~ | `Features/Calendar/CalendarTimeGridView.swift` | ~~60s now-line tick mutated grid-level `@State now` → full-grid relayout every minute~~ | **Resolved 2026-07-21** — now-line extracted into `NowIndicatorView` with `TimelineView(.periodic)` aligned to minute boundaries; top-level `now` state, Combine timer + import removed. Visually re-verify line/dot position on day + multi-day. | — |
