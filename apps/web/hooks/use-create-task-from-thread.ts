import { upsertTaskInTaskCaches } from '@/lib/task-cache';
import { useTRPC } from '@/providers/query-provider';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useThread } from '@/hooks/use-threads';
import { useCallback } from 'react';
import { useQueryState } from 'nuqs';
import { toast } from 'sonner';

export function useCreateTaskFromThread() {
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const [threadId] = useQueryState('threadId');
  const { data: thread } = useThread(threadId);
  const { mutateAsync: createTask, isPending } = useMutation(trpc.tasks.create.mutationOptions());

  const createTaskFromThread = useCallback(async () => {
    if (!threadId || !thread?.latest) return;
    const subject = thread.latest.subject?.trim();
    const senderName =
      thread.latest.sender?.name?.trim() || thread.latest.sender?.email || '';
    const title = subject?.length
      ? subject
      : senderName
        ? `Follow up with ${senderName}`
        : 'Follow up on email';

    try {
      const { task } = await createTask({
        title,
        emailThreadId: threadId,
        status: 'todo',
        priority: 'none',
      });
      upsertTaskInTaskCaches(queryClient, task);
      toast.success('Task created from email');
    } catch (error) {
      console.error('Failed to create task from thread:', error);
      toast.error('Could not create task. Please try again.');
    }
  }, [createTask, queryClient, thread?.latest, threadId]);

  return { createTaskFromThread, isPending };
}
