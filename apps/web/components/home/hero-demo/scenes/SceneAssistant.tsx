import { useEffect, useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import {
  Sparkles,
  ArrowUp,
  Calendar as CalendarIcon,
  CheckSquare,
  Mail,
  Plus,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import {
  ACCENT_BLUE,
  ASSISTANT_QUESTION,
  ASSISTANT_REPLY,
  PINNED_THREADS,
  PRIMARY_THREADS,
  type MockThread,
} from '../mockData';

const WORDS = ASSISTANT_REPLY.split(' ');

type Phase = 'typing' | 'streaming' | 'done';

export function SceneAssistant({ compact = false }: { compact?: boolean }) {
  if (compact) {
    return <AssistantPanel compact />;
  }
  return (
    <div className="flex h-full min-w-0 flex-1">
      <InboxStrip />
      <AssistantPanel />
    </div>
  );
}

function InboxStrip() {
  const items = [...PINNED_THREADS.slice(0, 2), ...PRIMARY_THREADS.slice(0, 4)];
  return (
    <section className="hidden w-[260px] shrink-0 flex-col border-r border-white/[0.06] lg:flex">
      <header className="flex items-center justify-between px-3 pt-3 pb-2">
        <h3 className="text-[12px] font-semibold text-white">Inbox</h3>
        <span className="text-[10px] text-white/45">281</span>
      </header>
      <ul className="flex-1 space-y-0.5 overflow-hidden px-1.5">
        {items.map((thread: MockThread, i) => (
          <motion.li
            key={thread.id}
            initial={{ opacity: 0, x: -4 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ duration: 0.24, delay: 0.03 * i, ease: [0.16, 1, 0.3, 1] }}
            className="flex items-start gap-2 rounded-md px-1.5 py-1.5 hover:bg-white/[0.03]"
          >
            <div
              className="grid h-6 w-6 shrink-0 place-items-center rounded text-[9px] font-semibold text-white"
              style={{ backgroundColor: thread.initialsColor }}
            >
              {thread.initials}
            </div>
            <div className="min-w-0 flex-1 leading-tight">
              <div className="flex items-baseline gap-1">
                <span
                  className={cn(
                    'truncate text-[10px]',
                    thread.unread ? 'font-semibold text-white' : 'font-medium text-white/80',
                  )}
                >
                  {thread.sender}
                </span>
                <span className="ml-auto shrink-0 text-[9px] text-white/40">{thread.time}</span>
              </div>
              <div className="truncate text-[10px] text-white/70">{thread.subject}</div>
            </div>
          </motion.li>
        ))}
      </ul>
    </section>
  );
}

function AssistantPanel({ compact }: { compact?: boolean }) {
  const [phase, setPhase] = useState<Phase>('typing');
  const [wordIdx, setWordIdx] = useState(0);

  useEffect(() => {
    if (compact) {
      const t = setTimeout(() => {
        setPhase('done');
        setWordIdx(WORDS.length);
      }, 700);
      return () => clearTimeout(t);
    }
    const t = setTimeout(() => setPhase('streaming'), 700);
    return () => clearTimeout(t);
  }, [compact]);

  useEffect(() => {
    if (phase !== 'streaming') return;
    if (wordIdx >= WORDS.length) {
      setPhase('done');
      return;
    }
    const t = setTimeout(() => setWordIdx((i) => i + 1), 95);
    return () => clearTimeout(t);
  }, [phase, wordIdx]);

  return (
    <section className="flex min-w-0 flex-1 flex-col">
      <header className="flex items-center justify-between border-b border-white/[0.06] px-4 py-3">
        <div className="flex items-center gap-2">
          <div className="grid h-7 w-7 place-items-center rounded-full bg-white/[0.06]">
            <Sparkles className="h-3.5 w-3.5" style={{ color: ACCENT_BLUE }} />
          </div>
          <div className="leading-tight">
            <h2 className="text-[13px] font-semibold tracking-tight text-white">Assistant</h2>
            <p className="text-[10px] text-white/45">Claude Sonnet 4.6</p>
          </div>
        </div>
        <div className="flex items-center gap-1">
          <button className="flex h-7 items-center gap-1 rounded-md border border-white/[0.08] px-2 text-[10px] text-white/75 hover:bg-white/[0.04]">
            <Plus className="h-3 w-3" />
            <span>New chat</span>
          </button>
        </div>
      </header>

      <div className="flex-1 space-y-3 overflow-hidden px-4 py-4">
        <motion.div
          initial={{ opacity: 0, y: 6 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.28, ease: [0.16, 1, 0.3, 1] }}
          className="flex justify-end"
        >
          <div
            className="max-w-[78%] rounded-2xl px-3 py-2 text-[11px] text-white"
            style={{ backgroundColor: ACCENT_BLUE }}
          >
            {ASSISTANT_QUESTION}
          </div>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 6 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.28, delay: 0.15, ease: [0.16, 1, 0.3, 1] }}
          className="flex"
        >
          <div className="max-w-[88%] rounded-2xl border border-white/[0.08] bg-white/[0.02] px-3 py-2.5">
            <AnimatePresence mode="wait">
              {phase === 'typing' ? (
                <motion.div
                  key="typing"
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  className="flex items-center gap-1 py-1"
                >
                  {[0, 1, 2].map((i) => (
                    <motion.span
                      key={i}
                      animate={{ opacity: [0.3, 1, 0.3] }}
                      transition={{ duration: 1.0, repeat: Infinity, delay: i * 0.15 }}
                      className="h-1 w-1 rounded-full bg-white/65"
                    />
                  ))}
                </motion.div>
              ) : (
                <motion.p
                  key="reply"
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  className="text-[11px] leading-relaxed text-white"
                  aria-live="off"
                >
                  {WORDS.slice(0, wordIdx).join(' ')}
                  {phase === 'streaming' && (
                    <span
                      className="ml-0.5 inline-block h-3 w-[2px] translate-y-[2px] animate-blink bg-white/75 align-middle"
                      aria-hidden="true"
                    />
                  )}
                </motion.p>
              )}
            </AnimatePresence>
          </div>
        </motion.div>

        <AnimatePresence>
          {phase === 'done' && (
            <motion.div
              initial={{ opacity: 0, y: 6 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.32, ease: [0.16, 1, 0.3, 1] }}
              className="flex flex-wrap gap-1.5"
            >
              <SuggestionCard
                icon={<CalendarIcon className="h-3 w-3" />}
                title="Design review"
                subtitle="9:30 AM · Today"
              />
              <SuggestionCard
                icon={<CheckSquare className="h-3 w-3" />}
                title="Reply to Nick"
                subtitle="Due today"
              />
              <SuggestionCard
                icon={<Mail className="h-3 w-3" />}
                title="Stripe invoice"
                subtitle="Yesterday · Read"
              />
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      <footer className="border-t border-white/[0.06] px-3 py-3">
        <div className="flex items-end gap-2 rounded-xl border border-white/[0.08] bg-white/[0.02] px-3 py-2">
          <div className="flex-1 text-[11px] text-white/45">Ask anything about your inbox…</div>
          <button
            className="grid h-7 w-7 place-items-center rounded-lg text-white"
            style={{ backgroundColor: ACCENT_BLUE }}
          >
            <ArrowUp className="h-3.5 w-3.5" />
          </button>
        </div>
      </footer>
    </section>
  );
}

function SuggestionCard({
  icon,
  title,
  subtitle,
}: {
  icon: React.ReactNode;
  title: string;
  subtitle: string;
}) {
  return (
    <div className="flex items-center gap-2 rounded-lg border border-white/[0.08] bg-white/[0.02] px-2.5 py-1.5">
      <div className="grid h-5 w-5 place-items-center rounded-md bg-white/[0.06] text-white/70">
        {icon}
      </div>
      <div className="leading-tight">
        <div className="text-[10px] font-semibold text-white">{title}</div>
        <div className="text-[9px] text-white/50">{subtitle}</div>
      </div>
    </div>
  );
}
