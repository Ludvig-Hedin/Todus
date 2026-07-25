---
id: 0127
title: "Recommended fix order"
status: done
tags: [ios, bug-hunt, ux, code-review-backlog]
files: []
created: 2026-05-17
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-17 — iOS Bug-Hunt + UX-Polish Audit

## Recommended fix order

1. **Today (security/data loss):** C1, H1 (auth token leaks); C2 (notification deep-links dead); C3+C4 (AI mutation deadlock+leak).
2. **This week (user-visible silent failures):** C5, H3, H4, H5 (email silent failures); H9, H10, H11 (calendar Day view + crashes); H15, H16 (TRPC wire format).
3. **Next sprint (data integrity):** H2, H6, H7, H8, H12, H17 + medium-severity sync/persistence items.
4. **Polish backlog:** Top-20 polish list — most are ≤5 line changes, batch into a single PR.

Full per-agent transcripts available at task IDs af528b40, ac4cfe8a, a5957fb7, a1675c0e, a8be1ed8, ad5e823b.

---
