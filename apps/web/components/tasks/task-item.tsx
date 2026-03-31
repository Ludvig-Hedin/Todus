import { useMutation, useQueryClient } from '@tanstack/react-query';
import type { Outputs } from '@zero/server/trpc';
import { formatDistanceToNow } from 'date-fns';
import { Calendar as CalendarIcon, Check, Circle } from 'lucide-react';
import { useTRPC } from '@/providers/query-provider';
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
