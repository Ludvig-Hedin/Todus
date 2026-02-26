/**
 * App group layout — Gmail-style drawer navigation.
 * The drawer sidebar shows mail folders and settings link.
 */
import { Drawer } from 'expo-router/drawer';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { StyleSheet } from 'react-native';
import { useTheme } from '../../src/shared/theme/ThemeContext';
import { MailSidebar } from '../../src/features/mail/MailSidebar';

export default function AppLayout() {
  const { colors } = useTheme();

  return (
    <GestureHandlerRootView style={styles.root}>
      <Drawer
        drawerContent={(props) => <MailSidebar {...props} />}
        screenOptions={{
          headerShown: false,
          drawerType: 'front',
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
        <Drawer.Screen name="settings" options={{ drawerLabel: 'Settings' }} />
      </Drawer>
    </GestureHandlerRootView>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
  },
});
