---
id: 0174
title: "✅ Auto-fixed this pass (3 — small, verified-safe)"
status: done
tags: [ios, macos, web, code-review, code-review-backlog]
files: []
created: 2026-06-13
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-13 — Full-repo review pass (uncommitted iOS/macOS/web + commits 3fc07eae, 2ca46e3b, 22afa335)

## ✅ Auto-fixed this pass (3 — small, verified-safe)

| File:line | Severity | What changed |
|-----------|----------|--------------|
| `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift:1532` | 🟡 med | `formatCredits` lacked the `scaled.isFinite` + `scaled < Double(Int.max)` guards that iOS `BillingSettingsView.formatCredits` has, yet is called with raw decoded server values (`aiUsageUsed`/`aiUsageLimit`). A corrupted/NaN value would trap `Int(NaN.rounded())` and crash the macOS Billing tab. Mirrored the two iOS guards verbatim (return `"—"`). Honors the "keep all three platforms in sync" rule. |
| `apps/ios/Todus/Todus/Services/Tasks/SupabaseSyncService.swift:64` | 🔵 info | Removed a stale, self-contradicting `TODO` claiming `retryUnsyncedTasks` still needed wiring to `NetworkMonitor` "at the AppServices level" — it is already wired at `AppServices.swift:926` (`networkMonitor.onReconnect`), as line 166 in the same file asserts. Replaced with an accurate doc line. |
| `apps/ios/Todus/Todus/Features/Calendar/CalendarTabView.swift:197` | 🔵 info | Fixed a stale comment ("Today FAB — bottom-left") that contradicted the code, which centers the FAB (Spacer on both sides; inner comment already says "Centered"). Changed to "bottom-center". |
