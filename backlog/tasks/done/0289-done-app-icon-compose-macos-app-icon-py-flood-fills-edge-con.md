---
id: 0289
title: "DONE App icon: compose-macos-app-icon.py flood-fills edge-connected background white to transparent,"
status: done
tags: [task-md, sprint]
files: [Info.plist]
created: unknown
source: TASK.md
---

> Source context: TASK.md → macOS UI

- `DONE` App icon: `compose-macos-app-icon.py` flood-fills edge-connected background white to transparent, then scales the opaque content to ~95% of 1024 (avoids a sharp inner “white frame” from the rect crop); `Info.plist` `CFBundleIconName` = `AppIcon`; no duplicate loose `AppIcon.icns` in the target.
