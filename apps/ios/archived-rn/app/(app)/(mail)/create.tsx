import { ActivityIndicator, StyleSheet, Text, View } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useTheme } from '../../../src/shared/theme/ThemeContext';
import { useEffect, useRef } from 'react';

type CreateParams = {
  to?: string | string[];
  subject?: string | string[];
  body?: string | string[];
};

function firstParam(value: string | string[] | undefined): string | undefined {
  if (!value) return undefined;
  if (Array.isArray(value)) return value[0];
  return value;
}

export default function MailCreateScreen() {
  const { colors } = useTheme();
  const router = useRouter();
  const params = useLocalSearchParams<CreateParams>();
  const hasRedirectedRef = useRef(false);

  useEffect(() => {
    if (hasRedirectedRef.current) return;
    hasRedirectedRef.current = true;

    const to = firstParam(params.to);
    const subject = firstParam(params.subject);
    const body = firstParam(params.body);

    router.replace({
      pathname: '/compose',
      params: {
        ...(to ? { to } : {}),
        ...(subject ? { subject } : {}),
        ...(body ? { body } : {}),
      },
    });
  }, [params.body, params.subject, params.to, router]);

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <ActivityIndicator color={colors.primary} />
      <Text style={[styles.label, { color: colors.mutedForeground }]}>Opening compose...</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 12,
  },
  label: {
    fontSize: 14,
  },
});
