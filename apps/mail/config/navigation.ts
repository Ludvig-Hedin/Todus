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
  LockIcon,
  Clock,
  Mail,
} from '@/components/icons/icons';
import { CalendarDays, CheckSquare2, Home, MessageSquareIcon, Search } from 'lucide-react';
import type { ComponentType, SVGProps } from 'react';
import { m } from '@/paraglide/messages';

export interface NavChildItem {
  id?: string;
  title: string;
  url: string;
  badge?: number;
}

export interface NavItem {
  id?: string;
  title: string;
  url: string;
  icon: ComponentType<SVGProps<SVGSVGElement>>;
  badge?: number;
  isBackButton?: boolean;
  isSettingsButton?: boolean;
  disabled?: boolean;
  target?: string;
  shortcut?: string;
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
        id: 'primary',
        title: '',
        items: [
          {
            id: 'home',
            title: 'Home',
            url: '/mail/home',
            icon: Home,
            shortcut: 'g + h',
          },
          {
            id: 'tasks',
            title: 'Tasks',
            url: '/mail/tasks',
            icon: CheckSquare2,
            shortcut: 'g + k',
          },
          {
            id: 'email',
            title: 'Email',
            url: '/mail/inbox',
            icon: Mail,
            children: [
              {
                id: 'inbox',
                title: m['navigation.sidebar.inbox'](),
                url: '/mail/inbox',
              },
              {
                id: 'drafts',
                title: m['navigation.sidebar.drafts'](),
                url: '/mail/draft',
              },
              {
                id: 'sent',
                title: m['navigation.sidebar.sent'](),
                url: '/mail/sent',
              },
            ],
          },
          {
            id: 'calendar',
            title: 'Calendar',
            url: '/mail/calendar',
            icon: CalendarDays,
            shortcut: 'g + c',
          },
        ],
      },
      {
        id: 'extras',
        title: '',
        items: [
          {
            id: 'search',
            title: 'Search',
            url: '/mail/search',
            icon: Search,
            shortcut: 'g + f',
          },
          {
            id: 'chat',
            title: 'AI Assistant',
            url: '/mail/chat',
            icon: MessageSquareIcon,
            shortcut: 'g + /',
          },
        ],
      },
      {
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
