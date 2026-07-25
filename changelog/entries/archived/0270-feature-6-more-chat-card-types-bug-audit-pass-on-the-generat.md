---
id: 0270
title: "Feature — 6 more chat-card types + bug-audit pass on the generative-UI catalog"
status: archived
category: Fixed
release_date: 2026-04-26
source: CHANGELOG.md
---

## [2026-04-26] Feature — 6 more chat-card types + bug-audit pass on the generative-UI catalog

- [Feature] **Six new card types** added to the catalog and shipped on web, iOS, and macOS in one pass: `AttachmentCard` (file chip with mime-icon, size, open-action), `CodeBlockCard` (syntax-aware code block with language label + copy + scrolling pre), `ChecklistCard` (interactive ad-hoc checklist with optimistic local toggles, separate from real tasks), `DocumentCard` (link to a user Doc), `WeeklyAgendaCard` (compact 7-day density grid; tap navigates to a day), `MetricCard` (single-stat tile with optional delta + direction). Four new actions wired through every layer: `open_attachment`, `toggle_checklist_item`, `navigate_document`, `navigate_day`. Server prompt taught new intent mappings (`reference_attachment`, `share_code_snippet`, `generate_steps_or_checklist`, `reference_document`, `weekly_overview`, `show_single_stat`).
- [Fix] **Autosave/send race in `InlineComposeCard`** — on every platform, the debounced 600ms autosave timer is now cancelled by Send, and `isDirty` resets after each fire. Previously, an orphan autosave fired right after Send and overwrote the just-sent state.
- [Fix] **Duplicate recipients on iOS + macOS `InlineComposeCard`** — adding the same address twice (or with whitespace, or `foo@` / `@bar`) is now rejected, matching the web behavior.
- [Fix] **`groupedThreshold` clamp** — iOS + macOS list cards now `max(1, …)` the threshold so a value of `0` or `-1` from the AI no longer breaks layout (web already did this).
- [Fix] **`uiSpec` not reset on retry (macOS)** — `MacAIChatService.retryMessage` now clears `messages[idx].uiSpec` alongside content/sources/etc., so old generative-UI cards no longer bleed into the regenerated bubble. iOS already did this.
- [Fix] **macOS draft send stuck "Sending…" on failure** — promoted the macOS spec-action callback to the same 3-arg `MacChatUISpecOnAction` typealias as iOS, plumbed through every macOS card view's call sites, and wired real `(success, errorMessage)` completion in `MacAssistantPanel.handleSpecAction` for `update_draft` / `send_draft`. The InlineCompose footer now flips to "Sent" / "Failed to send" instead of hanging.
- [Polish] `CopyableTextCard` now caps height at ~280px with internal scroll on every platform — long pastes don't blow out the chat. Empty state on iOS + macOS list cards mirrors web. Web `InlineComposeCard` now displays attachment chips (name + formatted size) when the AI emits an `attachments` array. iOS now opens `previewUrl` for `open_attachment` via `UIApplication.shared.open`; macOS via `NSWorkspace.shared.open`.
- [Architectural] The catalog + contract files now describe 21 card types and 17 actions. Action params remain stringly-typed; nested payloads continue to be JSON-encoded into a single `payload` string to preserve the existing flat-string callback contract.
- [Files] `apps/server/src/lib/generative-ui-contract.ts`, `apps/mail/components/generative-ui/{catalog.ts,registry.tsx}`, `apps/mail/components/generative-ui/components/{Attachment,CodeBlock,Checklist,Document,WeeklyAgenda,Metric}Card.tsx`, `apps/mail/components/generative-ui/components/{InlineCompose,CopyableText,EmailList,SuggestionsCard}.tsx` (polish), `apps/ios/Todus/Todus/Features/AI/{ChatUISpec,CardViews,ChatUISpecView,AIChatView}.swift`, `apps/macos/TodusMac/Views/AI/ChatUISpec/{ChatUISpec,CardViews,ChatUISpecView}.swift`, `apps/macos/TodusMac/Services/AI/MacAIChatService.swift`, `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift`, `CHANGELOG.md`, `TASK.md`
