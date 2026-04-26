import { format, isToday, isValid, parseISO } from 'date-fns';

interface DayCell {
  date: string;
  eventCount: number;
  taskCount: number;
  label: string | null;
}

interface WeeklyAgendaCardProps {
  props: {
    weekStart: string;
    days: DayCell[];
  };
  emit?: (event: string, params?: Record<string, unknown>) => void;
}

function densityClass(count: number): string {
  // Tailwind-only color ramp; tuned to read on both themes.
  if (count === 0) return 'bg-transparent text-[#8C8C8C]';
  if (count <= 2) return 'bg-[#437DFB]/15 text-[#437DFB]';
  if (count <= 5) return 'bg-[#437DFB]/35 text-[#437DFB] font-medium';
  return 'bg-[#437DFB] text-white font-semibold';
}

export function WeeklyAgendaCard({ props, emit }: WeeklyAgendaCardProps) {
  const handleDay = (date: string) => {
    emit?.('press', { action: 'navigate_day', date });
  };

  return (
    <div className="overflow-hidden rounded-xl border border-[#E7E7E7] bg-white dark:border-[#252525] dark:bg-[#1C1C1E]">
      <div className="grid grid-cols-7 divide-x divide-[#E7E7E7] dark:divide-[#252525]">
        {props.days.slice(0, 7).map((day) => {
          const parsed = parseISO(day.date);
          const validDate = isValid(parsed);
          const today = validDate ? isToday(parsed) : false;
          const dow = validDate ? format(parsed, 'EEE') : '';
          const dom = validDate ? format(parsed, 'd') : '';
          const label = day.label ?? (today ? 'Today' : dow);
          const total = day.eventCount + day.taskCount;
          return (
            <button
              key={day.date}
              type="button"
              onClick={() => handleDay(day.date)}
              className="flex flex-col items-center gap-1.5 px-1 py-2.5 text-center transition-colors hover:bg-[#F6F6F7] dark:hover:bg-[#252525]"
            >
              <span className="text-[10px] uppercase tracking-wide text-[#8C8C8C]">{label}</span>
              <span
                className={`flex h-7 w-7 items-center justify-center rounded-full text-sm ${
                  today
                    ? 'bg-[#437DFB] font-semibold text-white'
                    : 'text-black dark:text-white'
                }`}
              >
                {dom}
              </span>
              <span
                className={`flex h-5 w-7 items-center justify-center rounded text-[10px] ${densityClass(total)}`}
                title={`${day.eventCount} event${day.eventCount === 1 ? '' : 's'}, ${day.taskCount} task${day.taskCount === 1 ? '' : 's'}`}
              >
                {total === 0 ? '—' : total}
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
}
