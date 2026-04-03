# AI Chat Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix four AI chat issues across iOS, macOS, and web: iOS input-field hang, "not connected" service messaging with connect CTAs, prompt suggestion filtering by service availability, and proper markdown rendering on web.

**Architecture:** All fixes are self-contained UI/service changes. iOS/macOS share the same patterns (service state checks via `CalendarService.canReadEvents()` / `EmailService.threads`). Web uses `useConnections` hook and improves `markdownStyles`. System prompts updated to say "not connected" so AI language matches what the UI communicates.

**Tech Stack:** Swift 6 / SwiftUI (iOS + macOS), React + TypeScript + Tailwind (web), EventKit (iOS/macOS calendar access)

---

## File Map

| File | Change |
|------|--------|
| `apps/ios/Todus/Todus/Services/AI/AIChatService.swift` | Fix "disabled" → "not connected" wording in system prompt |
| `apps/ios/Todus/Todus/Features/AI/AIChatView.swift` | Fix input hang, filter suggestions, show connect CTA in messages |
| `apps/macos/TodusMac/Services/AI/MacAIChatService.swift` | Fix "not connected" wording in system prompt |
| `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift` | Filter suggestions, show connect CTA in messages |
| `apps/mail/components/create/ai-chat.tsx` | Fix markdown styles, filter suggestions, show connect button |

---

## Task 1: iOS — Fix Input Field Hang

**Root cause:** `mentionOptions` computed property iterates ALL email threads via `services.emailService.threads.map(\.from)` to build the people-mention dictionary. Runs on every view re-render (triggered by `isInputFocused` state change when user taps the input). If the inbox has hundreds of threads, this O(n) dictionary construction freezes the main thread for ~1–5 seconds.

**Files:**
- Modify: `apps/ios/Todus/Todus/Features/AI/AIChatView.swift:838-852`

- [ ] **Step 1: Open the file and confirm the offending code**

Read lines 815–853 of `AIChatView.swift`. Verify `mentionOptions` uses `services.emailService.threads.map(\.from)` without a prior `prefix`.

- [ ] **Step 2: Cap thread iteration before dictionary grouping**

In `AIChatView.swift`, in `private var mentionOptions`, change:
```swift
let peopleMentions = Dictionary(grouping: services.emailService.threads.map(\.from), by: \.email)
    .compactMap { _, senders in senders.first }
    .prefix(12)
    .map { sender in
```
to:
```swift
// Cap at 50 threads before dictionary grouping to avoid O(n) hang on tap
let peopleMentions = Dictionary(grouping: services.emailService.threads.prefix(50).map(\.from), by: \.email)
    .compactMap { _, senders in senders.first }
    .prefix(12)
    .map { sender in
```

- [ ] **Step 3: Verify build compiles**

```bash
cd apps/ios/Todus && xcodebuild -scheme Todus -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add apps/ios/Todus/Todus/Features/AI/AIChatView.swift
git commit -m "fix(ios): cap thread iteration in mentionOptions to prevent input-tap hang"
```

---

## Task 2: iOS — Update System Prompt "Not Connected" Wording

When a service isn't available, the AI currently says "access is disabled by the user" or "access not granted". Update these strings so the AI tells the user to connect the service, which matches the connect CTA we'll show in Task 3.

**Files:**
- Modify: `apps/ios/Todus/Todus/Services/AI/AIChatService.swift:793-820`

- [ ] **Step 1: Read the current system prompt context strings**

Read lines 791–820 of `AIChatService.swift`. Note the three strings to update:
1. `"## Calendar\nCalendar access is disabled by the user."`
2. `"## Calendar\nCalendar access not granted or not yet loaded."`
3. `"## Email\nEmail access is disabled by the user."`

- [ ] **Step 2: Replace all three strings**

Change the `calendarContext` block:
```swift
if !aiCanReadCalendar {
    calendarContext = "## Calendar\nCalendar access is disabled by the user."
} else if let snap = calendarSnapshot {
    calendarContext = snap
} else {
    calendarContext = "## Calendar\nCalendar access not granted or not yet loaded."
}
```
to:
```swift
if !aiCanReadCalendar {
    // Calendar permission not granted — tell AI to direct user to connect
    calendarContext = "## Calendar\nCalendar is not connected. Tell the user their calendar is not connected and they need to grant Calendar permission in iOS Settings."
} else if let snap = calendarSnapshot {
    calendarContext = snap
} else {
    // Permission may not be granted yet
    calendarContext = "## Calendar\nCalendar is not connected. Tell the user their calendar is not connected and they need to grant Calendar permission in iOS Settings."
}
```

Change the `emailContext` guard:
```swift
if !aiCanReadEmail {
    emailContext = "## Email\nEmail access is disabled by the user."
```
to:
```swift
if !aiCanReadEmail {
    // Email not connected — tell AI to direct user to connect
    emailContext = "## Email\nEmail is not connected. Tell the user their email inbox is not connected and they need to enable email access in settings."
```

- [ ] **Step 3: Verify build**

```bash
cd apps/ios/Todus && xcodebuild -scheme Todus -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add apps/ios/Todus/Todus/Services/AI/AIChatService.swift
git commit -m "fix(ios): update AI system prompt to say 'not connected' instead of 'access disabled'"
```

---

## Task 3: iOS — Filter Suggestions + Show Connect CTA

Two changes to `AIChatView.swift`:

**A)** `contextualSuggestionsPool` — skip calendar-specific suggestions when calendar isn't connected. Skip email-specific suggestions when email isn't connected. When NO services are connected, return only generic task suggestions + a `connectCalendar` / `connectEmail` sentinel the empty-state can act on.

**B)** `MessageBubble` — after a non-streaming assistant message, if a service isn't connected AND the message text mentions that service's name, show a small "Connect Calendar / Email" button below the message.

**Files:**
- Modify: `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`

- [ ] **Step 1: Add service-connection helper properties to `AIChatView`**

After the existing `private var chatService:` line (around line 71), add:
```swift
/// Whether calendar permission has been granted to this app.
private var calendarConnected: Bool {
    services.calendarService.canReadEvents()
}
/// Whether an email inbox is loaded (proxy for email being connected).
private var emailConnected: Bool {
    chatService.aiCanReadEmail && !services.emailService.threads.isEmpty
}
```

- [ ] **Step 2: Filter `contextualSuggestionsPool` by service availability**

Inside `contextualSuggestionsPool`, for each `case`, wrap calendar suggestions with a `calendarConnected` guard and email suggestions with an `emailConnected` guard. If neither service is connected and it's the `.home` tab, replace suggestions with generic task-only ones.

For the `.calendar` case, replace the entire `pinned`/`extended` with:
```swift
case .calendar:
    guard calendarConnected else {
        // Calendar not connected — return empty so the connect UI shows instead
        return []
    }
    pinned = [
        ("clock",                      "What's on my calendar today?"),
        ("calendar.badge.plus",        "Find free focus time this week"),
        ("person.2",                   "Help me schedule a meeting"),
    ]
    extended = [
        ("brain.head.profile",         "Create deep work blocks on my calendar tomorrow"),
        ("calendar",                   "Give me a full overview of this week"),
        ("moon.stars",                 "Block time tomorrow morning for planning"),
        ("calendar.badge.exclamationmark", "Do I have any scheduling conflicts?"),
        ("clock.badge.checkmark",      "When is my next free 2-hour window?"),
        ("person.badge.plus",          "Help me prepare for my next meeting"),
        ("sun.max",                    "Plan my ideal workday schedule"),
    ]
```

For the `.email` case, wrap the body:
```swift
case .email:
    guard emailConnected else {
        return []
    }
    pinned = [
        ("envelope.open",              "Summarize my recent emails"),
        // ... rest unchanged
    ]
    // ... extended unchanged
```

For the `.home` case (home tab shows mixed content), filter out email/calendar suggestions when those services aren't connected:
```swift
case .home:
    pinned = [
        ("sun.max",                    "Give me a morning briefing"),
        ("sparkle",                    "What should I focus on right now?"),
        // Only include calendar triage if calendar is connected
    ] + (calendarConnected ? [("calendar.badge.checkmark", "Triage my tasks and calendar for today")] : [])
    var extBase: [(icon: String, text: String)] = [
        ("moon.stars",                 "End-of-day review — what did I accomplish?"),
        ("chart.line.uptrend.xyaxis",  "Weekly retrospective — what went well?"),
        ("flag",                       "What are my top priorities this week?"),
        ("rocket",                     "Help me kick off a new project"),
        ("brain.head.profile",         "Block focus time and clear my schedule"),
        ("person.2",                   "Help me coordinate with my team today"),
    ]
    if emailConnected {
        extBase.append(("envelope.open", "Any important emails I should handle first?"))
    }
    extended = extBase
```

- [ ] **Step 3: Show "Connect" buttons in empty state when pool is empty**

In `emptyStateView`, after the suggestions `VStack`, add a connect-services block that shows when the current tab has no suggestions:

```swift
// When the current tab's suggestion pool is empty (service not connected),
// show compact connect buttons instead.
let pool = contextualSuggestionsPool
// ...existing shown/pool code...

// Connect prompt — shown when pool is empty (service not connected for this tab)
if pool.isEmpty {
    connectServicesPrompt
        .padding(.horizontal, 12)
        .padding(.top, 8)
}
```

Add `private var connectServicesPrompt: some View` to the view:
```swift
/// Compact row of "Connect [service]" buttons shown when the active tab's
/// service is not connected (calendar / email pool returned empty).
private var connectServicesPrompt: some View {
    VStack(alignment: .leading, spacing: 8) {
        Text("Connect a service to get started")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(AppTheme.mutedText)

        HStack(spacing: 8) {
            if !calendarConnected {
                Button {
                    Task { await services.calendarService.requestAccess() }
                } label: {
                    Label("Connect Calendar", systemImage: "calendar")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1), in: Capsule())
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
            if !emailConnected {
                Button {
                    // Navigate to email settings tab
                    services.navigateTo = .email
                    dismiss()
                } label: {
                    Label("Connect Email", systemImage: "envelope")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.1), in: Capsule())
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

- [ ] **Step 4: Show connect button below AI messages that mention a disconnected service**

`MessageBubble` needs to know service connection state. Add two new params and an `onConnect` callback:

Change `MessageBubble` struct definition:
```swift
private struct MessageBubble: View {
    let message: AIChatMessage
    let allTasks: [TaskRecord]
    let canRetry: Bool
    var calendarConnected: Bool = true
    var emailConnected: Bool = true
    var onRetry: () -> Void = {}
    var onNavigate: ((String, [String: String]) -> Void)?
    var onConnect: ((String) -> Void)?   // "calendar" or "email"
    // ... rest unchanged
```

In `assistantBubble`, after the main content block, add:
```swift
// Connect CTA — shown when a disconnected service is mentioned in the response
let lc = message.content.lowercased()
if !message.isStreaming && !message.content.isEmpty {
    if !calendarConnected && (lc.contains("calendar") || lc.contains("not connected")) {
        connectBanner(service: "calendar", icon: "calendar", color: .blue)
    }
    if !emailConnected && (lc.contains("email") || lc.contains("inbox") || lc.contains("not connected")) {
        connectBanner(service: "email", icon: "envelope", color: .orange)
    }
}
```

Add `connectBanner` helper:
```swift
private func connectBanner(service: String, icon: String, color: Color) -> some View {
    Button {
        onConnect?(service)
    } label: {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
            Text("Connect \(service.capitalized)")
                .font(.system(size: 13, weight: .medium))
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .foregroundStyle(color)
    }
    .buttonStyle(.plain)
    .padding(.top, 4)
}
```

Update all `MessageBubble(...)` call sites in `conversationView` to pass service state:
```swift
MessageBubble(
    message: message,
    allTasks: Array(allTasks),
    canRetry: chatService.canRetry(assistantMessageID: message.id),
    calendarConnected: calendarConnected,
    emailConnected: emailConnected,
    onRetry: { ... },
    onNavigate: { action, params in ... },
    onConnect: { service in
        if service == "calendar" {
            Task { await services.calendarService.requestAccess() }
        } else if service == "email" {
            services.navigateTo = .email
            dismiss()
        }
    }
)
```

- [ ] **Step 5: Build**

```bash
cd apps/ios/Todus && xcodebuild -scheme Todus -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -30
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add apps/ios/Todus/Todus/Features/AI/AIChatView.swift
git commit -m "feat(ios): filter AI suggestions by service connection; add connect CTA to messages"
```

---

## Task 4: macOS — Update System Prompt + Filter Suggestions + Connect CTA

**Files:**
- Modify: `apps/macos/TodusMac/Services/AI/MacAIChatService.swift:521-536`
- Modify: `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift`

- [ ] **Step 1: Update macOS system prompt "not connected" strings**

Read lines 519–540 of `MacAIChatService.swift`. Find:
```swift
let calendarContext: String
if let snap = calendarSnapshot {
    calendarContext = snap
} else {
    calendarContext = "## Calendar\nCalendar access not yet loaded."
}

let emailContext: String
// ...
emailContext = "## Email\nNo email threads loaded or email not connected."
```

Change the `else` branch for calendarContext:
```swift
} else {
    calendarContext = "## Calendar\nCalendar is not connected. Tell the user their calendar is not connected and they need to grant Calendar permission in macOS System Settings."
}
```

Change the email fallback:
```swift
emailContext = "## Email\nEmail is not connected. Tell the user their email inbox is not connected and they need to add an email account in settings."
```

- [ ] **Step 2: Add service-connection helpers to `MacAssistantPanel`**

After `private var chatService: MacAIChatService { services.aiChatService }` (around line 250), add:
```swift
private var calendarConnected: Bool {
    services.calendarService.canReadEvents()
}
private var emailConnected: Bool {
    !services.emailService.threads.isEmpty
}
```

- [ ] **Step 3: Filter `contextualSuggestionsPool` in MacAssistantPanel**

In `contextualSuggestionsPool` (line ~1182), for the `"calendar"` case, add a guard:
```swift
case "calendar":
    guard calendarConnected else { return [] }
    pinned = [
        ("clock",                "What's on my calendar today?"),
        // ... rest unchanged
    ]
    // extended unchanged
```

For the `"email"` case:
```swift
case "email":
    guard emailConnected else { return [] }
    pinned = [
        ("envelope.open",           "Summarize my recent emails"),
        // ... rest unchanged
    ]
    // extended unchanged
```

For the `default` (home) case, filter optionally:
```swift
default: // home
    var basePinned: [(icon: String, text: String)] = [
        ("sun.max",                  "Give me a morning briefing"),
        ("sparkle",                  "What should I focus on right now?"),
    ]
    if calendarConnected {
        basePinned.append(("calendar.badge.checkmark", "Triage my tasks and calendar for today"))
    }
    pinned = basePinned
    var extBase: [(icon: String, text: String)] = [
        ("moon.stars",                    "End-of-day review — what did I accomplish?"),
        ("chart.line.uptrend.xyaxis",     "Weekly retrospective — what went well?"),
        ("flag",                          "What are my top priorities this week?"),
        ("rocket",                        "Help me kick off a new project"),
        ("brain.head.profile",            "Block focus time and clear my schedule"),
    ]
    if emailConnected {
        extBase.append(("envelope.open", "Any important emails I should handle first?"))
    }
    extended = extBase
```

- [ ] **Step 4: Show connect CTA in empty state when pool is empty**

Find the empty state view in `MacAssistantPanel` (the block that shows suggestions). After the suggestion rendering, add:
```swift
// Show connect prompts when the active section's pool is empty (service not connected)
if contextualSuggestionsPool.isEmpty {
    HStack(spacing: 8) {
        if !calendarConnected {
            Button {
                Task { await services.calendarService.requestAccess() }
            } label: {
                Label("Connect Calendar", systemImage: "calendar")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.1), in: Capsule())
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        if !emailConnected {
            Button {
                // Navigate to email connections in macOS settings
            } label: {
                Label("Connect Email", systemImage: "envelope")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.1), in: Capsule())
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
        }
    }
    .padding(.horizontal, 12)
    .padding(.top, 6)
}
```

- [ ] **Step 5: Show connect button below macOS assistant messages**

In `MacAssistantPanel`, find the `MacMessageBubble` struct (or wherever `assistantContent` is rendered). After the main text content, add a connect CTA section:

```swift
// Connect CTA — shown after a non-streaming message that references a disconnected service
let lc = message.content.lowercased()
if !message.isStreaming && !message.content.isEmpty {
    if !calendarConnected && (lc.contains("calendar") || lc.contains("not connected")) {
        macConnectBanner(label: "Connect Calendar", icon: "calendar", color: .blue) {
            Task { await services.calendarService.requestAccess() }
        }
    }
    if !emailConnected && (lc.contains("email") || lc.contains("inbox") || lc.contains("not connected")) {
        macConnectBanner(label: "Connect Email", icon: "envelope", color: .orange) { }
    }
}
```

The `macConnectBanner` helper:
```swift
private func macConnectBanner(label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .medium))
            Text(label).font(.system(size: 12, weight: .medium))
            Image(systemName: "arrow.right").font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .foregroundStyle(color)
    }
    .buttonStyle(.plain)
    .padding(.top, 3)
}
```

Note: `MacMessageBubble` may be a nested struct or inline; read the file to find where `assistantContent` renders and insert after it. Pass `calendarConnected` and `emailConnected` as parameters, mirroring the iOS pattern.

- [ ] **Step 6: Build macOS**

```bash
cd apps/macos && xcodebuild -scheme TodusMac -destination 'platform=macOS' build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add apps/macos/TodusMac/Services/AI/MacAIChatService.swift apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift
git commit -m "feat(macos): filter AI suggestions by service connection; add connect CTA; fix system prompt wording"
```

---

## Task 5: Web — Fix Markdown + Filter Suggestions + Connect CTA

The web chat already uses `@react-email/components` `Markdown`, but `markdownStyles` flattens all headings to `1rem` with no weight differentiation, making responses look like an unstyled wall of text. Fix styles to give headings visual hierarchy. Also filter example queries and add connect button.

**Files:**
- Modify: `apps/mail/components/create/ai-chat.tsx`

- [ ] **Step 1: Fix `markdownStyles` to render markdown visually**

Replace the existing `markdownStyles` object (lines 141–162):
```tsx
const markdownStyles = {
  h1: { fontSize: '1rem' },
  h2: { fontSize: '1rem' },
  // ...all at 1rem
};
```
with:
```tsx
const markdownStyles = {
  h1: { fontSize: '1rem', fontWeight: '700', marginBottom: '0.25rem', marginTop: '0.5rem' },
  h2: { fontSize: '1rem', fontWeight: '600', marginBottom: '0.25rem', marginTop: '0.5rem' },
  h3: { fontSize: '1rem', fontWeight: '600', marginBottom: '0.1rem' },
  h4: { fontSize: '1rem', fontWeight: '600' },
  h5: { fontSize: '1rem', fontWeight: '600' },
  h6: { fontSize: '1rem', fontWeight: '600' },
  p: { fontSize: '0.875rem', marginBottom: '0.4rem' },
  li: {
    fontSize: '0.875rem',
    marginBottom: '0.15rem',
    listStyleType: 'disc' as const,
    listStylePosition: 'outside' as const,
    marginLeft: '1.25rem',
  },
  ul: { fontSize: '0.875rem', marginBottom: '0.4rem', paddingLeft: '0' },
  ol: { fontSize: '0.875rem', marginBottom: '0.4rem', paddingLeft: '0' },
  blockQuote: { fontSize: '0.875rem', borderLeft: '3px solid #888', paddingLeft: '0.75rem', opacity: '0.8' },
  codeBlock: { fontSize: '0.8rem', fontFamily: 'monospace', backgroundColor: 'rgba(128,128,128,0.15)', padding: '0.5rem', borderRadius: '0.375rem', display: 'block', marginBottom: '0.4rem' },
  codeInline: { fontSize: '0.8rem', fontFamily: 'monospace', backgroundColor: 'rgba(128,128,128,0.15)', padding: '0.1rem 0.3rem', borderRadius: '0.25rem' },
  link: { fontSize: '0.875rem', color: '#3b82f6', textDecoration: 'underline' },
  image: { maxWidth: '100%', borderRadius: '0.5rem' },
};
```

- [ ] **Step 2: Add line-break normalization before Markdown render**

Wherever `<Markdown markdownCustomStyles={markdownStyles}>` is used (lines ~385, ~401), wrap the content with a normalizer. Create a helper near the top of the component:

```tsx
// Normalize single newlines to double newlines so Markdown sees paragraph breaks.
// The AI often sends single \n which CommonMark collapses to a space.
const normalizeMarkdown = (text: string) =>
  text.replace(/(?<!\n)\n(?!\n)/g, '\n\n');
```

Then use it:
```tsx
<Markdown markdownCustomStyles={markdownStyles}>
  {normalizeMarkdown(textBefore)}
</Markdown>
// ...
<Markdown markdownCustomStyles={markdownStyles}>
  {normalizeMarkdown(part.text || ' ')}
</Markdown>
```

- [ ] **Step 3: Add `useConnections` to the chat component and pass it to `ExampleQueries`**

Import `useConnections` at the top of `ai-chat.tsx`:
```tsx
import { useConnections } from '@/hooks/use-connections';
```

Inside the main `AIChat` component function, add:
```tsx
const { data: connections } = useConnections();
const hasEmailConnection = (connections?.length ?? 0) > 0;
```

Update `ExampleQueries` signature:
```tsx
const ExampleQueries = ({
  onQueryClick,
  hasEmailConnection,
  onConnect,
}: {
  onQueryClick: (query: string) => void;
  hasEmailConnection: boolean;
  onConnect: () => void;
}) => {
```

- [ ] **Step 4: In `ExampleQueries`, hide email queries when not connected and show connect button**

Replace the current static arrays with conditional rendering:
```tsx
const ExampleQueries = ({
  onQueryClick,
  hasEmailConnection,
  onConnect,
}: {
  onQueryClick: (query: string) => void;
  hasEmailConnection: boolean;
  onConnect: () => void;
}) => {
  // All suggestions require an email connection in this app
  if (!hasEmailConnection) {
    return (
      <div className="mt-6 flex flex-col items-center gap-3">
        <p className="text-sm text-[#8C8C8C] dark:text-[#929292]">
          Connect an email account to get started
        </p>
        <button
          onClick={onConnect}
          className="flex items-center gap-2 rounded-lg bg-blue-500/10 px-4 py-2 text-sm font-medium text-blue-500 hover:bg-blue-500/20 transition-colors"
        >
          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
            <path d="M2.003 5.884L10 9.882l7.997-3.998A2 2 0 0016 4H4a2 2 0 00-1.997 1.884z" />
            <path d="M18 8.118l-8 4-8-4V14a2 2 0 002 2h12a2 2 0 002-2V8.118z" />
          </svg>
          Connect Email Account
        </button>
      </div>
    );
  }

  const firstRowQueries = [
    'Find all work meetings today',
    'Label all emails from Github as OSS',
    'Show recent Linear feedback',
  ];
  const secondRowQueries = ['Find receipt from OpenAI', 'What Asana projects do I have coming up'];

  return (
    <div className="relative mt-6 flex w-full max-w-xl flex-col items-center gap-2">
      {/* First row */}
      <div className="no-scrollbar relative flex w-full justify-center overflow-x-auto">
        <div className="flex gap-4 px-4">
          {firstRowQueries.map((query) => (
            <button
              key={query}
              onClick={() => onQueryClick(query)}
              className="shrink-0 rounded-md bg-[#f0f0f0] p-1 px-2 text-sm whitespace-nowrap text-[#555555] dark:bg-[#262626] dark:text-[#929292]"
            >
              {query}
            </button>
          ))}
        </div>
      </div>
      {/* Second row */}
      <div className="no-scrollbar relative flex w-full justify-center overflow-x-auto">
        <div className="flex gap-4 px-4">
          {secondRowQueries.map((query) => (
            <button
              key={query}
              onClick={() => onQueryClick(query)}
              className="shrink-0 rounded-md bg-[#f0f0f0] p-1 px-2 text-sm whitespace-nowrap text-[#555555] dark:bg-[#262626] dark:text-[#929292]"
            >
              {query}
            </button>
          ))}
        </div>
      </div>
      {/* Left/right masks unchanged */}
      <div className="from-panelLight dark:from-panelDark pointer-events-none absolute top-0 bottom-0 left-0 w-12 bg-linear-to-r to-transparent"></div>
      <div className="from-panelLight dark:from-panelDark pointer-events-none absolute top-0 right-0 bottom-0 w-12 bg-linear-to-l to-transparent"></div>
    </div>
  );
};
```

- [ ] **Step 5: Update the `ExampleQueries` call site**

In the main return, find the `<ExampleQueries onQueryClick={handleQueryClick} />` usage and update it:
```tsx
<ExampleQueries
  onQueryClick={handleQueryClick}
  hasEmailConnection={hasEmailConnection}
  onConnect={() => {
    // Navigate to connections settings
    window.location.href = '/settings/connections';
  }}
/>
```

- [ ] **Step 6: Show connect CTA in assistant messages that mention a disconnected service**

After each assistant message block's text parts, add:
```tsx
{/* Connect CTA — shown when AI mentions email not connected */}
{message.role === 'assistant' &&
  !hasEmailConnection &&
  textParts.some((p) =>
    p.text?.toLowerCase().includes('not connected') ||
    p.text?.toLowerCase().includes('email') ||
    p.text?.toLowerCase().includes('inbox')
  ) && (
    <a
      href="/settings/connections"
      className="mt-2 inline-flex items-center gap-2 rounded-lg bg-blue-500/10 px-3 py-1.5 text-xs font-medium text-blue-500 hover:bg-blue-500/20 transition-colors"
    >
      <span>Connect Email Account</span>
      <span>→</span>
    </a>
  )}
```

- [ ] **Step 7: Verify web build**

```bash
cd apps/mail && pnpm build 2>&1 | tail -20
```
Expected: build succeeds with no TypeScript errors.

- [ ] **Step 8: Commit**

```bash
git add apps/mail/components/create/ai-chat.tsx
git commit -m "feat(web): fix markdown styles, filter suggestions by connection, add connect CTA"
```

---

## Self-Review Checklist

- [x] **iOS input hang** — root cause identified (O(n) thread dictionary grouping), fixed with `prefix(50)` cap
- [x] **System prompt wording** — "disabled by user" / "access not granted" → "not connected" in both iOS and macOS; AI directed to tell user to connect
- [x] **iOS suggestions** — calendar tab returns empty pool when calendar not connected; email tab returns empty when email not connected; connect CTA shown in place
- [x] **iOS connect button** — `MessageBubble` detects service name in response + service state → shows capsule button
- [x] **macOS suggestions** — same filtering logic applied
- [x] **macOS connect button** — same detection pattern in message bubbles
- [x] **Web markdown** — headings get weight, paragraphs get correct size, lists use `outside` positioning, code blocks styled; line-break normalization added
- [x] **Web suggestions** — if no email connection, all suggestions hidden, connect button shown instead
- [x] **Web connect CTA** — inline anchor below assistant message linking to `/settings/connections`
- [x] **No regressions** — existing behaviour when services ARE connected is unchanged; only the empty/disconnected paths are new
