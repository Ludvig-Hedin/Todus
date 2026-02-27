import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { useSetAtom } from 'jotai';
import { useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Linking,
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { WebView } from 'react-native-webview';
import type { AuthStackParamList } from '../../app/navigation/types';
import { getNativeEnv } from '../../shared/config/env';
import {
  setBearerSessionAtom,
  setCurrentPathAtom,
  setWebCookieSessionAtom,
} from '../../shared/state/session';
import {
  isAllowedWebUrl,
  isLoginPath,
  isSignedInPath,
  parseAuthCallback,
  resolveWebPathFromUrl,
} from '../auth/native-auth';

type Props = NativeStackScreenProps<AuthStackParamList, 'WebAuthScreen'>;

export function WebAuthScreen({ route, navigation }: Props) {
  const env = getNativeEnv();
  const setWebCookieSession = useSetAtom(setWebCookieSessionAtom);
  const setBearerSession = useSetAtom(setBearerSessionAtom);
  const setCurrentPath = useSetAtom(setCurrentPathAtom);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const source = useMemo(() => ({ uri: route.params.url }), [route.params.url]);

  const completeCookieAuth = async (url: string) => {
    const path = resolveWebPathFromUrl(url);
    await setCurrentPath(path);
    await setWebCookieSession();
  };

  const completeBearerAuth = async (token: string, expiresAt?: number | null) => {
    await setBearerSession({ token, expiresAt: expiresAt ?? null });
  };

  return (
    <View style={styles.container}>
      <WebView
        source={source}
        userAgent={env.userAgent}
        sharedCookiesEnabled
        thirdPartyCookiesEnabled
        startInLoadingState
        onLoadStart={() => {
          setErrorMessage(null);
          setIsLoading(true);
        }}
        onLoadEnd={() => setIsLoading(false)}
        onError={() => {
          setIsLoading(false);
          setErrorMessage('Authentication page failed to load.');
        }}
        onNavigationStateChange={(navigationState) => {
          const currentUrl = navigationState.url;

          if (isSignedInPath(currentUrl, env.webUrl)) {
            completeCookieAuth(currentUrl).catch(() => {
              setErrorMessage('Could not complete sign-in.');
            });
          }

          if (isLoginPath(currentUrl, env.webUrl) && currentUrl.includes('error=')) {
            setErrorMessage('Sign-in failed. Please try again.');
          }
        }}
        onShouldStartLoadWithRequest={(request) => {
          const callback = parseAuthCallback(request.url);
          if (callback.token) {
            completeBearerAuth(callback.token, callback.expiresAt).catch(() => {
              setErrorMessage('Could not store authentication token.');
            });
            return false;
          }

          if (isAllowedWebUrl(request.url, env.allowedHosts)) {
            return true;
          }

          Linking.openURL(request.url).catch(() => {
            // No-op: if external URL cannot be opened, keep user on auth screen.
          });
          return false;
        }}
      />

      <View style={styles.topBar}>
        <Pressable style={styles.backButton} onPress={() => navigation.goBack()}>
          <Text style={styles.backButtonText}>Back</Text>
        </Pressable>
        <Text style={styles.topBarTitle}>Sign in with Web</Text>
      </View>

      {isLoading ? (
        <View style={styles.loadingPill}>
          <ActivityIndicator size="small" color="#111827" />
          <Text style={styles.loadingText}>Completing sign-in...</Text>
        </View>
      ) : null}

      {errorMessage ? (
        <View style={styles.errorPill}>
          <Text style={styles.errorText}>{errorMessage}</Text>
        </View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f4f4f5',
  },
  topBar: {
    position: 'absolute',
    left: 0,
    right: 0,
    top: 0,
    paddingTop: 10,
    paddingHorizontal: 10,
    paddingBottom: 8,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    backgroundColor: 'rgba(255, 255, 255, 0.95)',
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderColor: '#d4d4d8',
  },
  topBarTitle: {
    fontSize: 13,
    color: '#374151',
    fontWeight: '500',
    textTransform: 'capitalize',
  },
  backButton: {
    borderRadius: 8,
    backgroundColor: '#111827',
    paddingHorizontal: 10,
    paddingVertical: 6,
  },
  backButtonText: {
    color: '#ffffff',
    fontWeight: '600',
    fontSize: 13,
  },
  loadingPill: {
    position: 'absolute',
    bottom: 14,
    alignSelf: 'center',
    flexDirection: 'row',
    gap: 8,
    alignItems: 'center',
    borderRadius: 999,
    backgroundColor: '#ffffff',
    borderWidth: 1,
    borderColor: '#d4d4d8',
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  loadingText: {
    color: '#111827',
    fontSize: 13,
    fontWeight: '500',
  },
  errorPill: {
    position: 'absolute',
    bottom: 14,
    left: 14,
    right: 14,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: '#fecaca',
    backgroundColor: '#fef2f2',
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  errorText: {
    color: '#991b1b',
    fontSize: 13,
  },
});
