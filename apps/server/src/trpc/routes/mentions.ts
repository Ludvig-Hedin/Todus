import { getThread, getZeroAgent } from '../../lib/server-utils';
import { mentionKindSchema, mentionRefSchema, mentionSearchResultSchema } from '../../lib/mentions';
import { activeDriverProcedure, router } from '../trpc';
import { getContext } from 'hono/context-storage';
import { task } from '../../db/schema';
import type { HonoContext } from '../../ctx';
import { createDb } from '../../db';
import { and, desc, eq, ilike, or } from 'drizzle-orm';
import { env } from '../../env';
import { z } from 'zod';

const getDb = () => createDb(env.HYPERDRIVE.connectionString);

const taskMentionSchema = mentionRefSchema.extend({
  kind: z.literal('task'),
});

const threadMentionSchema = mentionRefSchema.extend({
  kind: z.literal('thread'),
});

const personMentionSchema = mentionRefSchema.extend({
  kind: z.literal('person'),
});

export const mentionsRouter = router({
  search: activeDriverProcedure
    .input(
      z.object({
        query: z.string().trim(),
        limit: z.number().int().min(1).max(10).default(5),
        kinds: z.array(mentionKindSchema).optional(),
      }),
    )
    .output(mentionSearchResultSchema)
    .query(async ({ ctx, input }) => {
      const query = input.query.trim();
      const normalizedQuery = query.toLowerCase();
      const escapedQuery = normalizedQuery
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
      const taskSearchPattern = `%${escapedQuery}%`;
      const kinds = new Set(input.kinds ?? ['task', 'thread', 'person']);
      const groups: z.infer<typeof mentionSearchResultSchema>['groups'] = [];
      const executionCtx = getContext<HonoContext>().executionCtx;
      const { activeConnection, sessionUser } = ctx;

      if (kinds.has('task')) {
        const { db, conn } = getDb();

        try {
          const tasks = await db
            .select({
              id: task.id,
              title: task.title,
              description: task.description,
              dueDate: task.dueDate,
            })
            .from(task)
            .where(
              and(
                eq(task.userId, sessionUser.id),
                or(
                  ilike(task.title, taskSearchPattern),
                  ilike(task.description, taskSearchPattern),
                ),
              ),
            )
            .orderBy(desc(task.updatedAt), desc(task.createdAt))
            .limit(input.limit);

          const items = tasks.map((item) =>
            taskMentionSchema.parse({
              id: item.id,
              kind: 'task',
              title: item.title,
              subtitle: item.dueDate ? `Due ${item.dueDate.toISOString()}` : item.description,
              displayText: item.title,
              accessibilityLabel: `Task mention ${item.title}`,
            }),
          );

          if (items.length > 0) {
            groups.push({
              kind: 'task',
              label: 'Tasks',
              items,
            });
          }
        } finally {
          await conn.end();
        }
      }

      const { stub: agent } = await getZeroAgent(activeConnection.id, executionCtx);

      if (kinds.has('thread')) {
        const threadMatches = (await agent.rawListThreads({
          query,
          folder: 'inbox',
          maxResults: input.limit,
        })) as {
          threads: Array<{ id: string }>;
        };

        const threadDetails = await Promise.all(
          threadMatches.threads.slice(0, input.limit).map(async (item: { id: string }) => {
            try {
              const thread = await getThread(activeConnection.id, item.id);
              return thread.result.latest;
            } catch (error) {
              console.warn('[mentions.search] Failed to resolve thread mention', error, item.id);
              return null;
            }
          }),
        );

        const items = threadDetails
          .filter((latest): latest is NonNullable<typeof latest> => latest !== null)
          .map((latest: NonNullable<(typeof threadDetails)[number]>) =>
            threadMentionSchema.parse({
              id: latest.threadId || latest.id,
              kind: 'thread',
              title: latest.subject || '(no subject)',
              subtitle: latest.sender?.email ?? latest.sender?.name ?? null,
              displayText: latest.subject || latest.title || '(no subject)',
              accessibilityLabel: `Email thread mention ${latest.subject || '(no subject)'}`,
            }),
          );

        if (items.length > 0) {
          groups.push({
            kind: 'thread',
            label: 'Email Threads',
            items,
          });
        }
      }

      if (kinds.has('person')) {
        const senders = await agent.listSenders({ folder: 'inbox' });
        const items = senders
          .filter((sender) => {
            const name = sender.name?.toLowerCase() ?? '';
            return (
              sender.email.toLowerCase().includes(normalizedQuery) || name.includes(normalizedQuery)
            );
          })
          .slice(0, input.limit)
          .map((sender) =>
            personMentionSchema.parse({
              id: sender.email,
              kind: 'person',
              title: sender.name || sender.email,
              subtitle: sender.email,
              displayText: sender.name || sender.email,
              accessibilityLabel: `Person mention ${sender.name || sender.email}`,
            }),
          );

        if (items.length > 0) {
          groups.push({
            kind: 'person',
            label: 'People',
            items,
          });
        }
      }

      return {
        groups: groups.filter((group) => group.items.length > 0),
      };
    }),
});
