import { TaskCard } from './TaskCard';

const DEFAULT_GROUPED_THRESHOLD = 4;

type Task = {
  taskId: string;
  title: string;
  description: string | null;
  status: 'todo' | 'doing' | 'done';
  priority: 'none' | 'low' | 'medium' | 'high';
  dueDate: string | null;
  folderName: string | null;
  emailThreadId: string | null;
};

interface TaskListCardProps {
  props: {
    title: string | null;
    tasks: Task[];
    followUp: string | null;
    groupedThreshold: number | null;
  };
  emit?: (event: string, params?: Record<string, unknown>) => void;
}

export function TaskListCard({ props, emit }: TaskListCardProps) {
  const threshold = Math.max(1, props.groupedThreshold ?? DEFAULT_GROUPED_THRESHOLD);
  const grouped = props.tasks.length >= threshold;

  return (
    <div className="flex flex-col gap-2">
      {props.title && (
        <p className="text-sm text-black dark:text-white">{props.title}</p>
      )}

      {grouped ? (
        <div className="overflow-hidden rounded-xl border border-[#E7E7E7] dark:border-[#252525]">
          {props.tasks.map((task, idx) => (
            <div
              key={task.taskId}
              className={idx > 0 ? 'border-t border-[#E7E7E7] dark:border-[#252525]' : ''}
            >
              <TaskCard props={task} emit={emit} />
            </div>
          ))}
        </div>
      ) : (
        <div className="flex flex-col gap-1.5">
          {props.tasks.map((task) => (
            <div
              key={task.taskId}
              className="rounded-xl border border-[#E7E7E7] dark:border-[#252525]"
            >
              <TaskCard props={task} emit={emit} />
            </div>
          ))}
        </div>
      )}

      {props.followUp && (
        <p className="mt-1 text-sm text-black dark:text-white">{props.followUp}</p>
      )}
    </div>
  );
}
