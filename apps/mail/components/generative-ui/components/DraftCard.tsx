import { FileEdit } from 'lucide-react';
import { format, parseISO } from 'date-fns';

interface DraftCardProps {
  props: {
    draftId: string;
    to: Array<{ name: string | null; email: string }> | null;
    subject: string;
    snippet: string;
    updatedAt: string | null;
  };
  emit?: (event: string, params?: Record<string, unknown>) => void;
}

export function DraftCard({ props, emit }: DraftCardProps) {
  const handleClick = () => {
    emit?.('press', { action: 'navigate_draft', draftId: props.draftId });
  };

  const recipients = props.to
    ?.map((r) => r.name || r.email)
    .slice(0, 2)
    .join(', ');

  const dateStr = (() => {
    if (!props.updatedAt) return null;
    try {
      return format(parseISO(props.updatedAt), 'MMM d');
    } catch {
      return props.updatedAt;
    }
  })();

  return (
    <div
      onClick={handleClick}
      className="hover:bg-offsetLight/30 dark:hover:bg-offsetDark/30 cursor-pointer rounded-lg p-2 transition-colors"
    >
      <div className="flex items-start gap-2.5">
        <FileEdit className="mt-0.5 h-4 w-4 shrink-0 text-[#8C8C8C]" />
        <div className="flex flex-1 flex-col gap-1">
          <div className="flex items-center justify-between gap-2">
            <p className="text-sm font-medium text-black dark:text-white">
              {props.subject || '(No subject)'}
            </p>
            {dateStr && <span className="shrink-0 text-xs text-[#8C8C8C]">{dateStr}</span>}
          </div>
          {recipients && <p className="text-xs text-[#8C8C8C]">To: {recipients}</p>}
          {props.snippet && (
            <p className="line-clamp-1 text-xs text-[#8C8C8C]">{props.snippet}</p>
          )}
        </div>
      </div>
    </div>
  );
}
