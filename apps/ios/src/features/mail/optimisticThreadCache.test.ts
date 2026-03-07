import assert from 'node:assert/strict';
import test from 'node:test';
import {
  getThreadListSnapshots,
  removeThreadIdsFromThreadListCaches,
  restoreThreadListSnapshots,
  toggleStarInThreadCache,
} from './optimisticThreadCache';
import { QueryClient } from '@tanstack/react-query';

test('removeThreadIdsFromThreadListCaches removes IDs from all matching list caches and restore reverses it', () => {
  const queryClient = new QueryClient();
  const listThreadsKey = ['mail', 'listThreads'] as const;

  const inboxKey = ['mail', 'listThreads', { folder: 'inbox' }] as const;
  const sentKey = ['mail', 'listThreads', { folder: 'sent' }] as const;

  queryClient.setQueryData(inboxKey, {
    threads: [
      { id: 't-1', historyId: null },
      { id: 't-2', historyId: null },
      { id: 't-3', historyId: null },
    ],
    nextPageToken: null,
  });
  queryClient.setQueryData(sentKey, {
    threads: [
      { id: 't-2', historyId: null },
      { id: 't-4', historyId: null },
    ],
    nextPageToken: null,
  });

  const snapshots = getThreadListSnapshots(queryClient, listThreadsKey);
  removeThreadIdsFromThreadListCaches(queryClient, listThreadsKey, ['t-2', 't-3']);

  assert.deepEqual(
    queryClient.getQueryData<any>(inboxKey).threads.map((thread: any) => thread.id),
    ['t-1'],
  );
  assert.deepEqual(
    queryClient.getQueryData<any>(sentKey).threads.map((thread: any) => thread.id),
    ['t-4'],
  );

  restoreThreadListSnapshots(queryClient, snapshots);

  assert.deepEqual(
    queryClient.getQueryData<any>(inboxKey).threads.map((thread: any) => thread.id),
    ['t-1', 't-2', 't-3'],
  );
  assert.deepEqual(
    queryClient.getQueryData<any>(sentKey).threads.map((thread: any) => thread.id),
    ['t-2', 't-4'],
  );
});

test('toggleStarInThreadCache toggles STARRED on latest message tags', () => {
  const queryClient = new QueryClient();
  const threadKey = ['mail', 'get', { id: 'thread-1' }] as const;

  queryClient.setQueryData(threadKey, {
    latest: {
      tags: [{ name: 'INBOX' }],
    },
    messages: [{ tags: [{ name: 'INBOX' }] }],
  });

  const previous = toggleStarInThreadCache(queryClient, threadKey);
  assert.ok(previous);
  assert.equal(
    queryClient
      .getQueryData<any>(threadKey)
      .latest.tags.some((tag: any) => tag.name === 'STARRED'),
    true,
  );

  toggleStarInThreadCache(queryClient, threadKey);
  assert.equal(
    queryClient
      .getQueryData<any>(threadKey)
      .latest.tags.some((tag: any) => tag.name === 'STARRED'),
    false,
  );
});

test('toggleStarInThreadCache falls back to last message when latest is missing', () => {
  const queryClient = new QueryClient();
  const threadKey = ['mail', 'get', { id: 'thread-2' }] as const;

  queryClient.setQueryData(threadKey, {
    messages: [{ tags: [{ name: 'UNREAD' }] }],
  });

  toggleStarInThreadCache(queryClient, threadKey);
  const next = queryClient.getQueryData<any>(threadKey);
  assert.equal(next.latest.tags.some((tag: any) => tag.name === 'STARRED'), true);
  assert.equal(next.messages[0].tags.some((tag: any) => tag.name === 'STARRED'), true);
});
