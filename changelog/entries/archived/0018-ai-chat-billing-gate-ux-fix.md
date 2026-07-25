---
id: 0018
title: "AI Chat Billing Gate UX Fix"
status: archived
category: Fixed
release_date: 2026-03-08
source: CHANGELOG.md
---

## [2026-03-08] AI Chat Billing Gate UX Fix

### Fixed

- **AI Chat Placeholder**: Restored visible placeholder text in the web AI chat composer by adding explicit Tiptap placeholder rendering styles.
- **Billing Gate Submit Guard**: Prevented `Enter` from submitting AI chat requests when `chat-messages` billing is disabled, so free/blocked states now open the pricing dialog instead of throwing a generic `useChat` error.
