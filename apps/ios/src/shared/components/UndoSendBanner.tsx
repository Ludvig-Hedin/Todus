import { Alert, Pressable, StyleSheet, Text, View } from 'react-native';
import { useMutation } from '@tanstack/react-query';
import { useRouter } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTRPC } from '../../providers/QueryTrpcProvider';
import { useTheme } from '../theme/ThemeContext';
import { useAtom } from 'jotai';
import { useEffect, useMemo, useState } from 'react';
import { pendingUndoSendAtom, undoComposePrefillAtom } from '../state/undoSend';

export function UndoSendBanner() {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const trpc = useTRPC();
  const [pendingUndoSend, setPendingUndoSend] = useAtom(pendingUndoSendAtom);
  const [, setUndoComposePrefill] = useAtom(undoComposePrefillAtom);
  const [remainingMs, setRemainingMs] = useState(0);

  const unsendMutation = useMutation(trpc.mail.unsend.mutationOptions());

  useEffect(() => {
    if (!pendingUndoSend) {
      setRemainingMs(0);
      return;
    }

    const tick = () => {
      const nextRemaining = Math.max(0, pendingUndoSend.sendAt - Date.now());
      setRemainingMs(nextRemaining);
      if (nextRemaining <= 0) {
        setPendingUndoSend(null);
      }
    };

    tick();
    const interval = setInterval(tick, 250);
    return () => clearInterval(interval);
  }, [pendingUndoSend, setPendingUndoSend]);

  const countdownSeconds = useMemo(() => Math.ceil(remainingMs / 1000), [remainingMs]);

  if (!pendingUndoSend || countdownSeconds <= 0) {
    return null;
  }

  const handleUndo = async () => {
    try {
      await unsendMutation.mutateAsync({ messageId: pendingUndoSend.messageId });

      if (!pendingUndoSend.wasUserScheduled && pendingUndoSend.payload) {
        setUndoComposePrefill(pendingUndoSend.payload);
        router.push('/compose');
      }
      setPendingUndoSend(null);
    } catch (error: any) {
      Alert.alert(
        'Undo failed',
        error?.message ||
          (pendingUndoSend.wasUserScheduled
            ? 'Could not cancel scheduled email.'
            : 'Could not cancel sent email.'),
      );
    }
  };

  return (
    <View
      style={[
        styles.container,
        {
          bottom: insets.bottom + 12,
          backgroundColor: colors.card,
          borderColor: colors.border,
        },
      ]}
    >
      <Text style={[styles.label, { color: colors.foreground }]}>
        {pendingUndoSend.wasUserScheduled ? 'Email scheduled' : 'Email sent'}
      </Text>
      <Text style={[styles.timer, { color: colors.mutedForeground }]}>{countdownSeconds}s</Text>
      <Pressable
        style={[styles.undoButton, { backgroundColor: colors.primary }]}
        onPress={handleUndo}
        disabled={unsendMutation.isPending}
      >
        <Text style={[styles.undoText, { color: colors.primaryForeground }]}>
          {unsendMutation.isPending ? 'Undoing...' : 'Undo'}
        </Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    left: 12,
    right: 12,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 14,
    paddingHorizontal: 14,
    paddingVertical: 10,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.15,
    shadowRadius: 4,
    elevation: 3,
  },
  label: {
    fontSize: 14,
    fontWeight: '600',
    flex: 1,
  },
  timer: {
    fontSize: 12,
    fontWeight: '500',
  },
  undoButton: {
    borderRadius: 8,
    paddingHorizontal: 10,
    paddingVertical: 6,
  },
  undoText: {
    fontSize: 13,
    fontWeight: '700',
  },
});
