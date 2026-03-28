import { cn } from '@/lib/utils';
import { format, parseISO, isPast } from 'date-fns';
import { CheckCircle2, Circle, Clock } from 'lucide-react';

interface TaskCardProps {
  props: {
    taskId: string;
    title: string;
    description: string | null;
    status: 'todo' | 'doing' | 'done';
    priority: 'none' | 'low' | 'medium' | 'high';
    dueDate: string | null;
    folderName: string | null;
    emailThreadId: string | null;
  };
  emit?: (event: string, params?: Record<string, unknown>) => void;
}

const priorityColors: Record<string, string> = {
  high: 'text-red-500',
  medium: 'text-orange-500',
  low: 'text-blue-500',
  none: 'text-[#8C8C8C]',
};

const priorityLabels: Record<string, string> = {
  high: 'High',
  medium: 'Med',
  low: 'Low',
  none: '',
};

const statusIcons: Record<string, React.ReactNode> = {
  todo: <Circle className="h-4 w-4 text-[#8C8C8C]" />,
  doing: <Clock className="h-4 w-4 text-orange-500" />,
  done: <CheckCircle2 className="h-4 w-4 text-green-500" />,
};

export function TaskCard({ props, emit }: TaskCardProps) {
  const handleClick = () => {
    emit?.('press', { action: 'navigate_task', taskId: props.taskId });
  };

  const isOverdue =
    props.dueDate && props.status !== 'done' && isPast(parseISO(props.dueDate));

  const dueDateStr = (() => {
    if (!props.dueDate) return null;
    try {
      return format(parseISO(props.dueDate), 'MMM d');
    } catch {
      return props.dueDate;
    }
  })();

  return (
    <div
      onClick={handleClick}
      className="hover:bg-offsetLight/30 dark:hover:bg-offsetDark/30 cursor-pointer rounded-lg p-2 transition-colors"
    >
      <div className="flex items-start gap-2.5">
        <div className="mt-0.5 shrink-0">{statusIcons[props.status]}</div>
        <div className="flex flex-1 flex-col gap-1">
          <div className="flex items-center justify-between gap-2">
            <p
              className={cn(
                'text-sm text-black dark:text-white',
                props.status === 'done' && 'text-[#8C8C8C] line-through',
              )}
            >
              {props.title}
            </p>
            {props.priority !== 'none' && (
              <span className={cn('text-xs font-medium', priorityColors[props.priority])}>
                {priorityLabels[props.priority]}
              </span>
            )}
          </div>
          {props.description && (
            <p className="line-clamp-1 text-xs text-[#8C8C8C]">{props.description}</p>
          )}
          <div className="flex items-center gap-2">
            {dueDateStr && (
              <span className={cn('text-xs', isOverdue ? 'text-red-500' : 'text-[#8C8C8C]')}>
                {isOverdue ? 'Overdue · ' : ''}
                {dueDateStr}
              </span>
            )}
            {props.folderName && (
              <span className="text-xs text-[#8C8C8C]">
                {dueDateStr ? '· ' : ''}
                {props.folderName}
              </span>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
