import {
  Archive,
  Bin,
  ExclamationCircle,
  SettingsGear,
  Stars,
  Tabs,
  Users,
  ArrowLeft,
  Danger,
  Sheet,
  Plane2,
  LockIcon,
  Clock,
  Mail,
} from '@/components/icons/icons';
import { MessageSquareIcon, Home, CheckSquare2, CalendarDays, Search } from 'lucide-react';
import { m } from '@/paraglide/messages';

// Child items inside an expandable nav group (e.g. Email → Inbox/Drafts/Sent)
export interface NavChildItem {
  id?: string;
  title: string;
  url: string;
}

export interface NavItem {
  id?: string;
  title: string;
  url: string;
  icon: React.ComponentType<any>;
  badge?: number;
  isBackButton?: boolean;
  isSettingsButton?: boolean;
  disabled?: boolean;
  target?: string;
  shortcut?: string;
  /** When set, the item renders as a collapsible group with these child links */
  children?: NavChildItem[];
}

interface NavSection {
  id?: string;
  title: string;
  items: NavItem[];
}

interface NavConfig {
  path: string;
  sections: NavSection[];
}

// ! items title has to be a message key (check messages/en.json)
export const navigationConfig: Record<string, NavConfig> = {
  mail: {
    path: '/mail',
    sections: [
      {
        // Primary nav — Home, Tasks, Email (expandable), Calendar
        // Mirrors macOS sidebar order
        id: 'primary',
        title: '',
        items: [
          {
            id: 'home',
            title: m['navigation.sidebar.home'](),
            url: '/mail/home',
            icon: Home,
            shortcut: 'g + h',
          },
          {
            id: 'tasks',
            title: m['navigation.sidebar.tasks'](),
            url: '/mail/tasks',
            // Use lucide CheckSquare2 — cleaner than the custom CircleCheck SVG
            icon: CheckSquare2,
            shortcut: 'g + k',
          },
          {
            id: 'email',
            title: 'Email',
            url: '/mail/inbox',
            icon: Mail,
            // Inbox/Drafts/Sent nested under collapsible Email parent (matches macOS)
            children: [
              { id: 'inbox', title: m['navigation.sidebar.inbox'](), url: '/mail/inbox' },
              { id: 'drafts', title: m['navigation.sidebar.drafts'](), url: '/mail/draft' },
              { id: 'sent', title: m['navigation.sidebar.sent'](), url: '/mail/sent' },
            ],
          },
          {
            id: 'calendar',
            title: m['navigation.sidebar.calendar'](),
            url: '/mail/calendar',
            // Use lucide CalendarDays — cleaner lines than custom SVG
            icon: CalendarDays,
            shortcut: 'g + c',
          },
        ],
      },
      {
        // Utility — Search only. AI Chat is FAB-only, not a sidebar nav item.
        id: 'extras',
        title: '',
        items: [
          {
            id: 'search',
            title: m['navigation.sidebar.search'](),
            url: '/mail/search',
            // Use lucide Search — consistent with lucide icon set
            icon: Search,
            shortcut: 'g + f',
          },
        ],
      },
      {
        // Archive / cleanup folders — de-emphasised, unlabeled
        id: 'archive',
        title: '',
        items: [
          {
            id: 'archive',
            title: m['navigation.sidebar.archive'](),
            url: '/mail/archive',
            icon: Archive,
            shortcut: 'g + a',
          },
          {
            id: 'snoozed',
            title: m['navigation.sidebar.snoozed'](),
            url: '/mail/snoozed',
            icon: Clock,
            shortcut: 'g + z',
          },
          {
            id: 'spam',
            title: m['navigation.sidebar.spam'](),
            url: '/mail/spam',
            icon: ExclamationCircle,
          },
          {
            id: 'trash',
            title: m['navigation.sidebar.bin'](),
            url: '/mail/bin',
            icon: Bin,
          },
        ],
      },
    ],
  },
  settings: {
    path: '/settings',
    sections: [
      {
        title: 'Settings',
        items: [
          {
            title: m['common.actions.back'](),
            url: '/mail',
            icon: ArrowLeft,
            isBackButton: true,
          },

          {
            title: m['navigation.settings.general'](),
            url: '/settings/general',
            icon: SettingsGear,
            shortcut: 'g + s',
          },
          {
            title: m['navigation.settings.connections'](),
            url: '/settings/connections',
            icon: Users,
          },
          {
            title: m['navigation.settings.security'](),
            url: '/settings/security',
            icon: LockIcon,
          },
          {
            title: m['navigation.settings.privacy'](),
            url: '/settings/privacy',
            icon: LockIcon,
          },
          {
            title: m['navigation.settings.appearance'](),
            url: '/settings/appearance',
            icon: Stars,
          },
          {
            title: m['navigation.settings.labels'](),
            url: '/settings/labels',
            icon: Sheet,
          },
          {
            title: m['navigation.settings.categories'](),
            url: '/settings/categories',
            icon: Tabs,
          },
          {
            title: m['navigation.settings.signatures'](),
            url: '/settings/signatures',
            icon: MessageSquareIcon,
          },
          {
            title: m['navigation.settings.shortcuts'](),
            url: '/settings/shortcuts',
            icon: Tabs,
            shortcut: '?',
          },
          {
            title: m['navigation.settings.deleteAccount'](),
            url: '/settings/danger-zone',
            icon: Danger,
          },
        ].map((item) => ({
          ...item,
          isSettingsPage: true,
        })),
      },
    ],
  },
};

export const bottomNavItems = [
  {
    title: '',
    items: [
      {
        id: 'settings',
        title: m['navigation.sidebar.settings'](),
        url: '/settings/general',
        icon: SettingsGear,
        isSettingsButton: true,
      },
    ],
  },
];
