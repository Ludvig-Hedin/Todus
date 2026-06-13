import { createContext, useContext, useState } from 'react';
import { useConversation } from '@elevenlabs/react';
import { callServerTool } from '@/lib/server-tool';
import { useSession } from '@/lib/auth-client';
import type { ReactNode } from 'react';
import { toast } from 'sonner';

export interface VoiceTranscriptEntry {
  role: 'user' | 'ai';
  text: string;
}

interface VoiceContextType {
  status: string;
  isInitializing: boolean;
  isSpeaking: boolean;
  hasPermission: boolean;
  lastToolCall: string | null;
  isOpen: boolean;
  transcript: VoiceTranscriptEntry[];

  startConversation: (context?: any) => Promise<void>;
  endConversation: () => Promise<void>;
  requestPermission: () => Promise<boolean>;
  sendContext: (context: any) => void;
}

// Client-tool names exposed to the ElevenLabs voice agent. These MUST match the
// server-side tool keys in apps/server/src/types.ts (`Tools` enum) verbatim, because
// the name is passed straight through to `aiRouter.post('/do/:action')` and used to
// look up `tools()[action]`. A mismatch → 404 "Tool not found".
//
// IMPORTANT: registering these here is only half the wiring. The same tool names +
// their JSON parameter schemas must also be added as Client Tools to the ElevenLabs
// agent in the dashboard, otherwise the model will never emit the tool call.
// See the project docs / PR notes for the exact dashboard schemas.
const toolNames = [
  // Tasks
  'createTask',
  'updateTask',
  'completeTask',
  'listTasks',
  // Calendar
  'createEvent',
  // Email actions
  'sendEmail',
  'composeEmail',
  'markThreadsRead',
  'markThreadsUnread',
  'bulkArchive',
  'bulkDelete',
  // Labels
  'createLabel',
  'deleteLabel',
  'modifyLabels',
  'getUserLabels',
  // Read / search
  'getThread',
  'getThreadSummary',
  'inboxRag',
  'buildGmailSearchQuery',
  'webSearch',
  'getCurrentDate',
  // Meetings ("second brain")
  'listMeetings',
  'getMeetingSummary',
  'searchMeetingTranscript',
] as const;

const VoiceContext = createContext<VoiceContextType | undefined>(undefined);

export function VoiceProvider({ children }: { children: ReactNode }) {
  const { data: session } = useSession();
  const [hasPermission, setHasPermission] = useState(false);
  const [isInitializing, setIsInitializing] = useState(false);
  const [lastToolCall, setLastToolCall] = useState<string | null>(null);
  const [isOpen, setOpen] = useState(false);
  const [, setCurrentContext] = useState<any>(null);
  const [transcript, setTranscript] = useState<VoiceTranscriptEntry[]>([]);

  const conversation = useConversation({
    onConnect: () => {
      setIsInitializing(false);
      // TODO: Send initial context if available when API supports it
    },
    onDisconnect: () => {
      setIsInitializing(false);
      setLastToolCall(null);
    },
    onError: (error: string | Error) => {
      toast.error(typeof error === 'string' ? error : error.message);
      setIsInitializing(false);
    },
    onMessage: ({ message, source }: { message: string; source: 'user' | 'ai' }) => {
      // Surface the live transcript so the conversation isn't "blind".
      // (Belongs on the hook callbacks, not startSession.)
      if (typeof message === 'string' && message.length > 0) {
        setTranscript((prev) => [...prev, { role: source, text: message }]);
      }
    },
    // Client tools: the voice agent calls these by name; we proxy each to the
    // server via callServerTool → POST /api/ai/do/:name (authed by session cookie).
    // ElevenLabs returns whatever we return here back into the conversation, so the
    // agent can confirm the action and read back results. Errors surface as toasts
    // and are re-thrown so the agent knows the tool failed.
    clientTools: toolNames.reduce(
      (acc, name) => {
        acc[name] = async (params: Record<string, unknown>) => {
          setLastToolCall(`Running ${name}…`);
          try {
            const result = await callServerTool(
              name,
              params ?? {},
              session?.user?.email ?? '',
            );
            setLastToolCall(null);
            // ElevenLabs requires a string return value for client tools.
            return typeof result === 'string' ? result : JSON.stringify(result ?? { success: true });
          } catch (err) {
            setLastToolCall(null);
            const message = err instanceof Error ? err.message : String(err);
            toast.error(`Voice action "${name}" failed: ${message}`);
            // Return (don't throw) a structured error so the agent can recover
            // gracefully and tell the user, instead of crashing the turn.
            return JSON.stringify({ success: false, error: message });
          }
        };
        return acc;
      },
      {} as Record<string, (params: Record<string, unknown>) => Promise<string>>,
    ),
  });

  const { status, isSpeaking } = conversation;

  const requestPermission = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      stream.getTracks().forEach((track) => track.stop());
      setHasPermission(true);
      return true;
    } catch {
      toast.error('Microphone access denied. Please enable microphone permissions.');
      setHasPermission(false);
      return false;
    }
  };

  const startConversation = async (context?: any) => {
    if (!hasPermission) {
      const result = await requestPermission();
      if (!result) return;
      setHasPermission(result);
    }

    try {
      setIsInitializing(true);
      setTranscript([]);
      if (context) {
        setCurrentContext(context);
      }

      const agentId = import.meta.env.VITE_PUBLIC_ELEVENLABS_AGENT_ID;
      if (!agentId) throw new Error('ElevenLabs Agent ID not configured');

      await conversation.startSession({
        agentId: agentId,
        connectionType: 'webrtc',
        dynamicVariables: {
          user_name: session?.user.name.split(' ')[0] || 'User',
          user_email: session?.user.email || '',
          current_time: new Date().toLocaleString(),
          has_open_email: context?.hasOpenEmail ? 'yes' : 'no',
          current_thread_id: context?.currentThreadId || 'none',
          email_context_info: context?.hasOpenEmail
            ? `The user currently has an email open (thread ID: ${context.currentThreadId}). When the user refers to "this email" or "the current email", you can use the getEmail or summarizeEmail tools WITHOUT providing a threadId parameter - the tools will automatically use the currently open email.`
            : 'No email is currently open. If the user asks about an email, you will need to ask them to open it first or provide a specific thread ID.',
          ...context,
        },
      });

      setOpen(true);
    } catch {
      toast.error('Failed to start conversation. Please try again.');
    }
  };

  const endConversation = async () => {
    try {
      await conversation.endSession();
      setCurrentContext(null);
    } catch {
      toast.error('Failed to end conversation');
    }
  };

  const sendContext = (context: any) => {
    setCurrentContext(context);
  };

  const value: VoiceContextType = {
    status,
    isInitializing,
    isSpeaking,
    hasPermission,
    lastToolCall,
    isOpen,
    transcript,
    startConversation,
    endConversation,
    requestPermission: requestPermission,
    sendContext,
  };

  return <VoiceContext.Provider value={value}>{children}</VoiceContext.Provider>;
}

export function useVoice() {
  const context = useContext(VoiceContext);
  if (!context) {
    throw new Error('useVoice must be used within a VoiceProvider');
  }
  return context;
}

export { VoiceContext };
