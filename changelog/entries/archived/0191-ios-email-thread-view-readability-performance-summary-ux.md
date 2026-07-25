---
id: 0191
title: "iOS Email Thread View — Readability, Performance & Summary UX"
status: archived
category: Changed
release_date: 2026-04-04
source: CHANGELOG.md
---

## [2026-04-04] iOS Email Thread View — Readability, Performance & Summary UX

- [Fix] Dark mode email readability: universal `* { background-color: transparent !important }` CSS override strips all inline/HTML backgrounds in WKWebView; JS post-load strips `bgcolor` HTML attributes; forces all text to `#e0e0e0` in dark mode so emails are always readable (`EmailThreadView.swift`)
- [Fix] Performance: email body shows plain text instantly on expand, defers WKWebView HTML rendering by 150ms to avoid 3-5 second UI hang (`EmailThreadView.swift`)
- [Enhancement] Summary card: "Not summarized yet" with outlined "Summarize" button (gradient sparkles icon, muted stroke, no fill) triggers on-demand summarization; shows actual error message on failure (`EmailThreadView.swift`, `EmailService.swift`)
- [Enhancement] Header background: pure gradient fade (no solid fill), starts at 0.9 opacity and fades to transparent — content smoothly fades under the bar (`EmailThreadView.swift`)
- [Fix] Bottom reply bar: removed solid `backgroundTop` fill behind buttons, replaced with single smooth gradient that extends 30pt above the buttons — no more harsh cutoff (`EmailThreadView.swift`)
- [Fix] Added `loadAssistantThrowing` to `EmailService` so Summarize button can surface real error messages instead of generic "Could not generate summary" (`EmailService.swift`)
