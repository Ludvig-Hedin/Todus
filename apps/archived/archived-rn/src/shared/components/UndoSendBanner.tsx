import { pendingUndoSendAtom, undoComposePrefillAtom } from '../state/undoSend';
import { Alert, Pressable, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTRPC } from '../../providers/QueryTrpcProvider';
import { useEffect, useMemo, useState } from 'react';
import { useMutation } from '@tanstack/react-query';
import { useTheme } from '../theme/ThemeContext';
import { useRouter } from 'expo-router';
import { useAtom } from 'jotai';

export function UndoSendBanner() {
  const { colors, ui } = useTheme();
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
          backgroundColor: ui.surfaceRaised,
          borderColor: ui.borderSubtle,
          shadowColor: ui.shadow,
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
    borderRadius: 18,
    paddingHorizontal: 14,
    paddingVertical: 11,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    shadowOffset: { width: 0, height: 12 },
    shadowOpacity: 0.12,
    shadowRadius: 22,
    elevation: 4,
  },
  label: {
    fontSize: 13,
    fontWeight: '600',
    flex: 1,
    letterSpacing: -0.1,
  },
  timer: {
    fontSize: 11,
    fontWeight: '500',
  },
  undoButton: {
    borderRadius: 10,
    paddingHorizontal: 11,
    paddingVertical: 7,
  },
  undoText: {
    fontSize: 12,
    fontWeight: '700',
  },
});
