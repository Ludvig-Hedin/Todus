import { CalendarEventCard } from './CalendarEventCard';

type CalendarEvent = {
  eventId: string;
  title: string;
  start: string;
  end: string;
  location: string | null;
  isAllDay: boolean | null;
  attendees: Array<{ name: string | null; email: string }> | null;
};

interface CalendarEventListCardProps {
  props: {
    title: string | null;
    events: CalendarEvent[];
    summary: string | null;
  };
  emit?: (event: string, params?: Record<string, unknown>) => void;
}

export function CalendarEventListCard({ props, emit }: CalendarEventListCardProps) {
  return (
    <div className="flex flex-col gap-2">
      {props.title && (
        <p className="text-base font-semibold text-black dark:text-white">{props.title}</p>
      )}

      <div className="overflow-hidden rounded-xl border border-[#E7E7E7] dark:border-[#252525]">
        {props.events.map((event, idx) => (
          <div
            key={event.eventId}
            className={idx > 0 ? 'border-t border-[#E7E7E7] dark:border-[#252525]' : ''}
          >
            <CalendarEventCard props={event} emit={emit} />
          </div>
        ))}
      </div>

      {props.summary && (
        <p className="mt-1 text-sm text-black dark:text-white">{props.summary}</p>
      )}
    </div>
  );
}
