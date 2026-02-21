import { StatusBar } from 'expo-status-bar';
import { useCallback, useRef, useState } from 'react';
import { ActivityIndicator, Linking, Pressable, SafeAreaView, StyleSheet, Text, View } from 'react-native';
import { WebView } from 'react-native-webview';

const APP_URL = process.env.EXPO_PUBLIC_WEB_URL ?? 'https://0.email';

export default function App() {
  const webviewRef = useRef<WebView>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [hasError, setHasError] = useState(false);

  const handleShouldStartLoadWithRequest = useCallback((request: { url: string }) => {
    const requestedUrl = request.url;
    if (requestedUrl.startsWith(APP_URL) || requestedUrl === 'about:blank') {
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
    <SafeAreaView style={styles.container}>
      <WebView
        ref={webviewRef}
        source={{ uri: APP_URL }}
        onLoadStart={() => setIsLoading(true)}
        onLoadEnd={() => setIsLoading(false)}
        onError={() => {
          setHasError(true);
          setIsLoading(false);
        }}
        onShouldStartLoadWithRequest={handleShouldStartLoadWithRequest}
        sharedCookiesEnabled
        thirdPartyCookiesEnabled
        allowsBackForwardNavigationGestures
        pullToRefreshEnabled
        refreshControlLightMode
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
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#ffffff',
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
