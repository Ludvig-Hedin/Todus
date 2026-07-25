---
id: 0260
title: "Fix — review follow-up for Ollama/session logout/native duplicate"
status: archived
category: Fixed
release_date: 2026-04-26
source: CHANGELOG.md
---

## [2026-04-26] Fix — review follow-up for Ollama/session logout/native duplicate

- [Fix] **The duplicate iOS assistant cache source is removed again.** `AssistantPersistedCache 2.swift` is no longer referenced by the Xcode project or present on disk, so the native target does not redeclare `AssistantPersistedCache`.
- [Fix] **Choosing Ollama can no longer persist an invalid empty model.** The shared web/mail `ModelSelector` now refuses the provider switch until at least one Ollama model is installed, and when a model exists it persists the first installed model immediately.
- [Fix] **"Sign out all other devices" now preserves the current session.** `sessions.revokeAll` excludes the resolved current session id, so the new security page action matches its label instead of logging out the active browser too.
- [Files] `apps/ios/Todus/Todus.xcodeproj/project.pbxproj`, `apps/ios/Todus/Todus/Services/Email/AssistantPersistedCache 2.swift`, `apps/server/src/trpc/routes/sessions.ts`, `apps/web/components/ui/model-selector.tsx`, `apps/mail/components/ui/model-selector.tsx`, `apps/web/app/(routes)/settings/security/page.tsx`, `CHANGELOG.md`, `TASK.md`
