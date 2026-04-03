import type { QueryClient } from '@tanstack/react-query';
import type { Outputs } from '@zero/server/trpc';

type Task = Outputs['tasks']['list']['tasks'][number];
type TaskListResult = Outputs['tasks']['list'];

export function upsertTaskInTaskCaches(queryClient: QueryClient, task: Task) {
  queryClient.setQueriesData({ queryKey: [['tasks', 'list']] }, (current: TaskListResult | undefined) => {
    if (!current) return current;

    const existingIndex = current.tasks.findIndex((currentTask) => currentTask.id === task.id);
    if (existingIndex === -1) {
      return {
        ...current,
        tasks: [task, ...current.tasks],
      };
    }

    const nextTasks = [...current.tasks];
    nextTasks[existingIndex] = {
      ...nextTasks[existingIndex],
      ...task,
    };

    return {
      ...current,
      tasks: nextTasks,
    };
  });
}

export function removeTaskFromTaskCaches(queryClient: QueryClient, taskId: string) {
  queryClient.setQueriesData({ queryKey: [['tasks', 'list']] }, (current: TaskListResult | undefined) => {
    if (!current) return current;

    return {
      ...current,
      tasks: current.tasks.filter((task) => task.id !== taskId),
    };
  });
}
