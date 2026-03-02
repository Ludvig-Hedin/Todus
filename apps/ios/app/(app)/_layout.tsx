/**
 * App group layout — Gmail-style drawer navigation.
 * The drawer sidebar shows mail folders and settings link.
 */
import { Platform, StyleSheet, useWindowDimensions } from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { identifyPostHog } from '../../src/shared/telemetry/posthog';
import { MailSidebar } from '../../src/features/mail/MailSidebar';
import { getNativeEnv } from '../../src/shared/config/env';
import { useTRPC } from '../../src/providers/QueryTrpcProvider';
import { UndoSendBanner } from '../../src/shared/components/UndoSendBanner';
import { useTheme } from '../../src/shared/theme/ThemeContext';
import { useQuery } from '@tanstack/react-query';
import { Drawer } from 'expo-router/drawer';
import { useEffect } from 'react';

export default function AppLayout() {
  const { colors } = useTheme();
  const { width } = useWindowDimensions();
  const isWideLayout = Platform.OS === 'macos' || width >= 768;
  const env = getNativeEnv();
  const trpc = useTRPC();
  const defaultConnectionQuery = useQuery({
    ...trpc.connections.getDefault.queryOptions(),
    enabled: !env.authBypassEnabled,
  });

  useEffect(() => {
    const defaultConnection = defaultConnectionQuery.data as any;
    if (!defaultConnection?.id) return;

    identifyPostHog(`connection:${defaultConnection.id}`, {
      email: defaultConnection.email ?? null,
      provider: defaultConnection.providerId ?? null,
    });
  }, [defaultConnectionQuery.data]);

  return (
    <GestureHandlerRootView style={styles.root}>
      <>
        <Drawer
          drawerContent={(props) => <MailSidebar {...props} />}
          screenOptions={{
            headerShown: false,
            drawerType: isWideLayout ? 'permanent' : 'front',
            swipeEnabled: !isWideLayout,
            drawerStyle: {
              backgroundColor: colors.background,
              width: 280,
            },
            sceneStyle: {
              backgroundColor: colors.background,
            },
          }}
        >
          <Drawer.Screen name="(mail)" options={{ drawerLabel: 'Mail' }} />
          <Drawer.Screen name="assistant" options={{ drawerLabel: 'Assistant' }} />
          <Drawer.Screen name="settings" options={{ drawerLabel: 'Settings' }} />
        </Drawer>
        <UndoSendBanner />
      </>
    </GestureHandlerRootView>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
  },
});
