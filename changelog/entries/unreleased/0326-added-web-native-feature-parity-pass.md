---
id: 0326
title: "Web reaches native parity on chat, task organize, folder contents, briefing actions and cancellation"
status: unreleased
category: Added
tags: [web, tasks, mail, ai, billing]
---

An audit of every tRPC procedure the iOS and macOS clients call, diffed against what
`apps/web` actually uses, surfaced a set of backend capabilities that existed and were
shipped natively but had no web surface at all. This closes them.

**Full-page AI chat was unreachable.** `apps/web/app/(routes)/mail/chat/page.tsx` had been
written for iOS `AIChatView` / macOS `MacAssistantPanel` parity, and `mail/layout.tsx`
already special-cased it to avoid opening a second agent WebSocket — but the route was
never registered in `routes.ts`, so `/mail/chat` fell through to the `/:folder` catch-all
and rendered as a mail folder named "chat". The route is now registered above `/:folder`,
with a sidebar entry and a ⌘6 shortcut alongside the existing ⌘1–5 section nav.

**AI task organize.** `tasks.organize` had no caller on web. The tasks page now has an
Organize action that mirrors iOS `TaskOrganizeService`: a deterministic folder-name rule
pass first (whole-word for single-word folders, substring for multi-word), then the AI
endpoint for whatever the rules didn't claim. Proposals land in a review dialog where each
row can be unchecked; nothing moves until Apply, and proposed new folders are get-or-create
by lowercased name so two proposals sharing a name collapse into one folder.

**Folders hold more than tasks.** `folders.addItem` / `removeItem` / `listContents` /
`summary` back the iOS `FolderDetailView` and `AddToFolderSheet`, where a folder can also
hold saved emails, events, docs and chats. Web only knew about `task.folderId`. Threads now
have a "Save to folder" context submenu (caching subject + sender as metadata, since Gmail
lives outside our DB and `listContents` renders from that cache), the tasks page shows the
folder's non-task members with per-item removal, and folder pills carry the same item count
the native folder cards show.

**Briefing trust loop.** `assistant.dismissOpenLoop`, `snoozeOpenLoop`,
`dismissPreparedAction` and `recordFeedback` were native-only. Home briefing rows now have a
per-row menu — mark done, snooze (later today / tomorrow morning / next week), and an honest
"Not a reply" / "Not a draft I want" dismissal — with the same feedback semantics iOS uses
(`completed` on done, `wrong` on dismiss, `helpful` when a prepared action is snoozed, since
prepared actions have no server-side snooze). Rows hide optimistically and reconcile on the
next briefing fetch.

**In-app cancellation.** Billing offered only "Cancel in portal", which bounced the user to
Autumn's hosted page. iOS cancels in-app via `subscription.cancel` with a confirmation
alert; web now does the same, using the `productId` `getStatus` already returns so
`pro_monthly` and `pro_annual` cancel correctly. The portal link stays for payment-method
and invoice changes.

Two things that looked like gaps were not: web bulk-archives through a single
`mail.modifyLabels` call with an id array (fewer round trips than the native per-thread
`mail.bulkArchive` loop), and the assistant automation policy is already fully exposed under
Settings → AI, a superset of the iOS `EmailAutomationPolicyView`.
