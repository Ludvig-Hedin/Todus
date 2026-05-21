/**
 * Starter prompts for the AI assistant empty state.
 *
 * Mirrors the macOS `MacAssistantPanel` prompt library so the iOS / macOS / web
 * experiences feel like the same product. Keep this list in sync with
 * `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift` (search for
 * `promptTemplates`).
 *
 * `icon` values are lucide-react icon names — the gallery resolves them lazily
 * so we don't have to import every icon up-front.
 */
export interface AIPrompt {
  id: string;
  title: string;
  body: string;
  icon?: string;
  category?: string;
}

export const AI_PROMPTS: AIPrompt[] = [
  {
    id: 'summarize-unread',
    title: 'Summarize unread',
    body: 'Summarize my unread emails from the last 24 hours.',
    icon: 'MailOpen',
    category: 'Summary',
  },
  {
    id: 'draft-reply',
    title: 'Draft a reply',
    body: 'Draft a polite, concise reply to the most recent email in my inbox.',
    icon: 'Pencil',
    category: 'Writing',
  },
  {
    id: 'find-action-items',
    title: 'Find action items',
    body: 'Scan my recent emails and list every action item that needs my attention.',
    icon: 'CheckCircle2',
    category: 'Tasks',
  },
  {
    id: 'schedule-meeting',
    title: 'Schedule a meeting',
    body: 'Help me schedule a 30-minute meeting next week and draft the invite.',
    icon: 'CalendarPlus',
    category: 'Scheduling',
  },
  {
    id: 'find-emails-about',
    title: 'Find emails about…',
    body: 'Find all emails about ',
    icon: 'Search',
    category: 'Search',
  },
  {
    id: 'weekly-digest',
    title: 'Weekly digest',
    body: 'Give me a digest of the most important emails from the past week.',
    icon: 'Newspaper',
    category: 'Summary',
  },
  {
    id: 'unsubscribe-newsletters',
    title: 'Unsubscribe newsletters',
    body: 'Find newsletters I rarely open and help me unsubscribe from them.',
    icon: 'BellOff',
    category: 'Cleanup',
  },
  {
    id: 'find-attachments',
    title: 'Find attachments',
    body: 'Find emails with attachments from the last month and group them by sender.',
    icon: 'Paperclip',
    category: 'Search',
  },
  {
    id: 'snooze-low-priority',
    title: 'Snooze low priority',
    body: 'Identify low-priority emails in my inbox and suggest which to snooze.',
    icon: 'Clock',
    category: 'Triage',
  },
  {
    id: 'label-triage-rules',
    title: 'Label triage rules',
    body: 'Suggest labels and triage rules based on the patterns in my inbox.',
    icon: 'Tag',
    category: 'Automation',
  },
  {
    id: 'brainstorm-subjects',
    title: 'Brainstorm subjects',
    body: 'Brainstorm five compelling subject lines for an email about ',
    icon: 'Lightbulb',
    category: 'Writing',
  },
  {
    id: 'translate-email',
    title: 'Translate email',
    body: 'Translate the most recent email in my inbox into English and summarize it.',
    icon: 'Languages',
    category: 'Translation',
  },
];
