---
id: 0312
title: "Added — iOS residual UX items shipped"
status: unreleased
category: Added
release_date: 2026-07-08
source: CHANGELOG.md
---

### Added — iOS residual UX items shipped, 2026-07-08

The last items the audit classified as product/feature residuals are now implemented (final assessment shows zero open findings):

- **Dynamic tab bar (BH-0613-6 resolved)** — `MainTabView` renders the bar from `services.tabBarTabs` (home-first, max 4, user-ordered) plus a fixed **More** tab; the other content pages stay instantiated as hidden tabs so `navigateTo` deep links (Home rows, search results, AI cards) still land on them. `MoreSheetView` (previously unreachable) is now the More tab's content, listing whatever isn't in the bar plus the un-gated "Customize Tab Bar" editor — changes apply live. New `AppTab.more` case; customization pool now `AppTab.contentTabs`.
- **In-composer attachment picker** — paperclip in the compose nav bar opens the same Take Photo / Library / Upload File chooser as task capture; imports append to the chip row and upload with the send. Session-added files are deleted on cancel/remove so nothing leaks (extracted to a `ComposeAttachmentPickers` modifier to stay inside SwiftUI's type-check budget).
- **Search covers all mail** — `searchThreadsServer` now passes an unscoped folder, which the Gmail driver translates to an all-mail query (inbox + archive + sent) instead of inbox-only.
- **Meeting Q&A survives navigation** — the "Ask about this meeting" thread moved from view `@State` to `MeetingsService.qaThreads` (keyed by meeting, session-lifetime); hint copy updated to "Answers are kept for this session."
- Compose Markdown→HTML now also covers the toolbar's `_italic_`, `> quote`, and `---` divider, and auto-links bare URLs; whitespace-only backend/Supabase plist URLs no longer flip remote-backend detection.
