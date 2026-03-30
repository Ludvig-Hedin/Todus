import { ActivityIndicator, StyleSheet, Text, View } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useMutation } from '@tanstack/react-query';
import { useTheme } from '../../src/shared/theme/ThemeContext';
import { authStatusAtom } from '../../src/shared/state/session';
import { useTRPC } from '../../src/providers/QueryTrpcProvider';
import { useAtomValue } from 'jotai';
import { useEffect, useMemo, useRef } from 'react';
import {
  buildComposePrefillParams,
  buildDraftInputFromMailto,
  getFirstQueryValue,
  parseMailtoUrl,
} from '../../src/features/compose/mailtoParity';

export default function MailtoHandlerScreen() {
  const router = useRouter();
  const trpc = useTRPC();
  const { colors } = useTheme();
  const authStatus = useAtomValue(authStatusAtom);
  const hasHandledRef = useRef(false);
  const params = useLocalSearchParams<{ mailto?: string | string[] }>();
  const mailtoParam = useMemo(() => getFirstQueryValue(params.mailto), [params.mailto]);
  const { mutateAsync: createDraft } = useMutation(trpc.drafts.create.mutationOptions());

  useEffect(() => {
    if (hasHandledRef.current) return;
    if (authStatus === 'bootstrapping') return;

    if (authStatus !== 'authenticated') {
      hasHandledRef.current = true;
      router.replace('/(auth)/login');
      return;
    }

    const handleMailto = async () => {
      if (!mailtoParam) {
        hasHandledRef.current = true;
        router.replace('/compose');
        return;
      }

      const parsed = parseMailtoUrl(mailtoParam);
      if (!parsed) {
        hasHandledRef.current = true;
        router.replace('/compose');
        return;
      }

      let draftId: string | undefined;
      try {
        const result = (await createDraft(buildDraftInputFromMailto(parsed) as any)) as {
          id?: string | null;
        };
        if (result?.id) {
          draftId = result.id;
        }
      } catch {
        draftId = undefined;
      }

      hasHandledRef.current = true;
      router.replace({
        pathname: '/compose',
        params: buildComposePrefillParams(parsed, draftId),
      });
    };

    void handleMailto();
  }, [authStatus, createDraft, mailtoParam, router]);

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <ActivityIndicator size="large" color={colors.primary} />
      <Text style={[styles.label, { color: colors.mutedForeground }]}>Preparing compose draft...</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 10,
    paddingHorizontal: 20,
  },
  label: {
    fontSize: 14,
    textAlign: 'center',
  },
});
