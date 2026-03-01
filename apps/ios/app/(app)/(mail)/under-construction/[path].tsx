import { Pressable, StyleSheet, Text, View } from 'react-native';
import { useTheme } from '../../../../src/shared/theme/ThemeContext';
import { useLocalSearchParams, useRouter } from 'expo-router';

export default function UnderConstructionScreen() {
  const { colors } = useTheme();
  const router = useRouter();
  const { path } = useLocalSearchParams<{ path: string }>();

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <Text style={[styles.title, { color: colors.foreground }]}>Under Construction</Text>
      <Text style={[styles.subtitle, { color: colors.mutedForeground }]}>
        `{path}` is not available in native yet.
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
    paddingHorizontal: 24,
    gap: 10,
  },
  title: {
    fontSize: 22,
    fontWeight: '700',
  },
  subtitle: {
    fontSize: 14,
    textAlign: 'center',
  },
  button: {
    marginTop: 10,
    borderRadius: 10,
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  buttonText: {
    fontSize: 14,
    fontWeight: '700',
  },
});
