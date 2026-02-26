/**
 * MessageCard — renders a single email message in the thread detail view.
 * Uses WebView for HTML email body rendering with auto-height adjustment.
 * CSP restricts email content from running scripts or loading external resources unsafely.
 */
import React, { useCallback, useState } from 'react';
import { Linking, View, Text, StyleSheet } from 'react-native';
import { WebView, type WebViewNavigation } from 'react-native-webview';
import { useTheme } from '../../shared/theme/ThemeContext';

interface MessageCardProps {
  message: {
    id: string;
    sender?: { name?: string; email: string };
    receivedOn?: string;
    processedHtml?: string;
    body?: string;
  };
}

export function MessageCard({ message }: MessageCardProps) {
  const { colors } = useTheme();
  const [webViewHeight, setWebViewHeight] = useState(100);

  const senderName = message.sender?.name || message.sender?.email || 'Unknown';
  const senderEmail = message.sender?.email || '';
  const date = message.receivedOn
    ? new Date(message.receivedOn).toLocaleDateString([], {
        month: 'short',
        day: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
      })
    : '';

  // Use processedHtml if available, otherwise fall back to body
  const htmlContent = message.processedHtml || message.body || '<p>No content</p>';

  // Open links in external browser instead of navigating within WebView
  const handleLinkPress = useCallback((request: WebViewNavigation): boolean => {
    const { url } = request;
    // Allow initial about:blank and data: loads, block external navigation
    if (url === 'about:blank' || url.startsWith('data:')) return true;
    // Open http/https links in Safari
    if (url.startsWith('http://') || url.startsWith('https://')) {
      Linking.openURL(url).catch(() => {});
      return false;
    }
    // Open mailto: and other schemes via OS
    Linking.openURL(url).catch(() => {});
    return false;
  }, []);

  // JS injected to measure the rendered HTML content height
  const injectedJavaScript = `
    setTimeout(function() {
      window.ReactNativeWebView.postMessage(
        Math.max(
          document.body.scrollHeight,
          document.documentElement.scrollHeight,
          document.body.offsetHeight,
          document.documentElement.offsetHeight,
          document.body.clientHeight,
          document.documentElement.clientHeight
        ).toString()
      );
    }, 200);
    true;
  `;

  return (
    <View style={[styles.card, { backgroundColor: colors.background, borderColor: colors.border }]}>
      {/* Message header: sender + date */}
      <View style={styles.header}>
        <View style={styles.senderContainer}>
          <Text style={[styles.senderName, { color: colors.foreground }]}>{senderName}</Text>
          {senderEmail && (
            <Text style={[styles.senderEmail, { color: colors.mutedForeground }]}>
              {'<'}
              {senderEmail}
              {'>'}
            </Text>
          )}
        </View>
        <Text style={[styles.date, { color: colors.mutedForeground }]}>{date}</Text>
      </View>

      {/* HTML email body rendered in WebView with CSP to prevent XSS */}
      <View style={{ height: webViewHeight, width: '100%' }}>
        <WebView
          source={{
            html: `<!DOCTYPE html>
              <html><head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src https: data: cid:; font-src 'none';">
              <style>
                body {
                  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                  font-size: 15px;
                  line-height: 1.5;
                  color: ${colors.foreground};
                  background-color: ${colors.background};
                  margin: 0;
                  padding: 0;
                  word-wrap: break-word;
                  overflow-wrap: break-word;
                }
                a { color: ${colors.primary}; }
                img { max-width: 100%; height: auto; }
                pre, code { overflow-x: auto; max-width: 100%; }
              </style>
              </head><body>${htmlContent}</body></html>
            `,
          }}
          injectedJavaScript={injectedJavaScript}
          onMessage={(event) => {
            const height = parseInt(event.nativeEvent.data, 10);
            if (!isNaN(height) && height > 0) {
              setWebViewHeight(height);
            }
          }}
          onShouldStartLoadWithRequest={handleLinkPress}
          scrollEnabled={false}
          showsVerticalScrollIndicator={false}
          showsHorizontalScrollIndicator={false}
          style={{ flex: 1, backgroundColor: 'transparent' }}
          containerStyle={{ flex: 1, backgroundColor: 'transparent' }}
        />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    padding: 16,
    marginBottom: 16,
    gap: 16,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'baseline',
  },
  senderContainer: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'baseline',
    gap: 6,
    flexWrap: 'wrap',
  },
  senderName: {
    fontSize: 16,
    fontWeight: '600',
  },
  senderEmail: {
    fontSize: 13,
  },
  date: {
    fontSize: 13,
  },
});
