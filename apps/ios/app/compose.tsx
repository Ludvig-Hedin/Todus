/**
 * Compose screen — full-screen modal for writing new emails or replying.
 * Supports new message, reply, reply-all, and forward modes.
 */
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
import { RichText, Toolbar, useEditorBridge, useEditorContent } from '@10play/tentap-editor';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { captureEvent } from '../src/shared/telemetry/posthog';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useTRPC } from '../src/providers/QueryTrpcProvider';
import { useEffect, useMemo, useRef, useState } from 'react';
import { useTheme } from '../src/shared/theme/ThemeContext';
import * as FileSystemLegacy from 'expo-file-system/legacy';
import * as DocumentPicker from 'expo-document-picker';
import { haptics } from '../src/shared/utils/haptics';

type SerializedAttachment = {
  name: string;
  type: string;
  size: number;
  lastModified: number;
  base64: string;
};

type DraftState = {
  to: string;
  cc: string;
  bcc: string;
  subject: string;
  message: string;
  attachments: SerializedAttachment[];
};

type SenderLike = {
  email?: string | null;
  name?: string | null;
};

export default function ComposeScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<{ mode?: string; threadId?: string }>();
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const trpc = useTRPC();
  const queryClient = useQueryClient();

  const [to, setTo] = useState('');
  const [cc, setCc] = useState('');
  const [bcc, setBcc] = useState('');
  const [subject, setSubject] = useState('');
  const [showCcBcc, setShowCcBcc] = useState(false);
  const [attachments, setAttachments] = useState<SerializedAttachment[]>([]);
  const editor = useEditorBridge({
    autofocus: false,
    avoidIosKeyboard: true,
    initialContent: '',
  });
  const editorHtml = useEditorContent(editor, { type: 'html', debounceInterval: 400 }) ?? '';
  const draftKey = useMemo(
    () => `compose-draft:${params.threadId ? `thread:${params.threadId}` : 'new'}`,
    [params.threadId],
  );

  // If replying/forwarding, fetch thread data to prefill fields
  const isReply = params.mode === 'reply' || params.mode === 'replyAll';
  const isReplyAll = params.mode === 'replyAll';
  const isForward = params.mode === 'forward';
  const defaultConnectionQuery = useQuery(trpc.connections.getDefault.queryOptions());

  const { data: threadData } = useQuery({
    ...trpc.mail.get.queryOptions({ id: params.threadId ?? '' }),
    enabled: !!params.threadId && (isReply || isForward),
  });

  // Prefill fields from thread data (in useEffect to avoid setState during render)
  const hasPrefilledRef = useRef(false);
  useEffect(() => {
    if (hasPrefilledRef.current) return;
    if (!threadData?.latest) return;
    if (!isReply && !isForward) return;
    if ((isReply || isReplyAll) && defaultConnectionQuery.isLoading) return;

    hasPrefilledRef.current = true;
    const latest = threadData.latest;
    const userEmail = ((defaultConnectionQuery.data as any)?.email as string | undefined)
      ?.trim()
      .toLowerCase();
    const senderEmail = latest.sender?.email?.trim() ?? '';
    const senderEmailNormalized = senderEmail.toLowerCase();
    const toRecipients = toEmailList(latest.to ?? []);
    const ccRecipients = toEmailList(latest.cc ?? []);

    if (isReplyAll) {
      const nextTo = uniqueEmails([
        ...(senderEmailNormalized && senderEmailNormalized !== userEmail ? [senderEmail] : []),
        ...toRecipients.filter((value) => {
          const normalized = value.toLowerCase();
          return normalized !== userEmail && normalized !== senderEmailNormalized;
        }),
      ]);
      const nextCc = uniqueEmails(
        ccRecipients.filter((value) => {
          const normalized = value.toLowerCase();
          if (normalized === userEmail) return false;
          return !nextTo.some((toValue) => toValue.toLowerCase() === normalized);
        }),
      );

      setTo(nextTo.join(', '));
      setCc(nextCc.join(', '));
      if (nextCc.length > 0) {
        setShowCcBcc(true);
      }
    } else if (isReply) {
      if (senderEmailNormalized && senderEmailNormalized !== userEmail) {
        setTo(senderEmail);
      } else {
        const fallbackRecipient =
          toRecipients.find((value) => value.toLowerCase() !== userEmail) ?? toRecipients[0] ?? '';
        setTo(fallbackRecipient);
      }
    } else if (isForward) {
      setTo('');
      setCc('');
      setBcc('');
    }

    if (latest.subject) {
      const replyPrefixRegex = /^re:/i;
      const forwardPrefixRegex = /^fwd:/i;

      if (isForward) {
        setSubject(
          forwardPrefixRegex.test(latest.subject) ? latest.subject : `Fwd: ${latest.subject}`,
        );
      } else if (isReply) {
        setSubject(
          replyPrefixRegex.test(latest.subject) ? latest.subject : `Re: ${latest.subject}`,
        );
      }
    }
  }, [defaultConnectionQuery.data, isForward, isReply, isReplyAll, threadData]);

  const hasRestoredDraftRef = useRef(false);
  const pendingSendEventRef = useRef<{ name: string; properties?: Record<string, unknown> } | null>(
    null,
  );
  useEffect(() => {
    if (hasRestoredDraftRef.current) return;
    hasRestoredDraftRef.current = true;

    const restoreDraft = async () => {
      try {
        const rawDraft = await AsyncStorage.getItem(draftKey);
        if (!rawDraft) return;

        const draft: DraftState = JSON.parse(rawDraft);
        setTo(draft.to ?? '');
        setCc(draft.cc ?? '');
        setBcc(draft.bcc ?? '');
        setSubject(draft.subject ?? '');
        setAttachments(draft.attachments ?? []);
        if ((draft.cc ?? '').trim() || (draft.bcc ?? '').trim()) {
          setShowCcBcc(true);
        }
        if (draft.message) {
          editor.setContent(draft.message);
        }
      } catch {
        // ignore corrupted draft payloads
      }
    };

    void restoreDraft();
  }, [draftKey, editor]);

  useEffect(() => {
    const draft: DraftState = {
      to,
      cc,
      bcc,
      subject,
      message: editorHtml,
      attachments,
    };
    const isEmpty =
      !draft.to.trim() &&
      !draft.cc.trim() &&
      !draft.bcc.trim() &&
      !draft.subject.trim() &&
      !stripHtml(draft.message).trim() &&
      draft.attachments.length === 0;

    const timer = setTimeout(async () => {
      if (isEmpty) {
        await AsyncStorage.removeItem(draftKey);
        return;
      }
      await AsyncStorage.setItem(draftKey, JSON.stringify(draft));
    }, 800);

    return () => clearTimeout(timer);
  }, [attachments, bcc, cc, draftKey, editorHtml, subject, to]);

  const sendMutation = useMutation({
    ...trpc.mail.send.mutationOptions(),
    onSuccess: async () => {
      if (pendingSendEventRef.current) {
        captureEvent(pendingSendEventRef.current.name, pendingSendEventRef.current.properties);
      }
      pendingSendEventRef.current = null;
      haptics.success();
      await AsyncStorage.removeItem(draftKey);
      queryClient.invalidateQueries({ queryKey: trpc.mail.listThreads.queryKey() });
      router.back();
    },
    onError: (error) => {
      pendingSendEventRef.current = null;
      haptics.error();
      Alert.alert('Send Failed', error.message || 'Could not send the email. Please try again.');
    },
  });

  const handleSend = async () => {
    if (!to.trim()) {
      Alert.alert('Missing Recipient', 'Please enter at least one recipient.');
      return;
    }

    const messageHtml = await editor.getHTML();
    const latestMessage = threadData?.latest;

    const toRecipients = to
      .split(',')
      .map((email) => email.trim())
      .filter(Boolean)
      .map((email) => ({ email }));
    const ccRecipients = cc
      ? cc
          .split(',')
          .map((email) => email.trim())
          .filter(Boolean)
          .map((email) => ({ email }))
      : [];
    const bccRecipients = bcc
      ? bcc
          .split(',')
          .map((email) => email.trim())
          .filter(Boolean)
          .map((email) => ({ email }))
      : [];

    const composedBody = buildThreadAwareBody({
      body: messageHtml?.trim() || '',
      mode: params.mode,
      latestMessage,
      recipients: toRecipients,
    });

    const references = [
      ...(latestMessage?.references ? latestMessage.references.split(' ') : []),
      latestMessage?.messageId,
    ]
      .filter(Boolean)
      .join(' ');

    pendingSendEventRef.current = getComposeSentEvent({
      mode: params.mode,
      hasCc: ccRecipients.length > 0,
      hasBcc: bccRecipients.length > 0,
    });

    sendMutation.mutate({
      to: toRecipients,
      cc: ccRecipients,
      bcc: bccRecipients,
      subject: subject.trim(),
      message: composedBody,
      attachments,
      headers:
        latestMessage && (isReply || isForward)
          ? {
              'In-Reply-To': latestMessage.messageId ?? '',
              References: references,
              'Thread-Id': latestMessage.threadId ?? '',
            }
          : undefined,
      isForward: isForward || undefined,
      originalMessage: latestMessage?.decodedBody || latestMessage?.body || undefined,
      ...(params.threadId ? { threadId: params.threadId } : {}),
    } as any);
  };

  const pickAttachments = async () => {
    try {
      const result = await DocumentPicker.getDocumentAsync({
        multiple: true,
        copyToCacheDirectory: true,
      });

      if (result.canceled || !result.assets) {
        return;
      }

      const nextAttachments: SerializedAttachment[] = [];
      for (const asset of result.assets) {
        const base64 = await FileSystemLegacy.readAsStringAsync(asset.uri, {
          encoding: FileSystemLegacy.EncodingType.Base64,
        });
        nextAttachments.push({
          name: asset.name,
          type: asset.mimeType || 'application/octet-stream',
          size: asset.size ?? 0,
          lastModified: asset.lastModified || Date.now(),
          base64,
        });
      }

      setAttachments((current) => [...current, ...nextAttachments]);
    } catch (error: any) {
      Alert.alert('Attachment failed', error?.message || 'Could not attach file.');
    }
  };

  const removeAttachment = (name: string, index: number) => {
    setAttachments((current) =>
      current.filter((attachment, attachmentIndex) => {
        return !(attachment.name === name && attachmentIndex === index);
      }),
    );
  };

  const isReplying = params.mode === 'reply' || params.mode === 'replyAll';
  const title = isReplying ? 'Reply' : params.mode === 'forward' ? 'Forward' : 'New Message';

  return (
    <KeyboardAvoidingView
      style={[styles.container, { backgroundColor: colors.background }]}
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
    >
      {/* Header */}
      <View
        style={[styles.header, { paddingTop: insets.top + 8, borderBottomColor: colors.border }]}
      >
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
          {!showCcBcc && (
            <Pressable onPress={() => setShowCcBcc(true)}>
              <Text style={[styles.ccToggle, { color: colors.mutedForeground }]}>Cc/Bcc</Text>
            </Pressable>
          )}
        </View>

        {/* CC/BCC fields (optional) */}
        {showCcBcc && (
          <>
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
            <View style={[styles.fieldRow, { borderBottomColor: colors.border }]}>
              <Text style={[styles.fieldLabel, { color: colors.mutedForeground }]}>Bcc:</Text>
              <TextInput
                style={[styles.fieldInput, { color: colors.foreground }]}
                placeholderTextColor={colors.mutedForeground}
                placeholder="BCC recipients"
                value={bcc}
                onChangeText={setBcc}
                keyboardType="email-address"
                autoCapitalize="none"
                autoCorrect={false}
              />
            </View>
          </>
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

        <View style={[styles.attachmentRow, { borderBottomColor: colors.border }]}>
          <Text style={[styles.fieldLabel, { color: colors.mutedForeground }]}>Attach:</Text>
          <Pressable
            style={[styles.attachmentButton, { backgroundColor: colors.secondary }]}
            onPress={pickAttachments}
          >
            <Text style={{ color: colors.secondaryForeground, fontWeight: '600' }}>Add File</Text>
          </Pressable>
        </View>

        {attachments.length > 0 && (
          <View style={[styles.attachmentsList, { borderBottomColor: colors.border }]}>
            {attachments.map((attachment, index) => (
              <View key={`${attachment.name}-${index}`} style={styles.attachmentItem}>
                <View style={styles.attachmentMeta}>
                  <Text style={[styles.attachmentName, { color: colors.foreground }]}>
                    {attachment.name}
                  </Text>
                  <Text style={[styles.attachmentSize, { color: colors.mutedForeground }]}>
                    {Math.max(1, Math.round(attachment.size / 1024))} KB
                  </Text>
                </View>
                <Pressable onPress={() => removeAttachment(attachment.name, index)}>
                  <Text style={{ color: colors.destructive, fontWeight: '600' }}>Remove</Text>
                </Pressable>
              </View>
            ))}
          </View>
        )}

        {/* Body */}
        <View style={styles.bodyContainer}>
          <RichText
            editor={editor}
            style={[
              styles.richText,
              {
                backgroundColor: colors.background,
                borderColor: colors.border,
              },
            ]}
          />
        </View>
        <View style={[styles.toolbarContainer, { borderTopColor: colors.border }]}>
          <Toolbar editor={editor} />
        </View>
      </View>
    </KeyboardAvoidingView>
  );
}

function stripHtml(value: string): string {
  return value.replace(/<[^>]*>/g, '');
}

function uniqueEmails(emails: string[]): string[] {
  const seen = new Set<string>();
  const deduped: string[] = [];
  for (const value of emails) {
    const trimmed = value.trim();
    if (!trimmed) continue;
    const normalized = trimmed.toLowerCase();
    if (seen.has(normalized)) continue;
    seen.add(normalized);
    deduped.push(trimmed);
  }
  return deduped;
}

function toEmailList(entries: SenderLike[] | null | undefined): string[] {
  return uniqueEmails(
    (entries ?? []).map((entry) => entry?.email?.trim() ?? '').filter((value) => value.length > 0),
  );
}

function constructReplyBody(
  messageHtml: string,
  originalDate: string,
  originalSender: SenderLike | undefined,
  recipients: SenderLike[],
) {
  const senderName = originalSender?.name || originalSender?.email || 'Unknown Sender';
  const recipientEmails = recipients
    .map((recipient) => recipient.email)
    .filter(Boolean)
    .join(', ');
  return `
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;">
      <div>
        ${messageHtml}
      </div>
      <div style="padding-left: 16px; border-left: 3px solid #e2e8f0; color: #64748b;">
        <div style="font-size: 12px;">
          On ${originalDate}, ${senderName} ${recipientEmails ? `&lt;${recipientEmails}&gt;` : ''} wrote:
        </div>
      </div>
    </div>
  `;
}

function constructForwardBody(
  messageHtml: string,
  originalDate: string,
  originalSender: (SenderLike & { subject?: string | null }) | undefined,
  recipients: SenderLike[],
) {
  const senderName = originalSender?.name || originalSender?.email || 'Unknown Sender';
  const recipientEmails = recipients
    .map((recipient) => recipient.email)
    .filter(Boolean)
    .join(', ');
  return `
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;">
      <div>
        ${messageHtml}
      </div>
      <div style="margin-top: 20px; border-top: 1px solid #e2e8f0; padding-top: 20px;">
        <div style="font-size: 12px; color: #64748b; margin-bottom: 10px;">
          ---------- Forwarded message ----------<br/>
          From: ${senderName} ${originalSender?.email ? `&lt;${originalSender.email}&gt;` : ''}<br/>
          Date: ${originalDate}<br/>
          Subject: ${originalSender?.subject || 'No Subject'}<br/>
          To: ${recipientEmails || 'No Recipients'}
        </div>
      </div>
    </div>
  `;
}

function buildThreadAwareBody({
  body,
  mode,
  latestMessage,
  recipients,
}: {
  body: string;
  mode: string | undefined;
  latestMessage: any;
  recipients: SenderLike[];
}) {
  if (!latestMessage || (!mode && !latestMessage)) {
    return body;
  }

  const originalDate = latestMessage.receivedOn
    ? new Date(latestMessage.receivedOn).toLocaleString()
    : new Date().toLocaleString();

  if (mode === 'forward') {
    return constructForwardBody(
      body,
      originalDate,
      {
        ...latestMessage.sender,
        subject: latestMessage.subject,
      },
      recipients,
    );
  }

  if (mode === 'reply' || mode === 'replyAll') {
    return constructReplyBody(body, originalDate, latestMessage.sender, recipients);
  }

  return body;
}

function getComposeSentEvent({
  mode,
  hasCc,
  hasBcc,
}: {
  mode: string | undefined;
  hasCc: boolean;
  hasBcc: boolean;
}) {
  if (mode === 'reply' || mode === 'replyAll' || mode === 'forward') {
    return { name: 'Reply Email Sent', properties: { mode } };
  }

  if (hasCc && hasBcc) {
    return { name: 'Create Email Sent with CC and BCC', properties: { hasCc, hasBcc } };
  }
  if (hasCc) {
    return { name: 'Create Email Sent with CC', properties: { hasCc, hasBcc } };
  }
  if (hasBcc) {
    return { name: 'Create Email Sent with BCC', properties: { hasCc, hasBcc } };
  }
  return { name: 'Create Email Sent', properties: { hasCc, hasBcc } };
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
  attachmentRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  attachmentButton: {
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  attachmentsList: {
    borderBottomWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 16,
    paddingVertical: 8,
    gap: 8,
  },
  attachmentItem: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 8,
  },
  attachmentMeta: {
    flex: 1,
    gap: 2,
  },
  attachmentName: {
    fontSize: 14,
    fontWeight: '500',
  },
  attachmentSize: {
    fontSize: 12,
  },
  bodyContainer: {
    flex: 1,
    padding: 12,
  },
  richText: {
    flex: 1,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 10,
    overflow: 'hidden',
  },
  toolbarContainer: {
    borderTopWidth: StyleSheet.hairlineWidth,
    paddingTop: 6,
    paddingBottom: 2,
  },
});
