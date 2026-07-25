---
id: 0118
title: "Hygiene (do not commit)"
status: done
tags: [code-review, code-review-backlog]
files: [new-website/dev.log, new-website/relume/dev.log, **/dev.log, new-website/check-font.js, new-website/check-page.js, new-website/screenshot.js]
created: 2026-05-02
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-02 — Full-repo Review

## Hygiene (do not commit)

_Closed by the 2026-06-13 backlog resolution pass (`CODE_REVIEW_BACKLOG.md` → "No open code defects remain": every code-defect item was fixed, built, tested and committed in passes 1-6). Re-open if this finding is still reproducible._


| ID | File | Action |
|----|------|--------|
| B-050 | `new-website/dev.log` (untracked), `new-website/relume/dev.log` (modified) | `git rm --cached new-website/relume/dev.log`; add `**/dev.log` to root `.gitignore`. |
| B-051 | `new-website/check-font.js`, `new-website/check-page.js`, `new-website/screenshot.js` (all 0 bytes) | Delete locally; if planned tooling, write content first. |
