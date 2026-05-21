import { useEffect, useState } from 'react';
import { motion } from 'motion/react';
import {
  Search,
  Filter,
  Bell,
  Tag,
  AlertCircle,
  Paperclip,
  CornerUpLeft,
  CornerUpRight,
  MoreHorizontal,
  Sparkles,
  Archive,
  Reply,
  Star,
  Pin,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import {
  ACCENT_BLUE,
  AI_SUMMARY,
  PINNED_THREADS,
  PRIMARY_THREADS,
  THREAD_ATTACHMENTS,
  THREAD_MESSAGES,
  type MockThread,
} from '../mockData';

export function SceneInbox({ compact = false }: { compact?: boolean }) {
  const [selectedId, setSelectedId] = useState<string>('p2');

  if (compact) {
    return (
      <div className="flex h-full flex-col">
        <CompactList onSelect={setSelectedId} selectedId={selectedId} />
      </div>
    );
  }

  return (
    <div className="flex h-full min-w-0 flex-1">
      <ThreadList onSelect={setSelectedId} selectedId={selectedId} />
      <ThreadReader />
    </div>
  );
}

function ThreadList({
  onSelect,
  selectedId,
}: {
  onSelect: (id: string) => void;
  selectedId: string;
}) {
  return (
    <section className="flex w-[300px] shrink-0 flex-col border-r border-white/[0.06]">
      <header className="flex items-center justify-between px-3 pt-3 pb-2">
        <h3 className="text-[13px] font-semibold text-white">Inbox</h3>
        <button className="text-[10px] font-medium text-white/45 hover:text-white/70">
          Select
        </button>
      </header>

      <div className="flex items-center gap-1.5 px-3 pb-2">
        <button
          className="flex h-7 items-center gap-1.5 rounded-md px-2.5 text-[10px] font-semibold text-white"
          style={{ backgroundColor: ACCENT_BLUE }}
        >
          <span className="h-1.5 w-1.5 rounded-full bg-white/80" />
          Primary
        </button>
        <button className="flex h-7 w-7 items-center justify-center rounded-md text-white/45 hover:bg-white/[0.05]">
          <AlertCircle className="h-3.5 w-3.5" />
        </button>
        <button className="flex h-7 w-7 items-center justify-center rounded-md text-white/45 hover:bg-white/[0.05]">
          <Bell className="h-3.5 w-3.5" />
        </button>
        <button className="flex h-7 w-7 items-center justify-center rounded-md text-white/45 hover:bg-white/[0.05]">
          <Tag className="h-3.5 w-3.5" />
        </button>
      </div>

      <div className="px-3 pb-2">
        <div className="flex h-7 items-center gap-1.5 rounded-md bg-white/[0.04] px-2 text-[10px] text-white/45">
          <Search className="h-3 w-3" />
          <span className="flex-1">Search</span>
          <kbd className="rounded bg-white/[0.06] px-1 py-px font-mono text-[9px] text-white/55">
            ⌘K
          </kbd>
        </div>
      </div>

      <div className="flex-1 overflow-hidden px-1.5">
        <SectionHeader label="Pinned" count={PINNED_THREADS.length} icon={Pin} />
        <ul className="space-y-0.5">
          {PINNED_THREADS.map((thread, i) => (
            <ThreadRow
              key={thread.id}
              thread={thread}
              index={i}
              selected={thread.id === selectedId}
              onClick={() => onSelect(thread.id)}
            />
          ))}
        </ul>

        <SectionHeader label="Primary" count={276} className="mt-2" />
        <ul className="space-y-0.5">
          {PRIMARY_THREADS.slice(0, 5).map((thread, i) => (
            <ThreadRow
              key={thread.id}
              thread={thread}
              index={i + PINNED_THREADS.length}
              selected={thread.id === selectedId}
              onClick={() => onSelect(thread.id)}
            />
          ))}
        </ul>
      </div>
    </section>
  );
}

function CompactList({
  onSelect,
  selectedId,
}: {
  onSelect: (id: string) => void;
  selectedId: string;
}) {
  const all = [...PINNED_THREADS, ...PRIMARY_THREADS].slice(0, 6);
  return (
    <div className="flex h-full flex-col">
      <header className="flex items-center justify-between px-3 pt-3 pb-2">
        <h3 className="text-[13px] font-semibold text-white">Inbox</h3>
        <span className="text-[10px] text-white/45">281</span>
      </header>
      <ul className="flex-1 space-y-0.5 overflow-hidden px-1.5">
        {all.map((thread, i) => (
          <ThreadRow
            key={thread.id}
            thread={thread}
            index={i}
            selected={thread.id === selectedId}
            onClick={() => onSelect(thread.id)}
            compact
          />
        ))}
      </ul>
    </div>
  );
}

function SectionHeader({
  label,
  count,
  className,
  icon: Icon,
}: {
  label: string;
  count: number;
  className?: string;
  icon?: React.ComponentType<{ className?: string }>;
}) {
  return (
    <div
      className={cn(
        'flex items-center gap-1 px-1.5 pb-1 pt-1 text-[9px] font-semibold uppercase tracking-wider text-white/40',
        className,
      )}
    >
      {Icon && <Icon className="h-2.5 w-2.5" />}
      <span>{label}</span>
      <span className="text-white/30">[{count}]</span>
    </div>
  );
}

function ThreadRow({
  thread,
  index,
  selected,
  onClick,
  compact,
}: {
  thread: MockThread;
  index: number;
  selected: boolean;
  onClick: () => void;
  compact?: boolean;
}) {
  return (
    <motion.li
      initial={{ opacity: 0, y: 4 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.24, delay: 0.025 * index, ease: [0.16, 1, 0.3, 1] }}
    >
      <button
        type="button"
        onClick={onClick}
        className={cn(
          'group flex w-full items-start gap-2.5 rounded-md px-1.5 py-1.5 text-left transition-colors',
          selected ? 'bg-white/[0.06]' : 'hover:bg-white/[0.03]',
        )}
      >
        <div
          className={cn(
            'grid shrink-0 place-items-center rounded text-[9px] font-semibold text-white',
            compact ? 'h-7 w-7' : 'h-6 w-6',
          )}
          style={{ backgroundColor: thread.initialsColor }}
        >
          {thread.initials}
        </div>
        <div className="min-w-0 flex-1 leading-tight">
          <div className="flex items-baseline gap-1.5">
            <span
              className={cn(
                'truncate text-[11px]',
                thread.unread ? 'font-semibold text-white' : 'font-medium text-white/85',
              )}
            >
              {thread.sender}
            </span>
            {typeof thread.count === 'number' && (
              <span className="text-[9px] text-white/45">[{thread.count}]</span>
            )}
            <span className="ml-auto shrink-0 text-[9px] text-white/40">{thread.time}</span>
          </div>
          <div className="truncate text-[11px] text-white/75">{thread.subject}</div>
          {!compact && (
            <div className="truncate text-[10px] text-white/45">{thread.snippet}</div>
          )}
        </div>
      </button>
    </motion.li>
  );
}

function ThreadReader() {
  const [summaryReady, setSummaryReady] = useState(false);

  useEffect(() => {
    const t = setTimeout(() => setSummaryReady(true), 600);
    return () => clearTimeout(t);
  }, []);

  return (
    <section className="flex min-w-0 flex-1 flex-col">
      <header className="flex items-start justify-between gap-2 border-b border-white/[0.06] px-4 pb-3 pt-3">
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2 text-[10px] text-white/40">
            <span className="inline-block h-1.5 w-1.5 rounded-full bg-amber-400" />
            <span>March 28 — March 26</span>
          </div>
          <h2 className="mt-1 truncate text-[15px] font-semibold tracking-tight text-white">
            Re: Design review feedback <span className="text-white/40">[6]</span>
          </h2>
          <div className="mt-2 flex items-center gap-2">
            <AvatarStack initials={[
              { letter: 'A', color: '#5957D6' },
              { letter: 'A', color: '#FA8C33' },
              { letter: 'S', color: '#33ADC7' },
            ]} />
            <div className="flex items-center gap-1 text-[10px] text-white/55">
              <span>Ali</span>
              <span className="text-white/30">·</span>
              <span>Alex</span>
              <span className="text-white/30">·</span>
              <span>Sarah</span>
            </div>
          </div>
        </div>
        <div className="flex shrink-0 items-center gap-1">
          <ReaderIconButton icon={Star} />
          <button
            className="flex h-7 items-center gap-1 rounded-md px-2.5 text-[10px] font-semibold text-white"
            style={{ backgroundColor: ACCENT_BLUE }}
          >
            <Reply className="h-3 w-3" />
            <span>Reply all</span>
          </button>
          <ReaderIconButton icon={Archive} />
          <ReaderIconButton icon={MoreHorizontal} />
        </div>
      </header>

      <div className="flex-1 space-y-3 overflow-hidden px-4 py-3">
        <motion.div
          initial={{ opacity: 0, y: 6 }}
          animate={{ opacity: summaryReady ? 1 : 0, y: summaryReady ? 0 : 6 }}
          transition={{ duration: 0.4, ease: [0.16, 1, 0.3, 1] }}
          className="rounded-lg border border-white/[0.08] bg-white/[0.025] px-3 py-2.5"
        >
          <div className="flex items-center gap-1.5 text-[10px] font-semibold uppercase tracking-wider text-white/65">
            <Sparkles className="h-3 w-3" style={{ color: ACCENT_BLUE }} />
            <span>AI Summary</span>
          </div>
          <p className="mt-1.5 text-[11px] leading-relaxed text-white/75">{AI_SUMMARY}</p>
        </motion.div>

        <div className="space-y-1.5">
          <div className="flex items-center gap-1.5 text-[10px] font-semibold uppercase tracking-wider text-white/45">
            <Paperclip className="h-2.5 w-2.5" />
            <span>Attachments [{THREAD_ATTACHMENTS.length}]</span>
          </div>
          <div className="flex flex-wrap gap-1.5">
            {THREAD_ATTACHMENTS.map((att) => (
              <AttachmentChip key={att.id} name={att.name} size={att.size} kind={att.kind} />
            ))}
          </div>
        </div>

        <ul className="space-y-3 overflow-hidden">
          {THREAD_MESSAGES.map((msg, i) => (
            <motion.li
              key={msg.id}
              initial={{ opacity: 0, y: 6 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.28, delay: 0.08 * i + 0.2, ease: [0.16, 1, 0.3, 1] }}
              className="rounded-lg border border-white/[0.05] bg-white/[0.015] px-3 py-2.5"
            >
              <div className="flex items-start gap-2">
                <div
                  className="grid h-6 w-6 shrink-0 place-items-center rounded-full text-[9px] font-semibold text-white"
                  style={{ backgroundColor: msg.initialsColor }}
                >
                  {msg.initials}
                </div>
                <div className="min-w-0 flex-1">
                  <div className="flex items-baseline justify-between gap-2">
                    <span className="text-[11px] font-semibold text-white">{msg.author}</span>
                    <span className="text-[9px] text-white/40">{msg.time}</span>
                  </div>
                  <p className="mt-1 text-[11px] leading-relaxed text-white/75 line-clamp-3">
                    {msg.body}
                  </p>
                  <div className="mt-2 flex items-center gap-1">
                    <ReplyButton icon={CornerUpLeft} label="Reply" />
                    <ReplyButton icon={CornerUpRight} label="Forward" />
                  </div>
                </div>
              </div>
            </motion.li>
          ))}
        </ul>
      </div>
    </section>
  );
}

function AvatarStack({ initials }: { initials: { letter: string; color: string }[] }) {
  return (
    <div className="flex -space-x-1.5">
      {initials.map((i, idx) => (
        <div
          key={idx}
          className="grid h-5 w-5 place-items-center rounded-full border-[1.5px] border-[#1C1C1E] text-[9px] font-semibold text-white"
          style={{ backgroundColor: i.color }}
        >
          {i.letter}
        </div>
      ))}
    </div>
  );
}

function ReaderIconButton({ icon: Icon }: { icon: React.ComponentType<{ className?: string }> }) {
  return (
    <button className="flex h-7 w-7 items-center justify-center rounded-md text-white/55 hover:bg-white/[0.05] hover:text-white">
      <Icon className="h-3.5 w-3.5" />
    </button>
  );
}

function ReplyButton({
  icon: Icon,
  label,
}: {
  icon: React.ComponentType<{ className?: string }>;
  label: string;
}) {
  return (
    <button className="flex h-6 items-center gap-1 rounded-md border border-white/[0.08] px-2 text-[10px] text-white/65 hover:bg-white/[0.04] hover:text-white">
      <Icon className="h-2.5 w-2.5" />
      <span>{label}</span>
    </button>
  );
}

const KIND_COLOR: Record<string, string> = {
  fig: '#0ACF83',
  doc: '#2563EB',
  image: '#A855F7',
  pdf: '#EF4444',
};

function AttachmentChip({
  name,
  size,
  kind,
}: {
  name: string;
  size: string;
  kind: string;
}) {
  const color = KIND_COLOR[kind] ?? '#737378';
  return (
    <div className="inline-flex items-center gap-1.5 rounded-md border border-white/[0.06] bg-white/[0.02] px-1.5 py-1">
      <div
        className="grid h-4 w-4 place-items-center rounded text-[7px] font-bold uppercase text-white"
        style={{ backgroundColor: color }}
      >
        {kind.slice(0, 3)}
      </div>
      <span className="text-[10px] text-white/80">{name}</span>
      <span className="text-[9px] text-white/40">{size}</span>
    </div>
  );
}
