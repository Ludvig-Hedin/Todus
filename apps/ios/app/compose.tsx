/**
 * Compose screen — full-screen modal for writing new emails or replying.
 * Supports new message, reply, reply-all, and forward modes.
 */
import {
  Alert,
  KeyboardAvoidingView,
  Modal,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { RichText, Toolbar, useEditorBridge, useEditorContent } from '@10play/tentap-editor';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import DateTimePicker, { type DateTimePickerEvent } from '@react-native-community/datetimepicker';
import { captureEvent } from '../src/shared/telemetry/posthog';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useTRPC } from '../src/providers/QueryTrpcProvider';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useTheme } from '../src/shared/theme/ThemeContext';
import * as FileSystemLegacy from 'expo-file-system/legacy';
import * as DocumentPicker from 'expo-document-picker';
import { haptics } from '../src/shared/utils/haptics';
import {
  formatScheduleLabel,
  isSendFailure,
  isUndoEligibleResult,
  nextDefaultScheduleDate,
  splitRecipientInput,
  toRecipientObjects,
  uniqueEmails,
  type SendResultLike,
} from '../src/features/compose/composeParity';
import {
  extractComposePrefillParams,
  hasComposePrefillContent,
  plainTextBodyToHtml,
  type ComposePrefillParams,
} from '../src/features/compose/mailtoParity';
import { useAtom } from 'jotai';
import {
  pendingUndoSendAtom,
  undoComposePrefillAtom,
  type UndoComposePayload,
} from '../src/shared/state/undoSend';

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
  scheduleAt?: string;
};

type SenderLike = {
  email?: string | null;
  name?: string | null;
};

type TemplateLike = {
  id: string;
  name: string;
  subject?: string | null;
  body?: string | null;
  to?: string[] | null;
  cc?: string[] | null;
  bcc?: string[] | null;
};

export default function ComposeScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<{
    mode?: string;
    threadId?: string;
    draftId?: string | string[];
    to?: string | string[];
    cc?: string | string[];
    bcc?: string | string[];
    subject?: string | string[];
    body?: string | string[];
  }>();
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
  const [scheduleAt, setScheduleAt] = useState<string | undefined>();
  const [scheduleModalVisible, setScheduleModalVisible] = useState(false);
  const [scheduleDraftDate, setScheduleDraftDate] = useState<Date>(() => nextDefaultScheduleDate());
  const [androidPickerMode, setAndroidPickerMode] = useState<'date' | 'time' | null>(null);
  const [showTemplatesModal, setShowTemplatesModal] = useState(false);
  const [showSaveTemplateModal, setShowSaveTemplateModal] = useState(false);
  const [templateName, setTemplateName] = useState('');
  const [templateSearch, setTemplateSearch] = useState('');
  const [, setPendingUndoSend] = useAtom(pendingUndoSendAtom);
  const [undoComposePrefill, setUndoComposePrefill] = useAtom(undoComposePrefillAtom);
  const pendingUndoPayloadRef = useRef<{
    wasUserScheduled: boolean;
    payload: UndoComposePayload;
  } | null>(null);

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
  const composeRoutePrefill = useMemo(
    () =>
      extractComposePrefillParams({
        draftId: params.draftId,
        to: params.to,
        cc: params.cc,
        bcc: params.bcc,
        subject: params.subject,
        body: params.body,
      }),
    [params.bcc, params.body, params.cc, params.draftId, params.subject, params.to],
  );
  const draftIdParam = composeRoutePrefill.draftId;
  const shouldApplyRoutePrefill =
    !isReply && !isForward && hasComposePrefillContent(composeRoutePrefill);
  const defaultConnectionQuery = useQuery(trpc.connections.getDefault.queryOptions());
  const templatesQuery = useQuery(trpc.templates.list.queryOptions());

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
  const hasAppliedUndoPrefillRef = useRef(false);
  const pendingSendEventRef = useRef<{ name: string; properties?: Record<string, unknown> } | null>(
    null,
  );

  const applyUndoPrefill = useCallback(
    (prefill: UndoComposePayload) => {
      hasAppliedUndoPrefillRef.current = true;
      setTo(prefill.to ?? '');
      setCc(prefill.cc ?? '');
      setBcc(prefill.bcc ?? '');
      setSubject(prefill.subject ?? '');
      setAttachments(prefill.attachments ?? []);
      setScheduleAt(undefined);
      if ((prefill.cc ?? '').trim() || (prefill.bcc ?? '').trim()) {
        setShowCcBcc(true);
      }
      if (prefill.message) {
        editor.setContent(prefill.message);
      }
      setUndoComposePrefill(null);
    },
    [editor, setUndoComposePrefill],
  );

  const applyRoutePrefill = useCallback(
    (prefill: ComposePrefillParams) => {
      setTo(prefill.to ?? '');
      setCc(prefill.cc ?? '');
      setBcc(prefill.bcc ?? '');
      setSubject(prefill.subject ?? '');
      setScheduleAt(undefined);
      if ((prefill.cc ?? '').trim() || (prefill.bcc ?? '').trim()) {
        setShowCcBcc(true);
      }
      if (prefill.body) {
        editor.setContent(plainTextBodyToHtml(prefill.body));
      }
    },
    [editor],
  );

  useEffect(() => {
    if (hasRestoredDraftRef.current) return;

    const restoreComposeState = async () => {
      if (undoComposePrefill) {
        applyUndoPrefill(undoComposePrefill);
        hasRestoredDraftRef.current = true;
        return;
      }

      if (shouldApplyRoutePrefill) {
        applyRoutePrefill(composeRoutePrefill);
        hasRestoredDraftRef.current = true;
        return;
      }

      try {
        const rawDraft = await AsyncStorage.getItem(draftKey);
        if (!rawDraft) {
          hasRestoredDraftRef.current = true;
          return;
        }

        const draft: DraftState = JSON.parse(rawDraft);
        setTo(draft.to ?? '');
        setCc(draft.cc ?? '');
        setBcc(draft.bcc ?? '');
        setSubject(draft.subject ?? '');
        setAttachments(draft.attachments ?? []);
        setScheduleAt(draft.scheduleAt);
        if ((draft.cc ?? '').trim() || (draft.bcc ?? '').trim()) {
          setShowCcBcc(true);
        }
        if (draft.message) {
          editor.setContent(draft.message);
        }
      } catch {
        // ignore corrupted draft payloads
      }
      hasRestoredDraftRef.current = true;
    };

    void restoreComposeState();
  }, [
    applyRoutePrefill,
    applyUndoPrefill,
    composeRoutePrefill,
    draftKey,
    editor,
    shouldApplyRoutePrefill,
    undoComposePrefill,
  ]);

  useEffect(() => {
    if (!undoComposePrefill || hasAppliedUndoPrefillRef.current) return;
    applyUndoPrefill(undoComposePrefill);
  }, [applyUndoPrefill, undoComposePrefill]);

  useEffect(() => {
    const draft: DraftState = {
      to,
      cc,
      bcc,
      subject,
      message: editorHtml,
      attachments,
      scheduleAt,
    };
    const isEmpty =
      !draft.to.trim() &&
      !draft.cc.trim() &&
      !draft.bcc.trim() &&
      !draft.subject.trim() &&
      !stripHtml(draft.message).trim() &&
      draft.attachments.length === 0 &&
      !draft.scheduleAt;

    const timer = setTimeout(async () => {
      if (isEmpty) {
        await AsyncStorage.removeItem(draftKey);
        return;
      }
      await AsyncStorage.setItem(draftKey, JSON.stringify(draft));
    }, 800);

    return () => clearTimeout(timer);
  }, [attachments, bcc, cc, draftKey, editorHtml, scheduleAt, subject, to]);

  const createTemplateMutation = useMutation({
    ...trpc.templates.create.mutationOptions(),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: trpc.templates.list.queryKey() });
      haptics.success();
      setTemplateName('');
      setShowSaveTemplateModal(false);
    },
    onError: (error) => {
      haptics.error();
      Alert.alert('Template save failed', error.message || 'Could not save template.');
    },
  });

  const deleteTemplateMutation = useMutation({
    ...trpc.templates.delete.mutationOptions(),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: trpc.templates.list.queryKey() });
    },
    onError: (error) => {
      Alert.alert('Template delete failed', error.message || 'Could not delete template.');
    },
  });

  const sendMutation = useMutation({
    ...trpc.mail.send.mutationOptions(),
    onSuccess: async (result) => {
      const sendResult = (result ?? {}) as SendResultLike;

      if (isSendFailure(sendResult)) {
        pendingSendEventRef.current = null;
        pendingUndoPayloadRef.current = null;
        haptics.error();
        Alert.alert(
          'Send Failed',
          sendResult.error || 'Could not send the email. Please try again.',
        );
        return;
      }

      if (pendingSendEventRef.current) {
        captureEvent(pendingSendEventRef.current.name, pendingSendEventRef.current.properties);
      }

      if (
        isUndoEligibleResult(sendResult) &&
        sendResult.messageId &&
        typeof sendResult.sendAt === 'number'
      ) {
        const pendingPayload = pendingUndoPayloadRef.current;
        setPendingUndoSend({
          messageId: sendResult.messageId,
          sendAt: sendResult.sendAt,
          wasUserScheduled: pendingPayload?.wasUserScheduled ?? false,
          payload: pendingPayload?.wasUserScheduled ? undefined : pendingPayload?.payload,
        });
      }

      pendingSendEventRef.current = null;
      pendingUndoPayloadRef.current = null;
      haptics.success();
      await AsyncStorage.removeItem(draftKey);
      queryClient.invalidateQueries({ queryKey: trpc.mail.listThreads.queryKey() });
      router.back();
    },
    onError: (error) => {
      pendingSendEventRef.current = null;
      pendingUndoPayloadRef.current = null;
      haptics.error();
      Alert.alert('Send Failed', error.message || 'Could not send the email. Please try again.');
    },
  });

  const handleSend = async () => {
    if (!to.trim()) {
      Alert.alert('Missing Recipient', 'Please enter at least one recipient.');
      return;
    }

    if (scheduleAt && new Date(scheduleAt).getTime() <= Date.now()) {
      Alert.alert('Invalid schedule', 'Scheduled time must be in the future.');
      return;
    }

    const messageHtml = await editor.getHTML();
    const latestMessage = threadData?.latest;

    const toRecipients = toRecipientObjects(to);
    const ccRecipients = toRecipientObjects(cc);
    const bccRecipients = toRecipientObjects(bcc);

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
    pendingUndoPayloadRef.current = {
      wasUserScheduled: Boolean(scheduleAt),
      payload: {
        to,
        cc,
        bcc,
        subject,
        message: messageHtml?.trim() || '',
        attachments,
      },
    };

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
      ...(draftIdParam ? { draftId: draftIdParam } : {}),
      ...(params.threadId ? { threadId: params.threadId } : {}),
      ...(scheduleAt ? { scheduleAt } : {}),
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

  const templates = ((templatesQuery.data as { templates?: TemplateLike[] } | undefined)
    ?.templates ?? []) as TemplateLike[];
  const filteredTemplates = templates.filter((template) =>
    template.name.toLowerCase().includes(templateSearch.trim().toLowerCase()),
  );

  const saveTemplate = async () => {
    if (!templateName.trim()) {
      Alert.alert('Missing name', 'Please provide a template name.');
      return;
    }

    const body = await editor.getHTML();
    createTemplateMutation.mutate({
      name: templateName.trim(),
      subject: subject.trim(),
      body: body?.trim() || '',
      to: splitRecipientInput(to),
      cc: splitRecipientInput(cc),
      bcc: splitRecipientInput(bcc),
    } as any);
  };

  const applyTemplate = (template: TemplateLike) => {
    setSubject(template.subject ?? '');
    setTo((template.to ?? []).join(', '));
    setCc((template.cc ?? []).join(', '));
    setBcc((template.bcc ?? []).join(', '));
    setShowCcBcc(Boolean((template.cc ?? []).length || (template.bcc ?? []).length));
    if (template.body) {
      editor.setContent(template.body);
    }
    setShowTemplatesModal(false);
  };

  const confirmDeleteTemplate = (template: TemplateLike) => {
    Alert.alert('Delete Template', `Delete "${template.name}"?`, [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: () => deleteTemplateMutation.mutate({ id: template.id }),
      },
    ]);
  };

  const openSchedulePicker = () => {
    const initialDate = scheduleAt ? new Date(scheduleAt) : nextDefaultScheduleDate();
    if (Platform.OS === 'android') {
      setScheduleDraftDate(initialDate);
      setAndroidPickerMode('date');
      return;
    }
    setScheduleDraftDate(initialDate);
    setScheduleModalVisible(true);
  };

  const clearSchedule = () => {
    setScheduleAt(undefined);
    setScheduleModalVisible(false);
    setAndroidPickerMode(null);
  };

  const applyScheduleDate = (value: Date) => {
    if (value.getTime() <= Date.now()) {
      Alert.alert('Invalid schedule', 'Scheduled time must be in the future.');
      return;
    }
    setScheduleAt(value.toISOString());
  };

  const handleAndroidScheduleChange = (event: DateTimePickerEvent, value?: Date) => {
    if (!androidPickerMode) return;

    if (event.type === 'dismissed') {
      setAndroidPickerMode(null);
      return;
    }

    if (!value) {
      setAndroidPickerMode(null);
      return;
    }

    if (androidPickerMode === 'date') {
      const merged = new Date(scheduleDraftDate);
      merged.setFullYear(value.getFullYear(), value.getMonth(), value.getDate());
      setScheduleDraftDate(merged);
      setAndroidPickerMode('time');
      return;
    }

    const merged = new Date(scheduleDraftDate);
    merged.setHours(value.getHours(), value.getMinutes(), 0, 0);
    setAndroidPickerMode(null);
    applyScheduleDate(merged);
  };

  const confirmIosSchedule = () => {
    applyScheduleDate(scheduleDraftDate);
    setScheduleModalVisible(false);
  };

  const scheduleLabel = scheduleAt ? formatScheduleLabel(scheduleAt) : 'Send later';
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
        <View style={styles.headerActions}>
          <Pressable
            style={[styles.headerSecondaryButton, { borderColor: colors.border }]}
            onPress={openSchedulePicker}
            disabled={sendMutation.isPending}
          >
            <Text style={[styles.headerSecondaryText, { color: colors.foreground }]}>Later</Text>
          </Pressable>
          <Pressable
            style={[
              styles.sendButton,
              { backgroundColor: sendMutation.isPending ? colors.secondary : colors.primary },
            ]}
            onPress={handleSend}
            disabled={sendMutation.isPending}
          >
            <Text style={[styles.sendText, { color: colors.primaryForeground }]}>
              {sendMutation.isPending ? 'Sending...' : scheduleAt ? 'Schedule' : 'Send'}
            </Text>
          </Pressable>
        </View>
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
          <Text style={[styles.fieldLabel, { color: colors.mutedForeground }]}>When:</Text>
          <Pressable
            style={[styles.inlineButton, { borderColor: colors.border }]}
            onPress={openSchedulePicker}
          >
            <Text style={{ color: colors.foreground, fontWeight: '500' }}>{scheduleLabel}</Text>
          </Pressable>
          {scheduleAt && (
            <Pressable onPress={clearSchedule}>
              <Text style={{ color: colors.destructive, fontWeight: '600' }}>Clear</Text>
            </Pressable>
          )}
        </View>

        <View style={[styles.attachmentRow, { borderBottomColor: colors.border }]}>
          <Text style={[styles.fieldLabel, { color: colors.mutedForeground }]}>Template:</Text>
          <View style={styles.inlineActions}>
            <Pressable
              style={[styles.inlineButton, { borderColor: colors.border }]}
              onPress={() => setShowTemplatesModal(true)}
            >
              <Text style={{ color: colors.foreground, fontWeight: '500' }}>Use</Text>
            </Pressable>
            <Pressable
              style={[styles.inlineButton, { borderColor: colors.border }]}
              onPress={() => setShowSaveTemplateModal(true)}
            >
              <Text style={{ color: colors.foreground, fontWeight: '500' }}>Save</Text>
            </Pressable>
          </View>
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

      {Platform.OS === 'android' && androidPickerMode ? (
        <DateTimePicker
          value={scheduleDraftDate}
          mode={androidPickerMode}
          minimumDate={androidPickerMode === 'date' ? new Date() : undefined}
          onChange={handleAndroidScheduleChange}
        />
      ) : null}

      <Modal
        visible={scheduleModalVisible}
        animationType="slide"
        transparent
        onRequestClose={() => setScheduleModalVisible(false)}
      >
        <View style={styles.modalScrim}>
          <View
            style={[
              styles.modalCard,
              {
                backgroundColor: colors.card,
                borderColor: colors.border,
              },
            ]}
          >
            <Text style={[styles.modalTitle, { color: colors.foreground }]}>Schedule Send</Text>
            <DateTimePicker
              value={scheduleDraftDate}
              mode="datetime"
              display="spinner"
              onChange={(_, value) => {
                if (value) setScheduleDraftDate(value);
              }}
              minimumDate={new Date()}
            />
            <View style={styles.modalActions}>
              <Pressable
                style={[styles.modalButton, { borderColor: colors.border }]}
                onPress={() => setScheduleModalVisible(false)}
              >
                <Text style={{ color: colors.foreground, fontWeight: '600' }}>Cancel</Text>
              </Pressable>
              <Pressable
                style={[styles.modalButton, { backgroundColor: colors.primary }]}
                onPress={confirmIosSchedule}
              >
                <Text style={{ color: colors.primaryForeground, fontWeight: '700' }}>Set</Text>
              </Pressable>
            </View>
          </View>
        </View>
      </Modal>

      <Modal
        visible={showTemplatesModal}
        animationType="slide"
        onRequestClose={() => setShowTemplatesModal(false)}
      >
        <View style={[styles.modalPage, { backgroundColor: colors.background }]}>
          <View style={[styles.modalHeader, { borderBottomColor: colors.border }]}>
            <Text style={[styles.modalTitle, { color: colors.foreground }]}>Templates</Text>
            <Pressable onPress={() => setShowTemplatesModal(false)}>
              <Text style={{ color: colors.primary, fontWeight: '600' }}>Close</Text>
            </Pressable>
          </View>
          <View style={[styles.searchRow, { borderColor: colors.border }]}>
            <TextInput
              value={templateSearch}
              onChangeText={setTemplateSearch}
              placeholder="Search templates"
              placeholderTextColor={colors.mutedForeground}
              style={[styles.searchInput, { color: colors.foreground }]}
            />
          </View>
          <ScrollView
            style={styles.templateList}
            contentContainerStyle={styles.templateListContent}
            keyboardShouldPersistTaps="handled"
          >
            {templatesQuery.isLoading && (
              <Text style={[styles.templateMeta, { color: colors.mutedForeground }]}>
                Loading templates...
              </Text>
            )}
            {!templatesQuery.isLoading && filteredTemplates.length === 0 && (
              <Text style={[styles.templateMeta, { color: colors.mutedForeground }]}>
                No templates found.
              </Text>
            )}
            {filteredTemplates.map((template) => (
              <View
                key={template.id}
                style={[styles.templateRow, { borderBottomColor: colors.border }]}
              >
                <Pressable style={styles.templateText} onPress={() => applyTemplate(template)}>
                  <Text style={[styles.templateName, { color: colors.foreground }]}>
                    {template.name}
                  </Text>
                  {!!template.subject && (
                    <Text style={[styles.templateMeta, { color: colors.mutedForeground }]}>
                      {template.subject}
                    </Text>
                  )}
                </Pressable>
                <Pressable onPress={() => confirmDeleteTemplate(template)}>
                  <Text style={{ color: colors.destructive, fontWeight: '600' }}>Delete</Text>
                </Pressable>
              </View>
            ))}
          </ScrollView>
        </View>
      </Modal>

      <Modal
        visible={showSaveTemplateModal}
        animationType="fade"
        transparent
        onRequestClose={() => setShowSaveTemplateModal(false)}
      >
        <View style={styles.modalScrim}>
          <View
            style={[
              styles.modalCard,
              {
                backgroundColor: colors.card,
                borderColor: colors.border,
              },
            ]}
          >
            <Text style={[styles.modalTitle, { color: colors.foreground }]}>Save Template</Text>
            <TextInput
              value={templateName}
              onChangeText={setTemplateName}
              placeholder="Template name"
              placeholderTextColor={colors.mutedForeground}
              style={[
                styles.templateNameInput,
                {
                  borderColor: colors.border,
                  color: colors.foreground,
                },
              ]}
            />
            <View style={styles.modalActions}>
              <Pressable
                style={[styles.modalButton, { borderColor: colors.border }]}
                onPress={() => {
                  setShowSaveTemplateModal(false);
                  setTemplateName('');
                }}
              >
                <Text style={{ color: colors.foreground, fontWeight: '600' }}>Cancel</Text>
              </Pressable>
              <Pressable
                style={[
                  styles.modalButton,
                  { backgroundColor: createTemplateMutation.isPending ? colors.secondary : colors.primary },
                ]}
                disabled={createTemplateMutation.isPending}
                onPress={() => {
                  void saveTemplate();
                }}
              >
                <Text style={{ color: colors.primaryForeground, fontWeight: '700' }}>
                  {createTemplateMutation.isPending ? 'Saving...' : 'Save'}
                </Text>
              </Pressable>
            </View>
          </View>
        </View>
      </Modal>
    </KeyboardAvoidingView>
  );
}

function stripHtml(value: string): string {
  return value.replace(/<[^>]*>/g, '');
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
  headerActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  headerSecondaryButton: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 8,
    paddingHorizontal: 10,
    paddingVertical: 8,
  },
  headerSecondaryText: {
    fontSize: 13,
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
  inlineActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  inlineButton: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 8,
    paddingHorizontal: 10,
    paddingVertical: 7,
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
  modalScrim: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.4)',
    justifyContent: 'center',
    paddingHorizontal: 20,
  },
  modalCard: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 14,
    padding: 16,
    gap: 12,
  },
  modalPage: {
    flex: 1,
  },
  modalHeader: {
    paddingHorizontal: 16,
    paddingVertical: 14,
    borderBottomWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  modalTitle: {
    fontSize: 17,
    fontWeight: '700',
  },
  modalActions: {
    flexDirection: 'row',
    justifyContent: 'flex-end',
    gap: 10,
  },
  modalButton: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 10,
    paddingHorizontal: 14,
    paddingVertical: 8,
  },
  searchRow: {
    margin: 16,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 10,
    paddingHorizontal: 10,
  },
  searchInput: {
    height: 40,
    fontSize: 15,
  },
  templateList: {
    flex: 1,
    paddingHorizontal: 16,
  },
  templateListContent: {
    paddingBottom: 24,
  },
  templateRow: {
    borderBottomWidth: StyleSheet.hairlineWidth,
    paddingVertical: 12,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 10,
  },
  templateText: {
    flex: 1,
    gap: 2,
  },
  templateName: {
    fontSize: 15,
    fontWeight: '600',
  },
  templateMeta: {
    fontSize: 13,
  },
  templateNameInput: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 10,
    fontSize: 15,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
});
