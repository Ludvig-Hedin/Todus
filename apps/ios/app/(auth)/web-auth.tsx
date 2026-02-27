/**
 * Web auth screen — WebView for OAuth callback flow.
 *
 * Two modes:
 * 1. Direct OAuth (provider param): Calls getSocialAuthUrl() natively to get the
 *    OAuth consent URL (e.g., Google), then loads that URL directly in the WebView.
 *    This avoids WKWebView's null-origin issue with inline HTML.
 * 2. Fallback URL (url param): Opens the given URL directly (e.g. web login page).
 *
 * After OAuth completes, extracts a bearer token via injected JS calling /api/auth/get-session.
 */
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useSetAtom } from 'jotai';
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { WebView } from 'react-native-webview';
import type { WebViewSourceUri } from 'react-native-webview/lib/WebViewTypes';
import { getNativeEnv } from '../../src/shared/config/env';
import {
  setBearerSessionAtom,
  setCurrentPathAtom,
  setWebCookieSessionAtom,
} from '../../src/shared/state/session';
import {
  getSocialAuthUrl,
  getWebLoginUrl,
  isLoginPath,
  isSignedInPath,
  parseAuthCallback,
  resolveWebPathFromUrl,
} from '../../src/features/auth/native-auth';

/**
 * Injected JS that extracts a bearer token from the session endpoint.
 * Retries up to 3 times with 1s delay to handle timing issues.
 * Reads the token from both the response header and body for maximum compatibility.
 */
const EXTRACT_TOKEN_JS = (backendUrl: string) => `
  (function() {
    var attempts = 0;
    var maxAttempts = 3;
    function post(token) {
      window.ReactNativeWebView.postMessage(JSON.stringify({
        type: 'bearer-token', token: token
      }));
    }
    function tryExtract() {
      fetch('${backendUrl}/api/auth/get-session', { credentials: 'include' })
        .then(function(r) {
          var headerToken = r.headers.get('set-auth-token');
          return r.json().then(function(data) {
            var bodyToken = (data && data.session) ? data.session.token : null;
            var token = headerToken || bodyToken;
            if (token) {
              post(token);
            } else if (++attempts < maxAttempts) {
              setTimeout(tryExtract, 1000);
            } else {
              post(null);
            }
          });
        })
        .catch(function() {
          if (++attempts < maxAttempts) {
            setTimeout(tryExtract, 1000);
          } else {
            post(null);
          }
        });
    }
    tryExtract();
  })();
  true;
`;

export default function WebAuthScreen() {
  const { url, provider, callbackUrl } = useLocalSearchParams<{
    url?: string;
    provider?: string;
    callbackUrl?: string;
  }>();
  const router = useRouter();
  const env = getNativeEnv();
  const setWebCookieSession = useSetAtom(setWebCookieSessionAtom);
  const setBearerSession = useSetAtom(setBearerSessionAtom);
  const setCurrentPath = useSetAtom(setCurrentPathAtom);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const webViewRef = useRef<WebView>(null);
  // Guard against race condition: both onNavigationStateChange and onShouldStartLoadWithRequest
  // can fire for the same auth completion event. Only process the first one.
  const authCompletedRef = useRef(false);

  // WebView source: null while resolving OAuth URL, then { uri: ... } once ready.
  // For url-param mode, set immediately. For provider mode, set after getSocialAuthUrl() resolves.
  const [source, setSource] = useState<WebViewSourceUri | null>(() => {
    if (url) return { uri: url };
    return null;
  });

  // When in provider mode, fetch the OAuth consent URL natively. This avoids the
  // WKWebView null-origin bug: loadHTMLString always sends Origin: null regardless
  // of baseUrl, but native fetch() can set the Origin header explicitly.
  useEffect(() => {
    if (!provider) return;

    let cancelled = false;

    const resolveOAuthUrl = async () => {
      try {
        const oauthUrl = await getSocialAuthUrl(
          env.backendUrl,
          env.webUrl,
          provider,
          callbackUrl ?? env.authCallbackUrl,
        );
        if (!cancelled) {
          setSource({ uri: oauthUrl });
        }
      } catch (err) {
        console.warn('[web-auth] getSocialAuthUrl failed, falling back to web login:', err);
        if (!cancelled) {
          setSource({ uri: getWebLoginUrl(env.webUrl) });
        }
      }
    };

    resolveOAuthUrl();

    return () => {
      cancelled = true;
    };
  }, [provider, callbackUrl, env.backendUrl, env.webUrl, env.authCallbackUrl]);

  /** After landing on an authenticated page via cookies, try to extract a bearer token
   * by injecting JS to call /api/auth/get-session. Falls back to cookie-based auth. */
  const completeCookieAuth = useCallback(async (currentUrl: string) => {
    if (authCompletedRef.current) return;
    const path = resolveWebPathFromUrl(currentUrl);
    await setCurrentPath(path);

    if (webViewRef.current) {
      webViewRef.current.injectJavaScript(EXTRACT_TOKEN_JS(env.backendUrl.replace(/\/$/, '')));
    } else {
      if (authCompletedRef.current) return;
      authCompletedRef.current = true;
      await setWebCookieSession();
    }
  }, [env.backendUrl, setCurrentPath, setWebCookieSession]);

  const completeBearerAuth = useCallback(async (token: string, expiresAt?: number | null) => {
    if (authCompletedRef.current) return;
    authCompletedRef.current = true;
    await setBearerSession({ token, expiresAt: expiresAt ?? null });
  }, [setBearerSession]);

  /** Handle messages from injected JS (bearer token extraction + OAuth errors) */
  const handleMessage = useCallback(async (event: { nativeEvent: { data: string } }) => {
    try {
      const data = JSON.parse(event.nativeEvent.data) as {
        type: string;
        token?: string | null;
        message?: string;
      };

      // OAuth trigger failed — show error and offer fallback
      if (data.type === 'oauth-error') {
        console.warn('[web-auth] OAuth trigger error:', data.message);
        setErrorMessage(`Sign-in failed: ${data.message ?? 'Unknown error'}`);
        return;
      }

      if (authCompletedRef.current) return;

      if (data.type === 'bearer-token' && data.token) {
        authCompletedRef.current = true;
        await setBearerSession({ token: data.token, expiresAt: null });
      } else {
        authCompletedRef.current = true;
        await setWebCookieSession();
      }
    } catch {
      if (authCompletedRef.current) return;
      authCompletedRef.current = true;
      await setWebCookieSession();
    }
  }, [setBearerSession, setWebCookieSession]);

  if (!url && !provider) {
    return (
      <View style={styles.container}>
        <Text style={styles.errorText}>No auth URL or provider specified</Text>
      </View>
    );
  }

  // Show loading screen while resolving OAuth URL (provider mode)
  if (!source) {
    return (
      <View style={styles.container}>
        <View style={styles.topBar}>
          <Pressable style={styles.backButton} onPress={() => router.back()}>
            <Text style={styles.backButtonText}>Back</Text>
          </Pressable>
          <Text style={styles.topBarTitle}>Sign in</Text>
        </View>
        <View style={styles.loadingPill}>
          <ActivityIndicator size="small" color="#111827" />
          <Text style={styles.loadingText}>Connecting to provider...</Text>
        </View>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <WebView
        ref={webViewRef}
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
        onMessage={handleMessage}
        onNavigationStateChange={(navigationState) => {
          const currentUrl = navigationState.url;

          // If we landed on an authenticated page, auth succeeded via cookies.
          // Extract a bearer token from the session endpoint for native TRPC calls.
          if (isSignedInPath(currentUrl, env.webUrl)) {
            completeCookieAuth(currentUrl).catch(() => {
              setErrorMessage('Could not complete sign-in.');
            });
          }

          // Detect errors on login page redirect
          if (isLoginPath(currentUrl, env.webUrl)) {
            if (currentUrl.includes('error=')) {
              setErrorMessage('Sign-in failed. Please try again.');
            }
          }
        }}
        onShouldStartLoadWithRequest={(request) => {
          const requestUrl = request.url;

          // Handle todus:// deep link scheme (safety net)
          if (requestUrl.startsWith('todus://')) {
            const callback = parseAuthCallback(requestUrl);
            if (callback.token) {
              completeBearerAuth(callback.token, callback.expiresAt).catch(() => {
                setErrorMessage('Could not store authentication token.');
              });
            }
            return false;
          }

          // Check if any HTTP/HTTPS callback contains a bearer token
          const callback = parseAuthCallback(requestUrl);
          if (callback.token) {
            completeBearerAuth(callback.token, callback.expiresAt).catch(() => {
              setErrorMessage('Could not store authentication token.');
            });
            return false;
          }

          // Allow all HTTP/HTTPS navigations during the OAuth flow.
          // The WebView navigates to various OAuth provider domains
          // (accounts.google.com, login.microsoftonline.com, etc.)
          try {
            const parsed = new URL(requestUrl);
            if (parsed.protocol === 'https:' || parsed.protocol === 'http:') {
              return true;
            }
          } catch {
            // Invalid URL — block
          }

          return false;
        }}
      />

      {/* Top bar with back button */}
      <View style={styles.topBar}>
        <Pressable style={styles.backButton} onPress={() => router.back()}>
          <Text style={styles.backButtonText}>Back</Text>
        </Pressable>
        <Text style={styles.topBarTitle}>Sign in</Text>
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
