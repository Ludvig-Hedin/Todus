import { StatusBar } from 'expo-status-bar';
import { useCallback, useRef, useState } from 'react';
import { ActivityIndicator, Linking, Pressable, StyleSheet, Text, View } from 'react-native';
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

  return (
    <View style={styles.container}>
      <WebView
        ref={webviewRef}
        source={{ uri: APP_ENTRY_URL }}
        style={styles.webView}
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
        startInLoadingState
      />

      {isLoading && !hasError ? (
        <View style={styles.loadingOverlay}>
          <ActivityIndicator size="small" color="#111827" />
          <Text style={styles.loadingText}>Loading Zero Mail...</Text>
        </View>
      ) : null}

      {hasError ? (
        <View style={styles.errorOverlay}>
          <Text style={styles.errorTitle}>Could not load the app</Text>
          <Text style={styles.errorBody}>Check your internet connection and try again.</Text>
          <Pressable style={styles.retryButton} onPress={handleRetry}>
            <Text style={styles.retryButtonText}>Retry</Text>
          </Pressable>
        </View>
      ) : null}

      <StatusBar style="dark" />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0b0f14',
  },
  webView: {
    flex: 1,
    backgroundColor: '#0b0f14',
  },
  loadingOverlay: {
    position: 'absolute',
    top: 12,
    alignSelf: 'center',
    borderRadius: 10,
    backgroundColor: '#ffffff',
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderWidth: 1,
    borderColor: '#e5e7eb',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  loadingText: {
    color: '#111827',
    fontSize: 13,
    fontWeight: '500',
  },
  errorOverlay: {
    position: 'absolute',
    left: 16,
    right: 16,
    top: '38%',
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#e5e7eb',
    backgroundColor: '#ffffff',
    padding: 16,
    gap: 10,
  },
  errorTitle: {
    color: '#111827',
    fontSize: 16,
    fontWeight: '600',
  },
  errorBody: {
    color: '#374151',
    fontSize: 14,
    lineHeight: 20,
  },
  retryButton: {
    alignSelf: 'flex-start',
    borderRadius: 8,
    backgroundColor: '#111827',
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  retryButtonText: {
    color: '#ffffff',
    fontSize: 14,
    fontWeight: '600',
  },
});
