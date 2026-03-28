import { format, parseISO, isSameDay } from 'date-fns';
import { Calendar, MapPin, Users } from 'lucide-react';

interface CalendarEventCardProps {
  props: {
    eventId: string;
    title: string;
    start: string;
    end: string;
    location: string | null;
    isAllDay: boolean | null;
    attendees: Array<{ name: string | null; email: string }> | null;
  };
  emit?: (event: string, params?: Record<string, unknown>) => void;
}

export function CalendarEventCard({ props, emit }: CalendarEventCardProps) {
  const handleClick = () => {
    emit?.('press', { action: 'navigate_event', eventId: props.eventId });
  };

  const startDate = parseISO(props.start);
  const endDate = parseISO(props.end);
  const sameDay = isSameDay(startDate, endDate);

  const timeStr = (() => {
    try {
      if (props.isAllDay) return 'All day';
      if (sameDay) {
        return `${format(startDate, 'h:mm a')} – ${format(endDate, 'h:mm a')}`;
      }
      return `${format(startDate, 'MMM d, h:mm a')} – ${format(endDate, 'MMM d, h:mm a')}`;
    } catch {
      return `${props.start} – ${props.end}`;
    }
  })();

  const dateStr = (() => {
    try {
      return format(startDate, 'EEE, MMM d');
    } catch {
      return '';
    }
  })();

  return (
    <div
      onClick={handleClick}
      className="hover:bg-offsetLight/30 dark:hover:bg-offsetDark/30 cursor-pointer rounded-lg p-2 transition-colors"
    >
      <div className="flex items-start gap-2.5">
        {/* Color bar */}
        <div className="mt-1 h-10 w-1 shrink-0 rounded-full bg-blue-500" />
        <div className="flex flex-1 flex-col gap-1">
          <p className="text-sm font-medium text-black dark:text-white">{props.title}</p>
          <div className="flex items-center gap-1.5">
            <Calendar className="h-3 w-3 text-[#8C8C8C]" />
            <span className="text-xs text-[#8C8C8C]">
              {dateStr} · {timeStr}
            </span>
          </div>
          {props.location && (
            <div className="flex items-center gap-1.5">
              <MapPin className="h-3 w-3 text-[#8C8C8C]" />
              <span className="text-xs text-[#8C8C8C]">{props.location}</span>
            </div>
          )}
          {props.attendees && props.attendees.length > 0 && (
            <div className="flex items-center gap-1.5">
              <Users className="h-3 w-3 text-[#8C8C8C]" />
              <span className="text-xs text-[#8C8C8C]">
                {props.attendees
                  .slice(0, 3)
                  .map((a) => a.name || a.email)
                  .join(', ')}
                {props.attendees.length > 3 && ` +${props.attendees.length - 3}`}
              </span>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
