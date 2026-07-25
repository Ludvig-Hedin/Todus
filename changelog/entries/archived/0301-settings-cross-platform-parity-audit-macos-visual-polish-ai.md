---
id: 0301
title: "Settings cross-platform parity audit — macOS visual polish + AI sheet, web notifications fix, multi-platform sync"
status: archived
category: Fixed
release_date: 2026-05-24
source: CHANGELOG.md
---

## [2026-05-24] Settings cross-platform parity audit — macOS visual polish + AI sheet, web notifications fix, multi-platform sync

Full Settings gap analysis and implementation across macOS, iOS, and web.

**Backend schema** (`apps/server/src/lib/schemas.ts`):

- Added `aiTone: z.enum(['professional','casual','concise'])` — was `@AppStorage`-only on iOS/macOS, now synced
- Added `taskRemindersEnabled: z.boolean()` and `calendarRemindersEnabled: z.boolean()` — same, now synced

**macOS Settings** (`MacTheme.swift`, `MacSettingsView.swift`, new `MacAISettingsView.swift`):

- Spacing tokens: `settingsRowVerticalPadding` 11→13, `settingsSectionSpacing` 28→32, new `settingsSubgroupSpacing = 16`
- Avatar: 36pt → 44pt (matches iOS baseline)
- Account card: "Delete account" removed from top card → moved to new **Danger Zone** section at bottom (matches iOS pattern)
- AI Assistant section: 30-item monolithic wall replaced by a single nav row → opens in a dedicated `MacAISettingsView` sheet with proper sub-grouping (Permissions / Personalization / Mail Assistant with 7 sub-groups / Model)
- Connected Services: refactored from legacy single-Gmail row → dynamic multi-account list via `connectionsService.connections` + "Add Gmail account" row
- Active Sessions: row padding 8→10, header font 10.5→11, value font 11.5→12, "This device" accent badge
- Notifications: `taskRemindersEnabled` / `calendarRemindersEnabled` now sync to backend via `syncSetting`
- `aiTone` now syncs to backend via `syncSetting`

**iOS Settings** (`SettingsView.swift`):

- `SettingsSyncModifier` extended: `taskRemindersEnabled`, `calendarRemindersEnabled`, `aiTonePreference` now call `syncSetting` on change

**Web** (`settings/notifications/page.tsx`, `settings/ai/page.tsx`):

- Notifications page fully rewritten: broken preview-only form (with nonexistent backend fields) replaced with working `taskRemindersEnabled` / `calendarRemindersEnabled` toggles wired to `trpc.settings.save`
- AI page: Response Tone `SelectRow` (Professional / Casual / Concise) added to Personalization section, wired to new `aiTone` backend key
