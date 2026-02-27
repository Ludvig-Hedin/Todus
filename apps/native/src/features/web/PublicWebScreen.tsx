import { useMemo } from 'react';
import { Linking, StyleSheet, Text, View } from 'react-native';
import { WebView } from 'react-native-webview';
import { getNativeEnv } from '../../shared/config/env';
import { isAllowedWebUrl } from '../auth/native-auth';

export function PublicWebScreen({ route }: any) {
  const env = getNativeEnv();
  const sourceUrl = useMemo(
    () => `${env.webUrl.replace(/\/$/, '')}${route.params.path}`,
    [env.webUrl, route.params.path],
  );

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>{route.params.title}</Text>
      </View>
      <WebView
        source={{ uri: sourceUrl }}
        userAgent={env.userAgent}
        onShouldStartLoadWithRequest={(request) => {
          if (isAllowedWebUrl(request.url, env.allowedHosts)) {
            return true;
          }

          Linking.openURL(request.url).catch(() => {
            // No-op: ignore inability to open third-party deep links.
          });
          return false;
        }}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  header: {
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderColor: '#d4d4d8',
    paddingHorizontal: 14,
    paddingVertical: 10,
    backgroundColor: '#ffffff',
  },
  title: {
    fontSize: 16,
    fontWeight: '600',
    color: '#111827',
  },
});
