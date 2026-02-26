/**
 * Compose screen — full-screen modal for writing new emails or replying.
 * Supports new message, reply, reply-all, and forward modes.
 */
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import {
  Alert,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useTheme } from '../src/shared/theme/ThemeContext';
import { useTRPC } from '../src/providers/QueryTrpcProvider';
import { haptics } from '../src/shared/utils/haptics';

export default function ComposeScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<{ mode?: string; threadId?: string }>();
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const trpc = useTRPC();
  const queryClient = useQueryClient();

  const [to, setTo] = useState('');
  const [cc, setCc] = useState('');
  const [subject, setSubject] = useState('');
  const [body, setBody] = useState('');
  const [showCc, setShowCc] = useState(false);

  // If replying, fetch thread data to prefill fields
  const isReply = params.mode === 'reply' || params.mode === 'replyAll';
  const { data: threadData } = useQuery({
    ...trpc.mail.get.queryOptions({ id: params.threadId ?? '' }),
    enabled: !!params.threadId && isReply,
  });

  // Prefill reply fields from thread data (in useEffect to avoid setState during render)
  const hasPrefilledRef = useRef(false);
  useEffect(() => {
    if (isReply && threadData?.latest && !hasPrefilledRef.current) {
      hasPrefilledRef.current = true;
      const latest = threadData.latest;
      if (latest.sender?.email) {
        setTo(latest.sender.email);
      }
      if (latest.subject) {
        setSubject(latest.subject.startsWith('Re:') ? latest.subject : `Re: ${latest.subject}`);
      }
    }
  }, [isReply, threadData]);

  const sendMutation = useMutation({
    ...trpc.mail.send.mutationOptions(),
    onSuccess: () => {
      haptics.success();
      queryClient.invalidateQueries({ queryKey: trpc.mail.listThreads.queryKey() });
      router.back();
    },
    onError: (error) => {
      haptics.error();
      Alert.alert('Send Failed', error.message || 'Could not send the email. Please try again.');
    },
  });

  const handleSend = () => {
    if (!to.trim()) {
      Alert.alert('Missing Recipient', 'Please enter at least one recipient.');
      return;
    }

    sendMutation.mutate({
      to: to.split(',').map((email) => ({ email: email.trim() })),
      cc: cc ? cc.split(',').map((email) => ({ email: email.trim() })) : [],
      subject: subject.trim(),
      message: body.trim(),
      ...(params.threadId ? { threadId: params.threadId } : {}),
    } as any);
  };

  const isReplying = params.mode === 'reply' || params.mode === 'replyAll';
  const title = isReplying ? 'Reply' : params.mode === 'forward' ? 'Forward' : 'New Message';

  return (
    <KeyboardAvoidingView
      style={[styles.container, { backgroundColor: colors.background }]}
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
    >
      {/* Header */}
      <View style={[styles.header, { paddingTop: insets.top + 8, borderBottomColor: colors.border }]}>
        <Pressable onPress={() => router.back()}>
          <Text style={[styles.cancelText, { color: colors.primary }]}>Cancel</Text>
        </Pressable>
        <Text style={[styles.headerTitle, { color: colors.foreground }]}>{title}</Text>
        <Pressable
          style={[
            styles.sendButton,
            { backgroundColor: sendMutation.isPending ? colors.secondary : colors.primary },
          ]}
          onPress={handleSend}
          disabled={sendMutation.isPending}
        >
          <Text style={[styles.sendText, { color: colors.primaryForeground }]}>
            {sendMutation.isPending ? 'Sending...' : 'Send'}
          </Text>
        </Pressable>
      </View>

      {/* Compose form */}
      <View style={styles.form}>
        {/* To field */}
        <View style={[styles.fieldRow, { borderBottomColor: colors.border }]}>
          <Text style={[styles.fieldLabel, { color: colors.mutedForeground }]}>To:</Text>
          <TextInput
            style={[styles.fieldInput, { color: colors.foreground }]}
            placeholderTextColor={colors.mutedForeground}
            placeholder="Recipients"
            value={to}
            onChangeText={setTo}
            keyboardType="email-address"
            autoCapitalize="none"
            autoCorrect={false}
          />
          {!showCc && (
            <Pressable onPress={() => setShowCc(true)}>
              <Text style={[styles.ccToggle, { color: colors.mutedForeground }]}>Cc/Bcc</Text>
            </Pressable>
          )}
        </View>

        {/* CC field (optional) */}
        {showCc && (
          <View style={[styles.fieldRow, { borderBottomColor: colors.border }]}>
            <Text style={[styles.fieldLabel, { color: colors.mutedForeground }]}>Cc:</Text>
            <TextInput
              style={[styles.fieldInput, { color: colors.foreground }]}
              placeholderTextColor={colors.mutedForeground}
              placeholder="CC recipients"
              value={cc}
              onChangeText={setCc}
              keyboardType="email-address"
              autoCapitalize="none"
              autoCorrect={false}
            />
          </View>
        )}

        {/* Subject field */}
        <View style={[styles.fieldRow, { borderBottomColor: colors.border }]}>
          <Text style={[styles.fieldLabel, { color: colors.mutedForeground }]}>Subject:</Text>
          <TextInput
            style={[styles.fieldInput, { color: colors.foreground }]}
            placeholderTextColor={colors.mutedForeground}
            placeholder="Subject"
            value={subject}
            onChangeText={setSubject}
          />
        </View>

        {/* Body */}
        <View style={styles.bodyContainer}>
          <TextInput
            style={[styles.bodyInput, { color: colors.foreground }]}
            placeholderTextColor={colors.mutedForeground}
            placeholder="Write your message..."
            multiline
            textAlignVertical="top"
            value={body}
            onChangeText={setBody}
          />
        </View>
      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingBottom: 12,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  cancelText: {
    fontSize: 16,
  },
  headerTitle: {
    fontSize: 17,
    fontWeight: '600',
  },
  sendButton: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 8,
  },
  sendText: {
    fontSize: 15,
    fontWeight: '600',
  },
  form: {
    flex: 1,
  },
  fieldRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  fieldLabel: {
    fontSize: 15,
    width: 60,
  },
  fieldInput: {
    flex: 1,
    fontSize: 15,
    padding: 0,
  },
  ccToggle: {
    fontSize: 14,
    paddingLeft: 8,
  },
  bodyContainer: {
    flex: 1,
    padding: 16,
  },
  bodyInput: {
    flex: 1,
    fontSize: 15,
    lineHeight: 22,
  },
});
