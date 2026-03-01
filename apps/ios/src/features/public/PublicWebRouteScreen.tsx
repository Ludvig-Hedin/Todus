import { ActivityIndicator, Pressable, StyleSheet, Text, View } from 'react-native';
import { useTheme } from '../../shared/theme/ThemeContext';
import { WebView } from 'react-native-webview';
import { getNativeEnv } from '../../shared/config/env';
import { useRouter } from 'expo-router';
import { useState } from 'react';

type PublicWebRouteScreenProps = {
  path: string;
  title: string;
};

export function PublicWebRouteScreen({ path, title }: PublicWebRouteScreenProps) {
  const env = getNativeEnv();
  const router = useRouter();
  const { colors } = useTheme();
  const [isLoading, setIsLoading] = useState(true);

  const targetUri = `${env.webUrl.replace(/\/$/, '')}${path}`;

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <WebView
        source={{ uri: targetUri }}
        userAgent={env.userAgent}
        startInLoadingState
        onLoadStart={() => setIsLoading(true)}
        onLoadEnd={() => setIsLoading(false)}
        sharedCookiesEnabled
        thirdPartyCookiesEnabled
      />

      <View style={[styles.topBar, { borderBottomColor: colors.border, backgroundColor: colors.card }]}>
        <Text style={[styles.title, { color: colors.foreground }]}>{title}</Text>
        <Pressable
          style={[styles.signInButton, { borderColor: colors.border }]}
          onPress={() => router.push('/(auth)/login')}
        >
          <Text style={[styles.signInText, { color: colors.foreground }]}>Sign in</Text>
        </Pressable>
      </View>

      {isLoading && (
        <View style={[styles.loadingPill, { backgroundColor: colors.card, borderColor: colors.border }]}>
          <ActivityIndicator size="small" color={colors.primary} />
          <Text style={[styles.loadingText, { color: colors.foreground }]}>Loading page...</Text>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  topBar: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    zIndex: 10,
    borderBottomWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  title: {
    fontSize: 15,
    fontWeight: '700',
  },
  signInButton: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 8,
    paddingHorizontal: 10,
    paddingVertical: 6,
  },
  signInText: {
    fontSize: 13,
    fontWeight: '600',
  },
  loadingPill: {
    position: 'absolute',
    bottom: 20,
    left: 20,
    right: 20,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 8,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
  },
  loadingText: {
    fontSize: 13,
    fontWeight: '500',
  },
});
