---
id: 0249
title: "DONE Review follow-up: duplicate iOS assistant cache file + invalid Ollama persistence + session log"
status: done
tags: [task-md, sprint]
files: []
created: unknown
source: TASK.md
---

> Source context: TASK.md → Current Native Fix Batch

- `DONE` **Review follow-up: duplicate iOS assistant cache file + invalid Ollama persistence + session logout semantics (2026-04):** removed `AssistantPersistedCache 2.swift` from the iOS project, prevented shared web/mail model selectors from saving `aiProvider='ollama'` without an installed model, and changed `sessions.revokeAll` to exclude the current session so "Sign out all other devices" matches the UI label.
