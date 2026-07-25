---
id: 0174
title: "Fix — AI chat persistence and input blocking"
status: archived
category: Fixed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] Fix — AI chat persistence and input blocking

### Web (`apps/mail`)

- **layout.tsx**: Moved `AISidebar` and `AIToggleButton` from `mail.tsx` into the shared mail layout so the chat persists on all pages (home, tasks, meetings, etc.).
- **ai-sidebar.tsx**: Replaced `ResizablePanel`-based sidebar with a `fixed` right panel (`fixed top-2 right-1 bottom-1 z-40 w-[360px]`) so sidebar mode works everywhere without needing a `ResizablePanelGroup`. Added self-gating `if (!activeConnection?.id) return null` inside the component.
- **ai-chat.tsx**: Fixed paywall overlay (`absolute inset-0`) covering the text input by adding `relative` to the scroll container, scoping the overlay to only the messages area. Fixed billing loading race condition: `isChatEnabled = !isBillingLoading && chatMessages.enabled` so users stay blocked until billing is loaded and entitlement is confirmed.
- **mail.tsx**: Removed `AISidebar` and `AIToggleButton` (now rendered globally in layout).
