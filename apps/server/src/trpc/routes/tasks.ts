import { task, taskFolder, folderItem, aiConversation } from '../../db/schema';
import { eq, and, desc, asc, like, sql, inArray, isNotNull, lte } from 'drizzle-orm';
import { privateProcedure, router } from '../trpc';
import { createDb } from '../../db';
import { env } from '../../env';
import { z } from 'zod';

// Helper to get a direct Drizzle DB connection
const getDb = () => createDb(env.HYPERDRIVE.connectionString);

// ─── Task Router ───────────────────────────────────────────────────────

export const tasksRouter = router({
  list: privateProcedure
    .input(
      z
        .object({
          folderId: z.string().optional(),
          status: z.enum(['todo', 'doing', 'done']).optional(),
          search: z.string().optional(),
          sortBy: z.enum(['newest', 'oldest', 'priority']).optional().default('newest'),
          limit: z.number().optional().default(100),
          offset: z.number().optional().default(0),
        })
        .optional()
        .default({}),
    )
    .query(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const conditions = [eq(task.userId, ctx.sessionUser.id)];

        if (input.folderId) {
          conditions.push(eq(task.folderId, input.folderId));
        }
        if (input.status) {
          conditions.push(eq(task.status, input.status));
        }
        if (input.search) {
          conditions.push(like(task.title, `%${input.search}%`));
        }

        const orderBy =
          input.sortBy === 'oldest'
            ? asc(task.createdAt)
            : input.sortBy === 'priority'
              ? desc(task.priority)
              : desc(task.createdAt);

        const tasks = await db
          .select()
          .from(task)
          .where(and(...conditions))
          .orderBy(orderBy)
          .limit(input.limit)
          .offset(input.offset);

        return { tasks };
      } finally {
        await conn.end();
      }
    }),

  create: privateProcedure
    .input(
      z.object({
        id: z.string().optional(),
        title: z.string(),
        description: z.string().optional().default(''),
        status: z.enum(['todo', 'doing', 'done']).optional().default('todo'),
        priority: z.enum(['none', 'low', 'medium', 'high']).optional().default('none'),
        dueDate: z.string().datetime().optional().nullable(),
        folderId: z.string().optional().nullable(),
        reminderIdentifier: z.string().optional().nullable(),
        emailThreadId: z.string().optional().nullable(),
        eventId: z.string().optional().nullable(),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const id = input.id ?? crypto.randomUUID();
        const now = new Date();

        const [created] = await db
          .insert(task)
          .values({
            id,
            userId: ctx.sessionUser.id,
            title: input.title,
            description: input.description,
            status: input.status,
            priority: input.priority,
            dueDate: input.dueDate ? new Date(input.dueDate) : null,
            folderId: input.folderId ?? null,
            reminderIdentifier: input.reminderIdentifier ?? null,
            emailThreadId: input.emailThreadId ?? null,
            eventId: input.eventId ?? null,
            createdAt: now,
            updatedAt: now,
          })
          .returning();

        return { task: created };
      } finally {
        await conn.end();
      }
    }),

  update: privateProcedure
    .input(
      z.object({
        id: z.string(),
        data: z.object({
          title: z.string().optional(),
          description: z.string().optional(),
          status: z.enum(['todo', 'doing', 'done']).optional(),
          priority: z.enum(['none', 'low', 'medium', 'high']).optional(),
          dueDate: z.string().datetime().optional().nullable(),
          folderId: z.string().optional().nullable(),
          reminderIdentifier: z.string().optional().nullable(),
          emailThreadId: z.string().optional().nullable(),
          eventId: z.string().optional().nullable(),
        }),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const updateData: Record<string, unknown> = { updatedAt: new Date() };

        if (input.data.title !== undefined) updateData.title = input.data.title;
        if (input.data.description !== undefined) updateData.description = input.data.description;
        if (input.data.status !== undefined) updateData.status = input.data.status;
        if (input.data.priority !== undefined) updateData.priority = input.data.priority;
        if (input.data.dueDate !== undefined)
          updateData.dueDate = input.data.dueDate ? new Date(input.data.dueDate) : null;
        if (input.data.folderId !== undefined) updateData.folderId = input.data.folderId;
        if (input.data.reminderIdentifier !== undefined)
          updateData.reminderIdentifier = input.data.reminderIdentifier;
        if (input.data.emailThreadId !== undefined)
          updateData.emailThreadId = input.data.emailThreadId;
        if (input.data.eventId !== undefined) updateData.eventId = input.data.eventId;

        const [updated] = await db
          .update(task)
          .set(updateData)
          .where(and(eq(task.id, input.id), eq(task.userId, ctx.sessionUser.id)))
          .returning();

        if (!updated) {
          throw new Error('Task not found');
        }

        return { task: updated };
      } finally {
        await conn.end();
      }
    }),

  delete: privateProcedure.input(z.object({ id: z.string() })).mutation(async ({ ctx, input }) => {
    const { db, conn } = getDb();
    try {
      await db.delete(task).where(and(eq(task.id, input.id), eq(task.userId, ctx.sessionUser.id)));

      return { success: true };
    } finally {
      await conn.end();
    }
  }),

  // Batch sync endpoint — iOS sends offline mutations (upsert/delete)
  sync: privateProcedure
    .input(
      z.object({
        mutations: z.array(
          z.object({
            type: z.enum(['upsert', 'delete']),
            id: z.string(),
            payload: z
              .object({
                title: z.string().optional(),
                description: z.string().optional(),
                status: z.enum(['todo', 'doing', 'done']).optional(),
                priority: z.enum(['none', 'low', 'medium', 'high']).optional(),
                dueDate: z.string().datetime().optional().nullable(),
                folderId: z.string().optional().nullable(),
                reminderIdentifier: z.string().optional().nullable(),
                emailThreadId: z.string().optional().nullable(),
                eventId: z.string().optional().nullable(),
              })
              .optional(),
          }),
        ),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const syncedIds: string[] = [];
        const now = new Date();

        for (const mutation of input.mutations) {
          if (mutation.type === 'delete') {
            await db
              .delete(task)
              .where(and(eq(task.id, mutation.id), eq(task.userId, ctx.sessionUser.id)));
            syncedIds.push(mutation.id);
          } else if (mutation.type === 'upsert' && mutation.payload) {
            await db
              .insert(task)
              .values({
                id: mutation.id,
                userId: ctx.sessionUser.id,
                title: mutation.payload.title ?? 'Untitled',
                description: mutation.payload.description ?? '',
                status: mutation.payload.status ?? 'todo',
                priority: mutation.payload.priority ?? 'none',
                dueDate: mutation.payload.dueDate ? new Date(mutation.payload.dueDate) : null,
                folderId: mutation.payload.folderId ?? null,
                reminderIdentifier: mutation.payload.reminderIdentifier ?? null,
                emailThreadId: mutation.payload.emailThreadId ?? null,
                eventId: mutation.payload.eventId ?? null,
                createdAt: now,
                updatedAt: now,
              })
              .onConflictDoUpdate({
                target: task.id,
                set: {
                  title: sql`EXCLUDED.title`,
                  description: sql`EXCLUDED.description`,
                  status: sql`EXCLUDED.status`,
                  priority: sql`EXCLUDED.priority`,
                  dueDate: sql`EXCLUDED.due_date`,
                  folderId: sql`EXCLUDED.folder_id`,
                  reminderIdentifier: sql`EXCLUDED.reminder_identifier`,
                  emailThreadId: sql`EXCLUDED.email_thread_id`,
                  eventId: sql`EXCLUDED.event_id`,
                  updatedAt: now,
                },
              });
            syncedIds.push(mutation.id);
          }
        }

        return { syncedIds };
      } finally {
        await conn.end();
      }
    }),
});

// ─── Folder Router ─────────────────────────────────────────────────────

const itemTypeEnum = z.enum(['email', 'event', 'doc']);

// Cross-type item shape returned by listContents and summary.recentItems.
type ContentItemType = 'task' | 'chat' | 'email' | 'event' | 'doc';
type ContentItem = {
  type: ContentItemType;
  id: string;
  title: string;
  subtitle?: string | null;
  sortAt: string; // ISO timestamp used to merge across sources
};

// Used by summary's per-folder breakdown.
type TypeBreakdown = {
  tasks: number;
  chats: number;
  emails: number;
  events: number;
  docs: number;
};

const emptyBreakdown = (): TypeBreakdown => ({ tasks: 0, chats: 0, emails: 0, events: 0, docs: 0 });

export const foldersRouter = router({
  list: privateProcedure.query(async ({ ctx }) => {
    const { db, conn } = getDb();
    try {
      const folders = await db
        .select()
        .from(taskFolder)
        .where(eq(taskFolder.userId, ctx.sessionUser.id))
        .orderBy(asc(taskFolder.position), asc(taskFolder.createdAt));

      return { folders };
    } finally {
      await conn.end();
    }
  }),

  create: privateProcedure
    .input(
      z.object({
        id: z.string().optional(),
        name: z.string(),
        color: z.string().optional().nullable(),
        icon: z.string().optional().nullable(),
        position: z.number().int().optional(),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const id = input.id ?? crypto.randomUUID();
        const now = new Date();

        const [created] = await db
          .insert(taskFolder)
          .values({
            id,
            userId: ctx.sessionUser.id,
            name: input.name,
            color: input.color ?? null,
            icon: input.icon ?? null,
            position: input.position ?? 0,
            createdAt: now,
            updatedAt: now,
          })
          .returning();

        return { folder: created };
      } finally {
        await conn.end();
      }
    }),

  update: privateProcedure
    .input(
      z.object({
        id: z.string(),
        name: z.string().optional(),
        color: z.string().optional().nullable(),
        icon: z.string().optional().nullable(),
        position: z.number().int().optional(),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const updateData: Record<string, unknown> = { updatedAt: new Date() };
        if (input.name !== undefined) updateData.name = input.name;
        if (input.color !== undefined) updateData.color = input.color;
        if (input.icon !== undefined) updateData.icon = input.icon;
        if (input.position !== undefined) updateData.position = input.position;

        const [updated] = await db
          .update(taskFolder)
          .set(updateData)
          .where(and(eq(taskFolder.id, input.id), eq(taskFolder.userId, ctx.sessionUser.id)))
          .returning();

        if (!updated) {
          throw new Error('Folder not found');
        }

        return { folder: updated };
      } finally {
        await conn.end();
      }
    }),

  delete: privateProcedure.input(z.object({ id: z.string() })).mutation(async ({ ctx, input }) => {
    const { db, conn } = getDb();
    try {
      // Tasks in this folder will have folderId set to null (onDelete: 'set null'),
      // AI conversations the same. folder_item rows cascade delete.
      await db
        .delete(taskFolder)
        .where(and(eq(taskFolder.id, input.id), eq(taskFolder.userId, ctx.sessionUser.id)));

      return { success: true };
    } finally {
      await conn.end();
    }
  }),

  // Custom ordering — sets position from index for the provided IDs.
  reorder: privateProcedure
    .input(z.object({ orderedIds: z.array(z.string()) }))
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const now = new Date();
        await Promise.all(
          input.orderedIds.map((id, idx) =>
            db
              .update(taskFolder)
              .set({ position: idx, updatedAt: now })
              .where(and(eq(taskFolder.id, id), eq(taskFolder.userId, ctx.sessionUser.id))),
          ),
        );
        return { success: true };
      } finally {
        await conn.end();
      }
    }),

  // Batch sync endpoint — iOS sends offline folder mutations (upsert/delete)
  sync: privateProcedure
    .input(
      z.object({
        mutations: z.array(
          z.discriminatedUnion('type', [
            z.object({
              type: z.literal('upsert'),
              id: z.string(),
              name: z.string(),
              color: z.string().nullable().optional(),
              icon: z.string().nullable().optional(),
              position: z.number().optional(),
            }),
            z.object({
              type: z.literal('delete'),
              id: z.string(),
            }),
          ])
        ),
      })
    )
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const syncedIds: string[] = [];

        for (const mutation of input.mutations) {
          if (mutation.type === 'upsert') {
            await db
              .insert(taskFolder)
              .values({
                id: mutation.id,
                userId: ctx.sessionUser.id,
                name: mutation.name,
                color: mutation.color ?? null,
                icon: mutation.icon ?? null,
                position: mutation.position ?? 0,
                createdAt: new Date(),
                updatedAt: new Date(),
              })
              .onConflictDoUpdate({
                target: taskFolder.id,
                set: {
                  name: mutation.name,
                  color: mutation.color ?? null,
                  icon: mutation.icon ?? null,
                  position: mutation.position ?? 0,
                  updatedAt: new Date(),
                },
              });
            syncedIds.push(mutation.id);
          } else {
            await db
              .delete(taskFolder)
              .where(
                and(
                  eq(taskFolder.id, mutation.id),
                  eq(taskFolder.userId, ctx.sessionUser.id)
                )
              );
            syncedIds.push(mutation.id);
          }
        }

        return { syncedIds };
      } finally {
        await conn.end();
      }
    }),

  // Add an email/event/doc bookmark to a folder. Tasks and chats use their own
  // folderId column instead — clients call tasks.update / ai.saveConversation.
  addItem: privateProcedure
    .input(
      z.object({
        folderId: z.string(),
        itemType: itemTypeEnum,
        itemId: z.string(),
        metadata: z.record(z.unknown()).optional(),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        // Verify folder belongs to user.
        const [folder] = await db
          .select({ id: taskFolder.id })
          .from(taskFolder)
          .where(and(eq(taskFolder.id, input.folderId), eq(taskFolder.userId, ctx.sessionUser.id)))
          .limit(1);
        if (!folder) throw new Error('Folder not found');

        const id = crypto.randomUUID();
        const [created] = await db
          .insert(folderItem)
          .values({
            id,
            folderId: input.folderId,
            userId: ctx.sessionUser.id,
            itemType: input.itemType,
            itemId: input.itemId,
            metadata: input.metadata ?? null,
            position: 0,
            createdAt: new Date(),
          })
          .onConflictDoUpdate({
            target: [folderItem.folderId, folderItem.itemType, folderItem.itemId],
            set: {
              metadata: sql`EXCLUDED.metadata`,
            },
          })
          .returning();

        return { item: created };
      } finally {
        await conn.end();
      }
    }),

  removeItem: privateProcedure
    .input(
      z.object({
        folderId: z.string(),
        itemType: itemTypeEnum,
        itemId: z.string(),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        await db
          .delete(folderItem)
          .where(
            and(
              eq(folderItem.folderId, input.folderId),
              eq(folderItem.itemType, input.itemType),
              eq(folderItem.itemId, input.itemId),
              eq(folderItem.userId, ctx.sessionUser.id),
            ),
          );
        return { success: true };
      } finally {
        await conn.end();
      }
    }),

  // Returns a unified, sorted feed of all items in a folder: tasks, chats, and
  // bookmarked emails/events/docs. Hydrates display data from cached metadata
  // for emails/events/docs (Gmail/Calendar live in external systems).
  listContents: privateProcedure
    .input(
      z.object({
        folderId: z.string(),
        types: z.array(z.enum(['task', 'chat', 'email', 'event', 'doc'])).optional(),
        limit: z.number().int().min(1).max(200).optional().default(100),
      }),
    )
    .query(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        // Confirm folder ownership before any reads.
        const [folder] = await db
          .select()
          .from(taskFolder)
          .where(and(eq(taskFolder.id, input.folderId), eq(taskFolder.userId, ctx.sessionUser.id)))
          .limit(1);
        if (!folder) throw new Error('Folder not found');

        const wantsType = (t: ContentItemType) => !input.types || input.types.includes(t);

        const items: ContentItem[] = [];

        if (wantsType('task')) {
          const rows = await db
            .select({
              id: task.id,
              title: task.title,
              status: task.status,
              updatedAt: task.updatedAt,
            })
            .from(task)
            .where(and(eq(task.folderId, input.folderId), eq(task.userId, ctx.sessionUser.id)))
            .orderBy(desc(task.updatedAt))
            .limit(input.limit);
          for (const r of rows) {
            items.push({
              type: 'task',
              id: r.id,
              title: r.title,
              subtitle: r.status,
              sortAt: r.updatedAt.toISOString(),
            });
          }
        }

        if (wantsType('chat')) {
          const rows = await db
            .select({
              id: aiConversation.id,
              title: aiConversation.title,
              updatedAt: aiConversation.updatedAt,
            })
            .from(aiConversation)
            .where(
              and(
                eq(aiConversation.folderId, input.folderId),
                eq(aiConversation.userId, ctx.sessionUser.id),
              ),
            )
            .orderBy(desc(aiConversation.updatedAt))
            .limit(input.limit);
          for (const r of rows) {
            items.push({
              type: 'chat',
              id: r.id,
              title: r.title || 'Untitled chat',
              sortAt: r.updatedAt.toISOString(),
            });
          }
        }

        const polyTypes = (['email', 'event', 'doc'] as const).filter((t) => wantsType(t));
        if (polyTypes.length > 0) {
          const rows = await db
            .select()
            .from(folderItem)
            .where(
              and(
                eq(folderItem.folderId, input.folderId),
                eq(folderItem.userId, ctx.sessionUser.id),
                inArray(folderItem.itemType, polyTypes),
              ),
            )
            .orderBy(desc(folderItem.createdAt))
            .limit(input.limit);
          for (const r of rows) {
            const meta = (r.metadata ?? {}) as Record<string, unknown>;
            items.push({
              type: r.itemType as ContentItemType,
              id: r.itemId,
              title:
                (meta.title as string | undefined) ??
                (meta.subject as string | undefined) ??
                r.itemId,
              subtitle:
                (meta.subtitle as string | undefined) ??
                (meta.sender as string | undefined) ??
                null,
              sortAt: r.createdAt.toISOString(),
            });
          }
        }

        items.sort((a, b) => (a.sortAt < b.sortAt ? 1 : -1));
        return { items: items.slice(0, input.limit), folder };
      } finally {
        await conn.end();
      }
    }),

  // Powers the folder cards on Home + Tasks views.
  // Returns every folder with item counts, per-type breakdown, and 3 most recent items.
  summary: privateProcedure.query(async ({ ctx }) => {
    const { db, conn } = getDb();
    try {
      const folders = await db
        .select()
        .from(taskFolder)
        .where(eq(taskFolder.userId, ctx.sessionUser.id))
        .orderBy(asc(taskFolder.position), asc(taskFolder.createdAt));

      if (folders.length === 0) return { folders: [] };

      const folderIds = folders.map((f) => f.id);

      const taskRanked = db
        .select({
          folderId: task.folderId,
          id: task.id,
          title: task.title,
          updatedAt: task.updatedAt,
          rn: sql<number>`row_number() over (partition by ${task.folderId} order by ${task.updatedAt} desc)`.as(
            'rn',
          ),
        })
        .from(task)
        .where(
          and(
            eq(task.userId, ctx.sessionUser.id),
            inArray(task.folderId, folderIds),
            isNotNull(task.folderId),
          ),
        )
        .as('task_ranked');

      const chatRanked = db
        .select({
          folderId: aiConversation.folderId,
          id: aiConversation.id,
          title: aiConversation.title,
          updatedAt: aiConversation.updatedAt,
          rn: sql<number>`row_number() over (partition by ${aiConversation.folderId} order by ${aiConversation.updatedAt} desc)`.as(
            'rn',
          ),
        })
        .from(aiConversation)
        .where(
          and(
            eq(aiConversation.userId, ctx.sessionUser.id),
            inArray(aiConversation.folderId, folderIds),
            isNotNull(aiConversation.folderId),
          ),
        )
        .as('chat_ranked');

      const polyRanked = db
        .select({
          folderId: folderItem.folderId,
          itemType: folderItem.itemType,
          itemId: folderItem.itemId,
          metadata: folderItem.metadata,
          createdAt: folderItem.createdAt,
          rn: sql<number>`row_number() over (partition by ${folderItem.folderId} order by ${folderItem.createdAt} desc)`.as(
            'rn',
          ),
        })
        .from(folderItem)
        .where(
          and(eq(folderItem.userId, ctx.sessionUser.id), inArray(folderItem.folderId, folderIds)),
        )
        .as('poly_ranked');

      const [
        taskCountRows,
        chatCountRows,
        polyCountRows,
        taskRecentRows,
        chatRecentRows,
        polyRecentRows,
      ] = await Promise.all([
        db
          .select({
            folderId: task.folderId,
            count: sql<number>`count(*)::int`,
          })
          .from(task)
          .where(
            and(
              eq(task.userId, ctx.sessionUser.id),
              inArray(task.folderId, folderIds),
              isNotNull(task.folderId),
            ),
          )
          .groupBy(task.folderId),
        db
          .select({
            folderId: aiConversation.folderId,
            count: sql<number>`count(*)::int`,
          })
          .from(aiConversation)
          .where(
            and(
              eq(aiConversation.userId, ctx.sessionUser.id),
              inArray(aiConversation.folderId, folderIds),
              isNotNull(aiConversation.folderId),
            ),
          )
          .groupBy(aiConversation.folderId),
        db
          .select({
            folderId: folderItem.folderId,
            itemType: folderItem.itemType,
            count: sql<number>`count(*)::int`,
          })
          .from(folderItem)
          .where(
            and(eq(folderItem.userId, ctx.sessionUser.id), inArray(folderItem.folderId, folderIds)),
          )
          .groupBy(folderItem.folderId, folderItem.itemType),
        db
          .select({
            folderId: taskRanked.folderId,
            id: taskRanked.id,
            title: taskRanked.title,
            updatedAt: taskRanked.updatedAt,
          })
          .from(taskRanked)
          .where(lte(taskRanked.rn, 3)),
        db
          .select({
            folderId: chatRanked.folderId,
            id: chatRanked.id,
            title: chatRanked.title,
            updatedAt: chatRanked.updatedAt,
          })
          .from(chatRanked)
          .where(lte(chatRanked.rn, 3)),
        db
          .select({
            folderId: polyRanked.folderId,
            itemType: polyRanked.itemType,
            itemId: polyRanked.itemId,
            metadata: polyRanked.metadata,
            createdAt: polyRanked.createdAt,
          })
          .from(polyRanked)
          .where(lte(polyRanked.rn, 3)),
      ]);

      const byFolder = new Map<string, { breakdown: TypeBreakdown; items: ContentItem[] }>();
      for (const id of folderIds) byFolder.set(id, { breakdown: emptyBreakdown(), items: [] });

      for (const r of taskCountRows) {
        const fid = r.folderId;
        if (!fid) continue;
        const bucket = byFolder.get(fid);
        if (bucket) bucket.breakdown.tasks = r.count;
      }
      for (const r of chatCountRows) {
        const fid = r.folderId;
        if (!fid) continue;
        const bucket = byFolder.get(fid);
        if (bucket) bucket.breakdown.chats = r.count;
      }
      for (const r of polyCountRows) {
        const bucket = byFolder.get(r.folderId);
        if (!bucket) continue;
        const t = r.itemType as 'email' | 'event' | 'doc';
        if (t === 'email') bucket.breakdown.emails += r.count;
        else if (t === 'event') bucket.breakdown.events += r.count;
        else if (t === 'doc') bucket.breakdown.docs += r.count;
      }

      for (const r of taskRecentRows) {
        const fid = r.folderId;
        if (!fid) continue;
        const bucket = byFolder.get(fid);
        if (!bucket) continue;
        bucket.items.push({
          type: 'task',
          id: r.id,
          title: r.title,
          sortAt: r.updatedAt.toISOString(),
        });
      }
      for (const r of chatRecentRows) {
        const fid = r.folderId;
        if (!fid) continue;
        const bucket = byFolder.get(fid);
        if (!bucket) continue;
        bucket.items.push({
          type: 'chat',
          id: r.id,
          title: r.title || 'Untitled chat',
          sortAt: r.updatedAt.toISOString(),
        });
      }
      for (const r of polyRecentRows) {
        const bucket = byFolder.get(r.folderId);
        if (!bucket) continue;
        const t = r.itemType as 'email' | 'event' | 'doc';
        const meta = (r.metadata ?? {}) as Record<string, unknown>;
        bucket.items.push({
          type: t,
          id: r.itemId,
          title:
            (meta.title as string | undefined) ?? (meta.subject as string | undefined) ?? r.itemId,
          subtitle:
            (meta.subtitle as string | undefined) ?? (meta.sender as string | undefined) ?? null,
          sortAt: r.createdAt.toISOString(),
        });
      }

      const result = folders.map((f) => {
        const bucket = byFolder.get(f.id)!;
        const breakdown = bucket.breakdown;
        const itemCount =
          breakdown.tasks + breakdown.chats + breakdown.emails + breakdown.events + breakdown.docs;
        const recentItems = bucket.items.sort((a, b) => (a.sortAt < b.sortAt ? 1 : -1)).slice(0, 3);
        return { folder: f, itemCount, breakdown, recentItems };
      });

      return { folders: result };
    } finally {
      await conn.end();
    }
  }),
});
