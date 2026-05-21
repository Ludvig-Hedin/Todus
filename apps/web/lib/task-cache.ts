import type { QueryClient } from '@tanstack/react-query';
import type { Outputs } from '@zero/server/trpc';

type Task = Outputs['tasks']['list']['tasks'][number];
type TaskListResult = Outputs['tasks']['list'];

// Mirror of `tasks.list` input that affects which tasks belong in each cache.
type TaskListFilter = {
  status?: string;
  folderId?: string | null;
  search?: string;
};

/**
 * Decide whether `task` belongs in a `tasks.list` cache page that was fetched
 * with `filter`. Used by upsert/remove to avoid injecting a task into a cache
 * whose filter excludes it (e.g. flipping status from `todo`→`done` would
 * otherwise leave the task visible in both the "To Do" AND "Done" filters).
 *
 * Conservative: when a filter field is unset/unknown, treat the cache as
 * accepting all values for that field.
 */
function taskMatchesFilter(task: Task, filter: TaskListFilter | null): boolean {
  if (!filter) return true;
  if (filter.status && (task as { status?: string }).status !== filter.status) return false;
  if (filter.folderId !== undefined) {
    const taskFolderId = (task as { folderId?: string | null }).folderId ?? null;
    if (filter.folderId !== taskFolderId) return false;
  }
  if (filter.search) {
    const haystack = `${(task as { title?: string }).title ?? ''}`.toLowerCase();
    if (!haystack.includes(filter.search.toLowerCase())) return false;
  }
  return true;
}

function extractFilterFromQueryKey(queryKey: unknown): TaskListFilter | null {
  if (!Array.isArray(queryKey)) return null;
  for (const slice of queryKey) {
    if (slice && typeof slice === 'object' && !Array.isArray(slice)) {
      // Two known shapes: bare params object, or tRPC's `{ input: {...} }` wrapper.
      const input =
        (slice as { input?: TaskListFilter }).input ?? (slice as TaskListFilter);
      if ('status' in input || 'folderId' in input || 'search' in input) return input;
    }
  }
  return null;
}

export function upsertTaskInTaskCaches(queryClient: QueryClient, task: Task) {
  // Walk each cached `tasks.list` separately so we can inspect its filter
  // before deciding whether to add/update/remove the row in that cache.
  const matches = queryClient.getQueriesData<TaskListResult>({
    queryKey: [['tasks', 'list']],
  });
  for (const [queryKey, current] of matches) {
    if (!current) continue;
    const filter = extractFilterFromQueryKey(queryKey);
    const fits = taskMatchesFilter(task, filter);
    const existingIndex = current.tasks.findIndex((currentTask) => currentTask.id === task.id);

    if (!fits) {
      // Task no longer belongs in this filter — drop if present, else no-op.
      if (existingIndex === -1) continue;
      queryClient.setQueryData<TaskListResult>(queryKey, {
        ...current,
        tasks: current.tasks.filter((currentTask) => currentTask.id !== task.id),
      });
      continue;
    }

    if (existingIndex === -1) {
      queryClient.setQueryData<TaskListResult>(queryKey, {
        ...current,
        tasks: [task, ...current.tasks],
      });
      continue;
    }

    const nextTasks = [...current.tasks];
    nextTasks[existingIndex] = {
      ...nextTasks[existingIndex],
      ...task,
    };
    queryClient.setQueryData<TaskListResult>(queryKey, { ...current, tasks: nextTasks });
  }
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
