import { signOutNativeSession } from '@zero/api-client';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { useAtomValue, useSetAtom } from 'jotai';
import { useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Linking,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { WebView } from 'react-native-webview';
import type { AppShellParamList } from '../../app/navigation/types';
import { getNativeEnv } from '../../shared/config/env';
import {
  authStatusAtom,
  clearSessionAtom,
  currentPathAtom,
  sessionAtom,
  setCurrentPathAtom,
} from '../../shared/state/session';
import { isAllowedWebUrl, isLoginPath, resolveWebPathFromUrl } from '../auth/native-auth';

type Props = NativeStackScreenProps<AppShellParamList, 'WebAppScreen'>;

type NavShortcut = {
  label: string;
  path: string;
};

const shortcuts: NavShortcut[] = [
  { label: 'Inbox', path: '/mail/inbox' },
  { label: 'Compose', path: '/mail/compose' },
  { label: 'Settings', path: '/settings/general' },
  { label: 'Pricing', path: '/pricing' },
  { label: 'Privacy', path: '/privacy' },
];

export function WebAppScreen({ route }: Props) {
  const env = getNativeEnv();
  const webViewRef = useRef<WebView>(null);
  const session = useAtomValue(sessionAtom);
  const authStatus = useAtomValue(authStatusAtom);
  const currentPath = useAtomValue(currentPathAtom);
  const clearSession = useSetAtom(clearSessionAtom);
  const setCurrentPath = useSetAtom(setCurrentPathAtom);
  const [isLoading, setIsLoading] = useState(true);
  const [isSigningOut, setIsSigningOut] = useState(false);

  const initialPath = route.params?.initialPath ?? currentPath;
  const [currentUrl, setCurrentUrl] = useState(
    `${env.webUrl.replace(/\/$/, '')}${initialPath.startsWith('/') ? initialPath : `/${initialPath}`}`,
  );

  const activePath = useMemo(() => resolveWebPathFromUrl(currentUrl), [currentUrl]);

  const navigateToPath = (path: string) => {
    const nextUrl = `${env.webUrl.replace(/\/$/, '')}${path}`;
    setCurrentUrl(nextUrl);
    webViewRef.current?.injectJavaScript(`window.location.href = ${JSON.stringify(nextUrl)}; true;`);
  };

  const handleLogout = async () => {
    setIsSigningOut(true);

    try {
      if (session?.mode === 'bearer' && session.token) {
        await signOutNativeSession(env.backendUrl, session.token);
      }
    } finally {
      await clearSession();
      setIsSigningOut(false);
    }
  };

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.shortcutRow}>
          {shortcuts.map((shortcut) => {
            const selected = activePath === shortcut.path || activePath.startsWith(`${shortcut.path}/`);
            return (
              <Pressable
                key={shortcut.path}
                style={[styles.shortcutButton, selected ? styles.shortcutButtonActive : null]}
                onPress={() => navigateToPath(shortcut.path)}
              >
                <Text style={[styles.shortcutText, selected ? styles.shortcutTextActive : null]}>
                  {shortcut.label}
                </Text>
              </Pressable>
            );
          })}
        </ScrollView>
        <Pressable
          style={[styles.logoutButton, isSigningOut ? styles.logoutButtonDisabled : null]}
          onPress={() => {
            handleLogout().catch(() => {
              setIsSigningOut(false);
            });
          }}
          disabled={isSigningOut}
        >
          <Text style={styles.logoutText}>{isSigningOut ? 'Signing out...' : 'Logout'}</Text>
        </Pressable>
      </View>

      <WebView
        ref={webViewRef}
        source={{ uri: currentUrl }}
        userAgent={env.userAgent}
        sharedCookiesEnabled
        thirdPartyCookiesEnabled
        startInLoadingState
        pullToRefreshEnabled
        setSupportMultipleWindows={false}
        onLoadStart={() => setIsLoading(true)}
        onLoadEnd={() => setIsLoading(false)}
        onNavigationStateChange={(navigationState) => {
          setCurrentUrl(navigationState.url);

          const path = resolveWebPathFromUrl(navigationState.url);
          setCurrentPath(path).catch(() => {
            // No-op: this only affects shell resume position.
          });

          if (authStatus === 'authenticated' && isLoginPath(navigationState.url, env.webUrl)) {
            clearSession().catch(() => {
              // No-op: guard will redirect on next render anyway.
            });
          }
        }}
        onShouldStartLoadWithRequest={(request) => {
          if (isAllowedWebUrl(request.url, env.allowedHosts)) {
            return true;
          }

          Linking.openURL(request.url).catch(() => {
            // No-op: keep user in app if OS cannot open external URL.
          });
          return false;
        }}
      />

      {isLoading ? (
        <View style={styles.loadingPill}>
          <ActivityIndicator size="small" color="#111827" />
          <Text style={styles.loadingText}>{`Loading ${env.appName}...`}</Text>
        </View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0b0f14',
  },
  header: {
    backgroundColor: '#ffffff',
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderColor: '#d4d4d8',
    paddingHorizontal: 10,
    paddingVertical: 8,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  shortcutRow: {
    gap: 8,
  },
  shortcutButton: {
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 999,
    backgroundColor: '#f4f4f5',
  },
  shortcutButtonActive: {
    backgroundColor: '#111827',
  },
  shortcutText: {
    fontSize: 12,
    fontWeight: '600',
    color: '#374151',
  },
  shortcutTextActive: {
    color: '#ffffff',
  },
  logoutButton: {
    marginLeft: 'auto',
    borderRadius: 8,
    paddingHorizontal: 10,
    paddingVertical: 7,
    backgroundColor: '#111827',
  },
  logoutButtonDisabled: {
    opacity: 0.6,
  },
  logoutText: {
    color: '#ffffff',
    fontSize: 12,
    fontWeight: '700',
  },
  loadingPill: {
    position: 'absolute',
    right: 12,
    bottom: 12,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    borderRadius: 999,
    backgroundColor: '#ffffff',
    borderWidth: 1,
    borderColor: '#d4d4d8',
    paddingHorizontal: 10,
    paddingVertical: 7,
  },
  loadingText: {
    color: '#111827',
    fontSize: 12,
    fontWeight: '500',
  },
});
