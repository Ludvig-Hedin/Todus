# Todus — Feature Catalog

Todus is a cross-platform mail + AI productivity client. Four surfaces share one backend:

- 🌐 **Web** (`apps/web`) — React Router v7 + Vite + Cloudflare Workers, the deployed mail product UI.
- ⚙️ **Backend** (`apps/server`) — Cloudflare Worker (Hono + tRPC + Durable Objects + Workflows).
- 📱 **iOS** (`apps/ios/Todus`) — Native SwiftUI (Swift 6, iOS 18+).
- 💻 **macOS** (`apps/macos/TodusMac`) — Native SwiftUI (Swift 6) with sidebar shell.

> Companion doc: [FEATURE_TEST_PLAN.md](FEATURE_TEST_PLAN.md) — section numbering mirrors this file.
> Last updated: 2026-05-27.

## Conventions

- File paths are clickable markdown links relative to repo root.
- Each entry has a one-line purpose. For "how it works" see source.
- A feature flagged "parity" exists on multiple surfaces with equivalent behavior; "(<surface> only)" means platform-specific.
- `apps/mail/` is the **legacy frontend** — read-only archive. Not catalogued here. All web work lives in [apps/web](apps/web/).
- Skip `apps/archived/` — reference-only legacy implementations.

---

## 1. Web Frontend (apps/web)

### 1.1 Marketing & Public Routes

Routing config: [apps/web/app/routes.ts](apps/web/app/routes.ts). Layout wrapper: [apps/web/app/(full-width)/layout.tsx](apps/web/app/(full-width)/layout.tsx).

| Route | File | Purpose |
| --- | --- | --- |
| `/` | [apps/web/app/page.tsx](apps/web/app/page.tsx) | Landing / unauthenticated home |
| `/home` | [apps/web/app/home/page.tsx](apps/web/app/home/page.tsx) | Public marketing home (alternate) |
| `/about` | [apps/web/app/(full-width)/about.tsx](apps/web/app/(full-width)/about.tsx) | About page |
| `/pricing` | [apps/web/app/(full-width)/pricing.tsx](apps/web/app/(full-width)/pricing.tsx) | Pricing tiers |
| `/terms` | [apps/web/app/(full-width)/terms.tsx](apps/web/app/(full-width)/terms.tsx) | Terms of service |
| `/privacy` | [apps/web/app/(full-width)/privacy.tsx](apps/web/app/(full-width)/privacy.tsx) | Privacy policy |
| `/downloads` | [apps/web/app/(full-width)/downloads.tsx](apps/web/app/(full-width)/downloads.tsx) | Native app download links |
| `/contact` | [apps/web/app/(full-width)/contact.tsx](apps/web/app/(full-width)/contact.tsx) | Contact form (→ `contact.submit` tRPC) |
| `/contributors` | [apps/web/app/(full-width)/contributors.tsx](apps/web/app/(full-width)/contributors.tsx) | Open-source contributors page |
| `/faq` | [apps/web/app/(full-width)/faq.tsx](apps/web/app/(full-width)/faq.tsx) | Frequently asked questions |
| `/hr` | [apps/web/app/(full-width)/hr.tsx](apps/web/app/(full-width)/hr.tsx) | Careers / hiring |
| `/blog` | [apps/web/app/(full-width)/blog/](apps/web/app/(full-width)/blog/) | Blog index |
| `/blog/:slug` | [apps/web/app/(full-width)/blog/[slug]/page.tsx](apps/web/app/(full-width)/blog/[slug]/page.tsx) | Individual blog post |
| `/compare/:competitor` | [apps/web/app/(full-width)/compare/[competitor]/page.tsx](apps/web/app/(full-width)/compare/[competitor]/page.tsx) | SEO competitor comparison |
| `/share/:slug` | [apps/web/app/(full-width)/share/[slug]/page.tsx](apps/web/app/(full-width)/share/[slug]/page.tsx) | Public read-only shared AI conversation |
| `/g/:token` | [apps/web/app/(full-width)/group-join/[token]/page.tsx](apps/web/app/(full-width)/group-join/[token]/page.tsx) | Group chat invite join landing |

### 1.2 Auth

| Route | File | Purpose |
| --- | --- | --- |
| `/login` | [apps/web/app/(auth)/todus/login/page.tsx](apps/web/app/(auth)/todus/login/page.tsx) | Sign in (Google / Apple / Email OTP / password) |
| `/signup` | [apps/web/app/(auth)/todus/signup/page.tsx](apps/web/app/(auth)/todus/signup/page.tsx) | New account creation |

Auth client wrapper: [apps/web/lib/auth-client.ts](apps/web/lib/auth-client.ts) (re-exports `signIn`, `signUp`, `signOut`, `useSession` from Better Auth).

### 1.3 Mail Product Shell

Layout: [apps/web/app/(routes)/mail/layout.tsx](apps/web/app/(routes)/mail/layout.tsx).

| Route | File | Purpose |
| --- | --- | --- |
| `/mail` | [apps/web/app/(routes)/mail/page.tsx](apps/web/app/(routes)/mail/page.tsx) | Redirects to `/mail/inbox` |
| `/mail/home` | [apps/web/app/(routes)/mail/home/page.tsx](apps/web/app/(routes)/mail/home/page.tsx) | Mail home / today view |
| `/mail/:folder` | [apps/web/app/(routes)/mail/[folder]/page.tsx](apps/web/app/(routes)/mail/[folder]/page.tsx) | Folder view: `inbox`, `draft`, `sent`, `spam`, `bin`, `archive`, `snoozed`, or custom label id |
| `/mail/create` | [apps/web/app/(routes)/mail/create/page.tsx](apps/web/app/(routes)/mail/create/page.tsx) | New item entry (compose / task / note) |
| `/mail/compose` | [apps/web/app/(routes)/mail/compose/page.tsx](apps/web/app/(routes)/mail/compose/page.tsx) | Full-window email composer |
| `/mail/chat` | [apps/web/app/(routes)/mail/chat/page.tsx](apps/web/app/(routes)/mail/chat/page.tsx) | Dedicated AI chat surface |
| `/mail/search` | [apps/web/app/(routes)/mail/search/page.tsx](apps/web/app/(routes)/mail/search/page.tsx) | Search results page |
| `/mail/tasks` | [apps/web/app/(routes)/mail/tasks/page.tsx](apps/web/app/(routes)/mail/tasks/page.tsx) | Tasks management |
| `/mail/calendar` | [apps/web/app/(routes)/mail/calendar/page.tsx](apps/web/app/(routes)/mail/calendar/page.tsx) | Calendar view |
| `/mail/meetings` | [apps/web/app/(routes)/mail/meetings/page.tsx](apps/web/app/(routes)/mail/meetings/page.tsx) | Recorded meetings list |
| `/mail/meetings/:meetingId` | [apps/web/app/(routes)/mail/meetings/[meetingId]/page.tsx](apps/web/app/(routes)/mail/meetings/[meetingId]/page.tsx) | Meeting detail + transcript + AI summary |
| `/mail/docs` | [apps/web/app/(routes)/mail/docs/page.tsx](apps/web/app/(routes)/mail/docs/page.tsx) | Documents list |
| `/mail/docs/:docId` | [apps/web/app/(routes)/mail/docs/[docId]/page.tsx](apps/web/app/(routes)/mail/docs/[docId]/page.tsx) | Document editor (Tiptap) |
| `/mail/under-construction/:path` | [apps/web/app/(routes)/mail/under-construction/[path]/page.tsx](apps/web/app/(routes)/mail/under-construction/[path]/page.tsx) | Placeholder for in-progress routes |

Folder validation (custom labels): hierarchical traversal inside `[folder]/page.tsx`.

### 1.4 Settings

Layout: [apps/web/app/(routes)/settings/layout.tsx](apps/web/app/(routes)/settings/layout.tsx). Index: [apps/web/app/(routes)/settings/page.tsx](apps/web/app/(routes)/settings/page.tsx).

| Route | File | Purpose |
| --- | --- | --- |
| `/settings/general` | [apps/web/app/(routes)/settings/general/page.tsx](apps/web/app/(routes)/settings/general/page.tsx) | Account, name, locale, language |
| `/settings/appearance` | [apps/web/app/(routes)/settings/appearance/page.tsx](apps/web/app/(routes)/settings/appearance/page.tsx) | Theme + density |
| `/settings/connections` | [apps/web/app/(routes)/settings/connections/page.tsx](apps/web/app/(routes)/settings/connections/page.tsx) | Gmail / Outlook OAuth connections |
| `/settings/categories` | [apps/web/app/(routes)/settings/categories/page.tsx](apps/web/app/(routes)/settings/categories/page.tsx) | Email category preferences |
| `/settings/labels` | [apps/web/app/(routes)/settings/labels/page.tsx](apps/web/app/(routes)/settings/labels/page.tsx) | Custom label management |
| `/settings/signatures` | [apps/web/app/(routes)/settings/signatures/page.tsx](apps/web/app/(routes)/settings/signatures/page.tsx) | Email signatures per connection |
| `/settings/notifications` | [apps/web/app/(routes)/settings/notifications/page.tsx](apps/web/app/(routes)/settings/notifications/page.tsx) | Email + push notification preferences |
| `/settings/privacy` | [apps/web/app/(routes)/settings/privacy/page.tsx](apps/web/app/(routes)/settings/privacy/page.tsx) | Privacy + cookie preferences |
| `/settings/security` | [apps/web/app/(routes)/settings/security/page.tsx](apps/web/app/(routes)/settings/security/page.tsx) | Sessions, devices, 2FA |
| `/settings/shortcuts` | [apps/web/app/(routes)/settings/shortcuts/page.tsx](apps/web/app/(routes)/settings/shortcuts/page.tsx) | Keyboard shortcut customization |
| `/settings/sharing` | [apps/web/app/(routes)/settings/sharing/page.tsx](apps/web/app/(routes)/settings/sharing/page.tsx) | Shared conversation/resource management |
| `/settings/meetings` | [apps/web/app/(routes)/settings/meetings/page.tsx](apps/web/app/(routes)/settings/meetings/page.tsx) | Recall.ai meeting bot defaults |
| `/settings/ai` | [apps/web/app/(routes)/settings/ai/page.tsx](apps/web/app/(routes)/settings/ai/page.tsx) | AI assistant + model preferences |
| `/settings/local-models` | [apps/web/app/(routes)/settings/local-models/page.tsx](apps/web/app/(routes)/settings/local-models/page.tsx) | Local LLM model selection (mirrors native) |
| `/settings/billing` | [apps/web/app/(routes)/settings/billing/page.tsx](apps/web/app/(routes)/settings/billing/page.tsx) | Subscription, plan, Autumn portal link |
| `/settings/calendars` | [apps/web/app/(routes)/settings/calendars/page.tsx](apps/web/app/(routes)/settings/calendars/page.tsx) | Per-account calendar visibility |
| `/settings/danger-zone` | [apps/web/app/(routes)/settings/danger-zone/page.tsx](apps/web/app/(routes)/settings/danger-zone/page.tsx) | Account deletion + destructive actions |
| `/settings/about` | [apps/web/app/(routes)/settings/about/page.tsx](apps/web/app/(routes)/settings/about/page.tsx) | Version, build, system info |
| `/settings/design-system` | [apps/web/app/(routes)/settings/design-system/page.tsx](apps/web/app/(routes)/settings/design-system/page.tsx) | 🔒 Design token browser (allowlist-gated) |
| `/settings/*` | [apps/web/app/(routes)/settings/[...settings]/page.tsx](apps/web/app/(routes)/settings/[...settings]/page.tsx) | Catch-all fallback |

### 1.5 Developer / Gated

| Route | File | Purpose |
| --- | --- | --- |
| `/developer` | [apps/web/app/(routes)/developer/page.tsx](apps/web/app/(routes)/developer/page.tsx) | 🔒 Developer mode dashboard (allowlist) |
| `/settings/design-system` | (above) | 🔒 Design token viewer (allowlist) |

Gating: [apps/web/lib/developer-access.ts](apps/web/lib/developer-access.ts) → `isAllowlisted(email)` checks `VITE_TODUS_ALLOWLISTED_EMAILS` env (comma-separated, trimmed, lowercased).

Manifest backing the design-system page: [apps/web/app/(routes)/settings/design-system/_components-manifest.tsx](apps/web/app/(routes)/settings/design-system/_components-manifest.tsx).

### 1.6 Components — Mail UI

[apps/web/components/mail/](apps/web/components/mail/)

| Component | Purpose |
| --- | --- |
| [mail.tsx](apps/web/components/mail/mail.tsx) | Mail layout container |
| [mail-list.tsx](apps/web/components/mail/mail-list.tsx) | Thread list |
| [mail-display.tsx](apps/web/components/mail/mail-display.tsx) | Thread display panel |
| [mail-content.tsx](apps/web/components/mail/mail-content.tsx) | Body renderer |
| [mail-skeleton.tsx](apps/web/components/mail/mail-skeleton.tsx) | Loading skeleton |
| [thread-display.tsx](apps/web/components/mail/thread-display.tsx) | Full conversation view |
| [thread-subject.tsx](apps/web/components/mail/thread-subject.tsx) | Subject header |
| [reply-composer.tsx](apps/web/components/mail/reply-composer.tsx) | Inline reply |
| [note-panel.tsx](apps/web/components/mail/note-panel.tsx) | Per-thread notes sidebar |
| [attachment-dialog.tsx](apps/web/components/mail/attachment-dialog.tsx) | Attachment viewer modal |
| [attachments-accordion.tsx](apps/web/components/mail/attachments-accordion.tsx) | Inline attachment list |
| [snooze-dialog.tsx](apps/web/components/mail/snooze-dialog.tsx) | Snooze date picker |
| [navbar.tsx](apps/web/components/mail/navbar.tsx) | Mail navigation header |
| [render-labels.tsx](apps/web/components/mail/render-labels.tsx) | Inline label pills |
| [select-all-checkbox.tsx](apps/web/components/mail/select-all-checkbox.tsx) | Bulk-select control |
| [email-verification-badge.tsx](apps/web/components/mail/email-verification-badge.tsx) | Verified-sender badge |
| [optimistic-thread-state.tsx](apps/web/components/mail/optimistic-thread-state.tsx) | Optimistic UI helpers |
| [use-mail.ts](apps/web/components/mail/use-mail.ts) | Mail state hook |
| [use-do-state.ts](apps/web/components/mail/use-do-state.ts) | Durable object state hook |

### 1.7 Components — Create / Composer

[apps/web/components/create/](apps/web/components/create/)

| Component | Purpose |
| --- | --- |
| [email-composer.tsx](apps/web/components/create/email-composer.tsx) | Full composer surface |
| [create-email.tsx](apps/web/components/create/create-email.tsx) | New-email shell |
| [editor.tsx](apps/web/components/create/editor.tsx) | Tiptap rich text editor |
| [editor-buttons.tsx](apps/web/components/create/editor-buttons.tsx) | Formatting toolbar |
| [editor-menu.tsx](apps/web/components/create/editor-menu.tsx) | Bubble menu |
| [editor.colors.tsx](apps/web/components/create/editor.colors.tsx) | Color palette picker |
| [editor.text-buttons.tsx](apps/web/components/create/editor.text-buttons.tsx) | Text formatting buttons |
| [extensions.ts](apps/web/components/create/extensions.ts) | Tiptap extension registry |
| [editor-autocomplete.ts](apps/web/components/create/editor-autocomplete.ts) | Inline ghost-text suggestions |
| [ai-chat.tsx](apps/web/components/create/ai-chat.tsx) | AI chat docked in composer |
| [ai-sources.tsx](apps/web/components/create/ai-sources.tsx) | AI context source picker |
| [ai-textarea.tsx](apps/web/components/create/ai-textarea.tsx) | AI prompt textarea |
| [template-button.tsx](apps/web/components/create/template-button.tsx) | Template insert |
| [slash-command.tsx](apps/web/components/create/slash-command.tsx) | `/` command palette in editor |
| [schedule-send-picker.tsx](apps/web/components/create/schedule-send-picker.tsx) | Schedule-send date/time |
| [toolbar.tsx](apps/web/components/create/toolbar.tsx) | Composer toolbar shell |
| [uploaded-file-icon.tsx](apps/web/components/create/uploaded-file-icon.tsx) | File chip |
| [image-compression-settings.tsx](apps/web/components/create/image-compression-settings.tsx) | Image upload quality control |
| [email-phrases.ts](apps/web/components/create/email-phrases.ts) | Quick phrase library |

### 1.8 Components — Generative UI

[apps/web/components/generative-ui/](apps/web/components/generative-ui/) — renders AI-emitted UI specs as React cards.

| File | Purpose |
| --- | --- |
| [ChatSpecRenderer.tsx](apps/web/components/generative-ui/ChatSpecRenderer.tsx) | Spec → component dispatcher |
| [catalog.ts](apps/web/components/generative-ui/catalog.ts) | Registered card-type catalog |
| [registry.tsx](apps/web/components/generative-ui/registry.tsx) | Card registry |
| [components/](apps/web/components/generative-ui/components/) | Card implementations: ActionConfirmation, Attachment, CalendarEvent, Checklist, CodeBlock, Contact, Document, Email, Task, Template, Meeting, Weather, URLPreview, Table, FilePicker, Form, Image, Text |

### 1.9 Components — Settings, Calendar, Tasks, Docs, Connection, Labels, Shortcuts

| Folder | Files | Purpose |
| --- | --- | --- |
| [components/settings/](apps/web/components/settings/) | `primitives.tsx`, `settings-card.tsx` | Settings UI primitives |
| [components/calendar/](apps/web/components/calendar/) | `calendar-grid.tsx` | Calendar grid view |
| [components/tasks/](apps/web/components/tasks/) | `task-item.tsx` | Task row component |
| [components/docs/](apps/web/components/docs/) | `doc-tree.tsx` | Document hierarchy tree |
| [components/connection/](apps/web/components/connection/) | `add.tsx`, `connection-wrapper.tsx` | Add / wrap email connection |
| [components/labels/](apps/web/components/labels/) | `label-dialog.tsx` | Create / edit label modal |
| [components/shortcuts/](apps/web/components/shortcuts/) | `keyboard-shortcuts-dialog.tsx` | Shortcuts reference dialog |
| [components/onboarding.tsx](apps/web/components/onboarding.tsx) | — | Onboarding flow |
| [components/pricing/](apps/web/components/pricing/) | — | Pricing UI components |
| [components/cookies/](apps/web/components/cookies/) | — | Cookie banner / consent |
| [components/subscription-success-watcher.tsx](apps/web/components/subscription-success-watcher.tsx) | — | Polls for post-checkout activation |

### 1.10 Components — Home (Marketing)

[apps/web/components/home/](apps/web/components/home/)

| File | Purpose |
| --- | --- |
| [HomeContent.tsx](apps/web/components/home/HomeContent.tsx) | Landing page composition |
| [hero-demo/](apps/web/components/home/hero-demo/) | Hero with embedded demo |
| [product-sections.tsx](apps/web/components/home/product-sections.tsx) | Feature highlight sections |
| [cta.tsx](apps/web/components/home/cta.tsx) | Call-to-action block |
| [footer.tsx](apps/web/components/home/footer.tsx) | Marketing footer |
| [pixelated-bg.tsx](apps/web/components/home/pixelated-bg.tsx) | Pixelated background effect |

### 1.11 Components — UI Primitives

[apps/web/components/ui/](apps/web/components/ui/) — 60+ shadcn-style primitives. Notable AI/product-specific extensions:

| File | Purpose |
| --- | --- |
| [app-sidebar.tsx](apps/web/components/ui/app-sidebar.tsx) | Mail app sidebar shell |
| [ai-sidebar.tsx](apps/web/components/ui/ai-sidebar.tsx) | Docked AI assistant sidebar |
| [model-selector.tsx](apps/web/components/ui/model-selector.tsx) | LLM model picker |
| [prompts-dialog.tsx](apps/web/components/ui/prompts-dialog.tsx) | Saved prompts dialog |
| [pricing-dialog.tsx](apps/web/components/ui/pricing-dialog.tsx) | In-app pricing surface |
| [pricing-switch.tsx](apps/web/components/ui/pricing-switch.tsx) | Monthly / annual toggle |
| [share-conversation-modal.tsx](apps/web/components/ui/share-conversation-modal.tsx) | Share AI conversation |
| [group-chat-view.tsx](apps/web/components/ui/group-chat-view.tsx) | Group chat surface |
| [bimi-avatar.tsx](apps/web/components/ui/bimi-avatar.tsx) | BIMI verified sender avatar |
| [recipient-autosuggest.tsx](apps/web/components/ui/recipient-autosuggest.tsx) | To/CC autocomplete |
| [recursive-folder.tsx](apps/web/components/ui/recursive-folder.tsx) | Nested folder tree |
| [sidebar-labels.tsx](apps/web/components/ui/sidebar-labels.tsx) | Sidebar label list |
| [sidebar-toggle.tsx](apps/web/components/ui/sidebar-toggle.tsx) | Sidebar collapse control |
| [todus-logo.tsx](apps/web/components/ui/todus-logo.tsx) | Brand logo |

Standard shadcn primitives: `accordion`, `alert`, `avatar`, `badge`, `button`, `calendar`, `card`, `chart`, `checkbox`, `collapsible`, `command`, `context-menu`, `dialog`, `drawer`, `dropdown-menu`, `form`, `input`, `input-otp`, `label`, `navigation-menu`, `popover`, `progress`, `radio-group`, `resizable`, `responsive-modal`, `scroll-area`, `select`, `separator`, `sheet`, `skeleton`, `spinner`, `switch`, `tabs`, `textarea`, `toast`, `toggle`, `toggle-group`, `tooltip`.

### 1.12 Context Providers

[apps/web/components/context/](apps/web/components/context/)

| File | Purpose |
| --- | --- |
| [thread-context.tsx](apps/web/components/context/thread-context.tsx) | Active thread state |
| [label-sidebar-context.tsx](apps/web/components/context/label-sidebar-context.tsx) | Sidebar label state |
| [command-palette-context.tsx](apps/web/components/context/command-palette-context.tsx) | ⌘K palette state |
| [sidebar-context.tsx](apps/web/components/context/sidebar-context.tsx) | Sidebar open/closed |
| [loading-context.tsx](apps/web/components/context/loading-context.tsx) | Global loading state |

### 1.13 Providers

[apps/web/components/providers/](apps/web/components/providers/)

| File | Purpose |
| --- | --- |
| [editor-provider.tsx](apps/web/components/providers/editor-provider.tsx) | Tiptap editor context |
| [hotkey-provider-wrapper.tsx](apps/web/components/providers/hotkey-provider-wrapper.tsx) | Global hotkey scope |
| [smooth-scroll.tsx](apps/web/components/providers/smooth-scroll.tsx) | Smooth scroll provider |

### 1.14 Theme

[apps/web/components/theme/](apps/web/components/theme/) — `theme-switcher.tsx`, `theme-toggle.tsx`, `sidebar-theme-switcher.tsx`.

Token source: [apps/web/app/globals.css](apps/web/app/globals.css) (Tailwind v4 `@theme` directive).

### 1.15 API Route

| Route | File | Purpose |
| --- | --- | --- |
| `mailto:` handler | [apps/web/app/mailto-handler.ts](apps/web/app/mailto-handler.ts) | Register web app as `mailto:` protocol handler |

---

## 2. Backend (apps/server)

Entry point: [apps/server/src/main.ts](apps/server/src/main.ts). tRPC composition: [apps/server/src/trpc/index.ts](apps/server/src/trpc/index.ts).

### 2.1 tRPC Routers

All routers live under [apps/server/src/trpc/routes/](apps/server/src/trpc/routes/).

#### `assistant` — [assistant.ts](apps/server/src/trpc/routes/assistant.ts)
| Procedure | Purpose |
| --- | --- |
| `getBriefing` | Daily email briefing |
| `getChangeFeed` | Activity feed since last open |
| `getThreadContext` | Per-thread assistant context |
| `getPersonContext` | Per-person assistant memory |
| `getWorkstreamContext` | Workstream/project memory |
| `listOpenLoops` | Unresolved action items |
| `listPreparedActions` | Pre-generated follow-up actions |
| `applyPreparedAction` | Execute a suggested action |
| `dismissPreparedAction` | Dismiss a prepared action |
| `dismissOpenLoop` | Dismiss an open loop |
| `snoozeOpenLoop` | Snooze open loop |
| `generateDraft` | AI-compose a draft |
| `recordFeedback` | Capture user feedback on assistant output |

#### `ai` — [ai/index.ts](apps/server/src/trpc/routes/ai/index.ts)
| Procedure | Source | Purpose |
| --- | --- | --- |
| `compose` | [ai/compose.ts](apps/server/src/trpc/routes/ai/compose.ts) | Generate email drafts from prompt |
| `generateEmailSubject` | [ai/compose.ts](apps/server/src/trpc/routes/ai/compose.ts) | Suggest a subject line |
| `generateSearchQuery` | [ai/search.ts](apps/server/src/trpc/routes/ai/search.ts) | NL → Gmail/Outlook query |
| `webSearch` | [ai/webSearch.ts](apps/server/src/trpc/routes/ai/webSearch.ts) | Perplexity web search |
| `transcribeAudio` | [ai/transcribeAudio.ts](apps/server/src/trpc/routes/ai/transcribeAudio.ts) | Audio → text (OpenAI Whisper) |
| `listConversations` | [ai/conversations.ts](apps/server/src/trpc/routes/ai/conversations.ts) | List saved chats |
| `getConversation` | [ai/conversations.ts](apps/server/src/trpc/routes/ai/conversations.ts) | Load conversation |
| `saveConversation` | [ai/conversations.ts](apps/server/src/trpc/routes/ai/conversations.ts) | Save / upsert conversation |
| `deleteConversation` | [ai/conversations.ts](apps/server/src/trpc/routes/ai/conversations.ts) | Delete conversation |

#### `mailAssistant` — [mail-assistant.ts](apps/server/src/trpc/routes/mail-assistant.ts)
| Procedure | Purpose |
| --- | --- |
| `generateDraft` | Mail-context-aware AI reply |
| `createEventFromSuggestion` | Convert AI suggestion → calendar event |
| `createTaskFromSuggestion` | Convert AI suggestion → task |
| `getActivity` | Per-thread assistant activity log |
| `logActivity` | Log a user action |
| `getInboxNudges` | Surface high-priority threads |
| `getThread` | Hydrated thread + assistant metadata |

#### `brain` — [brain.ts](apps/server/src/trpc/routes/brain.ts)
| Procedure | Purpose |
| --- | --- |
| `enableBrain` | Turn on background analysis for a connection |
| `disableBrain` | Turn off background analysis |
| `getState` | Current brain processing state |
| `generateSummary` | Summarize a thread/conversation |
| `getLabels` | List AI label classifications |
| `updateLabels` | Update label set |
| `getPrompts` | List per-use-case prompts |
| `updatePrompt` | Override a system prompt |

#### `mail` — [mail.ts](apps/server/src/trpc/routes/mail.ts)
| Procedure | Purpose |
| --- | --- |
| `listThreads` | Paginated folder listing |
| `listThreadsMulti` | Multi-connection folder listing |
| `get` | Fetch full thread |
| `send` | Send composed message |
| `unsend` | Unsend (within window) |
| `delete` | Trash a thread |
| `deleteAllSpam` | Empty spam folder |
| `forceSync` | Trigger full SyncThreadsWorkflow |
| `softSync` | Incremental sync (Gmail history API) |
| `rewatchGmail` | Re-register Gmail watch (push) |
| `suggestRecipients` | Autocomplete recipient addresses |
| `listSenders` | Connection sender alias list |
| `getEmailAliases` | Fetch send-as aliases |
| `verifyEmail` | Verify send-as alias |
| `getMessageAttachments` | Fetch attachment metadata |
| `getRawEmail` | Raw RFC822 download |
| `processEmailContent` | Server-side body sanitization |
| `modifyLabels` | Apply/remove labels |
| `markAsRead` | Mark thread read |
| `markAsUnread` | Mark thread unread |
| `toggleStar` | Star/unstar |
| `bulkStar` | Bulk star |
| `bulkUnstar` | Bulk unstar |
| `markAsImportant` | Mark important |
| `toggleImportant` | Toggle important |
| `bulkMarkImportant` | Bulk mark important |
| `bulkUnmarkImportant` | Bulk unmark important |
| `bulkArchive` | Bulk archive |
| `bulkDelete` | Bulk delete |
| `bulkMute` | Bulk mute thread |
| `snoozeThreads` | Snooze with return-at timestamp |
| `unsnoozeThreads` | Unsnooze |

#### `drafts` — [drafts.ts](apps/server/src/trpc/routes/drafts.ts)
`create`, `get`, `list`, `update`, `delete` — draft message CRUD.

#### `templates` — [templates.ts](apps/server/src/trpc/routes/templates.ts)
`create`, `list`, `delete` — email templates with variables.

#### `connections` — [connections.ts](apps/server/src/trpc/routes/connections.ts)
| Procedure | Purpose |
| --- | --- |
| `list` | All connected accounts |
| `getDefault` | Current default connection |
| `setDefault` | Change default account |
| `updateColor` | Customize account color |
| `delete` | Disconnect an account |

#### `calendar` — [calendar.ts](apps/server/src/trpc/routes/calendar.ts)
`calendars` (list), `events` (per-calendar), `eventsMulti` (across calendars), `createEvent`, `updateEvent`, `deleteEvent`.

#### `meet` — [meet.ts](apps/server/src/trpc/routes/meet.ts)
| Procedure | Purpose |
| --- | --- |
| `listMeetings` | List recorded meetings |
| `getMeeting` | Fetch meeting + transcript |
| `createMeeting` / `create` | Manual meeting creation |
| `deleteMeeting` | Delete meeting record |
| `scheduleBot` | Send Recall.ai bot to a meeting |
| `cancelBot` | Cancel scheduled bot |
| `syncFromCalendar` | Auto-create meetings from calendar |
| `getIntegration` | Recall integration state |
| `upsertIntegration` | Configure integration |
| `generateSummary` | AI summary of transcript |
| `askQuestion` | Q&A over transcript |

#### `tasks` — [tasks.ts](apps/server/src/trpc/routes/tasks.ts)
`create`, `list`, `update`, `delete`, `sync`, `reorder`, `summary`, `listContents`, `addItem`, `removeItem`.

#### `folders` — [tasks.ts](apps/server/src/trpc/routes/tasks.ts) (exported alongside `tasksRouter`)
Folder CRUD with color/icon/position.

#### `notes` — [notes.ts](apps/server/src/trpc/routes/notes.ts)
`create`, `list`, `update`, `delete`, `reorder`.

#### `docs` — [docs.ts](apps/server/src/trpc/routes/docs.ts)
`create`, `get`, `list`, `update`, `delete`, `search` — workspace document CRUD.

#### `categories` — [categories.ts](apps/server/src/trpc/routes/categories.ts)
`defaults` — default mail categories.

#### `labels` — [label.ts](apps/server/src/trpc/routes/label.ts)
`create`, `list`, `update`, `delete` — custom label management.

#### `groups` — [groups.ts](apps/server/src/trpc/routes/groups.ts)
| Procedure | Purpose |
| --- | --- |
| `create` | Create group |
| `update` | Update group |
| `delete` | Delete group |
| `get` | Get group by id |
| `getByInvite` | Resolve invite token |
| `join` | Join via invite |
| `leave` | Leave group |
| `kickMember` | Owner removes member |
| `regenerateInvite` | Rotate invite code |
| `listMine` | My groups |
| `sendMessage` | Post a message |
| `listMessages` | Paginated messages (cursor in [groups-cursor.ts](apps/server/src/trpc/routes/groups-cursor.ts)) |

#### `sharing` — [sharing.ts](apps/server/src/trpc/routes/sharing.ts)
`create`, `update`, `get`, `listMine`, `revoke` — shared conversation/resource links.

#### `mentions` — [mentions.ts](apps/server/src/trpc/routes/mentions.ts)
`search` — @-mention candidate lookup.

#### `contact` — [contact.ts](apps/server/src/trpc/routes/contact.ts)
`submit` — public contact form (Resend → support inbox).

#### `user` — [user.ts](apps/server/src/trpc/routes/user.ts)
`delete` — full account deletion cascade.

#### `settings` — [settings.ts](apps/server/src/trpc/routes/settings.ts)
`get`, `save` — user settings JSON blob.

#### `subscription` — [subscription.ts](apps/server/src/trpc/routes/subscription.ts)
| Procedure | Purpose |
| --- | --- |
| `getPricingTable` | Pricing tiers (Autumn) |
| `getStatus` | Active plan/status |
| `attach` | Attach a plan |
| `cancel` | Cancel subscription |
| `refresh` | Force-refresh status |
| `getBillingPortalUrl` | Autumn billing portal URL |

#### `sessions` — [sessions.ts](apps/server/src/trpc/routes/sessions.ts)
`list`, `revoke`, `revokeAll` — active session management.

#### `avatar` — [avatar.ts](apps/server/src/trpc/routes/avatar.ts)
`getByEmail` — sender avatar lookup.

#### `bimi` — [bimi.ts](apps/server/src/trpc/routes/bimi.ts)
`getByEmail`, `getByDomain` — BIMI brand-indicator logo fetch.

#### `shortcut` — [shortcut.ts](apps/server/src/trpc/routes/shortcut.ts)
`update` — store user hotkey overrides.

#### `logging` — [logging.ts](apps/server/src/trpc/routes/logging.ts)
`getSessionState`, `getSessionStats`, `clearSession` — client-side log session telemetry.

#### `cookiePreferences` — [cookies.ts](apps/server/src/trpc/routes/cookies.ts)
`getPreferences`, `updatePreferences` — cookie consent state.

### 2.2 HTTP Endpoints (non-tRPC)

Defined in [apps/server/src/main.ts](apps/server/src/main.ts) and sub-routers under [apps/server/src/routes/](apps/server/src/routes/).

| Method | Path | File | Purpose |
| --- | --- | --- | --- |
| GET | `/health` | [main.ts](apps/server/src/main.ts) | Health check |
| GET | `/` | [main.ts](apps/server/src/main.ts) | Redirect to `VITE_PUBLIC_APP_URL` |
| GET | `/auth/me` | [main.ts](apps/server/src/main.ts) | Current user identity |
| GET | `/auth/mobile-token` | [main.ts](apps/server/src/main.ts) | Issue mobile Bearer token |
| POST | `/auth/refresh-native-token` | [main.ts](apps/server/src/main.ts) | Refresh native Bearer |
| POST | `/auth/native-email-otp/verify` | [main.ts](apps/server/src/main.ts) | Verify email OTP for native apps |
| POST | `/auth/native-link-social` | [main.ts](apps/server/src/main.ts) | Link social account to native user |
| GET/POST/OPTIONS | `/auth/*` | [main.ts](apps/server/src/main.ts) | Better Auth handler |
| GET | `/.well-known/oauth-authorization-server` | [main.ts](apps/server/src/main.ts) | OAuth discovery |
| GET | `/.well-known/openid-configuration` | [main.ts](apps/server/src/main.ts) | OpenID discovery |
| — (mount) | `/sse/:sessionId` | [main.ts](apps/server/src/main.ts) | SSE stream (AI chat) |
| — (mount) | `/mcp/*` | [main.ts](apps/server/src/main.ts) | MCP server (ZeroMCP) |
| POST | `/admin/run-migrations` | [main.ts](apps/server/src/main.ts) | Run SQL migrations |
| POST | `/monitoring/sentry` | [main.ts](apps/server/src/main.ts) | Sentry relay |
| POST | `/a8n/notify/:providerId` | [main.ts](apps/server/src/main.ts) | Inbound notification dispatch |
| — | `/api` (mount) | [main.ts](apps/server/src/main.ts) | tRPC mount |
| — | `/ai` (route) | [routes/ai.ts](apps/server/src/routes/ai.ts) | Twilio + ElevenLabs phone AI + chat (`/ai/chat`, `/ai/voice-ws`, `/ai/voice-ping`, `/ai/voice/system-prompt`, `/ai/do/:action`, `/ai/call`) |
| — | `/autumn` (route) | [routes/autumn.ts](apps/server/src/routes/autumn.ts) | Autumn billing proxy (`customers`, `attach`, `cancel`, `check`, `track`, `billing_portal`, `openBillingPortal`, `entities`, `components/pricing_table`) |
| — | `/public` (route) | [routes/auth.ts](apps/server/src/routes/auth.ts) | Public auth utilities (`/public/providers`) |
| POST | `/webhooks/recall` | [routes/recall-webhook.ts](apps/server/src/routes/recall-webhook.ts) | Recall.ai bot event webhook |
| POST | `/webhooks/autumn` | [routes/autumn-webhook.ts](apps/server/src/routes/autumn-webhook.ts) | Autumn billing event webhook |

### 2.3 Auth System

Better Auth: [apps/server/src/lib/auth.ts](apps/server/src/lib/auth.ts).

Providers enabled: **Google OAuth**, **Apple Sign In**, **Email OTP** (via Resend), **phone number** (via Twilio), **email/password** (with required email verification). Microsoft is commented out.

Plugins: OAuth server (issues third-party tokens), mobile-token issuance, session metadata, JWKS for JWT signing.

`trustedOrigins` hard-coded in `createAuthConfig()`. Cookie domain `todus.app` set in [wrangler.jsonc](apps/server/wrangler.jsonc).

### 2.4 Durable Objects

| Class | File | Purpose |
| --- | --- | --- |
| `ZeroAgent` | [routes/agent/index.ts:1733](apps/server/src/routes/agent/index.ts) (canonical) + [routes/chat.ts](apps/server/src/routes/chat.ts) | AI chat agent (`AIChatAgent`) — per-user orchestrator |
| `ZeroMCP` | [routes/agent/mcp.ts](apps/server/src/routes/agent/mcp.ts) + [routes/chat.ts](apps/server/src/routes/chat.ts) | MCP server runtime for AI tool calls |
| `ZeroDB` | [main.ts](apps/server/src/main.ts) | SQLite-backed user data DO (notes, templates, style matrices, user CRUD) |
| `ZeroDriver` | [routes/agent/index.ts](apps/server/src/routes/agent/index.ts) | Top-level driver routing to shard agents |
| `ThinkingMCP` | [lib/sequential-thinking.ts:176](apps/server/src/lib/sequential-thinking.ts) | Sequential thinking / reflection MCP |
| `ShardRegistry` | [routes/agent/index.ts](apps/server/src/routes/agent/index.ts) | Maps userId → shard index |
| `ThreadSyncWorker` | [routes/agent/sync-worker.ts](apps/server/src/routes/agent/sync-worker.ts) | Paginated Gmail thread fetcher |
| `WorkflowRunner` | [pipelines.ts](apps/server/src/pipelines.ts) | Workflow execution DO |

### 2.5 Workflows

| Class | File | Purpose |
| --- | --- | --- |
| `SyncThreadsWorkflow` | [workflows/sync-threads-workflow.ts](apps/server/src/workflows/sync-threads-workflow.ts) | Per-connection Gmail thread sync |
| `SyncThreadsCoordinatorWorkflow` | [workflows/sync-threads-coordinator-workflow.ts](apps/server/src/workflows/sync-threads-coordinator-workflow.ts) | Fans out per-user sync across connections |

### 2.6 Queues & Scheduled

Bindings in [wrangler.jsonc](apps/server/wrangler.jsonc):

| Queue | Consumer in | Purpose |
| --- | --- | --- |
| `thread-queue` (`thread_queue` binding) | [main.ts](apps/server/src/main.ts) | Thread update processing → upsert tables |
| `subscribe-queue` (`subscribe_queue` binding) | [main.ts](apps/server/src/main.ts) | Trigger brain analysis on new threads |
| `send-email-queue` (`send_email_queue` binding) | [main.ts](apps/server/src/main.ts) | Outgoing Resend delivery |

Scheduled handler (cron): hourly check polls `scheduled_emails` KV, queues mature items to `send-email-queue`.

### 2.7 Database Schema

PostgreSQL via Hyperdrive. All tables prefixed `mail0_` (set by `pgTableCreator`). Schema: [apps/server/src/db/schema.ts](apps/server/src/db/schema.ts).

| Table | Purpose |
| --- | --- |
| `user` | User accounts (Better Auth) |
| `session` | Active sessions |
| `sessionMetadata` | Extended session data (ip, ua) |
| `account` | OAuth provider links |
| `verification` | Email/OTP verification tokens |
| `userSettings` | User preferences (JSON) |
| `userHotkeys` | Custom keyboard shortcuts |
| `connection` | Gmail / Outlook OAuth connections |
| `writingStyleMatrix` | Per-connection AI writing style |
| `note` | Notes |
| `summary` | Cached thread summaries |
| `emailTemplate` | Saved email templates |
| `doc` | Documents (markdown/Tiptap JSON) |
| `docWorkspace` | Document workspaces |
| `taskFolder` | Task folders w/ color/icon/position |
| `folderItem` | Custom folder ordering |
| `task` | Tasks |
| `assistantOpenLoop` | Unresolved action items |
| `assistantPreparedAction` | AI-suggested follow-ups |
| `assistantPersonMemory` | Per-person memory |
| `assistantWorkstreamMemory` | Per-project memory |
| `assistantFeedback` | User feedback on AI |
| `assistantBriefingSnapshot` | Cached daily briefing |
| `meeting` | Recall.ai meetings |
| `meetingMedia` | Recording media |
| `meetingTranscript` | Transcripts |
| `meetIntegration` | Calendar + Recall integration state |
| `group` | User groups |
| `groupMember` | Membership w/ roles |
| `groupMessage` | Group chat messages |
| `aiConversation` | Saved multi-turn chats |
| `sharedConversation` | Public shared chat links |
| `oauthApplication` | Registered OAuth clients (server) |
| `oauthAccessToken` | Issued tokens |
| `oauthConsent` | Consent records |
| `jwks` | JSON Web Key Set |
| `marketingEmailDelivery` | Resend campaign tracking |
| `earlyAccess` | Per-user feature flags |

### 2.8 wrangler.jsonc Bindings

[apps/server/wrangler.jsonc](apps/server/wrangler.jsonc)

**Workers AI**: `AI` binding.

**Vectorize**: `VECTORIZE` (threads), `VECTORIZE_MESSAGE` (messages).

**R2**: `THREADS_BUCKET` — large thread payload archive.

**Hyperdrive**: `HYPERDRIVE` — pooled Postgres connection.

**Durable Objects** (per environment): `ZERO_AGENT`, `ZERO_MCP`, `ZERO_DB`, `ZERO_DRIVER`, `THINKING_MCP`, `WORKFLOW_RUNNER`, `THREAD_SYNC_WORKER`, `SHARD_REGISTRY`.

**Workflows**: `SYNC_THREADS_WORKFLOW`, `SYNC_THREADS_COORDINATOR_WORKFLOW`.

**KV namespaces**:
| Binding | Purpose |
| --- | --- |
| `gmail_history_id` | Last synced history ID per connection |
| `gmail_processing_threads` | Threads in-flight |
| `subscribed_accounts` | Brain subscription list |
| `connection_labels` | Cached Gmail labels |
| `prompts_storage` | Custom AI prompts |
| `gmail_sub_age` | Gmail watch subscription age |
| `pending_emails_status` | Send-queue status (pending/sent/failed) |
| `pending_emails_payload` | Pending email bodies |
| `scheduled_emails` | Future-dated sends |
| `snoozed_emails` | Snoozed threads return-at |

### 2.9 External Integrations

| Service | Where | Purpose |
| --- | --- | --- |
| Resend | [main.ts](apps/server/src/main.ts), [contact.ts](apps/server/src/trpc/routes/contact.ts), `marketingEmailDelivery` | Transactional + marketing email |
| Recall.ai | [meet.ts](apps/server/src/trpc/routes/meet.ts), [recall-webhook.ts](apps/server/src/routes/recall-webhook.ts) | Meeting bot + transcripts |
| Autumn | [autumn.ts](apps/server/src/routes/autumn.ts), [autumn-webhook.ts](apps/server/src/routes/autumn-webhook.ts), [subscription.ts](apps/server/src/trpc/routes/subscription.ts) | Subscription billing |
| OpenAI | [ai/transcribeAudio.ts](apps/server/src/trpc/routes/ai/transcribeAudio.ts), AI SDK throughout | Whisper transcription, GPT models |
| Anthropic | AI SDK throughout | Claude models (thinking) |
| Perplexity | [ai/webSearch.ts](apps/server/src/trpc/routes/ai/webSearch.ts) | Web search |
| Google APIs | Gmail / Calendar | Mail + calendar OAuth |
| Microsoft Graph | Outlook (connection.providerId=`microsoft`) | Outlook mail |
| Twilio | [routes/ai.ts](apps/server/src/routes/ai.ts) | Phone / SMS |
| ElevenLabs | [routes/ai.ts](apps/server/src/routes/ai.ts) | Voice synthesis (phone AI) |
| Sentry | [main.ts](apps/server/src/main.ts) | Error tracking + relay |
| OpenTelemetry | Queue handlers, AI ops | Distributed tracing |

---

## 3. iOS (apps/ios/Todus)

Project: [apps/ios/Todus/Todus.xcodeproj](apps/ios/Todus/Todus.xcodeproj). Bundle: `com.ludvighedin.todus`. Deep link scheme: `todus://`.

### 3.1 Tabs & Navigation

Default tab order: **Home, Tasks, Email, Calendar** (Tab.role = .search reserved for AI; Create = action-only). Customizable via [TabBarCustomizationView](apps/ios/Todus/Todus/Features/Settings/TabBarCustomizationView.swift). More-sheet entry: [MoreSheetView.swift](apps/ios/Todus/Todus/Features/MoreSheetView.swift).

| Tab | Default | Role | Source |
| --- | --- | --- | --- |
| Home | ✓ | Destination | [Features/Home/HomeView.swift](apps/ios/Todus/Todus/Features/Home/HomeView.swift) |
| Tasks | ✓ | Destination | [Features/Tasks/TasksTabView.swift](apps/ios/Todus/Todus/Features/Tasks/TasksTabView.swift) |
| Email | ✓ | Destination | [Features/Email/EmailInboxView.swift](apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift) |
| Calendar | ✓ | Destination | [Features/Calendar/CalendarContainerView.swift](apps/ios/Todus/Todus/Features/Calendar/CalendarContainerView.swift) |
| Meetings | More | Destination | [Features/Meetings/MeetingsListView.swift](apps/ios/Todus/Todus/Features/Meetings/MeetingsListView.swift) |
| Docs | More | Destination | [Features/Docs/DocsListView.swift](apps/ios/Todus/Todus/Features/Docs/DocsListView.swift) |
| AI | Trailing | Search | [Features/AI/AIChatView.swift](apps/ios/Todus/Todus/Features/AI/AIChatView.swift) |
| Create | Hidden | Action | Opens CreateSheet (no destination) |

### 3.2 Mail

[Features/Email/](apps/ios/Todus/Todus/Features/Email/)

| View | Purpose |
| --- | --- |
| [EmailInboxView.swift](apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift) | Inbox thread list |
| [EmailThreadView.swift](apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift) | Conversation view |
| [EmailComposeView.swift](apps/ios/Todus/Todus/Features/Email/EmailComposeView.swift) | New / reply / forward composer |
| [EmailAIDraftSheet.swift](apps/ios/Todus/Todus/Features/Email/EmailAIDraftSheet.swift) | AI-assisted draft modal |
| [EmailConnectView.swift](apps/ios/Todus/Todus/Features/Email/EmailConnectView.swift) | Gmail OAuth flow |
| [EmailRowView.swift](apps/ios/Todus/Todus/Features/Email/EmailRowView.swift) | List row w/ swipe actions |
| [SenderAvatarView.swift](apps/ios/Todus/Todus/Features/Email/SenderAvatarView.swift) | Avatar component |
| [SenderIconRegistry.swift](apps/ios/Todus/Todus/Features/Email/SenderIconRegistry.swift) | Branded sender icon lookup |

### 3.3 AI / Assistant

[Features/AI/](apps/ios/Todus/Todus/Features/AI/)

| View | Purpose |
| --- | --- |
| [AIChatView.swift](apps/ios/Todus/Todus/Features/AI/AIChatView.swift) | Primary chat surface |
| [AIChatMessage.swift](apps/ios/Todus/Todus/Features/AI/AIChatMessage.swift) | Message model + view |
| [GroupChatView.swift](apps/ios/Todus/Todus/Features/AI/GroupChatView.swift) | Multi-participant chat |
| [SharedConversationView.swift](apps/ios/Todus/Todus/Features/AI/SharedConversationView.swift) | Deep-linked shared chat |
| [ShareConversationSheet.swift](apps/ios/Todus/Todus/Features/AI/ShareConversationSheet.swift) | Share-conversation modal |
| [AISourcesView.swift](apps/ios/Todus/Todus/Features/AI/AISourcesView.swift) | Context source picker |
| [AIAttachmentSheet.swift](apps/ios/Todus/Todus/Features/AI/AIAttachmentSheet.swift) | Attachment picker |
| [AttachmentPreviewSheet.swift](apps/ios/Todus/Todus/Features/AI/AttachmentPreviewSheet.swift) | Attachment preview |
| [MarkdownView.swift](apps/ios/Todus/Todus/Features/AI/MarkdownView.swift) | Markdown renderer |
| [ChatUISpec.swift](apps/ios/Todus/Todus/Features/AI/ChatUISpec.swift) | Generative UI spec |
| [ChatUISpecView.swift](apps/ios/Todus/Todus/Features/AI/ChatUISpecView.swift) | Spec renderer |
| [CardViews.swift](apps/ios/Todus/Todus/Features/AI/CardViews.swift) | Card primitives |
| [LocalModels/](apps/ios/Todus/Todus/Features/AI/LocalModels/) | Local model catalog + recommender |

### 3.4 Calendar

[Features/Calendar/](apps/ios/Todus/Todus/Features/Calendar/)

| View | Purpose |
| --- | --- |
| [CalendarContainerView.swift](apps/ios/Todus/Todus/Features/Calendar/CalendarContainerView.swift) | Tab root |
| [CalendarTabView.swift](apps/ios/Todus/Todus/Features/Calendar/CalendarTabView.swift) | View-mode switcher |
| [CalendarNavBar.swift](apps/ios/Todus/Todus/Features/Calendar/CalendarNavBar.swift) | Calendar nav bar |
| [CalendarViewMode.swift](apps/ios/Todus/Todus/Features/Calendar/CalendarViewMode.swift) | Mode enum |
| [CalendarViewModePicker.swift](apps/ios/Todus/Todus/Features/Calendar/CalendarViewModePicker.swift) | Mode picker UI |
| [CalendarMonthView.swift](apps/ios/Todus/Todus/Features/Calendar/CalendarMonthView.swift) | Month grid |
| [CalendarYearView.swift](apps/ios/Todus/Todus/Features/Calendar/CalendarYearView.swift) | Year overview |
| [CalendarMultiDayView.swift](apps/ios/Todus/Todus/Features/Calendar/CalendarMultiDayView.swift) | Week / multi-day |
| [CalendarTimeGridView.swift](apps/ios/Todus/Todus/Features/Calendar/CalendarTimeGridView.swift) | Hour grid |
| [CalendarListView.swift](apps/ios/Todus/Todus/Features/Calendar/CalendarListView.swift) | Event list |
| [CalendarEventBlockView.swift](apps/ios/Todus/Todus/Features/Calendar/CalendarEventBlockView.swift) | Event block |
| [CalendarPermissionView.swift](apps/ios/Todus/Todus/Features/Calendar/CalendarPermissionView.swift) | Permission request |
| [CalendarSourcePickerView.swift](apps/ios/Todus/Todus/Features/Calendar/CalendarSourcePickerView.swift) | Source/account picker |
| [CalendarViewController.swift](apps/ios/Todus/Todus/Features/Calendar/CalendarViewController.swift) | CalendarKit bridge |
| [EKWrapper.swift](apps/ios/Todus/Todus/Features/Calendar/EKWrapper.swift) | EventKit wrapper |

### 3.5 Tasks

[Features/Tasks/](apps/ios/Todus/Todus/Features/Tasks/)

| View | Purpose |
| --- | --- |
| [TasksTabView.swift](apps/ios/Todus/Todus/Features/Tasks/TasksTabView.swift) | Tab root |
| [CaptureComposer.swift](apps/ios/Todus/Todus/Features/Tasks/CaptureComposer.swift) | NL task input |
| [InboxView.swift](apps/ios/Todus/Todus/Features/Tasks/InboxView.swift) | Inbox (uncategorized) |
| [TaskTableView.swift](apps/ios/Todus/Todus/Features/Tasks/TaskTableView.swift) | List mode |
| [BoardView.swift](apps/ios/Todus/Todus/Features/Tasks/BoardView.swift) | Kanban board |
| [BoardColumnView.swift](apps/ios/Todus/Todus/Features/Tasks/BoardColumnView.swift) | Kanban column |
| [BoardTaskCard.swift](apps/ios/Todus/Todus/Features/Tasks/BoardTaskCard.swift) | Kanban card |
| [TaskRowView.swift](apps/ios/Todus/Todus/Features/Tasks/TaskRowView.swift) | List row |
| [TaskDetailSheet.swift](apps/ios/Todus/Todus/Features/Tasks/TaskDetailSheet.swift) | Detail modal |
| [CalendarTaskView.swift](apps/ios/Todus/Todus/Features/Tasks/CalendarTaskView.swift) | Calendar-overlay task |
| [CustomTabBar.swift](apps/ios/Todus/Todus/Features/Tasks/CustomTabBar.swift) | Legacy tab bar |

### 3.6 Notes / Docs

[Features/Docs/](apps/ios/Todus/Todus/Features/Docs/) — [DocsListView.swift](apps/ios/Todus/Todus/Features/Docs/DocsListView.swift) (list), [DocEditorView.swift](apps/ios/Todus/Todus/Features/Docs/DocEditorView.swift) (native shell), [DocsWebView.swift](apps/ios/Todus/Todus/Features/Docs/DocsWebView.swift) (Tiptap web wrapper).

### 3.7 Meetings

[Features/Meetings/](apps/ios/Todus/Todus/Features/Meetings/) — [MeetingsListView.swift](apps/ios/Todus/Todus/Features/Meetings/MeetingsListView.swift), [MeetingDetailView.swift](apps/ios/Todus/Todus/Features/Meetings/MeetingDetailView.swift) (transcript + AI summary).

### 3.8 Folders / Labels

[Features/Folders/](apps/ios/Todus/Todus/Features/Folders/)

| View | Purpose |
| --- | --- |
| [FolderDetailView.swift](apps/ios/Todus/Todus/Features/Folders/FolderDetailView.swift) | Folder contents |
| [FolderManagementView.swift](apps/ios/Todus/Todus/Features/Folders/FolderManagementView.swift) | CRUD |
| [FolderPickerSheet.swift](apps/ios/Todus/Todus/Features/Folders/FolderPickerSheet.swift) | Modal picker |
| [FolderEditSheet.swift](apps/ios/Todus/Todus/Features/Folders/FolderEditSheet.swift) | Edit modal |
| [MoveToFolderSheet.swift](apps/ios/Todus/Todus/Features/Folders/MoveToFolderSheet.swift) | Move action |
| [AddToFolderSheet.swift](apps/ios/Todus/Todus/Features/Folders/AddToFolderSheet.swift) | Add action |
| [FolderCardView.swift](apps/ios/Todus/Todus/Features/Folders/FolderCardView.swift) | Card component |

### 3.9 Voice

[Features/Voice/](apps/ios/Todus/Todus/Features/Voice/) — [VoiceChatModalView.swift](apps/ios/Todus/Todus/Features/Voice/VoiceChatModalView.swift), [VoiceInputButton.swift](apps/ios/Todus/Todus/Features/Voice/VoiceInputButton.swift), [VoiceChatViewModel.swift](apps/ios/Todus/Todus/Features/Voice/VoiceChatViewModel.swift). Backed by Gemini Live via services in §3.13.

### 3.10 Home, Search, Notifications, DesignSystem, Auth

| Area | File |
| --- | --- |
| Home | [Features/Home/HomeView.swift](apps/ios/Todus/Todus/Features/Home/HomeView.swift) |
| Global search | [Features/Search/GlobalSearchView.swift](apps/ios/Todus/Todus/Features/Search/GlobalSearchView.swift) |
| Notification center | [Features/Notifications/NotificationCenterView.swift](apps/ios/Todus/Todus/Features/Notifications/NotificationCenterView.swift) |
| Design system viewer | [Features/DesignSystem/DesignSystemView.swift](apps/ios/Todus/Todus/Features/DesignSystem/DesignSystemView.swift), [DSTokenRow.swift](apps/ios/Todus/Todus/Features/DesignSystem/DSTokenRow.swift) |
| Auth root | [Features/Auth/AuthView.swift](apps/ios/Todus/Todus/Features/Auth/AuthView.swift) |
| Onboarding auth | [Features/Auth/OnboardingAuthSheet.swift](apps/ios/Todus/Todus/Features/Auth/OnboardingAuthSheet.swift) |

### 3.11 Settings

[Features/Settings/](apps/ios/Todus/Todus/Features/Settings/)

| View | Purpose |
| --- | --- |
| [SettingsView.swift](apps/ios/Todus/Todus/Features/Settings/SettingsView.swift) | Settings root |
| [BillingSettingsView.swift](apps/ios/Todus/Todus/Features/Settings/BillingSettingsView.swift) | Subscription / Autumn |
| [CalendarAccountsView.swift](apps/ios/Todus/Todus/Features/Settings/CalendarAccountsView.swift) | Connected calendars |
| [EmailAutomationPolicyView.swift](apps/ios/Todus/Todus/Features/Settings/EmailAutomationPolicyView.swift) | Email automation rules |
| [EmptyGmailOnboardingView.swift](apps/ios/Todus/Todus/Features/Settings/EmptyGmailOnboardingView.swift) | Gmail-empty walkthrough |
| [LocalModelsView.swift](apps/ios/Todus/Todus/Features/Settings/LocalModelsView.swift) | Local model management |
| [RemindersSetupView.swift](apps/ios/Todus/Todus/Features/Settings/RemindersSetupView.swift) | Apple Reminders sync setup |
| [SignaturesView.swift](apps/ios/Todus/Todus/Features/Settings/SignaturesView.swift) | Email signatures |
| [TabBarCustomizationView.swift](apps/ios/Todus/Todus/Features/Settings/TabBarCustomizationView.swift) | Tab bar editor |
| [TabBarOnboardingView.swift](apps/ios/Todus/Todus/Features/Settings/TabBarOnboardingView.swift) | Initial tab setup |
| [VoiceAssistantSettingsView.swift](apps/ios/Todus/Todus/Features/Settings/VoiceAssistantSettingsView.swift) | Voice AI prefs |

### 3.12 Local AI / MLX

| Service | File | Purpose |
| --- | --- | --- |
| `AppleFoundationModelService` | [Services/AI/Local/AppleFoundationModelService.swift](apps/ios/Todus/Todus/Services/AI/Local/AppleFoundationModelService.swift) | On-device Apple Foundation Models |
| `LocalAIService` | [Services/AI/Local/LocalAIService.swift](apps/ios/Todus/Todus/Services/AI/Local/LocalAIService.swift) | Local model orchestrator |
| `LocalModelStateStore` | [Services/AI/Local/LocalModelStateStore.swift](apps/ios/Todus/Todus/Services/AI/Local/LocalModelStateStore.swift) | Model state persistence |
| `MLXInferenceService` | [Services/AI/Local/MLXInferenceService.swift](apps/ios/Todus/Todus/Services/AI/Local/MLXInferenceService.swift) | MLX inference (Metal) |
| `ModelDownloadService` | [Services/AI/Local/ModelDownloadService.swift](apps/ios/Todus/Todus/Services/AI/Local/ModelDownloadService.swift) | HuggingFace download mgr |

### 3.13 Services Layer

[Services/](apps/ios/Todus/Todus/Services/)

| Service | File | Purpose |
| --- | --- | --- |
| AuthService | [Services/Auth/AuthService.swift](apps/ios/Todus/Todus/Services/Auth/AuthService.swift) | Apple / Google / OTP + Keychain |
| AuthSessionStore | [Services/Auth/AuthSessionStore.swift](apps/ios/Todus/Todus/Services/Auth/AuthSessionStore.swift) | Session + deep link |
| AIChatService | [Services/AI/AIChatService.swift](apps/ios/Todus/Todus/Services/AI/AIChatService.swift) | Chat orchestrator + SSE streaming |
| GroupChatService | [Services/AI/GroupChatService.swift](apps/ios/Todus/Todus/Services/AI/GroupChatService.swift) | Multi-participant chat |
| ShareConversationService | [Services/AI/ShareConversationService.swift](apps/ios/Todus/Todus/Services/AI/ShareConversationService.swift) | Shareable conversation links |
| ConnectionsService | [Services/API/ConnectionsService.swift](apps/ios/Todus/Todus/Services/API/ConnectionsService.swift) | Third-party connection mgmt |
| TodosAPIClient | [Services/API/TodosAPIClient.swift](apps/ios/Todus/Todus/Services/API/TodosAPIClient.swift) | tRPC HTTP client |
| SupabaseEdgeFunctionClient | [Services/API/SupabaseEdgeFunctionClient.swift](apps/ios/Todus/Todus/Services/API/SupabaseEdgeFunctionClient.swift) | Edge function calls |
| CalendarService | [Services/Calendar/CalendarService.swift](apps/ios/Todus/Todus/Services/Calendar/CalendarService.swift) | Event CRUD |
| CalendarSource | [Services/Calendar/CalendarSource.swift](apps/ios/Todus/Todus/Services/Calendar/CalendarSource.swift) | Source enum |
| GoogleCalendarService | [Services/Calendar/GoogleCalendarService.swift](apps/ios/Todus/Todus/Services/Calendar/GoogleCalendarService.swift) | Google Calendar |
| UnifiedCalendarService | [Services/Calendar/UnifiedCalendarService.swift](apps/ios/Todus/Todus/Services/Calendar/UnifiedCalendarService.swift) | Apple + Google merge |
| DocsService | [Services/Docs/DocsService.swift](apps/ios/Todus/Todus/Services/Docs/DocsService.swift) | Documents CRUD |
| DraftService | [Services/Drafts/DraftService.swift](apps/ios/Todus/Todus/Services/Drafts/DraftService.swift) | Compose drafts |
| EmailService | [Services/Email/EmailService.swift](apps/ios/Todus/Todus/Services/Email/EmailService.swift) | Gmail wrapper |
| AssistantPersistedCache | [Services/Email/AssistantPersistedCache.swift](apps/ios/Todus/Todus/Services/Email/AssistantPersistedCache.swift) | Email AI analysis cache |
| MeetingsService | [Services/Meetings/MeetingsService.swift](apps/ios/Todus/Todus/Services/Meetings/MeetingsService.swift) | Meetings + transcripts |
| NotificationService | [Services/Notifications/NotificationService.swift](apps/ios/Todus/Todus/Services/Notifications/NotificationService.swift) | APNS + local |
| NotificationDigestService | [Services/Notifications/NotificationDigestService.swift](apps/ios/Todus/Todus/Services/Notifications/NotificationDigestService.swift) | Batched notifications |
| TaskParsingService | [Services/Parsing/TaskParsingService.swift](apps/ios/Todus/Todus/Services/Parsing/TaskParsingService.swift) | NL → task parsing protocol |
| RemoteFirstTaskParsingService | [Services/Parsing/RemoteFirstTaskParsingService.swift](apps/ios/Todus/Todus/Services/Parsing/RemoteFirstTaskParsingService.swift) | Cloud → local fallback |
| LocalTaskParsingService | [Services/Parsing/LocalTaskParsingService.swift](apps/ios/Todus/Todus/Services/Parsing/LocalTaskParsingService.swift) | On-device fallback |
| CompoundIntentParser | [Services/Parsing/CompoundIntentParser.swift](apps/ios/Todus/Todus/Services/Parsing/CompoundIntentParser.swift) | Multi-intent splitter |
| AppleRemindersSyncService | [Services/Reminders/AppleRemindersSyncService.swift](apps/ios/Todus/Todus/Services/Reminders/AppleRemindersSyncService.swift) | Reminders bidirectional |
| RemindersSyncState | [Services/Reminders/RemindersSyncState.swift](apps/ios/Todus/Todus/Services/Reminders/RemindersSyncState.swift) | Sync state |
| SubscriptionService | [Services/Subscription/SubscriptionService.swift](apps/ios/Todus/Todus/Services/Subscription/SubscriptionService.swift) | StoreKit + Autumn |
| SyncService | [Services/Tasks/SyncService.swift](apps/ios/Todus/Todus/Services/Tasks/SyncService.swift) | Task sync orchestrator |
| SupabaseSyncService | [Services/Tasks/SupabaseSyncService.swift](apps/ios/Todus/Todus/Services/Tasks/SupabaseSyncService.swift) | Supabase realtime sync |
| FolderSyncService | [Services/Tasks/FolderSyncService.swift](apps/ios/Todus/Todus/Services/Tasks/FolderSyncService.swift) | Folder CRUD + sync |
| TaskCaptureService | [Services/Tasks/TaskCaptureService.swift](apps/ios/Todus/Todus/Services/Tasks/TaskCaptureService.swift) | Task creation from parse |
| AttachmentService | [Services/Tasks/AttachmentService.swift](apps/ios/Todus/Todus/Services/Tasks/AttachmentService.swift) | File attachments |
| VoiceProvider | [Services/Voice/VoiceProvider.swift](apps/ios/Todus/Todus/Services/Voice/VoiceProvider.swift) | Voice provider protocol |
| VoiceSessionCoordinator | [Services/Voice/VoiceSessionCoordinator.swift](apps/ios/Todus/Todus/Services/Voice/VoiceSessionCoordinator.swift) | Voice chat orchestrator |
| VoiceSystemPromptClient | [Services/Voice/VoiceSystemPromptClient.swift](apps/ios/Todus/Todus/Services/Voice/VoiceSystemPromptClient.swift) | Prompt fetch |
| VoiceTokenService | [Services/Voice/VoiceTokenService.swift](apps/ios/Todus/Todus/Services/Voice/VoiceTokenService.swift) | Gemini Live token vending |
| VoiceToolRegistry | [Services/Voice/VoiceToolRegistry.swift](apps/ios/Todus/Todus/Services/Voice/VoiceToolRegistry.swift) | Voice tool/function registry |
| GeminiLiveProvider | [Services/Voice/GeminiLiveProvider.swift](apps/ios/Todus/Todus/Services/Voice/GeminiLiveProvider.swift) | Gemini Live implementation |
| VoiceAudioCapture | [Services/Voice/VoiceAudioCapture.swift](apps/ios/Todus/Todus/Services/Voice/VoiceAudioCapture.swift) | Mic capture |
| VoiceMicLock | [Services/Voice/VoiceMicLock.swift](apps/ios/Todus/Todus/Services/Voice/VoiceMicLock.swift) | Mic mutex |
| VoiceIntent | [Services/Voice/VoiceIntent.swift](apps/ios/Todus/Todus/Services/Voice/VoiceIntent.swift) | Intent enum |
| AudioPlayerManager | [Services/Voice/AudioPlayerManager.swift](apps/ios/Todus/Todus/Services/Voice/AudioPlayerManager.swift) | Speaker playback |
| WidgetUpdateManager | [Services/Widgets/WidgetUpdateManager.swift](apps/ios/Todus/Todus/Services/Widgets/WidgetUpdateManager.swift) | Widget timeline refresh |
| AppLogger | [Services/AppLogger.swift](apps/ios/Todus/Todus/Services/AppLogger.swift) | Logging |
| NetworkMonitor | [Services/NetworkMonitor.swift](apps/ios/Todus/Todus/Services/NetworkMonitor.swift) | Reachability |

### 3.14 Deep Links

| URL | Handler | Purpose |
| --- | --- | --- |
| `todus://share?slug=<id>` | `SharedConversationView` + `AIChatService` | Open shared AI conversation |
| `todus://auth-callback?email=<email>&token=<bearer>` | `AuthSessionStore.handleAuthCallback` | OAuth redirect / mobile token landing |
| `todus://link-callback` | App services | Generic link callback |
| `todus://` (root) | App launch | Default app launch |

### 3.15 Push Notifications

APNS registration via `AuthService` + `SubscriptionService`. Notification handling in [NotificationService.swift](apps/ios/Todus/Todus/Services/Notifications/NotificationService.swift); batching in [NotificationDigestService.swift](apps/ios/Todus/Todus/Services/Notifications/NotificationDigestService.swift); in-app history in [NotificationCenterView.swift](apps/ios/Todus/Todus/Features/Notifications/NotificationCenterView.swift). Notification Service Extension exists as a separate Xcode target.

---

## 4. macOS (apps/macos/TodusMac)

Project: [apps/macos/TodusMac.xcodeproj](apps/macos/TodusMac.xcodeproj). Swift 6. Native AppKit-bridged SwiftUI.

### 4.1 Sidebar Navigation

Root: [App/MacRootView.swift](apps/macos/TodusMac/App/MacRootView.swift). Sidebar: [App/MacSidebarView.swift](apps/macos/TodusMac/App/MacSidebarView.swift). App entry: [App/TodusMacApp.swift](apps/macos/TodusMac/App/TodusMacApp.swift). Header: [App/MacContentHeaderView.swift](apps/macos/TodusMac/App/MacContentHeaderView.swift).

Sidebar items: **Home, Tasks, Email (expandable → Inbox / Drafts / Sent / Archive / Snoozed / Spam / Trash), Calendar (expandable), Meetings, Docs, Voice, Settings, Log Out**. Unread badges on Tasks + Email.

### 4.2 Mail

[Views/Email/](apps/macos/TodusMac/Views/Email/)

| View | Purpose |
| --- | --- |
| [MacEmailInboxView.swift](apps/macos/TodusMac/Views/Email/MacEmailInboxView.swift) | Inbox |
| [MacEmailThreadView.swift](apps/macos/TodusMac/Views/Email/MacEmailThreadView.swift) | Thread |
| [MacEmailComposeView.swift](apps/macos/TodusMac/Views/Email/MacEmailComposeView.swift) | Composer |
| [MacMarkdownBodyEditor.swift](apps/macos/TodusMac/Views/Email/MacMarkdownBodyEditor.swift) | Markdown body editor (macOS-only) |
| [MacSenderIconRegistry.swift](apps/macos/TodusMac/Views/Email/MacSenderIconRegistry.swift) | Sender icon registry |
| [App/MacEmailTextField.swift](apps/macos/TodusMac/App/MacEmailTextField.swift) | Native email text field |

### 4.3 AI / Assistant

[Views/AI/](apps/macos/TodusMac/Views/AI/)

| View | Purpose |
| --- | --- |
| [MacAssistantPanel.swift](apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift) | Docked sidebar AI panel (macOS pattern) |
| [MacGroupChatView.swift](apps/macos/TodusMac/Views/AI/MacGroupChatView.swift) | Group chat |
| [MacAISourcesView.swift](apps/macos/TodusMac/Views/AI/MacAISourcesView.swift) | Sources |
| [MacShareConversationPanel.swift](apps/macos/TodusMac/Views/AI/MacShareConversationPanel.swift) | Share modal |
| [MacSharedConversationView.swift](apps/macos/TodusMac/Views/AI/MacSharedConversationView.swift) | Shared chat view |
| [MarkdownView.swift](apps/macos/TodusMac/Views/AI/MarkdownView.swift) | Markdown renderer |
| [ChatUISpec/](apps/macos/TodusMac/Views/AI/ChatUISpec/) | Spec + card primitives |
| [AssistantButton](apps/macos/TodusMac/App/AssistantButton.swift) | Toggle button (App/) |

### 4.4 Calendar

[Views/Calendar/](apps/macos/TodusMac/Views/Calendar/)

| View | Purpose |
| --- | --- |
| [MacCalendarView.swift](apps/macos/TodusMac/Views/Calendar/MacCalendarView.swift) | Calendar root |
| [CalendarTimeGridView.swift](apps/macos/TodusMac/Views/Calendar/CalendarTimeGridView.swift) | Time grid |
| [CalendarEventBlockView.swift](apps/macos/TodusMac/Views/Calendar/CalendarEventBlockView.swift) | Event block |
| [MacCalendarSourcePicker.swift](apps/macos/TodusMac/Views/Calendar/MacCalendarSourcePicker.swift) | Source picker |
| [MacEventEditSheet.swift](apps/macos/TodusMac/Views/Calendar/MacEventEditSheet.swift) | Event edit |
| [CalendarTrackpadNavigation.swift](apps/macos/TodusMac/Views/Calendar/CalendarTrackpadNavigation.swift) | Trackpad gesture nav (macOS-only) |

### 4.5 Tasks, Docs, Meetings, Folders, Home

| Area | File |
| --- | --- |
| Tasks | [Views/Tasks/MacTasksView.swift](apps/macos/TodusMac/Views/Tasks/MacTasksView.swift) (shared logic from iOS Tasks views) |
| Docs | [Views/Docs/MacDocsView.swift](apps/macos/TodusMac/Views/Docs/MacDocsView.swift), [MacDocsShellView.swift](apps/macos/TodusMac/Views/Docs/MacDocsShellView.swift), [MacDocEditorPane.swift](apps/macos/TodusMac/Views/Docs/MacDocEditorPane.swift), [TiptapDocEditorWebView.swift](apps/macos/TodusMac/Views/Docs/TiptapDocEditorWebView.swift) |
| Meetings | [Views/Meetings/MacMeetingsView.swift](apps/macos/TodusMac/Views/Meetings/MacMeetingsView.swift), [MacMeetingDetailView.swift](apps/macos/TodusMac/Views/Meetings/MacMeetingDetailView.swift) |
| Folders | [Views/Folders/MacFolderDetailView.swift](apps/macos/TodusMac/Views/Folders/MacFolderDetailView.swift), [MacFolderEditSheet.swift](apps/macos/TodusMac/Views/Folders/MacFolderEditSheet.swift), [MacFolderCardView.swift](apps/macos/TodusMac/Views/Folders/MacFolderCardView.swift), [App/MacFolderDTOs.swift](apps/macos/TodusMac/App/MacFolderDTOs.swift) |
| Home | [Views/Home/MacHomeView.swift](apps/macos/TodusMac/Views/Home/MacHomeView.swift) |

### 4.6 Search, Notifications, Create

| Area | File |
| --- | --- |
| Search | [Views/Search/MacSearchView.swift](apps/macos/TodusMac/Views/Search/MacSearchView.swift) |
| Notification center | [Views/Notifications/MacNotificationCenterView.swift](apps/macos/TodusMac/Views/Notifications/MacNotificationCenterView.swift) |
| Create sheet | [Views/Create/MacCreateSheet.swift](apps/macos/TodusMac/Views/Create/MacCreateSheet.swift) |

### 4.7 Voice

[Views/Voice/](apps/macos/TodusMac/Views/Voice/)

| View | Purpose |
| --- | --- |
| [MacVoiceChatPanel.swift](apps/macos/TodusMac/Views/Voice/MacVoiceChatPanel.swift) | Voice panel |
| [VoiceStatusWindow.swift](apps/macos/TodusMac/Views/Voice/VoiceStatusWindow.swift) | Floating status window |

### 4.8 Settings

[Views/Settings/](apps/macos/TodusMac/Views/Settings/)

| View | Purpose |
| --- | --- |
| [MacSettingsView.swift](apps/macos/TodusMac/Views/Settings/MacSettingsView.swift) | Settings root |
| [MacAISettingsView.swift](apps/macos/TodusMac/Views/Settings/MacAISettingsView.swift) | AI prefs |
| [MacLocalModelsView.swift](apps/macos/TodusMac/Views/Settings/MacLocalModelsView.swift) | Local models |
| [MacCalendarAccountsList.swift](apps/macos/TodusMac/Views/Settings/MacCalendarAccountsList.swift) | Connected calendars |
| [MacDesignSystemView.swift](apps/macos/TodusMac/Views/Settings/MacDesignSystemView.swift) | Design token viewer |

### 4.9 Auth / Onboarding

[App/MacAuthView.swift](apps/macos/TodusMac/App/MacAuthView.swift), [App/MacOnboardingViews.swift](apps/macos/TodusMac/App/MacOnboardingViews.swift), [App/MacAppServices.swift](apps/macos/TodusMac/App/MacAppServices.swift).

### 4.10 macOS-Unique Services

[Services/](apps/macos/TodusMac/Services/)

| Service | File | Purpose |
| --- | --- | --- |
| MacAIChatService | [Services/AI/MacAIChatService.swift](apps/macos/TodusMac/Services/AI/MacAIChatService.swift) | macOS chat orchestrator |
| HuggingFaceCacheConnector | [Services/AI/Local/HuggingFaceCacheConnector.swift](apps/macos/TodusMac/Services/AI/Local/HuggingFaceCacheConnector.swift) | Reuse cached HF models |
| OllamaConnector | [Services/AI/Local/OllamaConnector.swift](apps/macos/TodusMac/Services/AI/Local/OllamaConnector.swift) | Ollama connection probe |
| OllamaInferenceService | [Services/AI/Local/OllamaInferenceService.swift](apps/macos/TodusMac/Services/AI/Local/OllamaInferenceService.swift) | Ollama inference |
| MacDocsService | [Services/Docs/MacDocsService.swift](apps/macos/TodusMac/Services/Docs/MacDocsService.swift) | macOS docs CRUD |
| MacDraftService | [Services/Drafts/MacDraftService.swift](apps/macos/TodusMac/Services/Drafts/MacDraftService.swift) | macOS drafts |
| MacSignatureStore | [Services/Email/MacSignatureStore.swift](apps/macos/TodusMac/Services/Email/MacSignatureStore.swift) | Signatures |
| MacNotificationService | [Services/MacNotificationService.swift](apps/macos/TodusMac/Services/MacNotificationService.swift) | macOS notifications |
| MacSubscriptionService | [Services/Subscription/MacSubscriptionService.swift](apps/macos/TodusMac/Services/Subscription/MacSubscriptionService.swift) | StoreKit + Autumn macOS |
| AudioInputBroker | [Services/Voice/AudioInputBroker.swift](apps/macos/TodusMac/Services/Voice/AudioInputBroker.swift) | Audio input routing |
| HotkeyService | [Services/Voice/HotkeyService.swift](apps/macos/TodusMac/Services/Voice/HotkeyService.swift) | Global hotkey |
| WakeWordService | [Services/Voice/WakeWordService.swift](apps/macos/TodusMac/Services/Voice/WakeWordService.swift) | Wake-word activation |
| MacWidgetUpdateManager | [Services/Widgets/MacWidgetUpdateManager.swift](apps/macos/TodusMac/Services/Widgets/MacWidgetUpdateManager.swift) | macOS widget updates |
| ConnectionsService (App/) | [App/ConnectionsService.swift](apps/macos/TodusMac/App/ConnectionsService.swift) | macOS connection mgmt |

(Cross-platform services like AuthService, EmailService, CalendarService, AIChatService, etc. are shared from the iOS Services layer via SPM / mirrored files.)

### 4.11 macOS-Specific Capabilities

- Multi-window: compose detachable into its own window via SwiftUI WindowGroup.
- Custom scroll style: [DesignSystem/MacScrollStyle.swift](apps/macos/TodusMac/DesignSystem/MacScrollStyle.swift).
- Sidebar unread badges (Tasks, Email).
- Trackpad gestures for calendar nav.
- Global hotkey → voice chat.
- Wake-word detection.
- Audio input broker for shared mic routing.
- Floating voice status window.

---

## 5. Shared Packages (packages/)

| Package | Purpose |
| --- | --- |
| [packages/shared](packages/shared) | TS types + utilities shared between web and server |
| [packages/api-client](packages/api-client) | HTTP client for tRPC API calls |
| [packages/ui-native](packages/ui-native) | Shared React Native UI components |
| [packages/design-tokens](packages/design-tokens) | Theme + design constants |
| [packages/macos-doc-editor](packages/macos-doc-editor) | macOS-specific editor component library |
| [packages/cli](packages/cli) | `nizzy` CLI — workspace sync utilities (`postinstall`) |
| [packages/swift-auth](packages/swift-auth) | SPM: Swift auth utilities + developer-allowlist (`TodusDeveloperAccess.swift`) |
| [packages/swift-widgets](packages/swift-widgets) | SPM: Swift widget extensions |
| [packages/testing](packages/testing) | Vitest test suite |
| [packages/tsconfig](packages/tsconfig) | Shared TypeScript configs |
| [packages/eslint-config](packages/eslint-config) | Shared ESLint config |

---

## 6. Feature Flags & Gating

| Mechanism | Where | Purpose |
| --- | --- | --- |
| `VITE_TODUS_ALLOWLISTED_EMAILS` env | [apps/web/lib/developer-access.ts](apps/web/lib/developer-access.ts) | Web developer mode + design-system viewer |
| `TODUS_ALLOWLISTED_EMAILS` env | [packages/swift-auth/Sources/TodusAuth/TodusDeveloperAccess.swift](packages/swift-auth/Sources/TodusAuth/TodusDeveloperAccess.swift) | iOS + macOS developer mode + DS viewer |
| `earlyAccess` table | [apps/server/src/db/schema.ts](apps/server/src/db/schema.ts) | Per-user feature flags (server-side) |
| `isAllowlisted(email)` helper | Both clients | Returns boolean for gating |

---

## 7. Cross-Platform Parity Matrix

| Feature | 🌐 Web | ⚙️ Backend | 📱 iOS | 💻 macOS |
| --- | :-: | :-: | :-: | :-: |
| Sign in (Google/Apple/OTP) | ✓ | ✓ | ✓ | ✓ |
| Inbox list | ✓ | ✓ | ✓ | ✓ |
| Thread view | ✓ | ✓ | ✓ | ✓ |
| Compose / reply / forward | ✓ | ✓ | ✓ | ✓ |
| Schedule send | ✓ | ✓ | — | — |
| Snooze | ✓ | ✓ | ✓ | ✓ |
| Labels (custom + folders) | ✓ | ✓ | ✓ | ✓ |
| Search | ✓ | ✓ | ✓ | ✓ |
| Drafts | ✓ | ✓ | ✓ | ✓ |
| Signatures | ✓ | ✓ | ✓ | partial |
| AI chat (streaming) | ✓ | ✓ | ✓ | ✓ |
| AI compose | ✓ | ✓ | ✓ | ✓ |
| Generative UI cards | ✓ | ✓ | ✓ | ✓ |
| Shared conversation | ✓ | ✓ | ✓ | ✓ |
| Group chat | ✓ | ✓ | ✓ | ✓ |
| Voice AI (Gemini Live) | — | ✓ | ✓ | ✓ |
| Local LLM | — | N/A | ✓ (MLX) | ✓ (Ollama) |
| Calendar | ✓ | ✓ | ✓ | ✓ |
| Tasks | ✓ | ✓ | ✓ | ✓ |
| Kanban board | — | N/A | ✓ | ✓ |
| Apple Reminders sync | N/A | N/A | ✓ | ✓ |
| Docs / Tiptap | ✓ | ✓ | ✓ | ✓ |
| Meetings + Recall.ai | ✓ | ✓ | ✓ | ✓ |
| Billing (Autumn) | ✓ | ✓ | ✓ | ✓ |
| Notifications center | — | N/A | ✓ | ✓ |
| Push notifications | — | ✓ | ✓ | ✓ |
| Widgets / live activity | N/A | N/A | ✓ | ✓ |
| Global hotkey | N/A | N/A | — | ✓ |
| Wake word | N/A | N/A | — | ✓ |
| Multi-window | N/A | N/A | — | ✓ |
| Trackpad gesture nav | N/A | N/A | — | ✓ |
| Design system viewer | ✓ (gated) | N/A | ✓ (gated) | ✓ (gated) |
| Developer mode | ✓ (gated) | N/A | ✓ (gated) | ✓ (gated) |

Legend: ✓ available · partial = present but limited · — = not implemented · N/A = doesn't apply to surface.
