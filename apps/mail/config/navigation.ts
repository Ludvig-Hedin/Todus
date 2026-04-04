import {
  SettingsGear,
  Stars,
  Tabs,
  Users,
  ArrowLeft,
  Danger,
  Sheet,
  LockIcon,
  Mail,
} from '@/components/icons/icons';
import {
  CalendarDays,
  CheckSquare2,
  FileText,
  Home,
  MessageSquareIcon,
  Search,
  Video,
} from 'lucide-react';
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
            title: m['navigation.sidebar.home'](),
            url: '/mail/home',
            icon: Home,
            shortcut: 'g + h',
          },
          {
            id: 'tasks',
            title: m['navigation.sidebar.tasks'](),
            url: '/mail/tasks',
            icon: CheckSquare2,
            shortcut: 'g + k',
          },
          {
            id: 'email',
            title: m['navigation.sidebar.email'](),
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
              {
                id: 'archive',
                title: m['navigation.sidebar.archive'](),
                url: '/mail/archive',
              },
              {
                id: 'snoozed',
                title: m['navigation.sidebar.snoozed'](),
                url: '/mail/snoozed',
              },
              {
                id: 'spam',
                title: m['navigation.sidebar.spam'](),
                url: '/mail/spam',
              },
              {
                id: 'bin',
                title: m['navigation.sidebar.bin'](),
                url: '/mail/bin',
              },
            ],
          },
          {
            id: 'calendar',
            title: m['navigation.sidebar.calendar'](),
            url: '/mail/calendar',
            icon: CalendarDays,
            shortcut: 'g + c',
          },
          {
            id: 'meetings',
            title: m['navigation.sidebar.meetings'](),
            url: '/mail/meetings',
            icon: Video,
            shortcut: 'g + m',
          },
          {
            id: 'docs',
            title: 'Docs',
            url: '/mail/docs',
            icon: FileText,
            shortcut: 'g + d',
          },
        ],
      },
      {
        id: 'extras',
        title: '',
        items: [
          {
            id: 'search',
            title: m['navigation.sidebar.search'](),
            url: '/mail/search',
            icon: Search,
            shortcut: 'g + f',
          },
          {
            id: 'chat',
            title: m['navigation.sidebar.chat'](),
            url: '/mail/chat',
            icon: MessageSquareIcon,
            shortcut: 'g + /',
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
            title: m['navigation.settings.meetings'](),
            url: '/settings/meetings',
            icon: Video,
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
