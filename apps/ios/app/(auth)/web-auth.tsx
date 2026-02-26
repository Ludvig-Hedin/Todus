/**
 * Web auth screen — WebView for OAuth callback flow.
 * Handles bearer token extraction from callback URL and cookie-based auth.
 */
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useSetAtom } from 'jotai';
import { useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Linking,
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { WebView } from 'react-native-webview';
import { getNativeEnv } from '../../src/shared/config/env';
import {
  setBearerSessionAtom,
  setCurrentPathAtom,
  setWebCookieSessionAtom,
} from '../../src/shared/state/session';
import {
  isAllowedWebUrl,
  isLoginPath,
  isSignedInPath,
  parseAuthCallback,
  resolveWebPathFromUrl,
} from '../../src/features/auth/native-auth';

export default function WebAuthScreen() {
  const { url } = useLocalSearchParams<{ url: string }>();
  const router = useRouter();
  const env = getNativeEnv();
  const setWebCookieSession = useSetAtom(setWebCookieSessionAtom);
  const setBearerSession = useSetAtom(setBearerSessionAtom);
  const setCurrentPath = useSetAtom(setCurrentPathAtom);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  // Guard against race condition: both onNavigationStateChange and onShouldStartLoadWithRequest
  // can fire for the same auth completion event. Only process the first one.
  const authCompletedRef = useRef(false);

  const source = useMemo(() => ({ uri: url ?? '' }), [url]);

  const completeCookieAuth = async (currentUrl: string) => {
    if (authCompletedRef.current) return;
    authCompletedRef.current = true;
    const path = resolveWebPathFromUrl(currentUrl);
    await setCurrentPath(path);
    await setWebCookieSession();
  };

  const completeBearerAuth = async (token: string, expiresAt?: number | null) => {
    if (authCompletedRef.current) return;
    authCompletedRef.current = true;
    await setBearerSession({ token, expiresAt: expiresAt ?? null });
  };

  if (!url) {
    return (
      <View style={styles.container}>
        <Text style={styles.errorText}>No auth URL provided</Text>
      </View>
    );
  }

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

          // If we landed on an authenticated page, auth succeeded via cookies
          if (isSignedInPath(currentUrl, env.webUrl)) {
            completeCookieAuth(currentUrl).catch(() => {
              setErrorMessage('Could not complete sign-in.');
            });
          }

          // If we're back on login page with an error param
          if (isLoginPath(currentUrl, env.webUrl) && currentUrl.includes('error=')) {
            setErrorMessage('Sign-in failed. Please try again.');
          }
        }}
        onShouldStartLoadWithRequest={(request) => {
          // Check if callback contains a bearer token
          const callback = parseAuthCallback(request.url);
          if (callback.token) {
            completeBearerAuth(callback.token, callback.expiresAt).catch(() => {
              setErrorMessage('Could not store authentication token.');
            });
            return false;
          }

          // Allow navigation to allowed hosts
          if (isAllowedWebUrl(request.url, env.allowedHosts)) {
            return true;
          }

          // Open external URLs in Safari
          Linking.openURL(request.url).catch(() => {});
          return false;
        }}
      />

      {/* Top bar with back button */}
      <View style={styles.topBar}>
        <Pressable style={styles.backButton} onPress={() => router.back()}>
          <Text style={styles.backButtonText}>Back</Text>
        </Pressable>
        <Text style={styles.topBarTitle}>Sign in with Web</Text>
      </View>

      {isLoading && (
        <View style={styles.loadingPill}>
          <ActivityIndicator size="small" color="#111827" />
          <Text style={styles.loadingText}>Completing sign-in...</Text>
        </View>
      )}

      {errorMessage && (
        <View style={styles.errorPill}>
          <Text style={styles.errorPillText}>{errorMessage}</Text>
        </View>
      )}
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
  errorPillText: {
    color: '#991b1b',
    fontSize: 13,
  },
  errorText: {
    color: '#991b1b',
    fontSize: 16,
    textAlign: 'center',
    padding: 20,
  },
});
