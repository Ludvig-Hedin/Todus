export const mailFolders = ['inbox', 'sent', 'drafts', 'snoozed', 'archive', 'spam', 'bin'] as const;

export type MailFolder = (typeof mailFolders)[number];

export const settingsSections = [
  'general',
  'appearance',
  'connections',
  'labels',
  'categories',
  'notifications',
  'privacy',
  'security',
  'shortcuts',
  'danger-zone',
] as const;

export type SettingsSection = (typeof settingsSections)[number];

export type FeatureRouteMapping = {
  webPath: string;
  screenName: string;
  milestone: string;
  description: string;
};

export const featureRouteInventory: FeatureRouteMapping[] = [
  { webPath: '/', screenName: 'LandingScreen', milestone: 'M6', description: 'Landing screen' },
  { webPath: '/home', screenName: 'HomeScreen', milestone: 'M6', description: 'Public homepage' },
  { webPath: '/login', screenName: 'LoginScreen', milestone: 'M2', description: 'Auth login' },
  { webPath: '/about', screenName: 'AboutScreen', milestone: 'M6', description: 'Public about page' },
  { webPath: '/terms', screenName: 'TermsScreen', milestone: 'M6', description: 'Terms page' },
  { webPath: '/pricing', screenName: 'PricingScreen', milestone: 'M5', description: 'Pricing page' },
  { webPath: '/privacy', screenName: 'PrivacyScreen', milestone: 'M6', description: 'Privacy page' },
  {
    webPath: '/contributors',
    screenName: 'ContributorsScreen',
    milestone: 'M6',
    description: 'Contributors page',
  },
  { webPath: '/hr', screenName: 'HRScreen', milestone: 'M6', description: 'HR page' },
  {
    webPath: '/developer',
    screenName: 'DeveloperScreen',
    milestone: 'M6',
    description: 'Developer resources',
  },
  {
    webPath: '/mail',
    screenName: 'MailRedirectScreen',
    milestone: 'M1',
    description: 'Mail redirect',
  },
  {
    webPath: '/mail/:folder',
    screenName: 'MailFolderScreen',
    milestone: 'M3',
    description: 'Mail folder screen',
  },
  {
    webPath: '/mail/compose',
    screenName: 'ComposeScreen',
    milestone: 'M4',
    description: 'Compose modal/screen',
  },
  {
    webPath: '/mail/create',
    screenName: 'MailCreateRedirectScreen',
    milestone: 'M4',
    description: 'Legacy compose redirect',
  },
  {
    webPath: '/mail/under-construction/:path',
    screenName: 'UnderConstructionScreen',
    milestone: 'M4',
    description: 'Placeholder screen',
  },
  {
    webPath: '/settings',
    screenName: 'SettingsRedirectScreen',
    milestone: 'M5',
    description: 'Settings redirect',
  },
  {
    webPath: '/settings/general',
    screenName: 'SettingsGeneralScreen',
    milestone: 'M5',
    description: 'General settings',
  },
  {
    webPath: '/settings/appearance',
    screenName: 'SettingsAppearanceScreen',
    milestone: 'M5',
    description: 'Appearance settings',
  },
  {
    webPath: '/settings/connections',
    screenName: 'SettingsConnectionsScreen',
    milestone: 'M5',
    description: 'Connections settings',
  },
  {
    webPath: '/settings/labels',
    screenName: 'SettingsLabelsScreen',
    milestone: 'M5',
    description: 'Labels settings',
  },
  {
    webPath: '/settings/categories',
    screenName: 'SettingsCategoriesScreen',
    milestone: 'M5',
    description: 'Category settings',
  },
  {
    webPath: '/settings/notifications',
    screenName: 'SettingsNotificationsScreen',
    milestone: 'M5',
    description: 'Notification settings',
  },
  {
    webPath: '/settings/privacy',
    screenName: 'SettingsPrivacyScreen',
    milestone: 'M5',
    description: 'Privacy settings',
  },
  {
    webPath: '/settings/security',
    screenName: 'SettingsSecurityScreen',
    milestone: 'M5',
    description: 'Security settings',
  },
  {
    webPath: '/settings/shortcuts',
    screenName: 'SettingsShortcutsScreen',
    milestone: 'M5',
    description: 'Shortcuts settings',
  },
  {
    webPath: '/settings/danger-zone',
    screenName: 'SettingsDangerZoneScreen',
    milestone: 'M5',
    description: 'Danger zone settings',
  },
  {
    webPath: '/settings/*',
    screenName: 'SettingsFallbackScreen',
    milestone: 'M5',
    description: 'Settings fallback',
  },
  {
    webPath: '/*',
    screenName: 'NotFoundScreen',
    milestone: 'M1',
    description: 'Not found screen',
  },
];

export const publicScreenNames = [
  'LandingScreen',
  'HomeScreen',
  'AboutScreen',
  'TermsScreen',
  'PricingScreen',
  'PrivacyScreen',
  'ContributorsScreen',
  'HRScreen',
  'DeveloperScreen',
] as const;

export const appShellScreenNames = [
  'MailRedirectScreen',
  'MailFolderScreen',
  'ComposeScreen',
  'MailCreateRedirectScreen',
  'UnderConstructionScreen',
  'SettingsRedirectScreen',
  'SettingsGeneralScreen',
  'SettingsAppearanceScreen',
  'SettingsConnectionsScreen',
  'SettingsLabelsScreen',
  'SettingsCategoriesScreen',
  'SettingsNotificationsScreen',
  'SettingsPrivacyScreen',
  'SettingsSecurityScreen',
  'SettingsShortcutsScreen',
  'SettingsDangerZoneScreen',
  'SettingsFallbackScreen',
  'NotFoundScreen',
] as const;

const authPrefixes = ['/mail', '/settings'] as const;

export const nativeRouteDefaults = {
  appEntryPath: '/mail/inbox',
  loginPath: '/login',
  homePath: '/home',
} as const;

export type NativeAuthSessionMode = 'bearer' | 'web-cookie';

export type NativeAuthSession = {
  mode: NativeAuthSessionMode;
  token: string | null;
  createdAt: number;
  expiresAt?: number | null;
};

export type NativeAuthProvider = {
  id: string;
  name: string;
  enabled: boolean;
  required?: boolean;
  isCustom?: boolean;
  customRedirectPath?: string;
};

export type NativeRouteParamList = {
  LoginScreen: undefined;
  WebAuthScreen: { providerId: string; initialUrl: string };
  WebAppScreen: { initialPath?: string } | undefined;
};

export function normalizeWebPath(rawPath: string): string {
  if (!rawPath) return '/';
  try {
    const parsed = new URL(rawPath);
    return parsed.pathname + parsed.search + parsed.hash;
  } catch {
    if (rawPath.startsWith('/')) return rawPath;
    return `/${rawPath}`;
  }
}

export function routeRequiresAuth(path: string): boolean {
  const normalized = normalizeWebPath(path);
  return authPrefixes.some((prefix) => normalized === prefix || normalized.startsWith(`${prefix}/`));
}

export function isPublicRoute(path: string): boolean {
  return !routeRequiresAuth(path);
}

export function resolveInventoryPath(
  webPath: string,
  params: Record<string, string> = { folder: 'inbox', path: 'pending' },
): string {
  return webPath.replace(/:([a-zA-Z]+)/g, (_, key: string) => params[key] ?? 'pending').replace('/*', '/');
}

export function findRouteByScreenName(screenName: string): FeatureRouteMapping | undefined {
  return featureRouteInventory.find((route) => route.screenName === screenName);
}

export function isNativeAuthSessionExpired(session: NativeAuthSession, now = Date.now()): boolean {
  if (!session.expiresAt) return false;
  return session.expiresAt <= now;
}
