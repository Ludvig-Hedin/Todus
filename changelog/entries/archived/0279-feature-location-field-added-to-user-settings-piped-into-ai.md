---
id: 0279
title: "Feature — Location field added to user settings, piped into AI profile"
status: archived
category: Added
release_date: 2026-04-27
source: CHANGELOG.md
---

## [2026-04-27] Feature — Location field added to user settings, piped into AI profile

- [Feature] **`userSettingsSchema`** in [`apps/server/src/lib/schemas.ts`](apps/server/src/lib/schemas.ts) gains a `location: z.string().default('')` field. Backward-compatible: JSONB storage requires no migration; old clients that don't send `location` receive the `''` default via `mergeUserSettings`.
- [Feature] **`buildAIProfilePrompt`** now includes `- Location: <value>` in the `## Locale` section when the user has set a location. The line is omitted entirely when the field is empty so the prompt stays clean for users who haven't configured it. Result: the AI automatically knows the user's city/country and can give location-aware answers (local times, geographic references, nearby services) without the user having to repeat it.
- [Feature] **Web settings** ([`apps/web/app/(routes)/settings/general/page.tsx`](<apps/web/app/(routes)/settings/general/page.tsx>)) — a "Location" text input (with `MapPin` icon, placeholder "e.g. Oslo, Norway") appears beside the Language and Timezone selects. Saved with the rest of the general-settings form.
- [Feature] **iOS** (`AIAssistantSettingsView` in [`SettingsView.swift`](apps/ios/Todus/Todus/Features/Settings/SettingsView.swift)) — a `TextField` row for Location appears before "Context about you". `AppServices.location` persists to `UserDefaults` and is synced via `loadSharedAIProfile` / `saveSharedAIProfile`. `SharedAIProfileSaveInput` gains the `location` field. `MailAssistantSettingsResponse.Settings` gains `location: String?` (optional for backward compat).
- [Feature] **macOS** (`aiAssistantSection` in [`MacSettingsView.swift`](apps/macos/TodusMac/Views/Settings/MacSettingsView.swift)) — same text field in the styled card layout, bound to `MacAppServices.location`. Identical sync/save flow to iOS.
- [Files] `apps/server/src/lib/schemas.ts`, `apps/server/src/lib/ai-profile.ts`, `apps/web/app/(routes)/settings/general/page.tsx`, `apps/ios/Todus/Todus/Domain/MailAssistantModels.swift`, `apps/ios/Todus/Todus/App/AppServices.swift`, `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`, `apps/macos/TodusMac/Domain/MailAssistantModels.swift`, `apps/macos/TodusMac/App/MacAppServices.swift`, `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`, `CHANGELOG.md`
