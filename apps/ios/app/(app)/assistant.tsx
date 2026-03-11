import {
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  TextInput,
  View,
  type TextStyle,
  type ViewStyle,
} from 'react-native';
import {
  authBypassVoiceUnavailableMessage,
  buildAuthBypassAssistantReply,
} from '../../src/features/assistant/authBypassAssistant';
import { extractResponseText, nextStreamCursor } from '../../src/features/assistant/assistantUtils';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { captureEvent } from '../../src/shared/telemetry/posthog';
import { useTRPC } from '../../src/providers/QueryTrpcProvider';
import { useTheme } from '../../src/shared/theme/ThemeContext';
import * as FileSystemLegacy from 'expo-file-system/legacy';
import { getNativeEnv } from '../../src/shared/config/env';
import { Mic, Square, Volume2 } from 'lucide-react-native';
import { useMutation } from '@tanstack/react-query';
import * as Speech from 'expo-speech';
import type { Audio } from 'expo-av';

type AssistantMessage = {
  id: string;
  role: 'user' | 'assistant';
  text: string;
};

const QUICK_PROMPTS = [
  'Summarize what I should prioritize in my inbox today.',
  'Draft a polite follow-up for a delayed reply.',
  'Suggest a short response to decline a meeting.',
];

export default function AssistantScreen() {
  const env = getNativeEnv();
  const { colors, ui } = useTheme();
  const insets = useSafeAreaInsets();
  const trpc = useTRPC();
  const scrollRef = useRef<ScrollView>(null);
  const streamTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const recordingRef = useRef<Audio.Recording | null>(null);
  const audioModuleRef = useRef<typeof import('expo-av') | null>(null);
  const [messages, setMessages] = useState<AssistantMessage[]>([]);
  const [input, setInput] = useState('');
  const [isStreaming, setIsStreaming] = useState(false);
  const [isVoicePlaying, setIsVoicePlaying] = useState(false);
  const [isRecording, setIsRecording] = useState(false);
  const [autoSpeak, setAutoSpeak] = useState(false);
  const [handsFreeMode, setHandsFreeMode] = useState(false);
  const resumeConversationRef = useRef(false);

  const latestAssistantMessage = useMemo(() => {
    for (let index = messages.length - 1; index >= 0; index -= 1) {
      const message = messages[index];
      if (message.role === 'assistant' && message.text.trim().length > 0) {
        return message.text;
      }
    }
    return '';
  }, [messages]);

  const webSearchMutation = useMutation({
    ...trpc.ai.webSearch.mutationOptions(),
    onSuccess: (result) => {
      const responseText = extractResponseText(result);
      streamAssistantMessage(responseText || 'No response received.');
      captureEvent('AI Chat Response', {
        length: responseText.length,
      });
    },
    onError: (error) => {
      resumeConversationRef.current = false;
      const rawMessage = error.message || 'Something went wrong. Please try again.';
      const message = rawMessage.toUpperCase().includes('UNAUTHORIZED')
        ? 'Assistant requires a signed-in mailbox connection. Auth bypass mode cannot access this feature yet.'
        : rawMessage;
      streamAssistantMessage(message);
      captureEvent('AI Chat Error', {
        message,
      });
    },
  });

  const transcribeMutation = useMutation({
    ...trpc.ai.transcribeAudio.mutationOptions(),
    onSuccess: (result) => {
      const transcript = result.text.trim();
      if (!transcript) {
        resumeConversationRef.current = false;
        streamAssistantMessage('I could not detect speech. Please try again.');
        captureEvent('AI Voice Input Empty');
        return;
      }

      captureEvent('AI Voice Input Transcript', {
        length: transcript.length,
      });
      sendPrompt(transcript);
    },
    onError: (error) => {
      resumeConversationRef.current = false;
      const rawMessage = error.message || 'Voice transcription failed. Please try again.';
      const message = rawMessage.toUpperCase().includes('UNAUTHORIZED')
        ? 'Voice dictation requires a signed-in mailbox connection. Auth bypass mode cannot access this feature yet.'
        : rawMessage;
      streamAssistantMessage(message);
      captureEvent('AI Voice Input Error', {
        message,
      });
    },
  });

  const sendPrompt = useCallback(
    (rawPrompt?: string) => {
      const prompt = (rawPrompt ?? input).trim();
      if (!prompt || webSearchMutation.isPending || isStreaming || isRecording) {
        return;
      }

      const userMessage: AssistantMessage = {
        id: `user-${Date.now()}`,
        role: 'user',
        text: prompt,
      };
      setMessages((prev) => [...prev, userMessage]);
      setInput('');
      captureEvent('AI Chat Prompt', {
        length: prompt.length,
      });

      if (env.authBypassEnabled) {
        const fallbackText = buildAuthBypassAssistantReply(prompt);
        streamAssistantMessage(fallbackText);
        captureEvent('AI Chat Response', {
          length: fallbackText.length,
          source: 'auth_bypass_fallback',
        });
        return;
      }

      webSearchMutation.mutate({ query: prompt });
    },
    [env.authBypassEnabled, input, isRecording, isStreaming, webSearchMutation],
  );

  const pending = webSearchMutation.isPending || isStreaming || transcribeMutation.isPending;
  const canSend = input.trim().length > 0 && !pending && !isRecording;
  const composerPlaceholder = isRecording
    ? 'Listening...'
    : pending
      ? 'Waiting for assistant...'
      : 'Ask the assistant...';

  const loadAudioModule = useCallback(async () => {
    if (audioModuleRef.current) {
      return audioModuleRef.current;
    }

    try {
      const module = await import('expo-av');
      audioModuleRef.current = module;
      return module;
    } catch {
      return null;
    }
  }, []);

  useEffect(() => {
    scrollRef.current?.scrollToEnd({ animated: true });
  }, [messages]);

  const stopVoicePlayback = useCallback(() => {
    Speech.stop();
    setIsVoicePlaying(false);
  }, []);

  const speakAssistantText = useCallback(
    (text: string, mode: 'manual' | 'auto') => {
      const trimmed = text.trim();
      if (!trimmed) return;

      Speech.stop();
      setIsVoicePlaying(true);
      captureEvent('AI Voice Play', {
        mode,
        length: trimmed.length,
      });

      const stopVoice = () => {
        if (mode === 'auto' && handsFreeMode) {
          resumeConversationRef.current = true;
        }
        setIsVoicePlaying(false);
      };

      Speech.speak(trimmed, {
        language: 'en-US',
        rate: 0.96,
        pitch: 1.0,
        onDone: stopVoice,
        onStopped: stopVoice,
        onError: stopVoice,
      });
    },
    [handsFreeMode],
  );

  useEffect(() => {
    return () => {
      if (streamTimerRef.current) {
        clearInterval(streamTimerRef.current);
      }
      const activeRecording = recordingRef.current;
      if (activeRecording) {
        activeRecording.stopAndUnloadAsync().catch(() => undefined);
        recordingRef.current = null;
      }
      loadAudioModule()
        .then((module) =>
          module?.Audio.setAudioModeAsync({
            allowsRecordingIOS: false,
            playsInSilentModeIOS: true,
          }).catch(() => undefined),
        )
        .catch(() => undefined);
      Speech.stop();
    };
  }, [loadAudioModule]);

  const startVoiceRecording = useCallback(async () => {
    if (pending || isRecording) {
      return;
    }

    if (env.authBypassEnabled) {
      streamAssistantMessage(authBypassVoiceUnavailableMessage());
      captureEvent('AI Voice Input Bypass Blocked');
      return;
    }

    try {
      const audioModule = await loadAudioModule();
      if (!audioModule) {
        streamAssistantMessage(
          'Voice dictation is unavailable in this build. Install expo-av native module and rebuild the app.',
        );
        captureEvent('AI Voice Input Unavailable');
        return;
      }

      const permission = await audioModule.Audio.requestPermissionsAsync();
      if (!permission.granted) {
        streamAssistantMessage('Microphone access is required for voice input.');
        return;
      }

      await audioModule.Audio.setAudioModeAsync({
        allowsRecordingIOS: true,
        playsInSilentModeIOS: true,
      });

      const recording = new audioModule.Audio.Recording();
      await recording.prepareToRecordAsync(audioModule.Audio.RecordingOptionsPresets.HIGH_QUALITY);
      await recording.startAsync();
      recordingRef.current = recording;
      setIsRecording(true);

      captureEvent('AI Voice Input Start');
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unable to start recording.';
      streamAssistantMessage(message);
      setIsRecording(false);
      recordingRef.current = null;
    }
  }, [env.authBypassEnabled, isRecording, loadAudioModule, pending]);

  const stopVoiceRecording = useCallback(async () => {
    const recording = recordingRef.current;
    if (!recording) {
      return;
    }

    setIsRecording(false);
    recordingRef.current = null;

    let recordingUri: string | null = null;
    try {
      await recording.stopAndUnloadAsync();
      recordingUri = recording.getURI();
      if (!recordingUri) {
        throw new Error('Unable to process the recording.');
      }

      const audioBase64 = await FileSystemLegacy.readAsStringAsync(recordingUri, {
        encoding: FileSystemLegacy.EncodingType.Base64,
      });

      resumeConversationRef.current = handsFreeMode;
      captureEvent('AI Voice Input Stop', {
        bytes: audioBase64.length,
      });
      transcribeMutation.mutate({
        audioBase64,
        mimeType: 'audio/mp4',
        language: 'en',
      });
    } catch (error) {
      resumeConversationRef.current = false;
      const message = error instanceof Error ? error.message : 'Unable to transcribe recording.';
      streamAssistantMessage(message);
      captureEvent('AI Voice Input Error', { message });
    } finally {
      const audioModule = await loadAudioModule();
      await audioModule?.Audio.setAudioModeAsync({
        allowsRecordingIOS: false,
        playsInSilentModeIOS: true,
      }).catch(() => undefined);

      if (recordingUri) {
        await FileSystemLegacy.deleteAsync(recordingUri, { idempotent: true }).catch(
          () => undefined,
        );
      }
    }
  }, [handsFreeMode, loadAudioModule, transcribeMutation]);

  const streamAssistantMessage = (fullText: string) => {
    if (streamTimerRef.current) {
      clearInterval(streamTimerRef.current);
      streamTimerRef.current = null;
    }

    const messageId = `assistant-${Date.now()}`;
    setMessages((prev) => [...prev, { id: messageId, role: 'assistant', text: '' }]);
    setIsStreaming(true);

    let cursor = 0;
    const chunkSize = 3;
    streamTimerRef.current = setInterval(() => {
      cursor = nextStreamCursor(cursor, fullText.length, chunkSize);
      const nextText = fullText.slice(0, cursor);

      setMessages((prev) =>
        prev.map((message) =>
          message.id === messageId
            ? {
                ...message,
                text: nextText,
              }
            : message,
        ),
      );

      if (cursor >= fullText.length) {
        if (streamTimerRef.current) {
          clearInterval(streamTimerRef.current);
          streamTimerRef.current = null;
        }
        setIsStreaming(false);
        if (autoSpeak && fullText.trim()) {
          speakAssistantText(fullText, 'auto');
        } else if (handsFreeMode && fullText.trim()) {
          resumeConversationRef.current = true;
        }
      }
    }, 20);
  };

  useEffect(() => {
    if (!handsFreeMode) {
      resumeConversationRef.current = false;
      return;
    }
    if (!resumeConversationRef.current || pending || isRecording || isVoicePlaying) {
      return;
    }

    resumeConversationRef.current = false;
    startVoiceRecording().catch(() => {
      resumeConversationRef.current = false;
    });
  }, [handsFreeMode, isRecording, isVoicePlaying, pending, startVoiceRecording]);

  const emptyState = (
    <View
      style={[
        styles.emptyState,
        {
          backgroundColor: ui.surface,
          borderColor: ui.borderSubtle,
        },
      ]}
    >
      <Text style={[styles.emptyTitle, { color: colors.foreground }]}>Inbox assistant</Text>
      <Text style={[styles.emptyBody, { color: colors.mutedForeground }]}>
        Ask for summaries, draft ideas, and quick rewrites.
      </Text>
      <View
        style={[
          styles.quickPromptGroup,
          { borderColor: ui.borderSubtle, backgroundColor: ui.surfaceInset },
        ]}
      >
        {QUICK_PROMPTS.map((prompt, index) => (
          <Pressable
            key={prompt}
            style={[
              styles.quickPrompt,
              {
                borderBottomWidth: index < QUICK_PROMPTS.length - 1 ? StyleSheet.hairlineWidth : 0,
                borderBottomColor: ui.borderSubtle,
              },
            ]}
            onPress={() => sendPrompt(prompt)}
          >
            <Text style={[styles.quickPromptText, { color: colors.foreground }]}>{prompt}</Text>
          </Pressable>
        ))}
      </View>
    </View>
  );

  return (
    <KeyboardAvoidingView
      style={[styles.container, { backgroundColor: ui.canvas }]}
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
    >
      <View
        style={[
          styles.header,
          {
            paddingTop: insets.top + 8,
            borderBottomColor: ui.borderSubtle,
            backgroundColor: ui.canvas,
          },
        ]}
      >
        <View style={styles.headerTitleWrap}>
          <Text style={[styles.headerTitle, { color: colors.foreground }]}>Assistant</Text>
          <Text style={[styles.headerSubtitle, { color: colors.mutedForeground }]}>
            Focused help for email tasks
          </Text>
        </View>
        <Pressable
          style={[
            styles.clearButton,
            { borderColor: ui.borderSubtle, backgroundColor: ui.surface },
          ]}
          onPress={() => setMessages([])}
          disabled={pending || messages.length === 0}
        >
          <Text
            style={[
              styles.clearButtonText,
              {
                color:
                  pending || messages.length === 0 ? colors.mutedForeground : colors.foreground,
              },
            ]}
          >
            Clear
          </Text>
        </Pressable>
      </View>

      <ScrollView
        ref={scrollRef}
        style={[styles.messageList, { backgroundColor: ui.canvas }]}
        contentContainerStyle={styles.messageContent}
        keyboardShouldPersistTaps="handled"
      >
        {messages.length === 0 ? (
          emptyState
        ) : (
          <>
            {messages.map((message) => (
              <View
                key={message.id}
                style={[
                  styles.messageBubble,
                  message.role === 'user'
                    ? [
                        styles.userBubble,
                        {
                          backgroundColor: colors.primary,
                          borderColor: colors.primary,
                        },
                      ]
                    : [
                        styles.assistantBubble,
                        { backgroundColor: ui.surface, borderColor: ui.borderSubtle },
                      ],
                ]}
              >
                <Text
                  style={[
                    styles.messageText,
                    {
                      color: message.role === 'user' ? colors.primaryForeground : colors.foreground,
                    },
                  ]}
                >
                  {message.text}
                </Text>
              </View>
            ))}
            {pending && (
              <Text style={[styles.pendingText, { color: colors.mutedForeground }]}>
                Assistant is thinking...
              </Text>
            )}
          </>
        )}
      </ScrollView>

      <View
        style={[
          styles.composer,
          {
            paddingBottom: insets.bottom + 8,
            borderTopColor: ui.borderSubtle,
            backgroundColor: ui.canvas,
          },
        ]}
      >
        <View
          style={[styles.voicePanel, { borderColor: ui.borderSubtle, backgroundColor: ui.surface }]}
        >
          <View style={styles.voicePanelLeft}>
            <View style={styles.voiceActionsRow}>
              <Pressable
                style={[
                  styles.voiceAction,
                  {
                    borderColor: ui.borderSubtle,
                    backgroundColor: isVoicePlaying ? ui.surfaceInset : ui.surfaceRaised,
                  },
                ]}
                onPress={() => {
                  if (isVoicePlaying) {
                    stopVoicePlayback();
                    return;
                  }
                  speakAssistantText(latestAssistantMessage, 'manual');
                }}
                disabled={!isVoicePlaying && latestAssistantMessage.trim().length === 0}
              >
                {isVoicePlaying ? (
                  <Square size={14} color={colors.foreground} />
                ) : (
                  <Volume2 size={14} color={colors.foreground} />
                )}
                <Text style={[styles.voiceActionText, { color: colors.foreground }]}>
                  {isVoicePlaying ? 'Stop voice' : 'Read latest'}
                </Text>
              </Pressable>

              <Pressable
                style={[
                  styles.voiceAction,
                  {
                    borderColor: ui.borderSubtle,
                    backgroundColor: isRecording ? ui.surfaceInset : ui.surfaceRaised,
                  },
                ]}
                onPress={isRecording ? stopVoiceRecording : startVoiceRecording}
                disabled={pending && !isRecording}
              >
                {isRecording ? (
                  <Square size={14} color={colors.foreground} />
                ) : (
                  <Mic size={14} color={colors.foreground} />
                )}
                <Text style={[styles.voiceActionText, { color: colors.foreground }]}>
                  {isRecording
                    ? 'Stop rec'
                    : transcribeMutation.isPending
                      ? 'Transcribing'
                      : 'Dictate'}
                </Text>
              </Pressable>
            </View>
          </View>
          <View style={styles.voicePanelRight}>
            <View style={styles.voiceToggleRow}>
              <Text style={[styles.autoSpeakLabel, { color: colors.mutedForeground }]}>
                Auto-read
              </Text>
              <Switch
                value={autoSpeak}
                onValueChange={(enabled) => {
                  setAutoSpeak(enabled);
                  if (!enabled) {
                    stopVoicePlayback();
                  }
                }}
                trackColor={{ false: ui.surfaceInset, true: ui.accentSoft }}
                thumbColor={autoSpeak ? colors.foreground : ui.surfaceRaised}
              />
            </View>
            <View style={styles.voiceToggleRow}>
              <Text style={[styles.autoSpeakLabel, { color: colors.mutedForeground }]}>
                Hands-free
              </Text>
              <Switch
                value={handsFreeMode}
                onValueChange={(enabled) => {
                  if (enabled && env.authBypassEnabled) {
                    streamAssistantMessage(authBypassVoiceUnavailableMessage());
                    captureEvent('AI Voice HandsFree Blocked');
                    return;
                  }
                  setHandsFreeMode(enabled);
                  if (enabled) {
                    setAutoSpeak(true);
                    captureEvent('AI Voice HandsFree Enabled');
                  } else {
                    resumeConversationRef.current = false;
                    captureEvent('AI Voice HandsFree Disabled');
                  }
                }}
                trackColor={{ false: ui.surfaceInset, true: ui.accentSoft }}
                thumbColor={handsFreeMode ? colors.foreground : ui.surfaceRaised}
              />
            </View>
          </View>
        </View>

        <View style={styles.composerRow}>
          <TextInput
            value={input}
            onChangeText={setInput}
            placeholder={composerPlaceholder}
            placeholderTextColor={colors.mutedForeground}
            style={[
              styles.composerInput,
              {
                borderColor: ui.borderSubtle,
                color: colors.foreground,
                backgroundColor: ui.surface,
              },
            ]}
            multiline
            editable={!pending && !isRecording}
          />
          <Pressable
            style={[
              styles.sendButton,
              {
                backgroundColor: canSend ? colors.foreground : ui.surface,
                borderColor: canSend ? colors.foreground : ui.borderSubtle,
              },
            ]}
            onPress={() => sendPrompt()}
            disabled={!canSend}
          >
            <Text
              style={[
                styles.sendText,
                { color: canSend ? colors.primaryForeground : colors.mutedForeground },
              ]}
            >
              Send
            </Text>
          </Pressable>
        </View>
      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create<{
  container: ViewStyle;
  header: ViewStyle;
  headerTitleWrap: ViewStyle;
  headerTitle: TextStyle;
  headerSubtitle: TextStyle;
  clearButton: ViewStyle;
  clearButtonText: TextStyle;
  messageList: ViewStyle;
  messageContent: ViewStyle;
  emptyState: ViewStyle;
  emptyTitle: TextStyle;
  emptyBody: TextStyle;
  quickPromptGroup: ViewStyle;
  quickPrompt: ViewStyle;
  quickPromptText: TextStyle;
  messageBubble: ViewStyle;
  userBubble: ViewStyle;
  assistantBubble: ViewStyle;
  messageText: TextStyle;
  pendingText: TextStyle;
  composer: ViewStyle;
  voicePanel: ViewStyle;
  voicePanelLeft: ViewStyle;
  voiceActionsRow: ViewStyle;
  voiceAction: ViewStyle;
  voiceActionText: TextStyle;
  voicePanelRight: ViewStyle;
  voiceToggleRow: ViewStyle;
  autoSpeakLabel: TextStyle;
  composerRow: ViewStyle;
  composerInput: TextStyle;
  sendButton: ViewStyle;
  sendText: TextStyle;
}>({
  container: {
    flex: 1,
  },
  header: {
    borderBottomWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 16,
    paddingBottom: 10,
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'space-between',
    gap: 10,
  },
  headerTitleWrap: {
    flex: 1,
    gap: 1,
  },
  headerTitle: {
    fontSize: 17,
    fontWeight: '600',
    letterSpacing: 0,
  },
  headerSubtitle: {
    fontSize: 12,
    lineHeight: 15,
    letterSpacing: 0,
  },
  clearButton: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 12,
    paddingHorizontal: 11,
    paddingVertical: 6,
  },
  clearButtonText: {
    fontSize: 12,
    fontWeight: '600',
    letterSpacing: 0,
  },
  messageList: {
    flex: 1,
  },
  messageContent: {
    paddingHorizontal: 12,
    paddingTop: 12,
    paddingBottom: 14,
    gap: 10,
  },
  emptyState: {
    marginTop: 6,
    paddingHorizontal: 14,
    paddingVertical: 16,
    gap: 8,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 22,
  },
  emptyTitle: {
    fontSize: 15,
    fontWeight: '700',
    lineHeight: 20,
    letterSpacing: 0,
  },
  emptyBody: {
    fontSize: 12,
    lineHeight: 17,
    letterSpacing: 0,
  },
  quickPromptGroup: {
    marginTop: 8,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 16,
    overflow: 'hidden',
  },
  quickPrompt: {
    paddingHorizontal: 12,
    paddingVertical: 11,
  },
  quickPromptText: {
    fontSize: 12,
    lineHeight: 17,
    letterSpacing: 0,
  },
  messageBubble: {
    maxWidth: '88%',
    borderRadius: 18,
    paddingHorizontal: 11,
    paddingVertical: 9,
    borderWidth: StyleSheet.hairlineWidth,
  },
  userBubble: {
    alignSelf: 'flex-end',
  },
  assistantBubble: {
    alignSelf: 'flex-start',
  },
  messageText: {
    fontSize: 12,
    lineHeight: 17,
    letterSpacing: 0,
  },
  pendingText: {
    fontSize: 11,
    marginTop: 4,
    marginLeft: 2,
    lineHeight: 14,
    letterSpacing: 0,
  },
  composer: {
    borderTopWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 12,
    paddingTop: 8,
    gap: 8,
  },
  voicePanel: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 18,
    paddingHorizontal: 10,
    paddingVertical: 8,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 8,
  },
  voicePanelLeft: {
    flex: 1,
    alignItems: 'flex-start',
  },
  voiceActionsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  voiceAction: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 12,
    minHeight: 32,
    paddingHorizontal: 10,
    paddingVertical: 6,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
  },
  voiceActionText: {
    fontSize: 11,
    fontWeight: '600',
    letterSpacing: 0,
  },
  voicePanelRight: {
    alignItems: 'flex-end',
    gap: 6,
  },
  voiceToggleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  autoSpeakLabel: {
    fontSize: 11,
    fontWeight: '600',
    letterSpacing: 0,
  },
  composerRow: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    gap: 8,
  },
  composerInput: {
    flex: 1,
    minHeight: 40,
    maxHeight: 112,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 16,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 13,
    lineHeight: 17,
    letterSpacing: 0,
  },
  sendButton: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 16,
    minHeight: 40,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 13,
    paddingVertical: 8,
    alignSelf: 'flex-end',
  },
  sendText: {
    fontSize: 12,
    fontWeight: '700',
    letterSpacing: 0,
  },
});
