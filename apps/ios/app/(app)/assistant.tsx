import {
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { extractResponseText, nextStreamCursor } from '../../src/features/assistant/assistantUtils';
import { captureEvent } from '../../src/shared/telemetry/posthog';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTRPC } from '../../src/providers/QueryTrpcProvider';
import { useTheme } from '../../src/shared/theme/ThemeContext';
import { useMutation } from '@tanstack/react-query';
import { useEffect, useRef, useState } from 'react';

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

  const canSend = input.trim().length > 0 && !isStreaming;

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

  useEffect(() => {
    return () => {
      if (streamTimerRef.current) {
        clearInterval(streamTimerRef.current);
      }
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
      }
    }, 20);
  };

  const emptyState = (
    <View style={styles.emptyState}>
      <Text style={[styles.emptyTitle, { color: colors.foreground }]}>AI Assistant</Text>
      <Text style={[styles.emptyBody, { color: colors.mutedForeground }]}>
        Ask for summaries, drafts, or quick writing help.
      </Text>
      <View style={styles.quickPromptList}>
        {QUICK_PROMPTS.map((prompt) => (
          <Pressable
            key={prompt}
            style={[styles.quickPrompt, { borderColor: colors.border }]}
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
          { paddingTop: insets.top + 10, borderBottomColor: colors.border, backgroundColor: colors.card },
        ]}
      >
        <Text style={[styles.headerTitle, { color: colors.foreground }]}>Assistant</Text>
        <Pressable
          style={[styles.clearButton, { borderColor: colors.border }]}
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
        style={styles.messageList}
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
                    ? [styles.userBubble, { backgroundColor: colors.primary }]
                    : [styles.assistantBubble, { backgroundColor: colors.secondary }],
                ]}
              >
                <Text
                  style={[
                    styles.messageText,
                    {
                      color:
                        message.role === 'user' ? colors.primaryForeground : colors.secondaryForeground,
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
            paddingBottom: insets.bottom + 10,
            borderTopColor: colors.border,
            backgroundColor: colors.card,
          },
        ]}
      >
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
              backgroundColor: colors.background,
            },
          ]}
          multiline
          editable={!pending}
        />
        <Pressable
          style={[
            styles.sendButton,
            { backgroundColor: canSend ? colors.primary : colors.secondary },
          ]}
          onPress={() => sendPrompt()}
          disabled={!canSend}
        >
          <Text style={[styles.sendText, { color: colors.primaryForeground }]}>Send</Text>
        </Pressable>
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
    paddingBottom: 12,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: '700',
  },
  clearButton: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 8,
    paddingHorizontal: 10,
    paddingVertical: 6,
  },
  clearButtonText: {
    fontSize: 13,
    fontWeight: '600',
  },
  messageList: {
    flex: 1,
  },
  messageContent: {
    padding: 14,
    gap: 10,
  },
  emptyState: {
    paddingTop: 24,
    gap: 8,
  },
  emptyTitle: {
    fontSize: 20,
    fontWeight: '700',
  },
  emptyBody: {
    fontSize: 14,
    lineHeight: 20,
  },
  quickPromptList: {
    marginTop: 8,
    gap: 8,
  },
  quickPrompt: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 10,
    paddingHorizontal: 10,
    paddingVertical: 8,
  },
  quickPromptText: {
    fontSize: 13,
    lineHeight: 18,
  },
  messageBubble: {
    maxWidth: '90%',
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  userBubble: {
    alignSelf: 'flex-end',
  },
  assistantBubble: {
    alignSelf: 'flex-start',
  },
  messageText: {
    fontSize: 14,
    lineHeight: 20,
  },
  pendingText: {
    fontSize: 12,
    fontStyle: 'italic',
    marginTop: 4,
  },
  composer: {
    borderTopWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 12,
    paddingTop: 10,
    flexDirection: 'row',
    alignItems: 'flex-end',
    gap: 10,
  },
  composerInput: {
    flex: 1,
    minHeight: 42,
    maxHeight: 120,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 10,
    paddingHorizontal: 10,
    paddingVertical: 8,
    fontSize: 14,
  },
  sendButton: {
    borderRadius: 10,
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  sendText: {
    fontSize: 14,
    fontWeight: '700',
  },
});
