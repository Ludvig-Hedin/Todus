/**
 * MessageCard — renders a single email message in the thread detail view.
 * Uses WebView for HTML email body rendering with auto-height adjustment.
 * CSP restricts email content from running scripts or loading external resources unsafely.
 */
import { WebView, type WebViewNavigation } from 'react-native-webview';
import { Linking, View, Text, StyleSheet } from 'react-native';
import { useTheme } from '../../shared/theme/ThemeContext';
import { SenderAvatar } from './SenderAvatar';
import React, { useCallback, useState } from 'react';
import { useRouter } from 'expo-router';

interface MessageCardProps {
  message: {
    id: string;
    sender?: { name?: string; email: string };
    receivedOn?: string;
    processedHtml?: string;
    body?: string;
    decodedBody?: string;
  };
}

export function MessageCard({ message }: MessageCardProps) {
  const { colors, ui, isDark } = useTheme();
  const router = useRouter();
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

  // Native thread responses currently carry the readable body in decodedBody.
  const htmlContent = message.processedHtml || message.body || message.decodedBody || '<p>No content</p>';

  // Open links in external browser instead of navigating within WebView
  const handleLinkPress = useCallback(
    (request: WebViewNavigation): boolean => {
      const { url } = request;
      // Allow initial about:blank and data: loads, block external navigation
      if (url === 'about:blank' || url.startsWith('data:')) return true;
      // Open http/https links in Safari
      if (url.startsWith('http://') || url.startsWith('https://')) {
        Linking.openURL(url).catch(() => { });
        return false;
      }
      if (url.startsWith('mailto:')) {
        router.push({
          pathname: '/api/mailto-handler',
          params: { mailto: url },
        });
        return false;
      }
      // Open other schemes via OS
      Linking.openURL(url).catch(() => { });
      return false;
    },
    [router],
  );

  // JS injected to normalize low-contrast email markup and measure the rendered height.
  const injectedJavaScript = `
    (function() {
      var APP_THEME = {
        isDark: ${JSON.stringify(isDark)},
        foreground: ${JSON.stringify(colors.foreground)},
        canvas: ${JSON.stringify(ui.canvas)},
        surface: ${JSON.stringify(ui.surface)}
      };

      function parseColor(value) {
        if (!value || value === 'transparent') return { r: 0, g: 0, b: 0, a: 0 };
        var rgbaMatch = value.match(/rgba?\\(([^)]+)\\)/i);
        if (rgbaMatch) {
          var parts = rgbaMatch[1].split(',').map(function(part) { return parseFloat(part.trim()); });
          return {
            r: parts[0] || 0,
            g: parts[1] || 0,
            b: parts[2] || 0,
            a: typeof parts[3] === 'number' ? parts[3] : 1
          };
        }
        var hex = value.replace('#', '').trim();
        if (hex.length === 3) {
          hex = hex.split('').map(function(char) { return char + char; }).join('');
        }
        if (hex.length === 6) {
          return {
            r: parseInt(hex.slice(0, 2), 16),
            g: parseInt(hex.slice(2, 4), 16),
            b: parseInt(hex.slice(4, 6), 16),
            a: 1
          };
        }
        return null;
      }

      function luminance(color) {
        if (!color) return 0;
        var channels = [color.r, color.g, color.b].map(function(channel) {
          var normalized = channel / 255;
          return normalized <= 0.03928
            ? normalized / 12.92
            : Math.pow((normalized + 0.055) / 1.055, 2.4);
        });
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
      }

      function contrastRatio(a, b) {
        var l1 = luminance(a);
        var l2 = luminance(b);
        var lighter = Math.max(l1, l2);
        var darker = Math.min(l1, l2);
        return (lighter + 0.05) / (darker + 0.05);
      }

      function shouldTreatAsLightBackground(color) {
        return color && color.a > 0.7 && luminance(color) > 0.9;
      }

      function shouldTreatAsLightText(color) {
        return color && color.a > 0.7 && luminance(color) > 0.85;
      }

      function isTransparent(color) {
        return !color || color.a < 0.05;
      }

      function normalizeEmailColors() {
        var canvasColor = parseColor(APP_THEME.canvas);
        var surfaceColor = parseColor(APP_THEME.surface);
        var foregroundColor = parseColor(APP_THEME.foreground);
        var elements = document.querySelectorAll('body, body *');

        elements.forEach(function(element) {
          if (!(element instanceof HTMLElement)) return;
          var computed = window.getComputedStyle(element);
          var textColor = parseColor(computed.color);
          var backgroundColor = parseColor(computed.backgroundColor);
          var hasLightBackground = shouldTreatAsLightBackground(backgroundColor);
          var lowContrastOnOwnBackground =
            textColor && backgroundColor && !isTransparent(backgroundColor)
              ? contrastRatio(textColor, backgroundColor) < 3.2
              : false;
          var lowContrastOnCanvas =
            textColor && (isTransparent(backgroundColor) || hasLightBackground)
              ? contrastRatio(textColor, APP_THEME.isDark ? canvasColor : surfaceColor) < 4
              : false;

          if (APP_THEME.isDark) {
            if (hasLightBackground && lowContrastOnOwnBackground) {
              element.style.setProperty('background-color', 'transparent', 'important');
              element.style.setProperty('background-image', 'none', 'important');
              element.style.setProperty('color', APP_THEME.foreground, 'important');
              return;
            }

            if ((isTransparent(backgroundColor) || hasLightBackground) && lowContrastOnCanvas) {
              element.style.setProperty('color', APP_THEME.foreground, 'important');
              return;
            }

            if (hasLightBackground && shouldTreatAsLightText(textColor)) {
              element.style.setProperty('background-color', 'transparent', 'important');
              element.style.setProperty('background-image', 'none', 'important');
            }
            return;
          }

          if (hasLightBackground && lowContrastOnOwnBackground) {
            element.style.setProperty('color', '#111111', 'important');
            return;
          }

          if ((isTransparent(backgroundColor) || hasLightBackground) && lowContrastOnCanvas) {
            element.style.setProperty('color', '#111111', 'important');
          }
        });
      }

      function reportHeight() {
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
      }

      function normalizeAndMeasure() {
        normalizeEmailColors();
        reportHeight();
      }

      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', normalizeAndMeasure, { once: true });
      } else {
        normalizeAndMeasure();
      }

      setTimeout(normalizeAndMeasure, 150);
      setTimeout(normalizeAndMeasure, 350);
    })();
    true;
  `;

  return (
    <View
      style={[
        styles.card,
        {
          backgroundColor: ui.surfaceMuted,
          borderColor: ui.borderSubtle,
        },
      ]}
    >
      <View style={styles.header}>
        <View style={styles.senderMeta}>
          <SenderAvatar email={senderEmail} name={senderName} size={34} />
          <View style={styles.senderContainer}>
            <Text style={[styles.senderName, { color: colors.foreground }]}>{senderName}</Text>
            {senderEmail && (
              <Text style={[styles.senderEmail, { color: colors.mutedForeground }]}>
                {senderEmail}
              </Text>
            )}
          </View>
        </View>
        {date ? (
          <View
            style={[
              styles.dateChip,
              { backgroundColor: ui.surfaceInset, borderColor: ui.borderSubtle },
            ]}
          >
            <Text style={[styles.date, { color: colors.mutedForeground }]}>{date}</Text>
          </View>
        ) : null}
      </View>

      <View style={styles.bodyWrap}>
        <WebView
          source={{
            html: `<!DOCTYPE html>
              <html style="color-scheme: ${isDark ? 'dark' : 'light'};">
              <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=yes">
              <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src https: data: cid:; font-src 'none';">
              <style>
                body {
                  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                  font-size: 13px;
                  line-height: 1.4;
                  color: ${colors.foreground};
                  background-color: transparent;
                  margin: 0;
                  padding: 0;
                  word-wrap: break-word;
                  overflow-wrap: break-word;
                  overflow-x: hidden;
                  max-width: 100%;
                }
                a { color: ${colors.primary}; }
                img, video, iframe { max-width: 100% !important; height: auto !important; }
                pre, code { overflow-x: auto; max-width: 100%; white-space: pre-wrap; }
                
                /* Reset for wide tables/elements causing overflow */
                table, div, section, main {
                  max-width: 100% !important;
                }
                
                * {
                  max-width: 100vw !important;
                }
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
          scalesPageToFit={true}
          showsVerticalScrollIndicator={false}
          showsHorizontalScrollIndicator={false}
          style={{ height: webViewHeight, width: '100%', backgroundColor: 'transparent' }}
          containerStyle={{ backgroundColor: 'transparent' }}
        />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    paddingHorizontal: 14,
    paddingVertical: 14,
    marginBottom: 14,
    gap: 14,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 24,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    gap: 12,
  },
  senderMeta: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  senderContainer: {
    flex: 1,
    gap: 2,
  },
  senderName: {
    fontSize: 13,
    lineHeight: 16,
    fontWeight: '600',
    letterSpacing: -0.18,
  },
  senderEmail: {
    fontSize: 11,
    lineHeight: 14,
    letterSpacing: -0.08,
  },
  dateChip: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 999,
    paddingHorizontal: 8,
    paddingVertical: 3,
  },
  date: {
    fontSize: 11,
    fontWeight: '600',
    letterSpacing: -0.08,
  },
  bodyWrap: {
    minHeight: 100,
    width: '100%',
    overflow: 'hidden',
    borderRadius: 20,
  },
});
