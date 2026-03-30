import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { getEmailLogo, cn } from '@/lib/utils';
import { format, parseISO } from 'date-fns';

interface EmailCardProps {
  props: {
    threadId: string;
    sender: string;
    senderEmail: string;
    subject: string;
    snippet: string;
    receivedAt: string;
    isUnread: boolean | null;
    labels: Array<{ name: string; color: string | null }> | null;
  };
  emit?: (event: string, params?: Record<string, unknown>) => void;
}

export function EmailCard({ props, emit }: EmailCardProps) {
  const handleClick = () => {
    emit?.('press', { action: 'navigate_thread', threadId: props.threadId });
  };

  const receivedDate = (() => {
    try {
      return format(parseISO(props.receivedAt), 'MMM d');
    } catch {
      return props.receivedAt;
    }
  })();

  return (
    <div
      onClick={handleClick}
      className="hover:bg-offsetLight/30 dark:hover:bg-offsetDark/30 cursor-pointer rounded-lg transition-colors"
    >
      <div className="flex items-center justify-between p-2">
        <div className="flex w-full items-center gap-3">
          <Avatar className="h-8 w-8 shrink-0">
            <AvatarImage className="rounded-full" src={getEmailLogo(props.senderEmail)} />
            <AvatarFallback className="rounded-full bg-[#FFFFFF] font-bold text-[#9F9F9F] dark:bg-[#373737]">
              {props.sender?.[0]?.toUpperCase() ?? '?'}
            </AvatarFallback>
          </Avatar>
          <div className="flex w-full flex-col gap-1">
            <div className="flex w-full items-center justify-between gap-2">
              <p
                className={cn(
                  'max-w-[20ch] truncate text-sm text-black dark:text-white',
                  props.isUnread && 'font-semibold',
                )}
              >
                {props.sender}
              </p>
              <span className="shrink-0 text-xs text-[#8C8C8C]">{receivedDate}</span>
            </div>
            <div className="flex items-center justify-between">
              <span
                className={cn(
                  'max-w-[240px] truncate text-xs text-[#8C8C8C]',
                  props.isUnread && 'text-black dark:text-white',
                )}
              >
                {props.subject}
              </span>
              {props.labels && props.labels.length > 0 && (
                <div className="flex gap-1">
                  {props.labels.slice(0, 2).map((label) => (
                    <span
                      key={label.name}
                      className="rounded-sm px-1.5 py-0.5 text-[10px] font-medium"
                      style={{
                        backgroundColor: label.color ?? '#E7E7E7',
                        color: label.color ? '#fff' : '#555',
                      }}
                    >
                      {label.name}
                    </span>
                  ))}
                </div>
              )}
            </div>
            {props.snippet && (
              <span className="line-clamp-1 text-xs text-[#8C8C8C]">{props.snippet}</span>
            )}
          </div>
        </div>
      </div>
      {/* Unread indicator dot */}
      {props.isUnread && (
        <div className="absolute top-3 left-1 h-1.5 w-1.5 rounded-full bg-blue-500" />
      )}
    </div>
  );
}
