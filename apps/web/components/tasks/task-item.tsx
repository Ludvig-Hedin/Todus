import { useMutation, useQueryClient } from '@tanstack/react-query';
import type { Outputs } from '@zero/server/trpc';
import { formatDistanceToNow, isToday } from 'date-fns';
import { Calendar as CalendarIcon, Check, CheckCircle2, Circle } from 'lucide-react';
import { useTRPC } from '@/providers/query-provider';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';
import { toast } from 'sonner';

type Task = Outputs['tasks']['list']['tasks'][number];

export function TaskItem({ task }: { task: Task }) {
  const trpc = useTRPC();
  const queryClient = useQueryClient();

  const updateTask = useMutation({
    ...trpc.tasks.update.mutationOptions(),
    onError: (error) => {
      console.error(error);
      toast.error('Failed to update task.');
    },
    onSettled: () => {
      void queryClient.invalidateQueries(trpc.tasks.list.queryFilter());
    },
  });

  const handleToggleComplete = () => {
    updateTask.mutate({
      id: task.id,
      data: { status: task.status === 'done' ? 'todo' : 'done' },
    });
  };

  const priorityColors = {
    high: 'text-red-500 bg-red-500/10',
    medium: 'text-yellow-500 bg-yellow-500/10',
    low: 'text-blue-500 bg-blue-500/10',
    none: '',
  };

  return (
    <div
      className={cn(
        'group flex items-start gap-3 rounded-xl border border-border bg-card p-3 shadow-sm transition-colors hover:border-border/80',
        task.status === 'done' && 'opacity-60',
      )}
    >
      <button
        type="button"
        onClick={handleToggleComplete}
        className="mt-0.5 shrink-0"
        disabled={updateTask.isPending}
        aria-label={task.status === 'done' ? 'Mark as not done' : 'Mark as done'}
      >
        {task.status === 'done' ? (
          <div className="flex h-5 w-5 items-center justify-center rounded-full bg-primary">
            <Check className="h-3.5 w-3.5 text-primary-foreground" />
          </div>
        ) : (
          <Circle className="h-5 w-5 text-muted-foreground/30 transition-colors group-hover:text-primary" />
        )}
      </button>
      <div className="min-w-0 flex-1">
        <p
          className={cn(
            'text-[15px] font-medium',
            task.status === 'done' && 'text-muted-foreground line-through',
          )}
        >
          {task.title}
        </p>
        <div className="mt-1.5 flex flex-wrap items-center gap-3">
          {task.priority && task.priority !== 'none' && (
            <span
              className={cn(
                'rounded-md px-2 py-0.5 text-[11px] font-medium',
                priorityColors[task.priority],
              )}
            >
              {task.priority.charAt(0).toUpperCase() + task.priority.slice(1)}
            </span>
          )}
          {task.dueDate && (
            <span className="flex items-center gap-1 text-[11px] font-medium text-muted-foreground">
              <CalendarIcon className="h-3 w-3" />
              Due {formatDistanceToNow(new Date(task.dueDate), { addSuffix: true })}
            </span>
          )}
        </div>
      </div>
    </div>
  );
}

/**
 * Compact, *controlled* task row used in dense surfaces (home page sections).
 * Unlike {@link TaskItem}, it does not own the mutation — the parent supplies
 * `onToggle` and manages cache updates. Keeps the home page's exact compact
 * styling so behavior is unchanged after de-duplicating the inline copy.
 */
export function TaskItemCompact({ task, onToggle }: { task: Task; onToggle: () => void }) {
  return (
    <div className="flex items-center gap-3 py-2.5">
      <button
        type="button"
        onClick={onToggle}
        className="text-muted-foreground hover:text-primary shrink-0 transition-colors"
      >
        {task.status === 'done' ? (
          <CheckCircle2 className="text-primary h-4 w-4" />
        ) : (
          <Circle className="h-4 w-4" />
        )}
      </button>
      <div className="min-w-0 flex-1">
        <p
          className={cn(
            'truncate text-[13px] font-medium',
            task.status === 'done' && 'text-muted-foreground line-through',
          )}
        >
          {task.title}
        </p>
        {task.dueDate && isToday(new Date(task.dueDate)) && (
          <p className="text-muted-foreground text-[11px]">Due today</p>
        )}
      </div>
      {task.priority && task.priority !== 'none' && (
        <Badge
          variant="secondary"
          className={cn(
            'h-4 shrink-0 border-0 px-1.5 text-[10px] font-medium',
            task.priority === 'high' &&
              'bg-red-50 text-red-600 dark:bg-red-950/30 dark:text-red-400',
            task.priority === 'medium' &&
              'bg-yellow-50 text-yellow-600 dark:bg-yellow-950/30 dark:text-yellow-400',
            task.priority === 'low' &&
              'bg-blue-50 text-blue-600 dark:bg-blue-950/30 dark:text-blue-400',
          )}
        >
          {task.priority}
        </Badge>
      )}
    </div>
  );
}
