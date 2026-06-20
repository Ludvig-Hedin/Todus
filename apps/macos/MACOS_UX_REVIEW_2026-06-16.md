# macOS Todus — UX Review (assess-ux + ux-polish)

_Generated 2026-06-16. Read-only audits. Bug fixes tracked separately via bug-hunt → CODE_REVIEW_BACKLOG.md._

## Scope

- **UX flow assessment**: 164 findings across 16 main flows (new/active/power lenses).
- **UX polish**: 88 findings (19 high / 45 med / 24 low).

## Flow reachability (can a user complete it?)

- **Sign-in (email OTP or social) → 6-step onboarding (Gmail, Calendar, Re** — Yes. All gates are navigable via primary/secondary buttons. No dead-ends detected. Users can skip every step and reach the main app. Social sign-in and email OT
- **Home / Dashboard Landing** — Mostly reachable with friction: NEW user can tap 'Get started' cards and navigate. ACTIVE user can dismiss setup banner (doesn't persist). POWER user can click 
- **User opens Todus → sees task list → creates a task (Add Task button) →** — Yes. All major steps are reachable from the main Tasks view. Task creation is triggered via onCreateItem callback (caller not shown but presumed from parent con
- **User opens inbox → views thread list → clicks thread to open detail pa** — Yes. The inbox loads immediately, threads are clickable, all actions are discoverable via context menu or keyboard shortcuts. The flow is complete and navigable
- **Email thread reading & per-message actions** — Yes. NEW users can open a thread and see messages. ACTIVE users can reply and manage threads. POWER users have keyboard shortcuts (Cmd+R for reply, Cmd+Shift+R 
- **Email compose / reply / drafts / signatures** — Yes. All paths (new, reply, reply-all, forward, autosave restore) are reachable and functional. No hard blockers prevent sending or replying.
- **Calendar View (Day/Week/Month/Year) → View Events → Click Event → (Edi** — Yes, users can complete the core flow, but with friction points and missing states that impact discoverability and clarity.
- **Meetings (list, detail, notes/recordings)** — Yes, users can view meetings list, select one to view details with video, transcript, and AI summary. However, several friction points and missing capabilities 
- **Docs list (sidebar + grid/list) → New document (create) → Editor pane ** — Mostly yes; user can reach the full flow and create, edit, save. But four blockers risk silent data loss and broken editor on load.
- **User opens AI Assistant panel (floating/sidepane/window/full modes) → ** — Yes. All flows are reachable and work end-to-end. Core path (compose → send → see response) is solid. Secondary flows (history, share, groups) are complete and 
- **User initiates voice session via push-to-talk hotkey (⌘⇧Space), wake w** — Partially. NEW users can reach core flow (mic button → panel → listen → chat). Push-to-talk requires discovery of ⌘⇧Space (not visibly advertised at first launc
- **NEW user** — Partially. NEW and ACTIVE users can reach wins (recommended actions work, basic search + selection works). POWER user hits friction: no-results state doesn't pe
- **User presses ⌘N → Create sheet appears as side panel (right side of sp** — Yes. The flow is reachable and functional for all three user archetypes. ⌘N is globally bound (MacRootView:892), keyboard shortcuts work (Esc to close, ⌘⏎ to cr
- **Daily Brief / Notifications Center** — Yes — the flow is reachable from the header button and completes end-to-end without dead-ends. However there are friction points that degrade UX at each user ti
- **Settings → AI Assistant (sheet) → Local Models (nested sheet) → back →** — Yes, all flows are reachable and completable, though several UX friction points exist that compound for power users.
- **Sidebar navigation (left panel showing Home, Tasks, Email, etc.) → key** — Yes. The core flow is solid: users can navigate via sidebar clicks, keyboard shortcuts work, window chrome persists state and layout. The app is functional for 

## 🔴 Blockers (stop or badly break a flow)

| User | Issue | Where | Fix |
|---|---|---|---|
| all | No confirmation/warning before archive or delete | `MacEmailInboxView.swift:626-648 (archive/delete context` | Add a confirmation dialog before archive/delete: 'Move [subject] to Archive?' with Cancel/ |
| all | Archive/delete closes detail pane BEFORE operation completes, hiding f | `MacEmailInboxView.swift:630-633, 640-642 (closes select` | Only close the pane after the operation completes successfully. Either: (a) await the oper |
| all | No confirmation dialog before permanent delete | `MacEmailInboxView.swift:639-647 (destructive delete wit` | Add a confirmation dialog: 'Delete [subject]? This cannot be undone.' with 'Cancel' and 'D |
| new | Create document error dialog has no Retry button — user can't recover | `MacDocsShellView.swift:73-83 (newDocumentTapped), 38-45` | Add a Retry button to the create error alert. On retry, call newDocumentTapped() again. Al |
| new | Tiptap editor fails to load with vague error and no recovery path | `TiptapDocEditorWebView.swift:28-41 (missing file check ` | If the editor fails to load, show a more user-friendly message like: The editor is not ava |
| active | Autosave can fail silently when closing editor — data loss risk | `MacDocEditorPane.swift:67-73 (flushPendingSave on disap` | Before allowing the view to dismiss, show a loading state and wait for the final save to c |
| new | BLOCKER: Hotkey ⌘⇧Space not discoverable on first launch | `HotkeyService.swift:54 (hardcoded), VoiceStatusWindow.s` | Add a tooltip or help text in the VoiceStatusWindow showing 'Press ⌘⇧Space to push-to-talk |

## 🟠 High-severity UX issues (assessment)

| User | Issue | Where | Fix |
|---|---|---|---|
| new | No Confirmation or Error Recovery on Social Sign-In Failure | `MacAuthView.swift:254–303 (social buttons call authServ` | Distinguish between cancellation, network errors, and auth failures in the error message.  |
| active | Sync state (pending/failed) is invisible to the user in task rows | `MacTaskRow lines 1253-1331 renders the row but has no s` | Add a small status icon/badge to the right of each task row showing: (a) nothing when .syn |
| active | Network failures in mutations silently rollback, with no persistent er | `EmailService.swift:1376-1399 (markAsRead with rollback ` | Implement a persistent error banner or 'undo pending actions' queue in the inbox header. A |
| new | Archive and Delete buttons have identical visual hierarchy; Delete is  | `MacEmailThreadView.swift:380-400 - both buttons in a fl` | Add visual separation between the Archive and Delete buttons (e.g., a divider, spacing, or |
| power | Attachment double-send race condition unpatched in legacy path | `MacEmailComposeView.swift:13-17 documents the gap, line` | Unify isSending state: make EmailService.sendEmail also set/clear a shared isSending flag  |
| active | Error states from calendar service calls are not surfaced to the user | `MacCalendarView.swift:1428-1470 (loadEvents has no erro` | Wrap `loadEvents()` in a do-catch block. On error, set an `@State var loadError: String?`  |
| all | Delete meeting API exists but no UI affordance exposed | `/Users/ludvighedin/Programming/personal/mail/apps/macos` | Add a context-menu or three-dot menu on meeting rows in the list view (or in the detail he |
| active | Save state badge disappears when user switches documents — loss of err | `MacDocEditorPane.swift:27 (saveState is @State, recreat` | Move saveState to the service layer so it persists per-document. When opening a doc, check |
| power | Title and content autosave use separate debounce timers — inconsistent | `MacDocEditorPane.swift:163-168 (title debounce), 440-47` | Unify title and content saves into a single debounced update. Collect both title and conte |
| all | Delete Conversation lacks confirmation/undo — destructive operation wi | `MacAssistantPanel.swift:860-864 (menu button), :1433-14` | Add a destructive confirmation dialog ('Are you sure? This cannot be undone') before execu |
| new | Failed connection error message is terse and lacks recovery guidance | `VoiceSessionCoordinator.swift:291 (error.localizedDescr` | Enhance error messages to distinguish between categories: 'Network unreachable', 'Backend  |
| power | Transcript is not persisted if app crashes before disconnect | `VoiceSessionCoordinator.swift:516-567 (persistTranscrip` | Save finalized turns eagerly to the database as they complete (not just on disconnect). Us |
| all | Silent failure when pressing Return with no results | `MacSearchView.swift:215-217 (onSubmit), 287-293 (activa` | When Return is pressed with no matches and a non-empty query, automatically activate the ' |
| power | Compound intent parsing only fires in auto mode; manual type selection | `MacCreateSheet.swift:308-331 (compound check gated by `` | Run compound intent parsing regardless of manual type selection. If multiple intents are d |
| all | Modal save is not protected from network/persistence failure | `MacCreateSheet.swift:364-372` | Separate the insert and save into a transaction that reports errors. Show a toast on failu |
| active | Silent AI digest failure when backend model ID is stale | `MacNotificationCenterView.swift:97, 228-229` | Detect 400/422 (model/validation errors) separately from 5xx. When the digest fails with a |
| power | Model download state/error feedback is silent if bridge fails | `MacLocalModelsView.swift:258-285 (detached bridge task ` | Capture the result of bridgeIntoAppCacheIfPossible and surface errors: (a) Add @State erro |
| power | Settings close via Escape doesn't save AI profile changes | `MacAISettingsView.swift:32-36 (saves before closing)` | In MacAISettingsView, ALWAYS call saveSharedAIProfile() before dismiss(), even on Escape ( |

## ⚡ High-impact polish wins (small, self-contained)

| Category | Where | What's missing | Quick fix | Effort |
|---|---|---|---|---|
| disabled-async | `MacHomeView.swift:532-541` | Hover-revealed briefing row action buttons (checkmark, clock, xmark) invoke | Add @State flag `private var isProcessingBriefingAction = false` and w | ~15 lines |
| accessibility | `MacFolderEditSheet.swift:53-66` | Color picker buttons are icon-only circles with no .help() tooltip or .acce | Add .help("Select \(color) color") and .accessibilityLabel("Select \(c | ~5 lines |
| accessibility | `MacFolderEditSheet.swift:101-114` | Icon picker buttons are icon-only with no .help() tooltip or .accessibility | Add .help(symbol) and .accessibilityLabel(symbol) after .buttonStyle(. | ~5 lines |
| success-feedback | `MacFolderDetailView.swift:50-54` | Delete folder button inside confirmationDialog triggers deleteSharedFolder  | Add a @State private var deleteToast: MacToastMessage? and macToast($d | ~15 lines |
| destructive-confirm | `MacEmailInboxView.swift:639-643` | Destructive 'Move to Bin' action fires immediately on context-menu tap with | Wrap the delete closure in a `confirmationDialog` with a 'Delete', 'Ca | ~15 lines |
| hover-focus | `MacEmailThreadView.swift:337-346` | Back button in header has .help() tooltip but no visual hover affordance or | Add .macClickablePointer() after .buttonStyle(.plain) on line 344, or  | ~5 lines |
| success-feedback | `MacEmailThreadView.swift:381-382` | Archive action completes silently with no toast feedback; user gets no visu | After archiveThreads() call on line 381, add assistantToast = .success | ~5 lines |
| disabled-async | `MacEmailThreadView.swift:434-442` | Move-to-label menu items fire Task immediately when clicked with no loading | Add @State flag isMovingToLabel, set true before Task, disable buttons | ~15 lines |
| success-feedback | `MacEmailComposeView.swift:514-519` | Send succeeds silently — no toast confirmation shown to the user. After an  | Add @State private var sendSuccessToast: MacToastMessage? near line 12 | ~5 lines |
| accessibility | `MacMeetingDetailView.swift:425` | Q&A input field has placeholder text 'What were the key decisions?' but no  | Add .accessibilityLabel("Ask a question about this meeting") to the Te | ~5 lines |
| success-feedback | `MacMeetingDetailView.swift:489-496` | scheduleBot() mutation (auto-record button) succeeds silently—no toast, no  | After successful scheduleBot at line 494, call `services.showToast("Au | ~5 lines |
| disabled-async | `MacDocsShellView.swift:195` | Rename dialog (lines 190-201, 690-701) lacks disabled state on Save button  | Add `@State private var isSavingRename = false` at line 449, set it in | ~5 lines |
| destructive-confirm | `MacAssistantPanel.swift:598-623` | Move Conversation confirmationDialog has no safety measure for destructive  | Add a 2-step confirm flow: when user selects a folder/unfiled, show a  | ~15 lines |
| disabled-async | `MacShareConversationPanel.swift:156-169` | Create Link button can be tapped while isLoading=true (network request in f | Add .disabled(isLoading) to the Button(action: createLink()) to preven | 1 line |
| destructive-confirm | `MacSearchView.swift:469-475` | "Clear" button in recent searches section clears all history without a conf | Wrap the button action in a .confirmationDialog with a cancel and dest | ~15 lines |
| success-feedback | `MacCreateSheet.swift:364-372` | Task creation succeeds silently with no visual feedback (no toast). Event c | After modelContext.save() on line 372, add: toast = .success("Task cre | ~5 lines |
| error-state | `MacSettingsView.swift:1851` | performDisconnectGmail() catches errors but only logs them — no settingsErr | Add `settingsError = (error as? LocalizedError)?.errorDescription ?? " | 1 line |
| accessibility | `MacSidebarView.swift:501-516` | Icon-only '+' button (add task) has no .help() and no .accessibilityLabel() | Add `.help("Add task")` and `.accessibilityLabel("Add task")` after `. | 1 line |
| accessibility | `MacSidebarView.swift:771-796` | Connection avatar button in footer has .help(connection.email) but no .acce | Add `.accessibilityLabel("Toggle \(connection.email)")` after `.help(c | 1 line |

## Cross-cutting patterns

- **tooltip**: 25 occurrences — recurring gap across surfaces.
- **accessibility**: 16 occurrences — recurring gap across surfaces.
- **success-feedback**: 11 occurrences — recurring gap across surfaces.
- **hover-focus**: 11 occurrences — recurring gap across surfaces.
- **disabled-async**: 7 occurrences — recurring gap across surfaces.
- **error-state**: 5 occurrences — recurring gap across surfaces.
- **destructive-confirm**: 4 occurrences — recurring gap across surfaces.
- **micro-interaction**: 4 occurrences — recurring gap across surfaces.
- **copy**: 4 occurrences — recurring gap across surfaces.

## Severity distribution (assessment)

medium: 64, high: 18, low: 75, blocker: 7
