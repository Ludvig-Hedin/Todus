---
id: 0117
title: "Low severity / suggestions"
status: done
tags: [code-review, code-review-backlog]
files: [apps/ios/Todus/Todus/Services/AI/AIChatService.swift, apps/web/app/(routes)/mail/tasks/page.tsx]
created: 2026-05-02
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-02 — Full-repo Review

## Low severity / suggestions

_Closed by the 2026-06-13 backlog resolution pass (`CODE_REVIEW_BACKLOG.md` → "No open code defects remain": every code-defect item was fixed, built, tested and committed in passes 1-6). Re-open if this finding is still reproducible._


| ID | File:line | Type | Summary |
|----|-----------|------|---------|
| B-020 | `apps/server/src/trpc/routes/assistant.ts:432-453` | correctness | `extractVerificationCode` fallback regex picks any 4-8 digit number — order numbers, postal codes, phone fragments. Wrong "verification" code is a tap-to-copy footgun. Only return when labelled regex matched. |
| B-021 | `apps/server/src/trpc/routes/assistant.ts:498-507` | correctness | `extractReceiptDetails` amount regex matches unrelated numbers on noisy receipts. Anchor matches to a "Total/Amount/Charged" label nearby. |
| B-022 | `apps/server/src/trpc/routes/assistant.ts:2255-2354` | performance | Non-conversational threads pay the full `buildThreadAnalysis` cost (LLM/vector/related-task) and then zero out actionable fields. Classify early and short-circuit. |
| B-023 | `apps/server/src/pipelines.ts:622-637` and `795-810` | maintainability | Effect-based and imperative versions reimplement automation-policy fetch + default-fallthrough. Effect version's `Effect.orElse` after a `try` with catch is dead. Extract `getUserAutomationPolicy(userId)`. |
| B-024 | `apps/server/src/lib/ai-profile.ts:124-133` | prompt-injection (low) | `identity.name` / `identity.email` interpolated into system prompt unsanitized. Strip leading `#`, backticks, code fences. |
| B-025 | `apps/server/src/routes/ai.ts:524-542` | cost | 21 KB `GENERATIVE_UI_PROMPT` injected into every system prompt regardless of client capability. Gate by `clientCapabilities`. |
| B-026 | `apps/server/src/trpc/routes/assistant.ts:2759-2778` | consistency | `dismissPreparedAction` lacks `lastReviewedAt: new Date()` and `actionId` shape validation that sibling `dismissOpenLoop` has. |
| B-027 | `apps/server/src/lib/ai-profile.ts:78-87` | correctness (LLM context) | Formatted local time omits timezone designator — same wall-clock string in PST and EDT is ambiguous. Add `timeZoneName: 'short'`. |
| B-028 | `apps/server/src/thread-workflow-utils/workflow-engine.ts:382-385` | design | `vectorizationWorkflow` and `labelGenerationWorkflow` registered unconditionally even when user has disabled assistant automation. Worth a deliberate decision. |
| B-029 | `apps/macos/TodusMac/Views/Email/MacEmailComposeView.swift:497-506` | correctness | Compose autosave `Task` not cancelled on view dismiss; pending 1-second autosave can write after `clearAutosavedDraft()` runs on send. Add `.onDisappear { autosaveTask?.cancel() }`. |
| B-030 | macOS + iOS `EmailService.withTimeout` | performance | `defer { group.cancelAll() }` issues structured cancellation, but unclear if `URLSession.data(for:)` honors `Task.isCancelled` in `TodosAPIClient`. Verify; use `withTaskCancellationHandler` to call `urlTask.cancel()`. |
| B-031 | `apps/macos/TodusMac/Views/Home/MacHomeView.swift:567-577` | dead code | `openMacBriefingRow` thread-id branch and fallback both call `onNavigate?(.email(.inbox))`. Implement deep-link or simplify to single call. |
| B-032 | `apps/macos/TodusMac/Domain/TaskSmartSort.swift:70-76`, `99-114` (and iOS mirror) | consistency | `bucket(for:)` returns single `.noDate`; `score(for:)` splits high-priority no-date from other. Bucket header view groups them together so the split is visually invisible — pick one. |
| B-033 | `apps/ios/Todus/Todus/Features/Tasks/TaskRowView.swift:225` & `apps/macos/TodusMac/Domain/SnoozeOption.swift:38` | UX | `SnoozeOption.weekend` lands on next Saturday when called Saturday afternoon. On Saturday, prefer Sunday 9am. |
| B-034 | `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift:171-176` | edge case | `.onAppear` sets `hideTabBar = false`; no symmetric restore on dismiss. Document or restore previous value. |
| B-035 | `apps/ios/Todus/Todus/Navigation/CreateSheet.swift:880-897` | correctness contract | `CompoundIntentParser` multi-intent path uses `intent.date ?? selectedDate` for every intent; unclear whether explicit folder/date should override every sub-intent. Define contract. |
| B-036 | `apps/ios/Todus/Todus/Navigation/CreateSheet.swift:875` | UX regression? | Auto-resolve type now requires both keyword AND date for `.event`. "Dentist Tuesday 2pm" used to classify as `.event`, now falls through to `.task`. Confirm intentional. |
| B-037 | `apps/ios/Todus/Todus/Services/Email/EmailService.swift:282-287` | observability | Stale-refresh detection uses strict `<`, so equal-newest refresh is accepted. Surface dropped count to telemetry. |
| B-038 | `apps/ios/Todus/Todus/Services/AI/AIChatService.swift` | correctness (rare race) | Comment says "Load deleted IDs synchronously addresses this" but `deleteConversation` mutates `conversations` itself, which the async loader can overwrite. Verify and document. |
| B-039 | `apps/web/app/(routes)/mail/tasks/page.tsx:204` | performance | New `void queryClient.invalidateQueries(...)` runs on every create on top of optimistic cache update — can thrash. Debounce or only invalidate when sort/filter would actually move the inserted task. |
| B-040 | `apps/web/app/(routes)/mail/tasks/page.tsx` | i18n | `NlpQuickAdd` placeholder is hardcoded English with Swedish example — confusing and not localized via Paraglide. |
