---
id: 0119
title: "Test gaps"
status: done
tags: [code-review, code-review-backlog]
files: []
created: 2026-05-02
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-02 — Full-repo Review

## Test gaps

_Closed by the 2026-06-13 backlog resolution pass (`CODE_REVIEW_BACKLOG.md` → "No open code defects remain": every code-defect item was fixed, built, tested and committed in passes 1-6). Re-open if this finding is still reproducible._


| ID | Area | Approach |
|----|------|----------|
| B-060 | iOS + macOS parsers | Unit-test `LocalTaskParsingService`, `TaskSmartSort`, `CompoundIntentParser`. Cover `today 14` regression (B-011), weekday ordering, time rollover, smart-sort bucket assignment. |
| B-061 | apps/server | Unit-test `classifyThreadKind`, `extractVerificationCode`, `extractReceiptDetails`, `buildAiLeadLine`. Pure functions with high false-positive risk. |
| B-062 | iOS + macOS `withTimeout` | Sleep 5s with 0.1s timeout, assert `.timeout` thrown within ~150 ms. |
| B-063 | macOS compose | Smoke test that builds a draft with cc/bcc/connectionId and asserts wire payload (would have caught B-005). |
