import { Construction } from 'lucide-react-native';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { useTheme } from '../../../../src/shared/theme/ThemeContext';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useMemo } from 'react';

export default function UnderConstructionScreen() {
  const { colors } = useTheme();
  const router = useRouter();
  const { path } = useLocalSearchParams<{ path: string }>();
  const decodedPath = useMemo(() => {
    if (!path) return 'this route';
    try {
      return decodeURIComponent(path);
    } catch {
      return path;
    }
  }, [path]);

  const handleGoBack = () => {
    if (router.canGoBack()) {
      router.back();
      return;
    }
    router.replace('/(app)/(mail)/inbox');
  };

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <Construction size={56} color={colors.mutedForeground} />
      <Text style={[styles.title, { color: colors.foreground }]}>Under Construction</Text>
      <Text style={[styles.subtitle, { color: colors.mutedForeground }]}>
        The {decodedPath} page is currently under construction.
      </Text>
      <View style={styles.actions}>
        <Pressable
          style={[styles.secondaryButton, { borderColor: colors.border, backgroundColor: colors.secondary }]}
          onPress={handleGoBack}
        >
          <Text style={[styles.secondaryButtonText, { color: colors.foreground }]}>Go Back</Text>
        </Pressable>
        <Pressable
          style={[styles.button, { backgroundColor: colors.primary }]}
          onPress={() => router.replace('/(app)/(mail)/inbox')}
        >
          <Text style={[styles.buttonText, { color: colors.primaryForeground }]}>Go to Inbox</Text>
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 24,
    gap: 12,
  },
  title: {
    fontSize: 22,
    fontWeight: '700',
  },
  subtitle: {
    fontSize: 14,
    textAlign: 'center',
  },
  actions: {
    marginTop: 10,
    flexDirection: 'row',
    gap: 10,
  },
  button: {
    borderRadius: 10,
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  buttonText: {
    fontSize: 14,
    fontWeight: '700',
  },
  secondaryButton: {
    borderRadius: 10,
    borderWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  secondaryButtonText: {
    fontSize: 14,
    fontWeight: '600',
  },
});
