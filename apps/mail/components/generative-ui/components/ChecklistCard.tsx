import { Check } from 'lucide-react';
import { useState } from 'react';

interface ChecklistItem {
  id: string;
  label: string;
  done: boolean;
}

interface ChecklistCardProps {
  props: {
    title: string | null;
    items: ChecklistItem[];
  };
  emit?: (event: string, params?: Record<string, unknown>) => void;
}

export function ChecklistCard({ props, emit }: ChecklistCardProps) {
  // Local state so toggles feel instant; emit fires for server-side persistence if hooked up.
  const [items, setItems] = useState(props.items);

  const toggle = (id: string) => {
    setItems((prev) => prev.map((it) => (it.id === id ? { ...it, done: !it.done } : it)));
    const target = items.find((i) => i.id === id);
    const nextDone = target ? !target.done : true;
    emit?.('press', { action: 'toggle_checklist_item', id, done: nextDone ? 'true' : 'false' });
  };

  const total = items.length;
  const completed = items.filter((i) => i.done).length;

  return (
    <div className="overflow-hidden rounded-xl border border-[#E7E7E7] dark:border-[#252525]">
      <div className="flex items-center justify-between bg-[#F6F6F7] px-3 py-2 dark:bg-[#1C1C1E]">
        <p className="text-sm font-medium text-black dark:text-white">{props.title ?? 'Checklist'}</p>
        <span className="text-xs text-[#8C8C8C]">
          {completed}/{total}
        </span>
      </div>
      <ul className="flex flex-col">
        {items.map((it, idx) => (
          <li
            key={it.id}
            className={idx > 0 ? 'border-t border-[#E7E7E7] dark:border-[#252525]' : ''}
          >
            <button
              type="button"
              onClick={() => toggle(it.id)}
              className="flex w-full items-center gap-2.5 px-3 py-2 text-left transition-colors hover:bg-[#F6F6F7] dark:hover:bg-[#252525]"
            >
              <span
                className={`flex h-4 w-4 shrink-0 items-center justify-center rounded border ${
                  it.done
                    ? 'border-[#437DFB] bg-[#437DFB] text-white'
                    : 'border-[#E7E7E7] dark:border-[#3a3a3a]'
                }`}
              >
                {it.done && <Check className="h-2.5 w-2.5" />}
              </span>
              <span
                className={`text-sm ${it.done ? 'text-[#8C8C8C] line-through' : 'text-black dark:text-white'}`}
              >
                {it.label}
              </span>
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}
