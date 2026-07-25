---
id: 0327
title: "Organize keeps partial progress, and removing a saved item updates the folder count"
status: unreleased
category: Fixed
tags: [web, tasks, folders]
files: [apps/web/components/tasks/organize-dialog.tsx, apps/web/components/tasks/folder-contents.tsx]
---

Two review follow-ups on the web parity pass in 0326.

**Organize lost its partial progress on failure.** `apply()` files tasks one at a
time, so a mutation that fails halfway still leaves every earlier task filed on the
server. The counter lived inside the `try`, so the `catch` had no way to report it:
the dialog stayed open and no refetch fired, leaving the task list showing tasks as
unfiled that had already moved. The counter is now hoisted, the catch calls
`onApplied(moved)` when anything landed, and the toast says how far it got
("Filed 3 of 7 tasks — the rest failed.") instead of implying nothing happened.

**Folder pill counts went stale on removal.** Unfiling a saved email, event or doc
invalidated `folders.listContents` but not `folders.summary`, which is what backs the
count badge on each folder pill — so the badge kept showing the pre-removal number
until something else happened to refetch it. `removeItem` now invalidates both, the
same pair `folders.create` and `folders.delete` already invalidate.
