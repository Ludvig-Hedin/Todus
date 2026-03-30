/**
 * 404 screen — shown when no route matches.
 */
import { useRouter } from 'expo-router';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { useTheme } from '../src/shared/theme/ThemeContext';

export default function NotFoundScreen() {
  const router = useRouter();
  const { colors } = useTheme();

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <Text style={[styles.title, { color: colors.foreground }]}>Page Not Found</Text>
      <Text style={[styles.subtitle, { color: colors.mutedForeground }]}>
        This screen doesn't exist.
      </Text>
      <Pressable
        style={[styles.button, { backgroundColor: colors.primary }]}
        onPress={() => router.replace('/(app)/(mail)/inbox')}
      >
        <Text style={[styles.buttonText, { color: colors.primaryForeground }]}>Go to Inbox</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
    gap: 12,
  },
  title: {
    fontSize: 24,
    fontWeight: '700',
  },
  subtitle: {
    fontSize: 16,
    textAlign: 'center',
  },
  button: {
    paddingHorizontal: 24,
    paddingVertical: 12,
    borderRadius: 8,
    marginTop: 16,
  },
  buttonText: {
    fontSize: 16,
    fontWeight: '600',
  },
});
