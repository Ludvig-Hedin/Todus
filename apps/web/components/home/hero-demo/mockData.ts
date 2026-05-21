export type SceneId = 'mail' | 'calendar' | 'tasks' | 'assistant';

export const SCENES: readonly SceneId[] = ['mail', 'calendar', 'tasks', 'assistant'] as const;

export const ACCENT_BLUE = '#437DFB';

export interface MockThread {
  id: string;
  initials: string;
  initialsColor: string;
  sender: string;
  count?: number;
  subject: string;
  snippet: string;
  time: string;
  unread: boolean;
  pinned?: boolean;
  recipients?: string[];
  hasAttachment?: boolean;
}

export interface MockEvent {
  id: string;
  title: string;
  time: string;
  color: string;
  top: number;
  height: number;
}

export interface MockTask {
  id: string;
  label: string;
  due?: string;
  completed: boolean;
  list?: string;
}

export interface MockMessage {
  id: string;
  author: string;
  initials: string;
  initialsColor: string;
  time: string;
  body: string;
}

export interface MockAttachment {
  id: string;
  name: string;
  size: string;
  kind: 'fig' | 'doc' | 'image' | 'pdf';
}

export const SIDEBAR_FOLDERS = [
  { id: 'inbox', label: 'Inbox', count: 281, active: true },
  { id: 'favorites', label: 'Favorites' },
  { id: 'drafts', label: 'Drafts', count: 13 },
  { id: 'sent', label: 'Sent' },
] as const;

export const SIDEBAR_MANAGEMENT = [
  { id: 'archive', label: 'Archive' },
  { id: 'spam', label: 'Spam', count: 24 },
  { id: 'bin', label: 'Bin' },
] as const;

export const PINNED_THREADS: MockThread[] = [
  {
    id: 'p1',
    initials: 'AB',
    initialsColor: '#5957D6',
    sender: 'Ali from Baked',
    count: 8,
    subject: 'New design themes',
    snippet: 'Pushed three new themes, want your take before Friday.',
    time: 'Mar 28',
    unread: false,
    pinned: true,
    recipients: ['Alex', 'Sarah'],
  },
  {
    id: 'p2',
    initials: 'A',
    initialsColor: '#FA8C33',
    sender: 'Alex, Ali, Sarah',
    count: 6,
    subject: 'Re: Design review feedback',
    snippet: 'Loving the typography, one note about the hero.',
    time: 'Mar 28',
    unread: true,
    pinned: true,
    recipients: ['Alex', 'Ali', 'Sarah'],
  },
  {
    id: 'p3',
    initials: 'GH',
    initialsColor: '#1F2937',
    sender: 'GitHub',
    count: 3,
    subject: 'Security alert: Critical vulnerability',
    snippet: 'A new advisory was published for one of your dependencies.',
    time: 'Mar 28',
    unread: true,
    pinned: true,
  },
];

export const PRIMARY_THREADS: MockThread[] = [
  {
    id: 't1',
    initials: 'S',
    initialsColor: '#635BFF',
    sender: 'Stripe',
    subject: 'Payment confirmation #1234',
    snippet: 'Your monthly invoice is ready in the dashboard.',
    time: 'Mar 29',
    unread: true,
  },
  {
    id: 't2',
    initials: 'N',
    initialsColor: '#E50914',
    sender: 'Netflix',
    subject: 'New shows added to your list',
    snippet: 'Slow Horses season 4, House of the Dragon, and 12 more.',
    time: 'Mar 29',
    unread: false,
  },
  {
    id: 't3',
    initials: 'NK',
    initialsColor: '#33ADC7',
    sender: 'Nick',
    subject: 'Coffee next week?',
    snippet: 'Free Tuesday or Thursday morning, my treat this time.',
    time: 'Mar 29',
    unread: true,
  },
  {
    id: 't4',
    initials: 'A',
    initialsColor: '#F06A6A',
    sender: 'Asana',
    subject: 'Weekly task summary',
    snippet: 'You completed 14 tasks this week, 3 more than last week.',
    time: 'Mar 29',
    unread: false,
  },
  {
    id: 't5',
    initials: 'F',
    initialsColor: '#0ACF83',
    sender: 'Figma',
    subject: 'Comments on "Landing Page v2"',
    snippet: 'Sarah and 2 others left feedback on your draft.',
    time: 'Mar 29',
    unread: true,
  },
  {
    id: 't6',
    initials: 'DS',
    initialsColor: '#FFCC00',
    sender: 'DocuSign',
    subject: 'Urgent: Contract needs signature',
    snippet: 'The MSA from Acme is awaiting your countersign.',
    time: 'Mar 29',
    unread: false,
  },
  {
    id: 't7',
    initials: 'IN',
    initialsColor: '#0A66C2',
    sender: 'LinkedIn',
    subject: 'Job opportunities in your network',
    snippet: '5 roles match your saved searches this week.',
    time: 'Mar 29',
    unread: true,
  },
];

export const THREAD_MESSAGES: MockMessage[] = [
  {
    id: 'm1',
    author: 'Ali Mamedgasanov',
    initials: 'AM',
    initialsColor: '#5957D6',
    time: 'March 25, 10:15 AM',
    body: 'Hey team, I just uploaded the email client design with some new interactions, taking a different approach with the command center. Much cleaner now. Check out the new flows and let me know what you think.',
  },
  {
    id: 'm2',
    author: 'Sarah',
    initials: 'SA',
    initialsColor: '#33ADC7',
    time: 'March 25, 2:30 PM',
    body: "I've spent some time playing with the new version and have quite a few thoughts. The command center is definitely moving in the right direction, the new layout makes much more sense for power users. Really like how you've integrated the keyboard shortcuts naturally into the UI. Let me know what you think about these points. Happy to jump on a call to discuss in detail.",
  },
  {
    id: 'm3',
    author: 'Alex',
    initials: 'AL',
    initialsColor: '#FA8C33',
    time: 'March 25, 3:45 PM',
    body: 'Agree with Sarah on the command center. The shortcut layer is a big upgrade.',
  },
];

export const THREAD_ATTACHMENTS: MockAttachment[] = [
  { id: 'a1', name: 'cmd.center.fig', size: '21 MB', kind: 'fig' },
  { id: 'a2', name: 'comments.docx', size: '3.7 MB', kind: 'doc' },
  { id: 'a3', name: 'img.png', size: '2.2 MB', kind: 'image' },
  { id: 'a4', name: 'requirements.pdf', size: '1.5 MB', kind: 'pdf' },
];

export const AI_SUMMARY =
  'Design review of new email client features. Team discussed command center improvements and category system. General positive feedback, with suggestions for quick actions placement.';

export const EVENTS: MockEvent[] = [
  { id: 'e1', title: 'Design review', time: '9:30 — 10:30', color: '#5957D6', top: 6, height: 13 },
  { id: 'e2', title: 'Coffee with Maya', time: '11:00 — 11:45', color: '#33ADC7', top: 23, height: 10 },
  { id: 'e3', title: 'Product sync', time: '14:00 — 15:30', color: '#FA8C33', top: 48, height: 18 },
  { id: 'e4', title: 'Focus block', time: '16:30 — 18:00', color: '#33B866', top: 72, height: 18 },
];

export const TASKS: MockTask[] = [
  { id: 'ta1', label: 'Send sprint summary to the team', due: 'Today', completed: true, list: 'Work' },
  { id: 'ta2', label: 'Review onboarding copy in Figma', due: 'Today', completed: true, list: 'Work' },
  { id: 'ta3', label: 'Reply to Nick about the hero', due: 'Today', completed: false, list: 'Work' },
  { id: 'ta4', label: 'Book flights for the offsite', due: 'Tomorrow', completed: false, list: 'Personal' },
  { id: 'ta5', label: 'Read Stripe invoice', due: 'Fri', completed: false, list: 'Work' },
  { id: 'ta6', label: 'Renew domain', due: 'Sat', completed: false, list: 'Personal' },
];

export const ASSISTANT_QUESTION = "What's on my plate today?";
export const ASSISTANT_REPLY =
  'You have 3 meetings, 2 tasks due, and 4 emails waiting on a reply.';
