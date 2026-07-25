---
id: 0130
title: "Investigated, not bugs (false positives from investigator subagent)"
status: done
tags: [web, bug-hunt, code-review-backlog]
files: []
created: 2026-05-20
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-20 — Bug Hunt: apps/web main user flows

## Investigated, not bugs (false positives from investigator subagent)

- **`apps/web/components/mail/thread-display.tsx:212`** — `Math.max(1, focusedIndex + 1)`. `focusedIndex` is guaranteed `>= 0` by the `focusedIndex === null` early return on the previous line, so the clamp is a no-op (redundant but harmless).
- **`apps/web/components/mail/mail-list.tsx:177`** — `setFocusedIndex(focusedIndex)`. After the optimistic move/archive removes the current row, the list shifts left by one, so the OLD index now points at the formerly-next sibling — keeping the index intentional.
- **`apps/web/components/create/create-email.tsx:91`** — Calling `useActiveConnection()` twice (lines 79 + 91) produces two bindings (`activeConnection`, `activeAccount`) that resolve to the same react-query cache entry. Wasteful but not a bug; both used in different fallback chains for `userEmail` / `userName`.
- **`apps/web/components/create/email-composer.tsx:480`** — `editor.getHTML() === initialMessage.trim()` is a defensive double-check alongside the plain-text comparison on line 479. `initialMessage` may be HTML (draft body) or plain text (replies) depending on call site; the dual comparison catches both forms.
- **`apps/web/app/(routes)/mail/[folder]/page.tsx:59-61`** — The `else { setIsLabelValid(false) }` branch when `userLabels` is falsy. `useLabels()` returns `userLabels: []` (empty array, truthy) even on error/loading, so this branch is unreachable dead code. UI's auto-redirect timer still fires via the `if (userLabels)` path (empty array passes `checkLabelExists` returning false, then starts the timer).

---
