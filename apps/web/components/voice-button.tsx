import { Mic, MicOff, Loader2, WavesIcon } from 'lucide-react';
import { useVoice } from '@/providers/voice-provider';
import { motion } from 'motion/react';

import { useSession } from '@/lib/auth-client';
import { useQueryState } from 'nuqs';

export function VoiceButton() {
  const { data: session } = useSession();
  const [threadId] = useQueryState('threadId');

  const { status, isInitializing, isSpeaking, transcript, startConversation, endConversation } =
    useVoice();

  const isConnected = status === 'connected';

  const handleStartConversation = async () => {
    const context = {
      hasOpenEmail: !!threadId,
      currentThreadId: threadId || null,
    };

    await startConversation(context);
  };

  if (!session) {
    return null;
  }

  if (!isConnected) {
    return (
      <motion.div initial={{ scale: 0 }} animate={{ scale: 1 }} exit={{ scale: 0 }}>
        <button type="button" onClick={handleStartConversation} className="cursor-pointer">
          <div className="dark:bg[#141414] flex h-7 items-center justify-center rounded-sm bg-[#262626] px-2">
            <Mic className="h-4 w-4 text-white dark:text-[#929292]" />
          </div>
        </button>
      </motion.div>
    );
  }

  return (
    isConnected && (
      <div className="relative">
        {/* Live transcript — surfaces what was said so the call isn't "blind" */}
        {transcript.length > 0 && (
          <div className="bg-popover text-popover-foreground absolute bottom-full right-0 mb-2 max-h-48 w-72 overflow-y-auto rounded-lg border p-2 shadow-md">
            <div className="flex flex-col gap-1.5">
              {transcript.slice(-8).map((entry, i) => (
                <div key={`${i}-${entry.role}`} className="text-[12px] leading-snug">
                  <span
                    className={
                      entry.role === 'user'
                        ? 'text-muted-foreground font-medium'
                        : 'text-[var(--mainBlue)] font-medium'
                    }
                  >
                    {entry.role === 'user' ? 'You' : 'Assistant'}:{' '}
                  </span>
                  <span>{entry.text}</span>
                </div>
              ))}
            </div>
          </div>
        )}
        <button type="button" onClick={endConversation} className="cursor-pointer">
          <div className="dark:bg[#141414] flex h-7 items-center justify-center rounded-sm bg-[#262626] px-2">
            {isInitializing && (
              <div className="flex items-center justify-center gap-2">
                <Loader2 className="h-4 w-4 animate-spin" />
              </div>
            )}
            {!isInitializing &&
              (isSpeaking ? (
                <WavesIcon className="h-4 w-4 text-white dark:text-[#929292]" />
              ) : (
                <MicOff className="h-4 w-4 text-white dark:text-[#929292]" />
              ))}
          </div>
        </button>
      </div>
    )
  );
}
