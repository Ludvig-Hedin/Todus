import { StatusBar } from 'expo-status-bar';
import { useCallback, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Linking,
  Pressable,
  StyleSheet,
  Text,
  View,
  useColorScheme,
} from 'react-native';
import { WebView } from 'react-native-webview';

const WEB_BASE_URL =
  process.env.EXPO_PUBLIC_WEB_URL ?? 'https://zero-production.ludvighedin15.workers.dev';
const BACKEND_URL =
  process.env.EXPO_PUBLIC_BACKEND_URL ??
  'https://zero-server-v1-production.ludvighedin15.workers.dev';
const APP_ENTRY_URL = process.env.EXPO_PUBLIC_APP_ENTRY_URL ?? `${WEB_BASE_URL}/mail/inbox`;

const ALLOWED_AUTH_HOSTS = new Set([
  new URL(WEB_BASE_URL).host,
  new URL(BACKEND_URL).host,
  'accounts.google.com',
  'oauth2.googleapis.com',
]);

const isAllowedInWebView = (url: string) => {
  if (url === 'about:blank') return true;
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') return false;
    return ALLOWED_AUTH_HOSTS.has(parsed.host);
  } catch {
    return false;
  }
};

export default function App() {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';
  const webviewRef = useRef<WebView>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [hasError, setHasError] = useState(false);

  const handleShouldStartLoadWithRequest = useCallback((request: { url: string }) => {
    const requestedUrl = request.url;
    if (isAllowedInWebView(requestedUrl)) {
      return true;
    }

    Linking.openURL(requestedUrl).catch(() => {
      // Ignore failures when opening external URLs.
    });
    return false;
  }, []);

  const handleRetry = useCallback(() => {
    setHasError(false);
    setIsLoading(true);
    webviewRef.current?.reload();
  }, []);

  const resolvedTheme = isDark ? 'dark' : 'light';
  const injectedThemeSync = `
    try {
      var currentTheme = localStorage.getItem('theme');
      if (!currentTheme || currentTheme === 'system') {
        localStorage.setItem('theme', '${resolvedTheme}');
      }
      document.documentElement.style.colorScheme = '${resolvedTheme}';
    } catch (e) {}
    true;
  `;

  return (
    <View style={[styles.container, isDark ? styles.containerDark : styles.containerLight]}>
      <WebView
        ref={webviewRef}
        source={{ uri: APP_ENTRY_URL }}
        style={[styles.webView, isDark ? styles.webViewDark : styles.webViewLight]}
        onLoadStart={() => setIsLoading(true)}
        onLoadEnd={() => setIsLoading(false)}
        onError={() => {
          setHasError(true);
          setIsLoading(false);
        }}
        onShouldStartLoadWithRequest={handleShouldStartLoadWithRequest}
        sharedCookiesEnabled
        thirdPartyCookiesEnabled
        setSupportMultipleWindows={false}
        allowsBackForwardNavigationGestures
        pullToRefreshEnabled
        refreshControlLightMode
        automaticallyAdjustContentInsets={false}
        contentInsetAdjustmentBehavior="never"
        bounces={false}
        forceDarkOn={isDark}
        injectedJavaScriptBeforeContentLoaded={injectedThemeSync}
        startInLoadingState
      />

      {isLoading && !hasError ? (
        <View style={[styles.loadingOverlay, isDark ? styles.loadingOverlayDark : styles.loadingOverlayLight]}>
          <ActivityIndicator size="small" color={isDark ? '#e5e7eb' : '#111827'} />
          <Text style={[styles.loadingText, isDark ? styles.loadingTextDark : styles.loadingTextLight]}>
            Loading Todus...
          </Text>
        </View>
      ) : null}

      {hasError ? (
        <View style={[styles.errorOverlay, isDark ? styles.errorOverlayDark : styles.errorOverlayLight]}>
          <Text style={[styles.errorTitle, isDark ? styles.errorTitleDark : styles.errorTitleLight]}>
            Could not load the app
          </Text>
          <Text style={[styles.errorBody, isDark ? styles.errorBodyDark : styles.errorBodyLight]}>
            Check your internet connection and try again.
          </Text>
          <Pressable
            style={[styles.retryButton, isDark ? styles.retryButtonDark : styles.retryButtonLight]}
            onPress={handleRetry}
          >
            <Text style={[styles.retryButtonText, isDark ? styles.retryButtonTextDark : styles.retryButtonTextLight]}>
              Retry
            </Text>
          </Pressable>
        </View>
      ) : null}

      <StatusBar style={isDark ? 'light' : 'dark'} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  containerDark: { backgroundColor: '#0b0f14' },
  containerLight: { backgroundColor: '#f5f6f7' },
  webView: {
    flex: 1,
  },
  webViewDark: { backgroundColor: '#0b0f14' },
  webViewLight: { backgroundColor: '#f5f6f7' },
  loadingOverlay: {
    position: 'absolute',
    top: 12,
    alignSelf: 'center',
    borderRadius: 10,
    backgroundColor: '#ffffff',
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderWidth: 1,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  loadingOverlayDark: {
    backgroundColor: '#111827',
    borderColor: '#374151',
  },
  loadingOverlayLight: {
    backgroundColor: '#ffffff',
    borderColor: '#e5e7eb',
  },
  loadingText: {
    fontSize: 13,
    fontWeight: '500',
  },
  loadingTextDark: { color: '#e5e7eb' },
  loadingTextLight: { color: '#111827' },
  errorOverlay: {
    position: 'absolute',
    left: 16,
    right: 16,
    top: '38%',
    borderRadius: 12,
    borderWidth: 1,
    padding: 16,
    gap: 10,
  },
  errorOverlayDark: {
    borderColor: '#374151',
    backgroundColor: '#111827',
  },
  errorOverlayLight: {
    borderColor: '#e5e7eb',
    backgroundColor: '#ffffff',
  },
  errorTitle: {
    fontSize: 16,
    fontWeight: '600',
  },
  errorTitleDark: { color: '#f3f4f6' },
  errorTitleLight: { color: '#111827' },
  errorBody: {
    fontSize: 14,
    lineHeight: 20,
  },
  errorBodyDark: { color: '#d1d5db' },
  errorBodyLight: { color: '#374151' },
  retryButton: {
    alignSelf: 'flex-start',
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  retryButtonDark: {
    backgroundColor: '#f3f4f6',
  },
  retryButtonLight: {
    backgroundColor: '#111827',
  },
  retryButtonText: {
    fontSize: 14,
    fontWeight: '600',
  },
  retryButtonTextDark: {
    color: '#111827',
  },
  retryButtonTextLight: {
    color: '#ffffff',
  },
});
