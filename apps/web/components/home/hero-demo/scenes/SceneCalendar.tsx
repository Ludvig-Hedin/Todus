import { motion } from 'motion/react';
import { ChevronLeft, ChevronRight, Plus } from 'lucide-react';
import { cn } from '@/lib/utils';
import { ACCENT_BLUE, EVENTS } from '../mockData';

const WEEK_DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'] as const;
const WEEK_DATES = [17, 18, 19, 20, 21, 22, 23] as const;
const TODAY_INDEX = 4;
const HOUR_LABELS = ['9', '10', '11', '12', '13', '14', '15', '16', '17', '18'];
const NOW_POSITION = 53;

export function SceneCalendar({ compact = false }: { compact?: boolean }) {
  return (
    <div className="flex h-full min-w-0 flex-1 flex-col">
      <header className="flex items-center justify-between border-b border-white/[0.06] px-4 py-3">
        <div>
          <h2 className="text-[15px] font-semibold tracking-tight text-white">May 2026</h2>
          <p className="text-[10px] text-white/45">Thursday, May 21</p>
        </div>
        <div className="flex items-center gap-1">
          <CalendarIconBtn icon={ChevronLeft} />
          <button className="rounded-md border border-white/[0.08] px-2 py-1 text-[10px] font-medium text-white/75 hover:bg-white/[0.04]">
            Today
          </button>
          <CalendarIconBtn icon={ChevronRight} />
          <button
            className="ml-2 flex h-7 items-center gap-1 rounded-md px-2.5 text-[10px] font-semibold text-white"
            style={{ backgroundColor: ACCENT_BLUE }}
          >
            <Plus className="h-3 w-3" />
            <span>New event</span>
          </button>
        </div>
      </header>

      <div className="flex flex-1 min-h-0">
        <div className="hidden w-[200px] shrink-0 flex-col gap-3 border-r border-white/[0.06] px-3 py-3 lg:flex">
          <MiniMonth />
          <div>
            <div className="px-1 pb-1.5 text-[9px] font-semibold uppercase tracking-wider text-white/40">
              My calendars
            </div>
            <ul className="space-y-1">
              <CalendarLegend label="Work" color="#5957D6" />
              <CalendarLegend label="Personal" color="#33ADC7" />
              <CalendarLegend label="Focus" color="#33B866" />
              <CalendarLegend label="Travel" color="#FA8C33" />
            </ul>
          </div>
        </div>

        <div className="flex flex-1 min-w-0 flex-col px-3 py-3">
          <div className="mb-2 grid grid-cols-7 gap-1">
            {WEEK_DAYS.map((d, i) => {
              const isToday = i === TODAY_INDEX;
              return (
                <div
                  key={d}
                  className={cn(
                    'flex flex-col items-center gap-0.5 rounded-md py-1.5',
                    isToday ? 'text-white' : 'text-white/55',
                  )}
                  style={isToday ? { backgroundColor: ACCENT_BLUE } : undefined}
                >
                  <span className="text-[9px] uppercase tracking-wide opacity-70">{d}</span>
                  <span className="text-[12px] font-semibold tabular-nums">{WEEK_DATES[i]}</span>
                </div>
              );
            })}
          </div>

          <div className="relative flex-1 min-h-0 overflow-hidden rounded-lg border border-white/[0.05] bg-white/[0.015]">
            <div className="absolute inset-y-0 left-0 w-8 border-r border-white/[0.05]">
              {HOUR_LABELS.map((label, i) => (
                <div
                  key={label}
                  className="absolute left-0 right-0 px-1 pt-0.5 text-right text-[9px] text-white/35"
                  style={{ top: `${(i / HOUR_LABELS.length) * 100}%` }}
                >
                  {label}
                </div>
              ))}
            </div>

            <div className="absolute inset-y-0 left-8 right-0">
              {HOUR_LABELS.map((_, i) => (
                <div
                  key={i}
                  className="absolute inset-x-0 border-t border-white/[0.04]"
                  style={{ top: `${(i / HOUR_LABELS.length) * 100}%` }}
                />
              ))}

              {EVENTS.map((event, i) => (
                <motion.div
                  key={event.id}
                  initial={{ opacity: 0, y: 6 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ duration: 0.32, delay: 0.06 * i, ease: [0.16, 1, 0.3, 1] }}
                  className="absolute left-2 right-2 overflow-hidden rounded-md px-2 py-1"
                  style={{
                    top: `${event.top}%`,
                    height: `${event.height}%`,
                    backgroundColor: `${event.color}26`,
                    border: `1px solid ${event.color}55`,
                  }}
                >
                  <div className="flex items-center gap-1">
                    <span
                      className="h-1 w-1 shrink-0 rounded-full"
                      style={{ backgroundColor: event.color }}
                    />
                    <span className="truncate text-[10px] font-semibold text-white">
                      {event.title}
                    </span>
                  </div>
                  <div className="mt-0.5 text-[9px] text-white/65">{event.time}</div>
                </motion.div>
              ))}

              <motion.div
                animate={{ opacity: [0.6, 1, 0.6] }}
                transition={{ duration: 2.4, ease: 'easeInOut', repeat: Infinity }}
                className="absolute inset-x-0 z-10 flex items-center"
                style={{ top: `${NOW_POSITION}%` }}
                aria-hidden="true"
              >
                <div
                  className="h-1.5 w-1.5 -translate-x-[3px] rounded-full"
                  style={{ backgroundColor: ACCENT_BLUE }}
                />
                <div className="h-px flex-1" style={{ backgroundColor: ACCENT_BLUE }} />
              </motion.div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function CalendarIconBtn({ icon: Icon }: { icon: React.ComponentType<{ className?: string }> }) {
  return (
    <button className="flex h-7 w-7 items-center justify-center rounded-md text-white/55 hover:bg-white/[0.05] hover:text-white">
      <Icon className="h-3.5 w-3.5" />
    </button>
  );
}

function CalendarLegend({ label, color }: { label: string; color: string }) {
  return (
    <li className="flex items-center gap-2 px-1 text-[10px] text-white/70">
      <span
        className="h-2 w-2 rounded-sm"
        style={{ backgroundColor: `${color}80`, border: `1px solid ${color}` }}
      />
      {label}
    </li>
  );
}

function MiniMonth() {
  const start = -3;
  const cells = Array.from({ length: 35 }, (_, i) => i + start);
  return (
    <div>
      <div className="mb-1 flex items-center justify-between px-0.5">
        <span className="text-[10px] font-semibold text-white">May 2026</span>
        <div className="flex gap-1">
          <ChevronLeft className="h-3 w-3 text-white/45" />
          <ChevronRight className="h-3 w-3 text-white/45" />
        </div>
      </div>
      <div className="grid grid-cols-7 gap-0.5 px-0.5">
        {WEEK_DAYS.map((d) => (
          <div key={d} className="text-center text-[8px] uppercase text-white/35">
            {d.charAt(0)}
          </div>
        ))}
        {cells.map((n) => {
          const inMonth = n > 0 && n <= 31;
          const isToday = n === 21;
          return (
            <div
              key={n}
              className={cn(
                'grid h-5 place-items-center rounded text-[9px] tabular-nums',
                isToday ? 'font-semibold text-white' : inMonth ? 'text-white/65' : 'text-white/20',
              )}
              style={isToday ? { backgroundColor: ACCENT_BLUE } : undefined}
            >
              {inMonth ? n : ''}
            </div>
          );
        })}
      </div>
    </div>
  );
}
