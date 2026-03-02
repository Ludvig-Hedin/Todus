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
} from 'react-native';
import { extractResponseText, nextStreamCursor } from '../../src/features/assistant/assistantUtils';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { captureEvent } from '../../src/shared/telemetry/posthog';
import { useTRPC } from '../../src/providers/QueryTrpcProvider';
import { Square, Volume2 } from 'lucide-react-native';
import { useTheme } from '../../src/shared/theme/ThemeContext';
import { useMutation } from '@tanstack/react-query';
import * as Speech from 'expo-speech';

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
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const trpc = useTRPC();
  const scrollRef = useRef<ScrollView>(null);
  const streamTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const [messages, setMessages] = useState<AssistantMessage[]>([]);
  const [input, setInput] = useState('');
  const [isStreaming, setIsStreaming] = useState(false);
  const [isVoicePlaying, setIsVoicePlaying] = useState(false);
  const [autoSpeak, setAutoSpeak] = useState(false);

  const canSend = input.trim().length > 0 && !isStreaming;
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
      streamAssistantMessage(error.message || 'Something went wrong. Please try again.');
      captureEvent('AI Chat Error', {
        message: error.message,
      });
    },
  });

  const pending = webSearchMutation.isPending || isStreaming;
  const composerPlaceholder = pending ? 'Waiting for assistant...' : 'Ask the assistant...';

  useEffect(() => {
    scrollRef.current?.scrollToEnd({ animated: true });
  }, [messages]);

  const stopVoicePlayback = useCallback(() => {
    Speech.stop();
    setIsVoicePlaying(false);
  }, []);

  const speakAssistantText = useCallback((text: string, mode: 'manual' | 'auto') => {
    const trimmed = text.trim();
    if (!trimmed) return;

    Speech.stop();
    setIsVoicePlaying(true);
    captureEvent('AI Voice Play', {
      mode,
      length: trimmed.length,
    });

    Speech.speak(trimmed, {
      language: 'en-US',
      rate: 0.96,
      pitch: 1.0,
      onDone: () => setIsVoicePlaying(false),
      onStopped: () => setIsVoicePlaying(false),
      onError: () => setIsVoicePlaying(false),
    });
  }, []);

  useEffect(() => {
    return () => {
      if (streamTimerRef.current) {
        clearInterval(streamTimerRef.current);
      }
      Speech.stop();
    };
  }, []);

  const sendPrompt = (rawPrompt?: string) => {
    const prompt = (rawPrompt ?? input).trim();
    if (!prompt || pending) {
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

    webSearchMutation.mutate({ query: prompt });
  };

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
        }
      }
    }, 20);
  };

  const emptyState = (
    <View style={styles.emptyState}>
      <Text style={[styles.emptyTitle, { color: colors.foreground }]}>Inbox assistant</Text>
      <Text style={[styles.emptyBody, { color: colors.mutedForeground }]}>
        Ask for summaries, draft ideas, and quick rewrites.
      </Text>
      <View style={[styles.quickPromptGroup, { borderColor: colors.border, backgroundColor: colors.card }]}>
        {QUICK_PROMPTS.map((prompt, index) => (
          <Pressable
            key={prompt}
            style={[
              styles.quickPrompt,
              {
                borderBottomWidth: index < QUICK_PROMPTS.length - 1 ? StyleSheet.hairlineWidth : 0,
                borderBottomColor: colors.border,
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
      style={[styles.container, { backgroundColor: colors.background }]}
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
    >
      <View
        style={[
          styles.header,
          {
            paddingTop: insets.top + 8,
            borderBottomColor: colors.border,
            backgroundColor: colors.background,
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
          style={[styles.clearButton, { borderColor: colors.border, backgroundColor: colors.card }]}
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
        style={[styles.messageList, { backgroundColor: colors.background }]}
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
                          backgroundColor: colors.secondary,
                          borderColor: colors.border,
                        },
                      ]
                    : [
                        styles.assistantBubble,
                        { backgroundColor: colors.card, borderColor: colors.border },
                      ],
                ]}
              >
                <Text
                  style={[
                    styles.messageText,
                    {
                      color: message.role === 'user' ? colors.foreground : colors.foreground,
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
            borderTopColor: colors.border,
            backgroundColor: colors.background,
          },
        ]}
      >
        <View
          style={[styles.voicePanel, { borderColor: colors.border, backgroundColor: colors.card }]}
        >
          <View style={styles.voicePanelLeft}>
            <Pressable
              style={[
                styles.voiceAction,
                {
                  borderColor: colors.border,
                  backgroundColor: isVoicePlaying ? colors.secondary : colors.card,
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
          </View>
          <View style={styles.voicePanelRight}>
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
              trackColor={{ false: colors.border, true: colors.mutedForeground }}
              thumbColor={autoSpeak ? colors.foreground : colors.background}
            />
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
                borderColor: colors.border,
                color: colors.foreground,
                backgroundColor: colors.card,
              },
            ]}
            multiline
            editable={!pending}
          />
          <Pressable
            style={[
              styles.sendButton,
              {
                backgroundColor: canSend ? colors.foreground : colors.card,
                borderColor: colors.border,
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

const styles = StyleSheet.create({
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
    fontSize: 18,
    fontWeight: '650',
    letterSpacing: 0,
  },
  headerSubtitle: {
    fontSize: 12,
    lineHeight: 16,
    letterSpacing: 0,
  },
  clearButton: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 10,
    paddingHorizontal: 10,
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
    paddingTop: 10,
    paddingBottom: 14,
    gap: 8,
  },
  emptyState: {
    paddingTop: 14,
    gap: 6,
  },
  emptyTitle: {
    fontSize: 16,
    fontWeight: '700',
    lineHeight: 22,
    letterSpacing: 0,
  },
  emptyBody: {
    fontSize: 13,
    lineHeight: 18,
    letterSpacing: 0,
  },
  quickPromptGroup: {
    marginTop: 8,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 12,
    overflow: 'hidden',
  },
  quickPrompt: {
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  quickPromptText: {
    fontSize: 13,
    lineHeight: 18,
    letterSpacing: 0,
  },
  messageBubble: {
    maxWidth: '88%',
    borderRadius: 12,
    paddingHorizontal: 10,
    paddingVertical: 8,
    borderWidth: StyleSheet.hairlineWidth,
  },
  userBubble: {
    alignSelf: 'flex-end',
  },
  assistantBubble: {
    alignSelf: 'flex-start',
  },
  messageText: {
    fontSize: 13,
    lineHeight: 18,
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
    borderRadius: 10,
    paddingHorizontal: 8,
    paddingVertical: 6,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 8,
  },
  voicePanelLeft: {
    flex: 1,
    alignItems: 'flex-start',
  },
  voiceAction: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 9,
    minHeight: 30,
    paddingHorizontal: 9,
    paddingVertical: 5,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
  },
  voiceActionText: {
    fontSize: 12,
    fontWeight: '600',
    letterSpacing: 0,
  },
  voicePanelRight: {
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
    minHeight: 38,
    maxHeight: 112,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 10,
    paddingHorizontal: 10,
    paddingVertical: 8,
    fontSize: 13,
    lineHeight: 17,
    letterSpacing: 0,
  },
  sendButton: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 10,
    minHeight: 38,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 12,
    paddingVertical: 8,
    alignSelf: 'flex-end',
  },
  sendText: {
    fontSize: 12,
    fontWeight: '700',
    letterSpacing: 0,
  },
});
