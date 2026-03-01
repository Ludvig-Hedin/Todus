/**
 * Navigation type definitions for the native app.
 * Restructured from WebView-only params to support truly native screens.
 *
 * Hierarchy:
 *   RootStack
 *   ├── AuthStack (unauthenticated)
 *   │   ├── LoginScreen
 *   │   └── WebAuthScreen (OAuth callback WebView)
 *   ├── AppTabs (authenticated — main app)
 *   │   ├── MailStack
 *   │   │   ├── MailFolderScreen
 *   │   │   └── ThreadDetailScreen
 *   │   ├── SettingsStack
 *   │   │   ├── SettingsListScreen
 *   │   │   └── SettingsDetailScreen
 *   │   └── AIScreen
 *   └── Modals (compose, sheets, etc.)
 *       ├── ComposeScreen
 *       └── PublicWebScreen
 */

// -- Root --
export type RootStackParamList = {
  AuthStack: undefined;
  AppTabs: undefined;
  ComposeModal: { draftId?: string; replyToThreadId?: string; mode?: 'new' | 'reply' | 'replyAll' | 'forward' } | undefined;
  PublicWebScreen: { url: string; title?: string };
};

// -- Auth --
export type AuthStackParamList = {
  LoginScreen: undefined;
  WebAuthScreen: { url: string; callbackScheme?: string };
};

// -- App Tabs --
export type AppTabsParamList = {
  MailTab: undefined;
  SettingsTab: undefined;
};

// -- Mail Drawer (inside MailTab) --
export type MailDrawerParamList = {
  MailStack: { folder?: string };
};

// -- Mail Stack (inside MailDrawer) --
export type MailStackParamList = {
  MailFolderScreen: { folder?: string };
  ThreadDetailScreen: { threadId: string; folder?: string };
};

// -- Settings Stack (inside SettingsTab) --
export type SettingsStackParamList = {
  SettingsListScreen: undefined;
  SettingsGeneralScreen: undefined;
  SettingsAppearanceScreen: undefined;
  SettingsConnectionsScreen: undefined;
  SettingsLabelsScreen: undefined;
  SettingsCategoriesScreen: undefined;
  SettingsNotificationsScreen: undefined;
  SettingsPrivacyScreen: undefined;
  SettingsSecurityScreen: undefined;
  SettingsShortcutsScreen: undefined;
  SettingsDangerZoneScreen: undefined;
};

// -- Legacy types kept for backward compatibility during transition --
export type AppShellParamList = {
  WebAppScreen: { initialPath?: string };
};

export type PublicStackParamList = {
  PublicWebScreen: { url: string; title?: string };
};
