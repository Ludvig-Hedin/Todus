import {
  Calendar as CalendarIcon,
  ListTodo,
  Video,
  FileText,
  Check,
  Plus,
  Sparkles,
  CornerDownLeft,
  ChevronLeft,
  ChevronRight,
  MoreHorizontal,
  Star,
  Paperclip,
  Bold,
  Italic,
  List as ListIcon,
} from 'lucide-react';
import { SplitText } from '@/components/ui/split-text';
import { motion, AnimatePresence } from 'motion/react';
import { useEffect, useRef, useState, type ReactNode } from 'react';

const CalIcon = CalendarIcon as any;
const ListTodoIcon = ListTodo as any;
const VideoIcon = Video as any;
const FileTextIcon = FileText as any;
const CheckIcon = Check as any;
const PlusIcon = Plus as any;
const SparklesIcon = Sparkles as any;
const SubmitIcon = CornerDownLeft as any;
const ChevronLeftIcon = ChevronLeft as any;
const ChevronRightIcon = ChevronRight as any;
const MoreIcon = MoreHorizontal as any;
const StarIcon = Star as any;
const PaperclipIcon = Paperclip as any;
const BoldIcon = Bold as any;
const ItalicIcon = Italic as any;
const ListBulletIcon = ListIcon as any;

type Feature = {
  eyebrow: string;
  title: string;
  description: string;
  icon: ReactNode;
  mockup: ReactNode;
  reverse?: boolean;
};

const features: Feature[] = [
  {
    eyebrow: 'Calendar',
    title: 'See your week without leaving your inbox.',
    description:
      'Drag events around, snooze them to tomorrow, send invites from the same window you reply in.',
    icon: <CalIcon className="h-3.5 w-3.5" />,
    mockup: <CalendarDemo />,
  },
  {
    eyebrow: 'Tasks',
    title: 'Pull tasks out of email. Drop them where they go.',
    description:
      'Ask Todus to turn a thread into a task, or do it by hand. Track them in a list, a board, or by due date.',
    icon: <ListTodoIcon className="h-3.5 w-3.5" />,
    mockup: <TasksDemo />,
    reverse: true,
  },
  {
    eyebrow: 'Meetings',
    title: 'Meetings get transcribed and summarized.',
    description:
      'Record any call, get a clean transcript and a one-paragraph recap linked back to the thread that scheduled it.',
    icon: <VideoIcon className="h-3.5 w-3.5" />,
    mockup: <MeetingsDemo />,
  },
  {
    eyebrow: 'Docs',
    title: 'Notes that live next to the email.',
    description:
      'Write specs, journal a meeting, draft a reply. Docs stay attached to the work you opened them from.',
    icon: <FileTextIcon className="h-3.5 w-3.5" />,
    mockup: <DocsDemo />,
    reverse: true,
  },
];

export function ProductSections() {
  return (
    <div className="relative z-10 mx-auto w-full max-w-7xl px-4">
      <div className="mt-32 text-center md:mt-48">
        <motion.p
          initial={{ opacity: 0, y: 10 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: '-80px' }}
          transition={{ duration: 0.4 }}
          className="text-xs font-medium tracking-wider text-white/40"
        >
          More than email
        </motion.p>
        <h2 className="mx-auto mt-5 max-w-3xl text-3xl font-medium tracking-tight text-white md:text-5xl">
          <SplitText
            text="Inbox, calendar, tasks, meetings, and docs. One app."
            delay={0.1}
            stagger={0.03}
          />
        </h2>
      </div>

      <div className="mt-20 flex flex-col gap-28 md:mt-28 md:gap-40">
        {features.map((feature) => (
          <FeatureRow key={feature.title} {...feature} />
        ))}
      </div>
    </div>
  );
}

function FeatureRow({ eyebrow, title, description, icon, mockup, reverse }: Feature) {
  return (
    <div
      className={`grid grid-cols-1 items-center gap-12 lg:grid-cols-[5fr_7fr] lg:gap-20 ${
        reverse ? 'lg:[&>div:first-child]:order-2' : ''
      }`}
    >
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, margin: '-80px' }}
        transition={{ duration: 0.5 }}
        className="flex flex-col items-start gap-5"
      >
        <div className="inline-flex items-center gap-1.5 text-xs font-medium tracking-wide text-white/40">
          {icon}
          {eyebrow}
        </div>
        <h3 className="text-3xl font-medium tracking-tight text-white md:text-4xl">
          <SplitText text={title} delay={0.05} stagger={0.04} />
        </h3>
        <p className="max-w-md text-base leading-relaxed text-white/55 md:text-lg">
          {description}
        </p>
      </motion.div>

      <motion.div
        initial={{ opacity: 0, y: 30 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, margin: '-80px' }}
        transition={{ duration: 0.6, delay: 0.1 }}
        className="relative"
      >
        <div className="overflow-hidden rounded-2xl border border-white/[0.06] bg-[#0A0A0A] shadow-[0_40px_80px_-30px_rgba(0,0,0,0.7)]">
          {mockup}
        </div>

        <div className="pointer-events-none absolute inset-0 rounded-2xl ring-1 ring-inset ring-white/[0.04]" />
      </motion.div>
    </div>
  );
}

/* ====================================================================
   CALENDAR — interactive week picker, drag handle, animated "now" line
   ==================================================================== */

function CalendarDemo() {
  const [selectedDay, setSelectedDay] = useState(2);
  const [nowOffset, setNowOffset] = useState(155);

  useEffect(() => {
    const id = setInterval(() => {
      setNowOffset((o) => (o > 380 ? 60 : o + 0.5));
    }, 50);
    return () => clearInterval(id);
  }, []);

  const days = [
    { label: 'Mon', date: '12' },
    { label: 'Tue', date: '13' },
    { label: 'Wed', date: '14' },
    { label: 'Thu', date: '15' },
    { label: 'Fri', date: '16' },
  ];
  const hours = ['9 AM', '10 AM', '11 AM', '12 PM', '1 PM', '2 PM', '3 PM', '4 PM'];

  const events: {
    col: number;
    top: number;
    height: number;
    title: string;
    sub: string;
    tone: 'blue' | 'green' | 'pink' | 'amber';
    highlight?: boolean;
  }[] = [
    { col: 0, top: 6, height: 60, title: 'Standup', sub: '9:00 – 9:30', tone: 'blue' },
    { col: 2, top: 132, height: 86, title: 'Design review', sub: '11:00 – 12:00 · Sarah', tone: 'blue', highlight: true },
    { col: 1, top: 224, height: 50, title: '1:1 w/ Jay', sub: '12:30 – 1:00', tone: 'green' },
    { col: 4, top: 60, height: 44, title: 'Coffee · Sarah', sub: '10:00 – 10:30', tone: 'pink' },
    { col: 3, top: 290, height: 64, title: 'Ship plan', sub: '2:00 – 3:00 · Jay, Ali', tone: 'amber' },
    { col: 0, top: 240, height: 52, title: 'Review PRs', sub: '1:00 – 1:30', tone: 'green' },
  ];

  const tones = {
    blue: {
      solid: 'bg-[#007AFF] text-white border-[#007AFF]',
      soft: 'bg-[#007AFF]/15 text-[#9ECBFF] border-[#007AFF]/30',
    },
    green: {
      solid: 'bg-[#30D158] text-black border-[#30D158]',
      soft: 'bg-[#30D158]/12 text-[#7FE7A0] border-[#30D158]/25',
    },
    pink: {
      solid: 'bg-[#FF375F] text-white border-[#FF375F]',
      soft: 'bg-[#FF375F]/12 text-[#FFA0B4] border-[#FF375F]/25',
    },
    amber: {
      solid: 'bg-[#FFD60A] text-black border-[#FFD60A]',
      soft: 'bg-[#FFD60A]/12 text-[#FFE680] border-[#FFD60A]/25',
    },
  } as const;

  return (
    <div className="flex flex-col">
      <div className="flex items-center justify-between border-b border-white/[0.06] px-5 py-3">
        <div className="flex items-center gap-3">
          <div className="text-[13px] font-semibold text-white/90">May 12 – 16, 2026</div>
          <div className="flex items-center gap-0.5">
            <button className="flex h-6 w-6 items-center justify-center rounded-md text-white/50 transition-colors hover:bg-white/[0.06] hover:text-white">
              <ChevronLeftIcon className="h-3.5 w-3.5" />
            </button>
            <button className="flex h-6 w-6 items-center justify-center rounded-md text-white/50 transition-colors hover:bg-white/[0.06] hover:text-white">
              <ChevronRightIcon className="h-3.5 w-3.5" />
            </button>
          </div>
          <button className="rounded-md border border-white/[0.08] bg-white/[0.04] px-2 py-0.5 text-[11px] font-medium text-white/80 transition-colors hover:bg-white/[0.08]">
            Today
          </button>
        </div>
        <div className="flex items-center gap-0.5 rounded-md border border-white/[0.06] bg-white/[0.02] p-0.5 text-[10.5px]">
          {['Day', 'Week', 'Month', 'Year'].map((v) => (
            <button
              key={v}
              className={`rounded-[5px] px-2 py-1 transition-colors ${
                v === 'Week'
                  ? 'bg-white/[0.08] text-white'
                  : 'text-white/45 hover:text-white/75'
              }`}
            >
              {v}
            </button>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-[44px_repeat(5,minmax(0,1fr))] border-b border-white/[0.06]">
        <div />
        {days.map((d, i) => (
          <button
            key={d.label}
            onClick={() => setSelectedDay(i)}
            className={`group flex flex-col items-center gap-0.5 border-l border-white/[0.05] py-2 transition-colors ${
              selectedDay === i ? 'bg-white/[0.04]' : 'hover:bg-white/[0.02]'
            }`}
          >
            <span
              className={`text-[9px] font-medium tracking-wider ${
                selectedDay === i ? 'text-white/70' : 'text-white/40'
              }`}
            >
              {d.label.toUpperCase()}
            </span>
            <span
              className={`flex h-5 w-5 items-center justify-center rounded-full text-[11px] font-semibold ${
                selectedDay === i
                  ? 'bg-[#007AFF] text-white'
                  : 'text-white/85'
              }`}
            >
              {d.date}
            </span>
          </button>
        ))}
      </div>

      <div className="grid grid-cols-[44px_repeat(5,minmax(0,1fr))] border-b border-white/[0.05] bg-white/[0.01]">
        <div className="py-1 pr-1.5 text-right text-[8.5px] font-medium tracking-wider text-white/30">
          ALL-DAY
        </div>
        {days.map((d, i) => (
          <div key={d.label} className="border-l border-white/[0.04] p-1">
            {i === 1 && (
              <div className="rounded-sm bg-[#FFD60A]/15 px-1.5 py-0.5 text-[9px] font-medium text-[#FFE680]">
                Off-site
              </div>
            )}
          </div>
        ))}
      </div>

      <div className="relative grid grid-cols-[44px_repeat(5,minmax(0,1fr))]">
        <div className="flex flex-col">
          {hours.map((h) => (
            <div
              key={h}
              className="h-12 pr-1.5 pt-0.5 text-right text-[8.5px] font-medium text-white/30"
            >
              {h}
            </div>
          ))}
        </div>

        {days.map((d, colIdx) => (
          <div key={d.label} className="relative border-l border-white/[0.04]">
            {hours.map((h, i) => (
              <div
                key={h}
                className={`h-12 border-b border-white/[0.03] ${
                  selectedDay === colIdx ? 'bg-white/[0.012]' : ''
                }`}
              />
            ))}

            {events
              .filter((e) => e.col === colIdx)
              .map((e, i) => {
                const tone = tones[e.tone];
                return (
                  <motion.div
                    key={e.title}
                    initial={{ opacity: 0, y: 6, scale: 0.96 }}
                    whileInView={{ opacity: 1, y: 0, scale: 1 }}
                    whileHover={{ scale: 1.02 }}
                    viewport={{ once: true, margin: '-40px' }}
                    transition={{ duration: 0.4, delay: 0.15 + i * 0.06 }}
                    className={`absolute left-1 right-1 cursor-pointer overflow-hidden rounded-md border px-1.5 py-1 text-[10px] font-medium leading-tight ${
                      e.highlight ? tone.solid : tone.soft
                    } ${e.highlight ? 'shadow-[0_4px_12px_rgba(0,122,255,0.3)]' : ''}`}
                    style={{ top: `${e.top}px`, height: `${e.height}px` }}
                  >
                    <div className="flex items-start justify-between gap-1">
                      <div className="min-w-0 truncate">{e.title}</div>
                      {e.highlight && (
                        <div className="flex shrink-0 -space-x-0.5">
                          <div className="h-2.5 w-2.5 rounded-full border border-[#007AFF] bg-zinc-300" />
                          <div className="h-2.5 w-2.5 rounded-full border border-[#007AFF] bg-zinc-500" />
                        </div>
                      )}
                    </div>
                    <div
                      className={`mt-0.5 truncate text-[8.5px] font-normal ${
                        e.highlight ? 'text-white/80' : 'opacity-65'
                      }`}
                    >
                      {e.sub}
                    </div>
                  </motion.div>
                );
              })}
          </div>
        ))}

        <motion.div
          className="pointer-events-none absolute inset-x-0 z-10 h-px bg-[#FF453A]"
          style={{ top: `${nowOffset}px` }}
          animate={{ opacity: [0.6, 1, 0.6] }}
          transition={{ duration: 2.4, repeat: Infinity, ease: 'easeInOut' }}
        >
          <div className="absolute -left-1 -top-[3px] h-1.5 w-1.5 rounded-full bg-[#FF453A] ring-2 ring-[#FF453A]/30" />
          <div className="absolute -top-[6px] left-12 rounded-sm bg-[#FF453A] px-1 py-0.5 text-[7.5px] font-semibold text-white">
            NOW
          </div>
        </motion.div>
      </div>
    </div>
  );
}

/* ====================================================================
   TASKS — toggleable checkboxes, hover lift, generated-from-email card
   ==================================================================== */

function TasksDemo() {
  type Task = {
    id: string;
    title: string;
    desc?: string;
    due?: string;
    priority?: 'high' | 'med' | 'low';
    done?: boolean;
    fromThread?: string;
    avatars?: string[];
  };
  const initial: { label: string; tasks: Task[] }[] = [
    {
      label: 'To do',
      tasks: [
        {
          id: '1',
          title: 'Reply to Nick about Q3 plan',
          desc: 'Confirm scope + ETA, attach the new pricing deck.',
          due: 'Today',
          priority: 'high',
          fromThread: 'Nick · Re: Q3 budget review',
          avatars: ['N'],
        },
        {
          id: '2',
          title: 'Send invoice to Acme',
          desc: 'Use the May template, $12,500 net 30.',
          due: 'Tomorrow',
          priority: 'med',
          avatars: ['A'],
        },
        { id: '3', title: 'Draft launch tweet', priority: 'low' },
      ],
    },
    {
      label: 'Doing',
      tasks: [
        {
          id: '4',
          title: 'Spec mobile sync flow',
          desc: 'Edge cases: stale token, offline send, conflict resolution.',
          due: 'Fri',
          priority: 'med',
          avatars: ['L', 'J'],
        },
        { id: '5', title: 'Review design feedback', priority: 'low', avatars: ['S'] },
      ],
    },
    {
      label: 'Done',
      tasks: [
        { id: '6', title: 'Renew domain', done: true },
        { id: '7', title: 'Approve PR #2104', done: true },
        { id: '8', title: 'Pay Stripe invoice', done: true },
      ],
    },
  ];

  const [tasks, setTasks] = useState(initial);

  const toggle = (colIdx: number, id: string) => {
    setTasks((prev) =>
      prev.map((c, i) =>
        i === colIdx ? { ...c, tasks: c.tasks.map((t) => (t.id === id ? { ...t, done: !t.done } : t)) } : c,
      ),
    );
  };

  const priorityCls = {
    high: { dot: 'bg-[#FF453A]', label: 'text-[#FF6961]' },
    med: { dot: 'bg-[#FFD60A]', label: 'text-[#FFE680]' },
    low: { dot: 'bg-white/30', label: 'text-white/40' },
  } as const;

  return (
    <div className="p-4">
      <div className="mb-3 flex items-center justify-between px-1">
        <div className="flex items-center gap-2">
          <div className="text-[13px] font-semibold text-white/90">All tasks</div>
          <div className="rounded-full bg-white/[0.06] px-1.5 py-0.5 text-[9px] font-medium text-white/55">
            {tasks.reduce((n, c) => n + c.tasks.length, 0)}
          </div>
        </div>
        <div className="flex items-center gap-2">
          <div className="flex items-center gap-0.5 rounded-md border border-white/[0.06] bg-white/[0.02] p-0.5 text-[10px]">
            {['List', 'Board', 'Dates'].map((v) => (
              <button
                key={v}
                className={`rounded-[5px] px-1.5 py-0.5 transition-colors ${
                  v === 'Board' ? 'bg-white/[0.08] text-white' : 'text-white/40 hover:text-white/70'
                }`}
              >
                {v}
              </button>
            ))}
          </div>
          <button className="rounded-md border border-white/[0.06] bg-white/[0.02] p-1 text-white/45 transition-colors hover:bg-white/[0.06]">
            <PlusIcon className="h-3 w-3" />
          </button>
        </div>
      </div>

      <div className="grid grid-cols-3 gap-2">
        {tasks.map((col, colIdx) => (
          <div
            key={col.label}
            className="flex flex-col gap-1.5 rounded-xl border border-white/[0.06] bg-white/[0.018] p-2"
          >
            <div className="flex items-center justify-between px-1 py-1">
              <div className="flex items-center gap-1.5">
                <div
                  className={`h-1.5 w-1.5 rounded-full ${
                    colIdx === 0 ? 'bg-[#007AFF]' : colIdx === 1 ? 'bg-[#FFD60A]' : 'bg-[#30D158]'
                  }`}
                />
                <div className="text-[11px] font-semibold text-white/80">{col.label}</div>
                <span className="rounded-full bg-white/[0.06] px-1.5 py-0.5 text-[9px] font-medium text-white/50">
                  {col.tasks.length}
                </span>
              </div>
              <button className="rounded p-0.5 text-white/30 transition-colors hover:bg-white/[0.06] hover:text-white/60">
                <PlusIcon className="h-2.5 w-2.5" />
              </button>
            </div>

            <div className="flex flex-col gap-1.5">
              {col.tasks.map((task, i) => (
                <motion.div
                  key={task.id}
                  initial={{ opacity: 0, y: 8 }}
                  whileInView={{ opacity: 1, y: 0 }}
                  whileHover={{ y: -1 }}
                  viewport={{ once: true, margin: '-40px' }}
                  transition={{ duration: 0.4, delay: 0.05 + colIdx * 0.04 + i * 0.04 }}
                  className="group cursor-pointer rounded-lg border border-white/[0.06] bg-[#111111] p-2.5 shadow-[0_1px_0_rgba(255,255,255,0.02),0_8px_20px_-12px_rgba(0,0,0,0.6)] transition-colors hover:border-white/[0.12] hover:bg-[#141414]"
                >
                  <div className="flex items-start gap-2">
                    <button
                      type="button"
                      aria-label={task.done ? 'mark incomplete' : 'mark complete'}
                      onClick={() => toggle(colIdx, task.id)}
                      className={`mt-0.5 flex h-3.5 w-3.5 shrink-0 items-center justify-center rounded-full border transition-all ${
                        task.done
                          ? 'border-[#30D158] bg-[#30D158]'
                          : 'border-white/20 bg-white/[0.03] hover:border-white/40 hover:bg-white/[0.06]'
                      }`}
                    >
                      {task.done && <CheckIcon className="h-2 w-2 text-black" strokeWidth={3.5} />}
                    </button>
                    <div className="min-w-0 flex-1">
                      <div
                        className={`text-[11px] font-medium leading-snug ${
                          task.done ? 'text-white/35 line-through' : 'text-white/90'
                        }`}
                      >
                        {task.title}
                      </div>
                      {task.desc && !task.done && (
                        <div className="mt-0.5 line-clamp-2 text-[10px] leading-snug text-white/45">
                          {task.desc}
                        </div>
                      )}
                    </div>
                  </div>

                  {task.fromThread && !task.done && (
                    <div className="mt-2 ml-[22px] flex items-center gap-1 rounded border border-[#007AFF]/15 bg-[#007AFF]/[0.08] px-1.5 py-0.5">
                      <SparklesIcon className="h-2.5 w-2.5 text-[#9ECBFF]" />
                      <span className="truncate text-[8.5px] font-medium text-[#9ECBFF]">
                        {task.fromThread}
                      </span>
                    </div>
                  )}

                  {(task.due || task.priority || task.avatars) && !task.done && (
                    <div className="mt-2 ml-[22px] flex items-center justify-between">
                      <div className="flex items-center gap-1.5">
                        {task.priority && (
                          <div className="flex items-center gap-1">
                            <div className={`h-1 w-1 rounded-full ${priorityCls[task.priority].dot}`} />
                            <span
                              className={`text-[8.5px] font-medium uppercase tracking-wide ${priorityCls[task.priority].label}`}
                            >
                              {task.priority}
                            </span>
                          </div>
                        )}
                        {task.due && (
                          <>
                            <span className="text-white/15">·</span>
                            <span className="text-[9px] text-white/50">{task.due}</span>
                          </>
                        )}
                      </div>
                      {task.avatars && (
                        <div className="flex -space-x-1">
                          {task.avatars.map((a, idx) => (
                            <div
                              key={`${a}-${idx}`}
                              className="flex h-3.5 w-3.5 items-center justify-center rounded-full border border-[#111111] bg-gradient-to-br from-zinc-600 to-zinc-800 text-[7px] font-semibold text-white/85"
                            >
                              {a}
                            </div>
                          ))}
                        </div>
                      )}
                    </div>
                  )}
                </motion.div>
              ))}
            </div>

            {colIdx === 0 && (
              <button className="flex items-center gap-1 rounded-md border border-dashed border-white/[0.08] px-2 py-1.5 text-[9.5px] font-medium text-white/30 transition-colors hover:border-white/[0.15] hover:bg-white/[0.02] hover:text-white/55">
                <PlusIcon className="h-2.5 w-2.5" />
                Add task
              </button>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

/* ====================================================================
   MEETINGS — live recording waveform, AI recap, real transcript scroll
   ==================================================================== */

function MeetingsDemo() {
  const meetings: {
    title: string;
    time: string;
    status: 'live' | 'ready' | 'scheduled' | 'processing';
    duration?: string;
  }[] = [
    { title: 'Launch readiness sync', time: 'Live now', status: 'live', duration: '23:42' },
    { title: 'Design review', time: 'Today · 2:00 PM', status: 'scheduled', duration: '60m' },
    { title: 'Acme intro call', time: 'Yesterday', status: 'ready', duration: '34m' },
    { title: 'Eng standup', time: 'Yesterday', status: 'ready', duration: '12m' },
    { title: 'Investor update', time: 'Mon, May 5', status: 'processing' },
  ];

  const statusBadge = {
    live: { label: 'REC', cls: 'text-[#FF453A] bg-[#FF453A]/12', dot: 'bg-[#FF453A] animate-pulse' },
    scheduled: { label: 'Upcoming', cls: 'text-[#9ECBFF] bg-[#007AFF]/10', dot: 'bg-[#007AFF]/70' },
    ready: { label: 'Recap ready', cls: 'text-[#7FE7A0] bg-[#30D158]/10', dot: 'bg-[#30D158]' },
    processing: { label: 'Processing', cls: 'text-[#FFE680] bg-[#FFD60A]/10', dot: 'bg-[#FFD60A] animate-pulse' },
  } as const;

  return (
    <div className="grid grid-cols-1 gap-0 lg:grid-cols-[1fr_1.2fr]">
      <div className="border-b border-white/[0.06] lg:border-b-0 lg:border-r">
        <div className="flex items-center justify-between border-b border-white/[0.06] px-4 py-3">
          <div className="text-[12px] font-semibold text-white/90">Meetings</div>
          <button className="rounded-md border border-white/[0.06] bg-white/[0.02] p-1 text-white/40 transition-colors hover:bg-white/[0.06] hover:text-white/70">
            <PlusIcon className="h-3 w-3" />
          </button>
        </div>
        <div className="flex flex-col gap-0.5 p-1.5">
          {meetings.map((m, i) => {
            const s = statusBadge[m.status];
            return (
              <motion.div
                key={m.title}
                initial={{ opacity: 0, x: -8 }}
                whileInView={{ opacity: 1, x: 0 }}
                whileHover={i !== 0 ? { x: 2 } : {}}
                viewport={{ once: true, margin: '-40px' }}
                transition={{ duration: 0.4, delay: 0.08 + i * 0.05 }}
                className={`group flex cursor-pointer items-center gap-2.5 rounded-lg px-2.5 py-2 transition-colors ${
                  i === 0
                    ? 'bg-white/[0.05] ring-1 ring-inset ring-white/[0.04]'
                    : 'hover:bg-white/[0.025]'
                }`}
              >
                <div className={`h-1.5 w-1.5 shrink-0 rounded-full ${s.dot}`} />
                <div className="min-w-0 flex-1">
                  <div className="truncate text-[11.5px] font-medium tracking-tight text-white/90">
                    {m.title}
                  </div>
                  <div className="text-[10px] tracking-tight text-white/40">{m.time}</div>
                </div>
                {m.status === 'live' ? (
                  <div className="flex shrink-0 items-center gap-1 rounded-full bg-[#FF453A]/12 px-1.5 py-0.5">
                    <span className="text-[8.5px] font-bold tracking-wider text-[#FF453A]">REC</span>
                    <span className="font-mono text-[8.5px] text-[#FF453A]">{m.duration}</span>
                  </div>
                ) : (
                  <span
                    className={`shrink-0 rounded-full px-1.5 py-0.5 text-[8.5px] font-medium ${s.cls}`}
                  >
                    {s.label}
                  </span>
                )}
              </motion.div>
            );
          })}
        </div>
      </div>

      <div className="flex flex-col gap-3 p-4">
        <div className="flex items-start justify-between gap-2">
          <div className="min-w-0">
            <div className="flex items-center gap-2">
              <div className="flex items-center gap-1 rounded-full bg-[#FF453A]/12 px-1.5 py-0.5">
                <div className="h-1 w-1 animate-pulse rounded-full bg-[#FF453A]" />
                <span className="text-[8px] font-bold tracking-wider text-[#FF453A]">RECORDING</span>
              </div>
              <span className="font-mono text-[10px] text-white/45">00:23:42</span>
            </div>
            <div className="mt-1.5 truncate text-[13px] font-semibold text-white/90">
              Launch readiness sync
            </div>
            <div className="text-[10px] text-white/40">Tue, May 12 · 10:30 – 11:00 AM</div>
          </div>
          <button className="shrink-0 rounded-md border border-white/[0.08] bg-white/[0.03] p-1 text-white/50 hover:bg-white/[0.06]">
            <MoreIcon className="h-3 w-3" />
          </button>
        </div>

        <Waveform />

        <div className="flex items-center justify-between">
          <div className="flex -space-x-1">
            {['EM', 'JL', 'SP', 'TN'].map((a, i) => (
              <div
                key={a}
                className={`flex h-5 w-5 items-center justify-center rounded-full border border-[#0A0A0A] text-[8px] font-semibold text-white/85 ${
                  i === 0
                    ? 'bg-gradient-to-br from-[#007AFF] to-[#0050A0]'
                    : i === 1
                      ? 'bg-gradient-to-br from-[#FF375F] to-[#A0203E]'
                      : i === 2
                        ? 'bg-gradient-to-br from-[#30D158] to-[#1F8939]'
                        : 'bg-gradient-to-br from-[#FFD60A] to-[#A08800]'
                }`}
                style={{ zIndex: 10 - i }}
              >
                {a}
              </div>
            ))}
          </div>
          <div className="text-[9.5px] text-white/40">4 in call</div>
        </div>

        <motion.div
          initial={{ opacity: 0, y: 8 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: '-40px' }}
          transition={{ duration: 0.5, delay: 0.4 }}
          className="rounded-lg border border-[#30D158]/15 bg-[#30D158]/[0.04] p-2.5"
        >
          <div className="flex items-center gap-1.5">
            <SparklesIcon className="h-3 w-3 text-[#30D158]" />
            <span className="text-[9.5px] font-semibold tracking-wider text-[#7FE7A0]">
              AI RECAP · LIVE
            </span>
          </div>
          <div className="mt-1.5 text-[10.5px] leading-relaxed text-white/75">
            Launch confirmed for May 15. Sasha owns the iOS screenshot, due EOD Thursday. Hero shot
            already signed off.
          </div>
        </motion.div>

        <div className="flex flex-col gap-1.5 rounded-lg border border-white/[0.05] bg-white/[0.015] p-2.5">
          <div className="mb-0.5 flex items-center justify-between">
            <span className="text-[9px] font-semibold tracking-wider text-white/35">
              TRANSCRIPT
            </span>
            <span className="font-mono text-[8.5px] text-white/30">00:23:38</span>
          </div>
          <TranscriptLine who="Emma" tone="blue" text="OK, launch is locked for the 15th." />
          <TranscriptLine who="Jay" tone="pink" text="Hero is approved. Waiting on Sasha for the iOS shot." />
          <TranscriptLine who="Sasha" tone="green" text="EOD Thursday, you'll have it." typing />
        </div>
      </div>
    </div>
  );
}

function Waveform() {
  const bars = 40;
  return (
    <div className="flex h-10 items-center gap-[3px] rounded-lg border border-white/[0.05] bg-white/[0.015] px-2.5">
      {Array.from({ length: bars }).map((_, i) => (
        <motion.div
          key={i}
          className="w-0.5 rounded-full bg-[#FF453A]/70"
          animate={{
            height: [
              `${20 + Math.sin(i) * 30 + Math.random() * 10}%`,
              `${60 + Math.cos(i * 0.7) * 20}%`,
              `${15 + Math.sin(i * 1.5) * 25}%`,
            ],
          }}
          transition={{
            duration: 1.2 + (i % 5) * 0.15,
            repeat: Infinity,
            repeatType: 'mirror',
            ease: 'easeInOut',
            delay: i * 0.02,
          }}
        />
      ))}
    </div>
  );
}

function TranscriptLine({
  who,
  text,
  tone,
  typing,
}: {
  who: string;
  text: string;
  tone: 'blue' | 'pink' | 'green';
  typing?: boolean;
}) {
  const colors = {
    blue: 'text-[#9ECBFF]',
    pink: 'text-[#FFA0B4]',
    green: 'text-[#7FE7A0]',
  } as const;
  return (
    <div className="flex gap-2 text-[10px] leading-snug">
      <div className={`w-12 shrink-0 font-semibold ${colors[tone]}`}>{who}</div>
      <div className="text-white/75">
        {text}
        {typing && (
          <span className="ml-0.5 inline-block h-3 w-[2px] -translate-y-[1px] animate-pulse bg-white/60 align-middle" />
        )}
      </div>
    </div>
  );
}

/* ====================================================================
   DOCS — typing title cursor, slash menu, AI rewrite suggestion
   ==================================================================== */

function DocsDemo() {
  const fullTitle = 'Q3 Launch Plan';
  const [titleProgress, setTitleProgress] = useState(fullTitle.length);
  const [editingTitle, setEditingTitle] = useState(false);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    if (!editingTitle) return;
    setTitleProgress(0);
    intervalRef.current = setInterval(() => {
      setTitleProgress((p) => {
        if (p >= fullTitle.length) {
          if (intervalRef.current) clearInterval(intervalRef.current);
          setTimeout(() => setEditingTitle(false), 1400);
          return p;
        }
        return p + 1;
      });
    }, 80);
    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
  }, [editingTitle]);

  const docs = [
    { label: 'Q3 launch plan', active: true, icon: '🚀' },
    { label: 'Hiring loop notes', icon: '📋' },
    { label: 'Pricing experiments', icon: '💰' },
    { label: 'Onboarding rewrite', icon: '📝' },
    { label: 'OKRs · May', icon: '🎯' },
  ];

  return (
    <div className="grid grid-cols-[180px_1fr]">
      <div className="border-r border-white/[0.06] bg-white/[0.005] p-2">
        <div className="flex items-center justify-between px-1.5 py-1">
          <span className="text-[9px] font-bold tracking-wider text-white/35">
            MY WORKSPACE
          </span>
          <button className="rounded p-0.5 text-white/25 hover:bg-white/[0.06] hover:text-white/60">
            <PlusIcon className="h-2.5 w-2.5" />
          </button>
        </div>
        <div className="mt-1 flex flex-col gap-0.5">
          {docs.map((d) => (
            <button
              key={d.label}
              className={`group flex items-center gap-1.5 rounded-md px-2 py-1.5 text-left text-[11px] transition-colors ${
                d.active
                  ? 'bg-white/[0.07] text-white'
                  : 'text-white/55 hover:bg-white/[0.03] hover:text-white/80'
              }`}
            >
              <span className="text-[10px] opacity-80">{d.icon}</span>
              <span className="flex-1 truncate">{d.label}</span>
            </button>
          ))}
        </div>

        <div className="mt-4 px-1.5 py-1 text-[9px] font-bold tracking-wider text-white/35">
          LINKED THREAD
        </div>
        <div className="mt-1 rounded-md border border-white/[0.06] bg-white/[0.025] p-2">
          <div className="flex items-center gap-1.5">
            <div className="h-1 w-1 rounded-full bg-[#007AFF]" />
            <div className="truncate text-[10px] font-semibold text-white/85">Sarah Chen</div>
            <span className="ml-auto text-[8.5px] text-white/35">10:42</span>
          </div>
          <div className="mt-1 truncate text-[9.5px] text-white/45">
            Re: design review for Q3 launch
          </div>
          <div className="mt-1.5 flex items-center gap-1">
            <PaperclipIcon className="h-2 w-2 text-white/35" />
            <span className="text-[8.5px] text-white/35">2 attachments</span>
          </div>
        </div>
      </div>

      <div className="flex flex-col">
        <div className="flex items-center justify-between border-b border-white/[0.04] px-4 py-2">
          <div className="flex items-center gap-1.5 text-[10px] text-white/45">
            <span className="rounded bg-white/[0.06] px-1.5 py-0.5 font-medium text-white/75">
              🚀 Q3 launch plan
            </span>
            <span>·</span>
            <span>Edited 4m ago</span>
          </div>
          <div className="flex items-center gap-0.5">
            <button className="rounded p-1 text-white/40 hover:bg-white/[0.06] hover:text-white/80">
              <BoldIcon className="h-2.5 w-2.5" />
            </button>
            <button className="rounded p-1 text-white/40 hover:bg-white/[0.06] hover:text-white/80">
              <ItalicIcon className="h-2.5 w-2.5" />
            </button>
            <button className="rounded p-1 text-white/40 hover:bg-white/[0.06] hover:text-white/80">
              <ListBulletIcon className="h-2.5 w-2.5" />
            </button>
            <div className="mx-1 h-3 w-px bg-white/10" />
            <button className="rounded p-1 text-white/40 hover:bg-white/[0.06] hover:text-white/80">
              <StarIcon className="h-2.5 w-2.5" />
            </button>
          </div>
        </div>

        <div className="px-5 py-4">
          <button
            onClick={() => setEditingTitle(true)}
            className="text-left text-xl font-bold leading-tight tracking-tight text-white outline-none"
          >
            {editingTitle ? fullTitle.slice(0, titleProgress) : fullTitle}
            {editingTitle && (
              <span className="ml-0.5 inline-block h-4 w-[2px] -translate-y-0.5 animate-pulse bg-[#007AFF] align-middle" />
            )}
          </button>
          <div className="mt-3 h-px w-full bg-white/[0.06]" />

          <motion.div
            initial={{ opacity: 0, y: 6 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true, margin: '-40px' }}
            transition={{ duration: 0.4, delay: 0.2 }}
            className="mt-3 space-y-1.5"
          >
            <div className="h-1.5 w-11/12 rounded-full bg-white/12" />
            <div className="h-1.5 w-10/12 rounded-full bg-white/12" />
            <div className="h-1.5 w-9/12 rounded-full bg-white/12" />
          </motion.div>

          <div className="mt-4 text-[11px] font-bold uppercase tracking-wider text-white/35">
            Owners
          </div>
          <div className="mt-1.5 flex flex-wrap items-center gap-1.5">
            {[
              { name: 'Sarah', role: 'Design', color: 'from-[#007AFF]' },
              { name: 'Jay', role: 'Eng', color: 'from-[#30D158]' },
              { name: 'Emma', role: 'PM', color: 'from-[#FF375F]' },
            ].map((p) => (
              <div
                key={p.name}
                className="flex items-center gap-1.5 rounded-full border border-white/[0.06] bg-white/[0.025] py-0.5 pl-0.5 pr-2"
              >
                <div
                  className={`flex h-4 w-4 items-center justify-center rounded-full bg-gradient-to-br ${p.color} to-zinc-800 text-[7.5px] font-semibold text-white`}
                >
                  {p.name[0]}
                </div>
                <span className="text-[9.5px] text-white/75">{p.name}</span>
                <span className="text-[8.5px] text-white/35">· {p.role}</span>
              </div>
            ))}
          </div>

          <div className="mt-4 text-[11px] font-bold uppercase tracking-wider text-white/35">
            Checklist
          </div>
          <div className="mt-2 flex flex-col gap-1.5">
            {[
              { label: 'Finalize hero copy', done: true },
              { label: 'Capture iOS screenshots', done: true },
              { label: 'Send to investors', done: false },
              { label: 'Schedule launch tweet', done: false },
            ].map((c, i) => (
              <motion.div
                key={c.label}
                initial={{ opacity: 0, x: -4 }}
                whileInView={{ opacity: 1, x: 0 }}
                viewport={{ once: true, margin: '-40px' }}
                transition={{ duration: 0.3, delay: 0.35 + i * 0.05 }}
                className="flex items-center gap-2"
              >
                <div
                  className={`flex h-3.5 w-3.5 items-center justify-center rounded border ${
                    c.done
                      ? 'border-[#30D158] bg-[#30D158]'
                      : 'border-white/15 bg-white/[0.03]'
                  }`}
                >
                  {c.done && <CheckIcon className="h-2 w-2 text-black" strokeWidth={3.5} />}
                </div>
                <div className={`text-[11px] ${c.done ? 'text-white/35 line-through' : 'text-white/85'}`}>
                  {c.label}
                </div>
              </motion.div>
            ))}
          </div>
        </div>

        <div className="mt-auto border-t border-white/[0.04] p-3">
          <AISuggestion onTrigger={() => setEditingTitle(true)} />
        </div>
      </div>
    </div>
  );
}

function AISuggestion({ onTrigger }: { onTrigger: () => void }) {
  return (
    <motion.button
      onClick={onTrigger}
      initial={{ opacity: 0, y: 6 }}
      whileInView={{ opacity: 1, y: 0 }}
      whileHover={{ borderColor: 'rgba(0,122,255,0.4)' }}
      viewport={{ once: true, margin: '-40px' }}
      transition={{ duration: 0.4, delay: 0.6 }}
      className="flex w-full items-center gap-2 rounded-lg border border-white/[0.08] bg-gradient-to-r from-[#007AFF]/[0.06] to-transparent px-2.5 py-2 text-left transition-colors"
    >
      <SparklesIcon className="h-3 w-3 text-[#007AFF]" />
      <div className="flex-1 text-[10.5px]">
        <span className="text-white/80">Summarize the linked thread </span>
        <span className="text-white/35">into a doc section</span>
      </div>
      <kbd className="rounded border border-white/[0.08] bg-white/[0.04] px-1.5 py-0.5 text-[8.5px] font-medium text-white/55">
        <SubmitIcon className="inline h-2.5 w-2.5" />
      </kbd>
    </motion.button>
  );
}
