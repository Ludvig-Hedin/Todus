import { useEffect, useState } from 'react';
import { motion } from 'motion/react';
import { Check, Plus, Inbox, ListChecks, Star, Calendar as CalendarIcon } from 'lucide-react';
import { cn } from '@/lib/utils';
import { ACCENT_BLUE, TASKS, type MockTask } from '../mockData';

const SIDEBAR_LISTS = [
  { id: 'today', label: 'Today', icon: ListChecks, count: 4, active: true },
  { id: 'next7', label: 'Next 7 days', icon: CalendarIcon, count: 9 },
  { id: 'flagged', label: 'Flagged', icon: Star, count: 2 },
  { id: 'all', label: 'All', icon: Inbox, count: 27 },
];

const LISTS = [
  { id: 'work', label: 'Work', color: '#5957D6', count: 18 },
  { id: 'personal', label: 'Personal', color: '#33ADC7', count: 6 },
  { id: 'reading', label: 'Reading', color: '#FA8C33', count: 3 },
];

export function SceneTasks({ compact = false }: { compact?: boolean }) {
  const [autoCheckedId, setAutoCheckedId] = useState<string | null>(null);

  useEffect(() => {
    const t = setTimeout(() => setAutoCheckedId('ta3'), 1500);
    return () => clearTimeout(t);
  }, []);

  if (compact) {
    return <TaskBody autoCheckedId={autoCheckedId} compact />;
  }

  return (
    <div className="flex h-full min-w-0 flex-1">
      <aside className="hidden w-[170px] shrink-0 flex-col gap-3 border-r border-white/[0.06] px-2.5 py-3 lg:flex">
        <div>
          <div className="px-1.5 pb-1 text-[9px] font-semibold uppercase tracking-wider text-white/40">
            Smart lists
          </div>
          <ul className="flex flex-col">
            {SIDEBAR_LISTS.map((item) => {
              const Icon = item.icon;
              const isActive = item.active;
              return (
                <li key={item.id}>
                  <button
                    className={cn(
                      'relative flex h-7 w-full items-center gap-2 rounded-md px-1.5 text-left text-[11px]',
                      isActive ? 'text-white' : 'text-white/70 hover:text-white',
                    )}
                  >
                    {isActive && (
                      <span className="absolute inset-0 rounded-md bg-white/[0.06]" />
                    )}
                    <Icon className="relative h-3.5 w-3.5" />
                    <span className="relative flex-1 font-medium">{item.label}</span>
                    <span className="relative text-[10px] tabular-nums text-white/40">
                      {item.count}
                    </span>
                  </button>
                </li>
              );
            })}
          </ul>
        </div>

        <div>
          <div className="px-1.5 pb-1 text-[9px] font-semibold uppercase tracking-wider text-white/40">
            Lists
          </div>
          <ul className="flex flex-col">
            {LISTS.map((list) => (
              <li key={list.id}>
                <button className="flex h-7 w-full items-center gap-2 rounded-md px-1.5 text-left text-[11px] text-white/70 hover:text-white">
                  <span
                    className="h-2 w-2 rounded-sm"
                    style={{
                      backgroundColor: `${list.color}80`,
                      border: `1px solid ${list.color}`,
                    }}
                  />
                  <span className="flex-1 font-medium">{list.label}</span>
                  <span className="text-[10px] tabular-nums text-white/40">{list.count}</span>
                </button>
              </li>
            ))}
          </ul>
        </div>
      </aside>

      <TaskBody autoCheckedId={autoCheckedId} />
    </div>
  );
}

function TaskBody({
  autoCheckedId,
  compact = false,
}: {
  autoCheckedId: string | null;
  compact?: boolean;
}) {
  const left = TASKS.filter((t) => !t.completed && t.id !== autoCheckedId).length;
  const grouped = groupBy(TASKS, (t) => t.list ?? 'Other');

  return (
    <section className="flex min-w-0 flex-1 flex-col">
      <header className="flex items-center justify-between border-b border-white/[0.06] px-4 py-3">
        <div>
          <h2 className="text-[15px] font-semibold tracking-tight text-white">Today</h2>
          <p className="text-[10px] text-white/45">{left} tasks remaining</p>
        </div>
        <button
          className="flex h-7 items-center gap-1 rounded-md px-2.5 text-[10px] font-semibold text-white"
          style={{ backgroundColor: ACCENT_BLUE }}
        >
          <Plus className="h-3 w-3" />
          <span>New task</span>
        </button>
      </header>

      <div className="flex-1 overflow-hidden px-4 py-3">
        {Object.entries(grouped).map(([listName, items], gIdx) => (
          <div key={listName} className={cn(gIdx > 0 && 'mt-4')}>
            <div className="mb-1.5 flex items-center gap-1.5 text-[10px] font-semibold uppercase tracking-wider text-white/45">
              <span>{listName}</span>
              <span className="text-white/30">[{items.length}]</span>
            </div>
            <ul className="space-y-0.5">
              {items.map((task, i) => (
                <TaskRow
                  key={task.id}
                  task={task}
                  index={i + gIdx * 10}
                  autoChecked={autoCheckedId === task.id}
                  compact={compact}
                />
              ))}
            </ul>
          </div>
        ))}

        <div className="mt-3 flex items-center gap-2 rounded-md border border-dashed border-white/[0.08] px-2.5 py-2 text-[11px] text-white/45">
          <Plus className="h-3 w-3" />
          <span>Add task</span>
          <motion.span
            animate={{ opacity: [1, 0, 1] }}
            transition={{ duration: 1.1, repeat: Infinity, ease: 'easeInOut' }}
            className="ml-0.5 h-3 w-px bg-white/65"
            aria-hidden="true"
          />
        </div>
      </div>
    </section>
  );
}

function TaskRow({
  task,
  index,
  autoChecked,
  compact,
}: {
  task: MockTask;
  index: number;
  autoChecked: boolean;
  compact?: boolean;
}) {
  const isChecked = task.completed || autoChecked;
  return (
    <motion.li
      initial={{ opacity: 0, y: 4 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.24, delay: 0.04 * index, ease: [0.16, 1, 0.3, 1] }}
      className="flex items-center gap-3 rounded-md px-1.5 py-1.5 hover:bg-white/[0.03]"
    >
      <span
        aria-hidden="true"
        className={cn(
          'grid h-4 w-4 shrink-0 place-items-center rounded-full border transition-colors duration-200',
          isChecked
            ? 'border-white bg-white text-[#1C1C1E]'
            : 'border-white/35',
        )}
      >
        {isChecked && <Check className="h-2.5 w-2.5" strokeWidth={3} />}
      </span>
      <div className="relative min-w-0 flex-1">
        <span
          className={cn(
            'block truncate text-[11px] font-medium transition-colors duration-200',
            isChecked ? 'text-white/45' : 'text-white',
          )}
        >
          {task.label}
        </span>
        <motion.span
          initial={false}
          animate={{ scaleX: isChecked ? 1 : 0 }}
          transition={{ duration: 0.28, ease: [0.16, 1, 0.3, 1] }}
          className="absolute left-0 top-1/2 h-px w-full origin-left bg-white/40"
          aria-hidden="true"
        />
      </div>
      {task.due && !compact && (
        <span
          className={cn(
            'shrink-0 rounded px-1.5 py-0.5 text-[9px] font-medium',
            isChecked ? 'text-white/40' : 'bg-white/[0.06] text-white/75',
          )}
        >
          {task.due}
        </span>
      )}
    </motion.li>
  );
}

function groupBy<T, K extends string>(arr: T[], fn: (item: T) => K): Record<K, T[]> {
  return arr.reduce(
    (acc, item) => {
      const key = fn(item);
      (acc[key] = acc[key] ?? []).push(item);
      return acc;
    },
    {} as Record<K, T[]>,
  );
}
