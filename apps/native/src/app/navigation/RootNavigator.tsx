/**
 * RootNavigator — main navigation hierarchy for the native app.
 *
 * Restructured from WebView-only to truly native screens:
 *   RootStack (no header)
 *   ├── AuthStack (unauthenticated)
 *   │   ├── LoginScreen
 *   │   └── WebAuthScreen (OAuth callback)
 *   ├── AppTabs (authenticated)
 *   │   ├── MailTab → MailStack
 *   │   │   ├── MailFolderScreen
 *   │   │   └── ThreadDetailScreen
 *   │   └── SettingsTab → SettingsStack
 *   │       ├── SettingsListScreen
 *   │       └── All individual settings screens
 *   └── ComposeModal (full-screen modal)
 *   └── PublicWebScreen (WebView for public/legal pages)
 */
import { DarkTheme, DefaultTheme, NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { createDrawerNavigator } from '@react-navigation/drawer';
import { semanticColors } from '@zero/design-tokens';
import { useAtomValue } from 'jotai';
import { ActivityIndicator, StyleSheet, Text, useColorScheme, View } from 'react-native';
import { LoginScreen } from '../../features/auth/LoginScreen';
import { WebAuthScreen } from '../../features/web/WebAuthScreen';
import { PublicWebScreen } from '../../features/web/PublicWebScreen';
import { MailSidebar } from '../../features/mail/MailSidebar';
import { MailFolderScreen } from '../../features/mail/MailFolderScreen';
import { ThreadDetailScreen } from '../../features/mail/ThreadDetailScreen';
import { ComposeScreen } from '../../features/compose/ComposeScreen';
import { SettingsListScreen } from '../../features/settings/SettingsListScreen';
import { SettingsDetailScreen } from '../../features/settings/SettingsDetailScreen';
import { authStatusAtom } from '../../shared/state/session';
import type {
  AppTabsParamList,
  AuthStackParamList,
  MailStackParamList,
  MailDrawerParamList,
  RootStackParamList,
  SettingsStackParamList,
} from './types';

const RootStack = createNativeStackNavigator<RootStackParamList>();
const AuthStackNav = createNativeStackNavigator<AuthStackParamList>();
const MailStack = createNativeStackNavigator<MailStackParamList>();
const MailDrawerNav = createDrawerNavigator<MailDrawerParamList>();
const SettingsStack = createNativeStackNavigator<SettingsStackParamList>();
const TabNav = createBottomTabNavigator<AppTabsParamList>();

// -- Auth Stack (unauthenticated users) --
function AuthStackNavigator() {
  return (
    <AuthStackNav.Navigator>
      <AuthStackNav.Screen name="LoginScreen" component={LoginScreen} options={{ title: 'Login' }} />
      <AuthStackNav.Screen
        name="WebAuthScreen"
        component={WebAuthScreen}
        options={{ headerShown: false }}
      />
    </AuthStackNav.Navigator>
  );
}

// -- Mail Stack (inbox, thread detail) --
function MailStackNavigator() {
  return (
    <MailStack.Navigator>
      <MailStack.Screen
        name="MailFolderScreen"
        component={MailFolderScreen}
        options={{ headerShown: false }}
        initialParams={{ folder: 'inbox' }}
      />
      <MailStack.Screen
        name="ThreadDetailScreen"
        component={ThreadDetailScreen}
        options={{ title: '' }}
      />
    </MailStack.Navigator>
  );
}

// -- Mail Drawer (wraps the Mail Stack) --
function MailDrawerNavigator() {
  return (
    <MailDrawerNav.Navigator
      drawerContent={(props) => <MailSidebar {...props} />}
      screenOptions={{ headerShown: false, drawerType: 'front' }}
    >
      <MailDrawerNav.Screen name="MailStack" component={MailStackNavigator} />
    </MailDrawerNav.Navigator>
  );
}

// -- Settings Stack (settings hub + individual screens) --
function SettingsStackNavigator() {
  return (
    <SettingsStack.Navigator>
      <SettingsStack.Screen
        name="SettingsListScreen"
        component={SettingsListScreen}
        options={{ headerShown: false }}
      />
      <SettingsStack.Screen
        name="SettingsGeneralScreen"
        component={SettingsDetailScreen as any}
        options={{ title: 'General' }}
      />
      <SettingsStack.Screen
        name="SettingsAppearanceScreen"
        component={SettingsDetailScreen as any}
        options={{ title: 'Appearance' }}
      />
      <SettingsStack.Screen
        name="SettingsConnectionsScreen"
        component={SettingsDetailScreen as any}
        options={{ title: 'Connections' }}
      />
      <SettingsStack.Screen
        name="SettingsLabelsScreen"
        component={SettingsDetailScreen as any}
        options={{ title: 'Labels' }}
      />
      <SettingsStack.Screen
        name="SettingsCategoriesScreen"
        component={SettingsDetailScreen as any}
        options={{ title: 'Categories' }}
      />
      <SettingsStack.Screen
        name="SettingsNotificationsScreen"
        component={SettingsDetailScreen as any}
        options={{ title: 'Notifications' }}
      />
      <SettingsStack.Screen
        name="SettingsPrivacyScreen"
        component={SettingsDetailScreen as any}
        options={{ title: 'Privacy' }}
      />
      <SettingsStack.Screen
        name="SettingsSecurityScreen"
        component={SettingsDetailScreen as any}
        options={{ title: 'Security' }}
      />
      <SettingsStack.Screen
        name="SettingsShortcutsScreen"
        component={SettingsDetailScreen as any}
        options={{ title: 'Shortcuts' }}
      />
      <SettingsStack.Screen
        name="SettingsDangerZoneScreen"
        component={SettingsDetailScreen as any}
        options={{ title: 'Danger Zone' }}
      />
    </SettingsStack.Navigator>
  );
}

// -- App Tabs (authenticated users: Mail + Settings) --
function AppTabsNavigator() {
  const systemColorScheme = useColorScheme();
  const isDark = systemColorScheme === 'dark';
  const colors = isDark ? semanticColors.dark : semanticColors.light;

  return (
    <TabNav.Navigator
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: colors.primary,
        tabBarInactiveTintColor: colors.mutedForeground,
        tabBarStyle: {
          backgroundColor: colors.background,
          borderTopColor: colors.border,
        },
      }}
    >
      <TabNav.Screen
        name="MailTab"
        component={MailDrawerNavigator}
        options={{
          tabBarLabel: 'Mail',
          // Icons will use lucide-react-native once deps finish installing
          tabBarIcon: ({ color, size }: { color: string; size: number }) => (
            <Text style={{ color, fontSize: size - 4 }}>✉️</Text>
          ),
        }}
      />
      <TabNav.Screen
        name="SettingsTab"
        component={SettingsStackNavigator}
        options={{
          tabBarLabel: 'Settings',
          tabBarIcon: ({ color, size }: { color: string; size: number }) => (
            <Text style={{ color, fontSize: size - 4 }}>⚙️</Text>
          ),
        }}
      />
    </TabNav.Navigator>
  );
}

// -- Boot screen (shown during session bootstrap) --
function BootScreen() {
  const systemColorScheme = useColorScheme();
  const isDark = systemColorScheme === 'dark';
  const colors = isDark ? semanticColors.dark : semanticColors.light;

  return (
    <View style={[styles.bootScreen, { backgroundColor: colors.background }]}>
      <ActivityIndicator size="large" color={colors.primary} />
      <Text style={[styles.bootText, { color: colors.mutedForeground }]}>Loading...</Text>
    </View>
  );
}

// -- Root Navigator --
export function RootNavigator() {
  const authStatus = useAtomValue(authStatusAtom);
  const systemColorScheme = useColorScheme();
  const isDark = systemColorScheme === 'dark';

  const navTheme = isDark
    ? {
      ...DarkTheme,
      colors: {
        ...DarkTheme.colors,
        background: semanticColors.dark.background,
        card: semanticColors.dark.card,
        text: semanticColors.dark.foreground,
        border: semanticColors.dark.border,
        primary: semanticColors.dark.primary,
        notification: semanticColors.dark.destructive,
      },
    }
    : {
      ...DefaultTheme,
      colors: {
        ...DefaultTheme.colors,
        background: semanticColors.light.background,
        card: semanticColors.light.card,
        text: semanticColors.light.foreground,
        border: semanticColors.light.border,
        primary: semanticColors.light.primary,
        notification: semanticColors.light.destructive,
      },
    };

  if (authStatus === 'bootstrapping') {
    return <BootScreen />;
  }

  return (
    <NavigationContainer theme={navTheme}>
      <RootStack.Navigator screenOptions={{ headerShown: false }}>
        {authStatus === 'authenticated' ? (
          <>
            <RootStack.Screen name="AppTabs" component={AppTabsNavigator} />
            <RootStack.Screen
              name="ComposeModal"
              component={ComposeScreen}
              options={{ presentation: 'modal' }}
            />
            <RootStack.Screen
              name="PublicWebScreen"
              component={PublicWebScreen}
              options={{ presentation: 'modal' }}
            />
          </>
        ) : (
          <RootStack.Screen name="AuthStack" component={AuthStackNavigator} />
        )}
      </RootStack.Navigator>
    </NavigationContainer>
  );
}

const styles = StyleSheet.create({
  bootScreen: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 12,
  },
  bootText: {
    fontSize: 14,
  },
});
