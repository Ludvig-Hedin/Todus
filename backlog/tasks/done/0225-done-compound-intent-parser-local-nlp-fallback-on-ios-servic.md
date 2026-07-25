---
id: 0225
title: "DONE Compound intent parser + local NLP fallback on iOS — Services/Parsing/CompoundIntentParser.swif"
status: done
tags: [task-md, sprint]
files: [Services/Parsing/CompoundIntentParser.swift]
created: 2026-05-17
source: TASK.md
---

> Source context: TASK.md → Current iOS Parity + Hardening Sprint (2026-05-17)

- `DONE` **Compound intent parser + local NLP fallback on iOS** — `Services/Parsing/CompoundIntentParser.swift` patched with word-boundary regex (port of macOS refinements); `RemoteFirstTaskParsingService.parseCompoundLocally(...)` hook added so callers can get multi-intent results.
