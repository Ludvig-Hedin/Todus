export type TaskSyncMutationIdentity = {
  type: 'upsert' | 'delete';
  id: string;
};

// Deletion is terminal for native UUIDs. Include every delete in the current
// batch as well as durable server tombstones so mutation ordering or a stale
// offline upsert cannot resurrect an explicitly deleted task.
export function collectDeletionWinsIDs(
  mutations: TaskSyncMutationIdentity[],
  persistedDeletedIDs: Iterable<string>,
): Set<string> {
  const deletedIDs = new Set(persistedDeletedIDs);
  for (const mutation of mutations) {
    if (mutation.type === 'delete') deletedIDs.add(mutation.id);
  }
  return deletedIDs;
}
