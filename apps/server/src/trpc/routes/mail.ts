import {
  forceReSync,
  getThreadsFromDB,
  getZeroAgent,
  getZeroDB,
  getThread,
  modifyThreadLabelsInDB,
  deleteAllSpam,
  reSyncThread,
} from '../../lib/server-utils';
import {
  IGetThreadResponseSchema,
  IGetThreadsResponseSchema,
  type IGetThreadsResponse,
  type ThreadSummary,
} from '../../lib/driver/types';
import { updateWritingStyleMatrix } from '../../services/writing-style-service';
import type { DeleteAllSpamResponse, IEmailSendBatch } from '../../types';
import { activeDriverProcedure, multiConnectionProcedure, router, privateProcedure } from '../trpc';
import { processEmailHtml } from '../../lib/email-processor';
import { defaultPageSize, FOLDERS } from '../../lib/utils';
import { toAttachmentFiles } from '../../lib/attachments';
import { serializedFileSchema } from '../../lib/schemas';
import { getContext } from 'hono/context-storage';
import { type HonoContext } from '../../ctx';
import { TRPCError } from '@trpc/server';
import { env } from '../../env';
import { EProviders, type ISubscribeBatch } from '../../types';
import { z } from 'zod';

const senderSchema = z.object({
  name: z.string().optional(),
  email: z.string().email(),
});

// const getFolderLabelId = (folder: string) => {
//   // Handle special cases first
//   if (folder === 'bin') return 'TRASH';
//   if (folder === 'archive') return ''; // Archive doesn't have a specific label

//   // For other folders, convert to uppercase (same as database method)
//   return folder.toUpperCase();
// };

export const mailRouter = router({
  suggestRecipients: activeDriverProcedure
    .input(
      z.object({
        query: z.string().optional().default(''),
        limit: z.number().optional().default(10),
      }),
    )
    .query(async ({ ctx, input }) => {
      const { activeConnection } = ctx;
      const executionCtx = getContext<HonoContext>().executionCtx;
      const { stub: agent } = await getZeroAgent(activeConnection.id, executionCtx);

      return await agent.suggestRecipients(input.query, input.limit);
    }),
  listSenders: activeDriverProcedure
    .input(
      z.object({
        folder: z.string().optional().default('inbox'),
      }),
    )
    .output(
      z.array(
        z.object({
          email: z.string(),
          name: z.string().nullable(),
          threadCount: z.number(),
          latestDate: z.string().nullable(),
          latestSubject: z.string().nullable(),
        }),
      ),
    )
    .query(async ({ ctx, input }) => {
      const { activeConnection } = ctx;
      const executionCtx = getContext<HonoContext>().executionCtx;
      const { stub: agent } = await getZeroAgent(activeConnection.id, executionCtx);
      return await agent.listSenders({ folder: input.folder });
    }),
  forceSync: activeDriverProcedure.mutation(async ({ ctx }) => {
    const { activeConnection } = ctx;
    return await forceReSync(activeConnection.id);
  }),
  /**
   * Re-arm the Gmail PubSub watch + push subscription for this connection.
   *
   * Gmail watches expire after ~7 days. The hourly scheduled() cron renews any
   * watch older than 5 days, but a connection whose watch was lost (subscription
   * deleted, IAM policy gone, Gmail API blip) gets stuck — no new mail arrives
   * because the webhook never fires. The "stale 2-month-old inbox" symptom on
   * native clients is this state.
   *
   * This mutation force-renews the watch immediately by clearing the
   * `gmail_sub_age` KV stamp (so the cron-style renewal logic treats it as
   * expired) and enqueueing a fresh subscribe job onto `subscribe_queue` —
   * the same path that runs on initial connect and on cron renewal.
   *
   * Safe to call repeatedly: the underlying setup is idempotent (PubSub topic
   * `Already Exists` is swallowed).
   */
  rewatchGmail: activeDriverProcedure.mutation(async ({ ctx }) => {
    const { activeConnection } = ctx;
    if (activeConnection.providerId !== EProviders.google) {
      return { ok: false, reason: 'unsupported-provider' as const };
    }
    try {
      await env.gmail_sub_age.delete(`${activeConnection.id}__${EProviders.google}`);
    } catch (error) {
      console.warn('[rewatchGmail] gmail_sub_age delete failed', {
        connectionId: activeConnection.id,
        error,
      });
    }
    await env.subscribe_queue.send({
      connectionId: activeConnection.id,
      providerId: EProviders.google,
    } as ISubscribeBatch);
    return { ok: true } as const;
  }),
  /**
   * Non-destructive sync. Lists the newest N thread IDs directly from Gmail and
   * upserts each into the shard DB via `agent.syncThread`. Unlike `forceSync`,
   * this does NOT drop tables, so the existing inbox stays visible while fresh
   * threads land. Preferred for routine pull-to-refresh and scene-foreground
   * refreshes; `forceSync` should only be used when the DB looks broken (e.g.
   * after a connection swap or a deep "rebuild" user action).
   */
  softSync: activeDriverProcedure
    .input(
      z.object({
        folder: z.string().optional().default('inbox'),
        maxResults: z.number().optional().default(30),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { activeConnection } = ctx;
      const executionCtx = getContext<HonoContext>().executionCtx;
      const { stub: agent } = await getZeroAgent(activeConnection.id, executionCtx);

      let list: { threads: { id: string }[] };
      try {
        list = (await agent.rawListThreads({
          folder: input.folder,
          maxResults: input.maxResults,
        })) as { threads: { id: string }[] };
      } catch (error) {
        console.error('[softSync] rawListThreads failed:', error);
        return { synced: 0, failed: 0, total: 0, ok: false };
      }

      const ids = list.threads.map((t) => t.id).filter(Boolean);
      let synced = 0;
      let failed = 0;
      await Promise.allSettled(
        ids.map(async (id) => {
          try {
            const r = await agent.syncThread({ threadId: id });
            if (r?.success === true || (r?.success !== false && !r?.reason)) synced++;
            else failed++;
          } catch (error) {
            console.error(`[softSync] syncThread failed for ${id}:`, error);
            failed++;
          }
        }),
      );
      try {
        await agent.reloadFolder(input.folder);
      } catch (error) {
        console.warn('[softSync] reloadFolder failed:', error);
      }
      return { synced, failed, total: ids.length, ok: true };
    }),
  get: activeDriverProcedure
    .input(
      z.object({
        id: z.string(),
      }),
    )
    .output(IGetThreadResponseSchema)
    .query(async ({ input, ctx }) => {
      const { activeConnection } = ctx;
      // Wrap the shard fetch in a hard 15s server-side timeout. Without it a
      // hung Gmail subrequest or stuck shard RPC would keep the connection
      // open until Cloudflare's outer limit, producing a multi-minute spinner
      // on the client with no recoverable error. 15s is well under the iOS
      // client's per-request budget and gives users a chance to retry while
      // upstream recovers.
      const THREAD_FETCH_TIMEOUT_MS = 15_000;
      let timeoutHandle: ReturnType<typeof setTimeout> | undefined;
      const TIMEOUT_SENTINEL = Symbol('thread-fetch-timeout');
      try {
        const result = await Promise.race<
          Awaited<ReturnType<typeof getThread>> | typeof TIMEOUT_SENTINEL
        >([
          getThread(activeConnection.id, input.id),
          new Promise<typeof TIMEOUT_SENTINEL>((resolve) => {
            timeoutHandle = setTimeout(() => resolve(TIMEOUT_SENTINEL), THREAD_FETCH_TIMEOUT_MS);
          }),
        ]);
        if (result === TIMEOUT_SENTINEL) {
          console.warn('[mail.get] thread fetch timed out', {
            threadId: input.id,
            timeoutMs: THREAD_FETCH_TIMEOUT_MS,
          });
          throw new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: 'Thread fetch timed out',
          });
        }
        return result.result;
      } catch (error) {
        if (error instanceof TRPCError) throw error;
        console.warn('[mail.get] thread fetch failed', {
          threadId: input.id,
          error: error instanceof Error ? error.message : String(error),
        });
        throw new TRPCError({
          code: 'INTERNAL_SERVER_ERROR',
          message: 'Failed to load thread',
          cause: error,
        });
      } finally {
        if (timeoutHandle) clearTimeout(timeoutHandle);
      }
    }),
  listThreads: activeDriverProcedure
    .input(
      z.object({
        folder: z.string().optional().default('inbox'),
        q: z.string().optional().default(''),
        maxResults: z.number().optional().default(defaultPageSize),
        cursor: z.string().optional().default(''),
        labelIds: z.array(z.string()).optional().default([]),
      }),
    )
    .output(IGetThreadsResponseSchema)
    .query(async ({ ctx, input }) => {
      const { folder, maxResults, cursor, q, labelIds } = input;
      const { activeConnection } = ctx;
      const executionCtx = getContext<HonoContext>().executionCtx;
      const { stub: agent } = await getZeroAgent(activeConnection.id, executionCtx);

      console.debug('[listThreads] input:', { folder, maxResults, cursor, q, labelIds });

      if (folder === FOLDERS.DRAFT) {
        console.debug('[listThreads] Listing drafts');
        const drafts = await agent.listDrafts({
          q,
          maxResults,
          pageToken: cursor,
        });
        console.debug('[listThreads] Drafts result:', drafts);
        return drafts;
      }

      type ThreadItem = { id: string; historyId: string | null; $raw?: unknown };

      let threadsResponse: IGetThreadsResponse;

      // Apply folder-to-label mapping when no search query is provided
      const effectiveLabelIds = labelIds;

      if (q) {
        threadsResponse = await agent.rawListThreads({
          query: q,
          maxResults,
          labelIds: effectiveLabelIds,
          pageToken: cursor,
          folder,
        });

        threadsResponse.threads = await Promise.all(
          threadsResponse.threads.map(async (thread): Promise<ThreadSummary> => {
            if (thread.latestSender || thread.latestSubject || thread.latestReceivedOn) {
              return thread;
            }

            try {
              const { result } = await getThread(activeConnection.id, thread.id);
              const labelIds = result.labels.map((label) => label.id);

              return {
                ...thread,
                latestSender: result.latest?.sender ?? null,
                latestSubject: result.latest?.subject ?? null,
                latestReceivedOn: result.latest?.receivedOn ?? null,
                hasUnread: result.hasUnread,
                isStarred: labelIds.includes('STARRED'),
                isImportant: labelIds.includes('IMPORTANT'),
                labelIds,
                snippet: result.latest?.body ?? result.latest?.subject ?? null,
                hasDraft: result.isLatestDraft ?? false,
                summaryUpdatedAt: result.threadDetailUpdatedAt ?? result.latest?.receivedOn ?? null,
              };
            } catch (error) {
              console.warn('[listThreads] Failed to hydrate search result summary', {
                threadId: thread.id,
                error,
              });

              return thread;
            }
          }),
        );
      } else {
        threadsResponse = await getThreadsFromDB(activeConnection.id, {
          folder,
          // query: q,
          maxResults,
          labelIds: effectiveLabelIds,
          pageToken: cursor,
        });
      }

      if (folder === FOLDERS.SNOOZED) {
        const nowTs = Date.now();

        console.debug('[listThreads] Filtering snoozed threads at', new Date(nowTs).toISOString());

        // Preserve original date-desc ordering by computing a parallel keep[] array
        // indexed by position. Pushing into a shared array from concurrent async
        // callbacks would yield completion order, breaking newest-first invariant.
        const keep = await Promise.all(
          threadsResponse.threads.map(async (t: ThreadItem) => {
            const keyName = `${t.id}__${activeConnection.id}`;
            try {
              const wakeAtIso = await env.snoozed_emails.get(keyName);
              if (!wakeAtIso) return true;

              const wakeAt = new Date(wakeAtIso).getTime();
              if (wakeAt > nowTs) return true;

              console.debug('[UNSNOOZE_ON_ACCESS] Expired thread', t.id, {
                wakeAtIso,
                now: new Date(nowTs).toISOString(),
              });

              await modifyThreadLabelsInDB(activeConnection.id, t.id, ['INBOX'], ['SNOOZED']);
              await env.snoozed_emails.delete(keyName);
              return false;
            } catch (error) {
              console.error('[UNSNOOZE_ON_ACCESS] Failed for', t.id, error);
              return true;
            }
          }),
        );

        const filtered = threadsResponse.threads.filter((_, i) => keep[i]);
        threadsResponse.threads = filtered;
        console.debug('[listThreads] Snoozed threads after filtering:', filtered);
      }

      if (folder === FOLDERS.INBOX && !q) {
        const now = Date.now();
        const threadsCount = threadsResponse.threads.length;
        // Treat the inbox as stale when:
        //  - DB is empty (workflow never ran, or just-dropped after forceSync), OR
        //  - newest stored thread is older than STALE_THRESHOLD_MS (continuous sync
        //    has stopped delivering mail — without this branch, users with 60+
        //    stale DB rows would never get fresh mail unless they explicitly
        //    pull-to-refresh, because the previous trigger only fired on `count === 0`).
        const STALE_THRESHOLD_MS = 60 * 60 * 1000; // 1 hour
        let newestAgeMs = Number.POSITIVE_INFINITY;
        if (threadsCount > 0) {
          const newestIso = (threadsResponse.threads[0] as { latestReceivedOn?: string | null })
            .latestReceivedOn;
          if (newestIso) {
            const newestTs = new Date(newestIso).getTime();
            if (!Number.isNaN(newestTs)) newestAgeMs = now - newestTs;
          }
        }
        const isEmpty = threadsCount === 0;
        const isStale = newestAgeMs > STALE_THRESHOLD_MS;

        if (isEmpty || isStale) {
          const cooldownKey = `resync_cooldown_${activeConnection.id}`;
          const lastResyncStr = await env.gmail_processing_threads.get(cooldownKey);
          const lastResync = lastResyncStr ? parseInt(lastResyncStr, 10) : 0;
          // Tighter cooldown when DB has rows we can keep — soft sync is cheap and
          // non-destructive, so a 30s gate would leave users seeing stale data far
          // longer than necessary. Empty-DB path keeps the longer cooldown because
          // its only option is the destructive forceReSync.
          const RESYNC_COOLDOWN_MS = isEmpty ? 30000 : 15000;

          if (now - lastResync > RESYNC_COOLDOWN_MS) {
            await env.gmail_processing_threads.put(cooldownKey, now.toString(), {
              expirationTtl: 60,
            });

            // Self-heal the Gmail push subscription when the inbox has been stale for
            // long enough that the watch likely expired. The hourly cron is supposed
            // to renew watches before they hit Gmail's 7-day limit, but a connection
            // whose watch was lost (PubSub deleted, IAM blip, missed cron tick) gets
            // stuck — no new mail until the user triggers a manual rewatch. Threshold
            // is conservative (24h) so we don't enqueue subscribe jobs for every short
            // gap, but tight enough that a multi-day stale inbox triggers recovery on
            // the user's next list call without any client-side change.
            const REWATCH_STALE_MS = 24 * 60 * 60 * 1000;
            const watchProbablyExpired = isEmpty || newestAgeMs > REWATCH_STALE_MS;
            if (
              watchProbablyExpired &&
              activeConnection.providerId === EProviders.google
            ) {
              try {
                await env.gmail_sub_age.delete(
                  `${activeConnection.id}__${EProviders.google}`,
                );
                await env.subscribe_queue.send({
                  connectionId: activeConnection.id,
                  providerId: EProviders.google,
                } as ISubscribeBatch);
                console.log('[listThreads] Auto-rewatch enqueued', {
                  connectionId: activeConnection.id,
                  newestAgeMs,
                  isEmpty,
                });
              } catch (error) {
                console.error('[listThreads] Auto-rewatch enqueue failed', {
                  connectionId: activeConnection.id,
                  error,
                });
              }
            }

            getZeroAgent(activeConnection.id, executionCtx)
              .then(async (_agent) => {
                try {
                  if (isEmpty) {
                    // No DB rows — only path is the destructive workflow that
                    // refills tables from scratch.
                    await _agent.stub.forceReSync();
                  } else {
                    // DB has rows but they're stale. Soft-sync: list newest IDs
                    // from Gmail and upsert each via syncThread. Keeps the
                    // existing inbox visible while fresh threads land.
                    const list = (await _agent.stub.rawListThreads({
                      folder: 'inbox',
                      maxResults: 30,
                    })) as { threads: { id: string }[] };
                    const ids = list.threads.map((t) => t.id).filter(Boolean);
                    await Promise.allSettled(
                      ids.map((id) =>
                        _agent.stub.syncThread({ threadId: id }).catch((err) => {
                          console.error(`[listThreads] async syncThread ${id} failed:`, err);
                        }),
                      ),
                    );
                    await _agent.stub.reloadFolder('inbox').catch(() => {});
                  }
                } catch (error) {
                  console.error('[listThreads] Async resync failed:', error);
                }
              })
              .catch((error) => {
                console.error('[listThreads] Failed to get agent for async resync:', error);
              });
          }
        }
      }

      console.debug('[listThreads] Returning threadsResponse:', threadsResponse);
      return threadsResponse;
    }),

  /** Fetch threads from multiple connections in parallel — for unified inbox view */
  listThreadsMulti: multiConnectionProcedure
    .input(
      z.object({
        folder: z.string().optional().default('inbox'),
        q: z.string().optional().default(''),
        maxResults: z.number().optional().default(defaultPageSize),
        /** Per-connection cursors for pagination */
        cursors: z.record(z.string(), z.string()).optional().default({}),
        labelIds: z.array(z.string()).optional().default([]),
        /** Filter to specific connection IDs (omit for all) */
        connectionIds: z.array(z.string()).optional(),
      }),
    )
    .query(async ({ ctx, input }) => {
      const { connections } = ctx;
      const { folder, q, maxResults, cursors, labelIds, connectionIds } = input;

      // Filter to requested connections, or use all
      const targetConnections = connectionIds
        ? connections.filter((c) => connectionIds.includes(c.id))
        : connections;

      // Only include connections that have valid tokens
      const validConnections = targetConnections.filter(
        (c) => c.accessToken && c.refreshToken,
      );

      // Per-connection limit: distribute maxResults evenly, minimum 5 per connection
      const perConnectionLimit =
        validConnections.length === 0
          ? Math.max(5, maxResults)
          : Math.max(5, Math.ceil(maxResults / validConnections.length));

      // Sentinel value the client sends back for a connection that has already
      // exhausted its pages. The server must NOT restart pagination for those
      // connections; previously a missing cursor fell back to '' which re-ran
      // page 1 for the exhausted account on every `fetchNextPage` → its first
      // page of threads kept reappearing merged into later pages.
      const EXHAUSTED_CURSOR = '__exhausted__';

      const results = await Promise.allSettled(
        validConnections.map(async (conn) => {
          const cursor = cursors[conn.id] ?? '';
          if (cursor === EXHAUSTED_CURSOR) {
            return {
              connectionId: conn.id,
              connectionEmail: conn.email,
              connectionColor: conn.color,
              threads: [] as ThreadSummary[],
              nextPageToken: null as string | null,
              exhausted: true,
            };
          }
          const threadsResponse = await getThreadsFromDB(conn.id, {
            folder,
            q,
            maxResults: perConnectionLimit,
            labelIds,
            pageToken: cursor,
          });

          return {
            connectionId: conn.id,
            connectionEmail: conn.email,
            connectionColor: conn.color,
            threads: threadsResponse.threads,
            nextPageToken: threadsResponse.nextPageToken,
            exhausted: false,
          };
        }),
      );

      // Merge results, tracking errors per connection
      const allThreads: Array<ThreadSummary & { connectionId: string; connectionEmail: string; connectionColor: string | null }> = [];
      const nextCursors: Record<string, string> = {};
      const errors: Array<{ connectionId: string; connectionEmail: string; error: string }> = [];

      for (const result of results) {
        if (result.status === 'fulfilled') {
          const { connectionId, connectionEmail, connectionColor, threads, nextPageToken, exhausted } = result.value;
          for (const thread of threads) {
            allThreads.push({ ...thread, connectionId, connectionEmail, connectionColor });
          }
          if (nextPageToken) {
            nextCursors[connectionId] = nextPageToken;
          } else {
            // Preserve "done" status for this connection so the next fetchNextPage
            // doesn't restart its pagination from page 1.
            nextCursors[connectionId] = EXHAUSTED_CURSOR;
          }
          // `exhausted` returned above for ALREADY-exhausted connections — also
          // preserve the sentinel in that case.
          if (exhausted) nextCursors[connectionId] = EXHAUSTED_CURSOR;
        } else {
          // Extract connectionId from the error context
          const connIndex = results.indexOf(result);
          const conn = validConnections[connIndex];
          if (conn) {
            errors.push({
              connectionId: conn.id,
              connectionEmail: conn.email,
              error: result.reason instanceof Error ? result.reason.message : 'Unknown error',
            });
          }
        }
      }

      // Sort merged threads by date (newest first)
      allThreads.sort((a, b) => {
        const dateA = a.latestReceivedOn ? new Date(a.latestReceivedOn).getTime() : 0;
        const dateB = b.latestReceivedOn ? new Date(b.latestReceivedOn).getTime() : 0;
        return dateB - dateA;
      });

      // Cap to maxResults
      const threads = allThreads.slice(0, maxResults);

      return { threads, nextCursors, errors };
    }),

  markAsRead: activeDriverProcedure
    .input(
      z.object({
        ids: z.string().array(),
      }),
    )
    .mutation(async ({ input, ctx }) => {
      const { activeConnection } = ctx;
      return Promise.all(
        input.ids.map((threadId) =>
          modifyThreadLabelsInDB(activeConnection.id, threadId, [], ['UNREAD']),
        ),
      );
    }),
  markAsUnread: activeDriverProcedure
    .input(
      z.object({
        ids: z.string().array(),
      }),
    )
    // TODO: Add batching
    .mutation(async ({ input, ctx }) => {
      const { activeConnection } = ctx;
      return Promise.all(
        input.ids.map((threadId) =>
          modifyThreadLabelsInDB(activeConnection.id, threadId, ['UNREAD'], []),
        ),
      );
    }),
  markAsImportant: activeDriverProcedure
    .input(
      z.object({
        ids: z.string().array(),
      }),
    )
    .mutation(async ({ input, ctx }) => {
      const { activeConnection } = ctx;
      return Promise.all(
        input.ids.map((threadId) =>
          modifyThreadLabelsInDB(activeConnection.id, threadId, ['IMPORTANT'], []),
        ),
      );
    }),
  modifyLabels: activeDriverProcedure
    .input(
      z.object({
        threadId: z.string().array(),
        addLabels: z.string().array().optional().default([]),
        removeLabels: z.string().array().optional().default([]),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { activeConnection } = ctx;
      const executionCtx = getContext<HonoContext>().executionCtx;
      const { stub: agent } = await getZeroAgent(activeConnection.id, executionCtx);
      const { threadId, addLabels, removeLabels } = input;

      console.log(`Server: updateThreadLabels called for thread ${threadId}`);
      console.log(`Adding labels: ${addLabels.join(', ')}`);
      console.log(`Removing labels: ${removeLabels.join(', ')}`);

      const result = await agent.normalizeIds(threadId);
      const { threadIds } = result;

      if (threadIds.length) {
        await Promise.all(
          threadIds.map((threadId) =>
            modifyThreadLabelsInDB(activeConnection.id, threadId, addLabels, removeLabels),
          ),
        );
        return { success: true };
      }

      console.log('Server: No label changes specified');
      return { success: false, error: 'No label changes specified' };
    }),

  toggleStar: activeDriverProcedure
    .input(
      z.object({
        ids: z.string().array(),
      }),
    )
    .mutation(async ({ input, ctx }) => {
      const { activeConnection } = ctx;
      const executionCtx = getContext<HonoContext>().executionCtx;
      const { stub: agent } = await getZeroAgent(activeConnection.id, executionCtx);
      const { threadIds } = await agent.normalizeIds(input.ids);

      if (!threadIds.length) {
        return { success: false, error: 'No thread IDs provided' };
      }

      const threadResults = await Promise.allSettled(
        threadIds.map(async (id: string) => {
          const thread = await getThread(activeConnection.id, id);
          return thread.result;
        }),
      );

      let anyStarred = false;
      let processedThreads = 0;

      for (const result of threadResults) {
        if (result.status === 'fulfilled' && result.value && result.value.messages.length > 0) {
          processedThreads++;
          const isThreadStarred = result.value.messages.some((message) =>
            message.tags?.some((tag) => tag.name.toLowerCase().startsWith('starred')),
          );
          if (isThreadStarred) {
            anyStarred = true;
            break;
          }
        }
      }

      const shouldStar = processedThreads > 0 && !anyStarred;

      await Promise.all(
        threadIds.map((threadId) =>
          modifyThreadLabelsInDB(
            activeConnection.id,
            threadId,
            shouldStar ? ['STARRED'] : [],
            shouldStar ? [] : ['STARRED'],
          ),
        ),
      );

      return { success: true };
    }),
  toggleImportant: activeDriverProcedure
    .input(
      z.object({
        ids: z.string().array(),
      }),
    )
    .mutation(async ({ input, ctx }) => {
      const { activeConnection } = ctx;
      const executionCtx = getContext<HonoContext>().executionCtx;
      const { stub: agent } = await getZeroAgent(activeConnection.id, executionCtx);
      const { threadIds } = await agent.normalizeIds(input.ids);

      if (!threadIds.length) {
        return { success: false, error: 'No thread IDs provided' };
      }

      const threadResults = await Promise.allSettled(
        threadIds.map(async (id: string) => {
          const thread = await getThread(activeConnection.id, id);
          return thread.result;
        }),
      );

      let anyImportant = false;
      let processedThreads = 0;

      for (const result of threadResults) {
        if (result.status === 'fulfilled' && result.value && result.value.messages.length > 0) {
          processedThreads++;
          const isThreadImportant = result.value.messages.some((message) =>
            message.tags?.some((tag) => tag.name.toLowerCase().startsWith('important')),
          );
          if (isThreadImportant) {
            anyImportant = true;
            break;
          }
        }
      }

      const shouldMarkImportant = processedThreads > 0 && !anyImportant;

      await Promise.all(
        threadIds.map((threadId) =>
          modifyThreadLabelsInDB(
            activeConnection.id,
            threadId,
            shouldMarkImportant ? ['IMPORTANT'] : [],
            shouldMarkImportant ? [] : ['IMPORTANT'],
          ),
        ),
      );

      return { success: true };
    }),
  bulkStar: activeDriverProcedure
    .input(
      z.object({
        ids: z.string().array(),
      }),
    )
    .mutation(async ({ input, ctx }) => {
      const { activeConnection } = ctx;
      return Promise.all(
        input.ids.map((threadId) =>
          modifyThreadLabelsInDB(activeConnection.id, threadId, ['STARRED'], []),
        ),
      );
    }),
  bulkMarkImportant: activeDriverProcedure
    .input(
      z.object({
        ids: z.string().array(),
      }),
    )
    .mutation(async ({ input, ctx }) => {
      const { activeConnection } = ctx;
      return Promise.all(
        input.ids.map((threadId) =>
          modifyThreadLabelsInDB(activeConnection.id, threadId, ['IMPORTANT'], []),
        ),
      );
    }),
  bulkUnstar: activeDriverProcedure
    .input(
      z.object({
        ids: z.string().array(),
      }),
    )
    .mutation(async ({ input, ctx }) => {
      const { activeConnection } = ctx;
      return Promise.all(
        input.ids.map((threadId) =>
          modifyThreadLabelsInDB(activeConnection.id, threadId, [], ['STARRED']),
        ),
      );
    }),
  deleteAllSpam: activeDriverProcedure.mutation(async ({ ctx }): Promise<DeleteAllSpamResponse> => {
    const { activeConnection } = ctx;
    try {
      const result = await deleteAllSpam(activeConnection.id);
      return {
        success: true,
        message: `Spam emails deleted ${result.deletedCount} threads`,
        count: result.deletedCount,
      };
    } catch (error) {
      console.error('Error deleting spam emails:', error);
      return {
        success: false,
        message: 'Failed to delete spam emails',
        error: String(error),
        count: 0,
      };
    }
  }),
  bulkUnmarkImportant: activeDriverProcedure
    .input(
      z.object({
        ids: z.string().array(),
      }),
    )
    .mutation(async ({ input, ctx }) => {
      const { activeConnection } = ctx;
      return Promise.all(
        input.ids.map((threadId) =>
          modifyThreadLabelsInDB(activeConnection.id, threadId, [], ['IMPORTANT']),
        ),
      );
    }),

  send: activeDriverProcedure
    .input(
      z.object({
        to: z.array(senderSchema).min(1, 'At least one recipient is required'),
        subject: z.string(),
        message: z.string(),
        attachments: z.array(serializedFileSchema).optional().default([]),
        headers: z.record(z.string()).optional().default({}),
        cc: z.array(senderSchema).optional(),
        bcc: z.array(senderSchema).optional(),
        threadId: z.string().optional(),
        fromEmail: z.string().optional(),
        draftId: z.string().optional(),
        isForward: z.boolean().optional(),
        originalMessage: z.string().optional(),
        scheduleAt: z.string().optional(),
        // Client-supplied idempotency key. Native clients retry sends that were
        // in-flight when the app crashed; without this the retry delivers the
        // email twice (the recipient gets duplicates). Stable per logical send
        // (e.g. the local draft record id).
        clientSendId: z.string().max(128).optional(),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { activeConnection, sessionUser } = ctx;
      const executionCtx = getContext<HonoContext>().executionCtx;
      const agent = await getZeroAgent(activeConnection.id, executionCtx);

      const { draftId, scheduleAt, attachments, clientSendId, ...mail } = input as typeof input & {
        scheduleAt?: string;
        clientSendId?: string;
      };

      // Idempotency gate: if this clientSendId already completed a send for
      // this connection, treat the retry as a success without re-sending.
      const dedupeKey = clientSendId
        ? `send-dedupe:${activeConnection.id}:${clientSendId}`
        : null;
      if (dedupeKey) {
        const already = await env.pending_emails_status.get(dedupeKey);
        if (already) {
          return { success: true, deduplicated: true } as const;
        }
      }

      const db = await getZeroDB(sessionUser.id);
      const userSettings = await db.findUserSettings();
      const undoSendEnabled = userSettings?.settings?.undoSendEnabled ?? false;
      const shouldSchedule = !!scheduleAt || undoSendEnabled;

      const afterTask = async () => {
        try {
          console.warn('Saving writing style matrix...');
          await updateWritingStyleMatrix(activeConnection.id, input.message);
          console.warn('Saved writing style matrix.');
        } catch (error) {
          console.error('Failed to save writing style matrix', error);
        }
      };

      if (shouldSchedule) {
        const messageId = crypto.randomUUID();

        // Validate scheduleAt if provided
        let targetTime: number;
        if (scheduleAt) {
          const parsedTime = Date.parse(scheduleAt);
          if (isNaN(parsedTime)) {
            return { success: false, error: 'Invalid schedule date format' } as const;
          }

          const now = Date.now();

          if (parsedTime <= now) {
            return { success: false, error: 'Schedule time must be in the future' } as const;
          }

          targetTime = parsedTime;
        } else {
          targetTime = Date.now() + 15_000;
        }

        const rawDelaySeconds = Math.floor((targetTime - Date.now()) / 1000);
        const maxQueueDelay = 43200; // 12 hours
        const isLongTerm = rawDelaySeconds > maxQueueDelay;

        const {
          pending_emails_status: statusKV,
          pending_emails_payload: payloadKV,
          scheduled_emails: scheduledKV,
          send_email_queue,
        } = env;

        try {
          await statusKV.put(messageId, 'pending', {
            expirationTtl: 60 * 60 * 24,
          });
        } catch (error) {
          console.error(`Failed to write pending status to KV for message ${messageId}`, error);
          return { success: false, error: 'Failed to schedule email status' } as const;
        }

        const mailPayload = {
          ...mail,
          draftId,
          attachments,
          connectionId: activeConnection.id,
        };

        try {
          await payloadKV.put(messageId, JSON.stringify(mailPayload), {
            expirationTtl: 60 * 60 * 24,
          });
        } catch (error) {
          console.error(`Failed to write email payload to KV for message ${messageId}`, error);
          return { success: false, error: 'Failed to schedule email payload' } as const;
        }

        if (isLongTerm) {
          try {
            await scheduledKV.put(
              messageId,
              JSON.stringify({
                messageId,
                connectionId: activeConnection.id,
                sendAt: targetTime,
              }),
              { expirationTtl: Math.min(Math.ceil(rawDelaySeconds + 3600), 31556952) },
            );
          } catch (error) {
            console.error(
              `Failed to write long-term schedule to KV for message ${messageId}`,
              error,
            );
            return { success: false, error: 'Failed to schedule email (long-term)' } as const;
          }
        } else {
          const delaySeconds = rawDelaySeconds;
          const queueBody: IEmailSendBatch = {
            messageId,
            connectionId: activeConnection.id,
            sendAt: targetTime,
          };
          try {
            await send_email_queue.send(queueBody, { delaySeconds });
          } catch (error) {
            console.error(`Failed to enqueue email send for message ${messageId}`, error);
            return { success: false, error: 'Failed to enqueue email send' } as const;
          }
        }

        ctx.c.executionCtx.waitUntil(afterTask());

        // The send is now owned by the scheduler — a crash-retry with the same
        // clientSendId must not enqueue it a second time.
        if (dedupeKey) {
          ctx.c.executionCtx.waitUntil(
            env.pending_emails_status.put(dedupeKey, 'scheduled', {
              expirationTtl: 60 * 60 * 24,
            }),
          );
        }

        if (isLongTerm) {
          return { success: true, scheduled: true, messageId, sendAt: targetTime };
        } else {
          return { success: true, queued: true, messageId, sendAt: targetTime };
        }
      }

      const mailWithAttachments = {
        ...mail,
        attachments: attachments?.map((att: any) =>
          typeof att?.arrayBuffer === 'function' ? att : toAttachmentFiles([att])[0],
        ),
      } as typeof mail & { attachments: any[] };

      if (draftId) {
        await agent.stub.sendDraft(draftId, mailWithAttachments);
      } else {
        await agent.stub.create(mailWithAttachments);
      }

      // Mark this clientSendId as delivered so a crash-retry of the same
      // logical send is acknowledged instead of re-sent (24h window covers any
      // realistic retry-after-relaunch).
      if (dedupeKey) {
        executionCtx.waitUntil(
          env.pending_emails_status.put(dedupeKey, 'sent', { expirationTtl: 60 * 60 * 24 }),
        );
      }

      console.log('[send] input.threadId:', input);

      if (input.threadId)
        ctx.c.executionCtx.waitUntil(reSyncThread(activeConnection.id, input.threadId));
      ctx.c.executionCtx.waitUntil(afterTask());
      return { success: true };
    }),
  unsend: activeDriverProcedure
    .input(
      z.object({
        messageId: z.string(),
      }),
    )
    .mutation(async ({ input, ctx }) => {
      const { messageId } = input;
      const { activeConnection } = ctx;
      const {
        pending_emails_status: statusKV,
        pending_emails_payload: payloadKV,
        scheduled_emails: scheduledKV,
      } = env;

      const scheduledData = await scheduledKV.get(messageId);
      if (scheduledData) {
        try {
          const { connectionId } = JSON.parse(scheduledData);
          if (connectionId !== activeConnection.id) {
            return {
              success: false,
              error: "Unauthorized: Cannot cancel another user's scheduled email",
            } as const;
          }
        } catch (error) {
          console.error('Failed to parse scheduled data for ownership verification:', error);
          return { success: false, error: 'Invalid scheduled email data' } as const;
        }
      }

      const payloadData = await payloadKV.get(messageId);
      if (payloadData) {
        try {
          const payload = JSON.parse(payloadData);
          if (payload.connectionId && payload.connectionId !== activeConnection.id) {
            return {
              success: false,
              error: "Unauthorized: Cannot cancel another user's queued email",
            } as const;
          }
        } catch (error) {
          console.error('Failed to parse payload data:', error);
          return { success: false, error: 'Invalid payload data' } as const;
        }
      }

      await statusKV.put(messageId, 'cancelled', {
        expirationTtl: 60 * 60,
      });

      await payloadKV.delete(messageId);
      await scheduledKV.delete(messageId); // Clean up long-term schedule if it exists

      return { success: true };
    }),
  delete: activeDriverProcedure
    .input(
      z.object({
        id: z.string(),
      }),
    )
    .mutation(async ({ input, ctx }) => {
      const { activeConnection } = ctx;
      const executionCtx = getContext<HonoContext>().executionCtx;
      const { exec, stub } = await getZeroAgent(activeConnection.id, executionCtx);
      await exec(`DELETE FROM threads WHERE thread_id = ?`, input.id);
      await stub.reloadFolder('bin');
      return true;
    }),
  bulkDelete: activeDriverProcedure
    .input(
      z.object({
        ids: z.string().array(),
      }),
    )
    .mutation(async ({ input, ctx }) => {
      const { activeConnection } = ctx;
      return Promise.all(
        input.ids.map((threadId) =>
          modifyThreadLabelsInDB(activeConnection.id, threadId, ['TRASH'], []),
        ),
      );
    }),
  bulkArchive: activeDriverProcedure
    .input(
      z.object({
        ids: z.string().array(),
      }),
    )
    .mutation(async ({ input, ctx }) => {
      const { activeConnection } = ctx;
      return Promise.all(
        input.ids.map((threadId) =>
          modifyThreadLabelsInDB(activeConnection.id, threadId, [], ['INBOX']),
        ),
      );
    }),
  bulkMute: activeDriverProcedure
    .input(
      z.object({
        ids: z.string().array(),
      }),
    )
    .mutation(async ({ input, ctx }) => {
      const { activeConnection } = ctx;
      return Promise.all(
        input.ids.map((threadId) =>
          modifyThreadLabelsInDB(activeConnection.id, threadId, ['MUTE'], []),
        ),
      );
    }),
  getEmailAliases: activeDriverProcedure.query(async ({ ctx }) => {
    const { activeConnection } = ctx;
    const executionCtx = getContext<HonoContext>().executionCtx;
    const { stub: agent } = await getZeroAgent(activeConnection.id, executionCtx);
    return agent.getEmailAliases();
  }),
  snoozeThreads: activeDriverProcedure
    .input(
      z.object({
        ids: z.string().array(),
        wakeAt: z.string(),
      }),
    )
    .mutation(async ({ input, ctx }) => {
      const { activeConnection } = ctx;
      if (!input.ids.length) {
        return { success: false, error: 'No thread IDs provided' };
      }

      const wakeAtDate = new Date(input.wakeAt);
      if (wakeAtDate <= new Date()) {
        return { success: false, error: 'Snooze time must be in the future' };
      }

      await Promise.all(
        input.ids.map((threadId) =>
          modifyThreadLabelsInDB(activeConnection.id, threadId, ['SNOOZED'], ['INBOX']),
        ),
      );

      const wakeAtIso = wakeAtDate.toISOString();
      await Promise.all(
        input.ids.map((threadId) =>
          env.snoozed_emails.put(`${threadId}__${activeConnection.id}`, wakeAtIso, {
            metadata: { wakeAt: wakeAtIso },
          }),
        ),
      );

      return { success: true };
    }),
  unsnoozeThreads: activeDriverProcedure
    .input(
      z.object({
        ids: z.array(z.string()),
      }),
    )
    .mutation(async ({ input, ctx }) => {
      const { activeConnection } = ctx;
      if (!input.ids.length) return { success: false, error: 'No thread IDs' };
      await Promise.all(
        input.ids.map((threadId) =>
          modifyThreadLabelsInDB(activeConnection.id, threadId, ['INBOX'], ['SNOOZED']),
        ),
      );
      await Promise.all(
        input.ids.map((threadId) =>
          env.snoozed_emails.delete(`${threadId}__${activeConnection.id}`),
        ),
      );
      return { success: true };
    }),
  getMessageAttachments: activeDriverProcedure
    .input(
      z.object({
        messageId: z.string(),
      }),
    )
    .query(async ({ ctx, input }) => {
      const { activeConnection } = ctx;
      const executionCtx = getContext<HonoContext>().executionCtx;
      const { stub: agent } = await getZeroAgent(activeConnection.id, executionCtx);
      return agent.getMessageAttachments(input.messageId) as Promise<
        {
          filename: string;
          mimeType: string;
          size: number;
          attachmentId: string;
          headers: {
            name: string;
            value: string;
          }[];
          body: string;
        }[]
      >;
    }),
  processEmailContent: privateProcedure
    .input(
      z.object({
        html: z.string(),
        shouldLoadImages: z.boolean(),
        theme: z.enum(['light', 'dark']),
      }),
    )
    .mutation(async ({ input }) => {
      try {
        const { processedHtml, hasBlockedImages } = processEmailHtml({
          html: input.html,
          shouldLoadImages: input.shouldLoadImages,
          theme: input.theme,
        });

        return {
          processedHtml,
          hasBlockedImages,
        };
      } catch (error) {
        console.error('Error processing email content:', error);
        throw new TRPCError({
          code: 'INTERNAL_SERVER_ERROR',
          message: 'Failed to process email content',
        });
      }
    }),
  getRawEmail: activeDriverProcedure
    .input(
      z.object({
        id: z.string(),
      }),
    )
    .query(async ({ input, ctx }) => {
      const { activeConnection } = ctx;
      const { stub: agent } = await getZeroAgent(activeConnection.id);
      return agent.getRawEmail(input.id);
    }),
  verifyEmail: activeDriverProcedure
    .input(
      z.object({
        id: z.string(),
      }),
    )
    .query(async ({ input, ctx }) => {
      try {
        const { activeConnection } = ctx;
        const { stub: agent } = await getZeroAgent(activeConnection.id);

        console.log(`[VERIFY_EMAIL] Getting raw email for message ID: ${input.id}`);
        const rawEmail = await agent.getRawEmail(input.id);

        const { verify } = await import('../../lib/email-verification');
        const result = await verify(rawEmail);
        console.log(`[VERIFY_EMAIL] Verification result for message ID ${input.id}:`, result);
        return result;
      } catch (error) {
        console.error('Email verification error:', error);
        return { isVerified: false };
      }
    }),
});
