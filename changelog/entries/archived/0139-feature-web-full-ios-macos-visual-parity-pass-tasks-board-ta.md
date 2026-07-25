---
id: 0139
title: "Feature — web: Full iOS/macOS visual parity pass (Tasks board/table, Home redesign, Chat history, Calendar quick-add)"
status: archived
category: Added
release_date: 2026-03-31
source: CHANGELOG.md
---

## [2026-03-31] Feature — web: Full iOS/macOS visual parity pass (Tasks board/table, Home redesign, Chat history, Calendar quick-add)

### Tasks page (`/mail/tasks`) — full rewrite

- **View mode picker**: segmented control (List / Board / Table) at top right
- **Horizontal folder pill strip**: scrollable row of pills replaces old sidebar layout — "All" + each folder + "+" add folder button
- **Board view** (kanban): 3 draggable columns (To Do / Doing / Done) using `@dnd-kit/core`. Drag cards between columns to update `status` via `tasks.update`. `DragOverlay` renders the card while dragging.
- **Table view**: compact single-line `<table>` rows (checkbox, title, priority, status, due, folder, menu) — dense Linear-style view
- **Quick-add row**: inline text input at top of list view — Enter creates task with current folder pre-selected
- **Task detail Sheet**: clicking a task title opens a `<Sheet side="right">` with full metadata (title, description, priority, status, due date, folder), edit + delete buttons
- **TypeScript fix**: `isDueDateWarning` now accepts `string | Date | null | undefined` since tRPC can return `Date` objects

### Home page (`/mail/home`) — redesign

- **Section headers**: iOS-style `SectionHeader` component — icon + title + count badge + "See all" link + optional "+" button
- **Today's Events section**: "Connect Google Calendar" CTA card (dashed border, links to Settings → Connections). No fake data shown since backend Calendar API isn't wired yet.
- **Sections**: Events → Due Tasks → Recent Emails (matches iOS order)
- **Card containers**: each section wrapped in `rounded-xl border bg-card px-4 py-4`
- **Greeting**: larger `text-[22px]` heading with date subtitle

### Chat page (`/mail/chat`) — conversation history + markdown

- **Left sidebar** (hidden on mobile): `w-56` conversation list from `ai.listConversations`. Each row shows title + relative date. Active row highlighted with `bg-accent`.
- **Load conversation**: clicking a past chat loads its messages via `ai.getConversation` and restores to `setMessages()`
- **Auto-save**: on first assistant response (not mid-stream), saves conversation with title = first 60 chars of user's first message via `ai.saveConversation`
- **Delete**: hover → MoreHorizontal → dropdown → Delete triggers `ai.deleteConversation`, refreshes sidebar
- **Markdown**: AI responses rendered with `react-markdown` + `remark-gfm` inside `prose prose-sm dark:prose-invert` container (wrapped in div — react-markdown v10 doesn't accept className directly)
- **AI bubble style**: `border bg-card` instead of plain `bg-muted` for visual separation

### Calendar page (`/mail/calendar`) — polish + features

- **Inline quick-add row**: always-visible input at top of day panel — Enter creates task with `dueDate = selectedDate`
- **Connect Google Calendar CTA**: dashed-border card in left sidebar below week overview, links to Settings → Connections
- **Week overview**: dates with tasks show count badge
- **Empty state**: shows link to Tasks page
- **Header**: slimmer `py-3.5` consistent with other page headers

**Files:**

- `apps/web/app/(routes)/mail/tasks/page.tsx` — full rewrite
- `apps/web/app/(routes)/mail/home/page.tsx` — full rewrite
- `apps/web/app/(routes)/mail/chat/page.tsx` — full rewrite
- `apps/web/app/(routes)/mail/calendar/page.tsx` — full rewrite
- `apps/web/config/navigation.ts` — Email expandable parent + icon updates
- `apps/web/components/ui/nav-main.tsx` — NavItemExpandable, NavChildRow, removed feedback link
- `apps/web/components/ui/app-sidebar.tsx` — removed dead badge mutations
- `apps/web/components/ai-toggle-button.tsx` — circular FAB polish
