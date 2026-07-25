---
id: 0074
title: "BH-0601b-1 — Recipient TextFields tokenize in the Binding set on every keystroke. Typing a separator eats it:"
status: open
priority: P2
tags: [ios, bug-hunt, code-review-backlog]
files: []
created: 2026-06-01
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-01 — Bug hunt (iOS screenshots: bg color / alignment / thread-load) → Needs attention (not auto-fixed)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| BH-0601b-1 | iOS compose | `apps/ios/Todus/Todus/Features/Email/EmailComposeView.swift:538` (to), cc/bcc same pattern | ⚠️ high (user-facing) | Recipient TextFields tokenize in the Binding `set` on every keystroke. Typing a separator eats it: `"a@b.com,"` → `tokenizeRecipients` → `["a@b.com"]` → `get` re-joins `"a@b.com"`, so the comma/semicolon vanishes and a **2nd recipient cannot be typed** (paste of a full list still works). Classic transform-in-binding SwiftUI anti-pattern. TODO added in code. | Bind each field to a raw `@State` string; tokenize on `.onSubmit` and immediately before send, not on every change. Needs simulator verification — not safely testable in this sandbox. |
