import { task, taskFolder } from '../../db/schema';
import { privateProcedure, router } from '../trpc';
import { getContext } from 'hono/context-storage';
import type { HonoContext } from '../../ctx';
import { createDb } from '../../db';
import { eq, and, desc, asc, like, sql } from 'drizzle-orm';
import { env } from '../../env';
import { z } from 'zod';

// Helper to get a direct Drizzle DB connection
const getDb = () => createDb(env.HYPERDRIVE.connectionString);

// ─── Task Router ───────────────────────────────────────────────────────

export const tasksRouter = router({
  list: privateProcedure
    .input(
      z.object({
        folderId: z.string().optional(),
        status: z.enum(['todo', 'doing', 'done']).optional(),
        search: z.string().optional(),
        sortBy: z.enum(['newest', 'oldest', 'priority']).optional().default('newest'),
        limit: z.number().optional().default(100),
        offset: z.number().optional().default(0),
      }).optional().default({}),
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

        const orderBy = input.sortBy === 'oldest'
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
        if (input.data.dueDate !== undefined) updateData.dueDate = input.data.dueDate ? new Date(input.data.dueDate) : null;
        if (input.data.folderId !== undefined) updateData.folderId = input.data.folderId;
        if (input.data.reminderIdentifier !== undefined) updateData.reminderIdentifier = input.data.reminderIdentifier;

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

  delete: privateProcedure
    .input(z.object({ id: z.string() }))
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        await db
          .delete(task)
          .where(and(eq(task.id, input.id), eq(task.userId, ctx.sessionUser.id)));

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
            payload: z.object({
              title: z.string().optional(),
              description: z.string().optional(),
              status: z.enum(['todo', 'doing', 'done']).optional(),
              priority: z.enum(['none', 'low', 'medium', 'high']).optional(),
              dueDate: z.string().datetime().optional().nullable(),
              folderId: z.string().optional().nullable(),
              reminderIdentifier: z.string().optional().nullable(),
            }).optional(),
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

export const foldersRouter = router({
  list: privateProcedure.query(async ({ ctx }) => {
    const { db, conn } = getDb();
    try {
      const folders = await db
        .select()
        .from(taskFolder)
        .where(eq(taskFolder.userId, ctx.sessionUser.id))
        .orderBy(asc(taskFolder.createdAt));

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
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const id = input.id ?? crypto.randomUUID();

        const [created] = await db
          .insert(taskFolder)
          .values({
            id,
            userId: ctx.sessionUser.id,
            name: input.name,
            createdAt: new Date(),
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
        name: z.string(),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const [updated] = await db
          .update(taskFolder)
          .set({ name: input.name })
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

  delete: privateProcedure
    .input(z.object({ id: z.string() }))
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        // Tasks in this folder will have folderId set to null (onDelete: 'set null')
        await db
          .delete(taskFolder)
          .where(and(eq(taskFolder.id, input.id), eq(taskFolder.userId, ctx.sessionUser.id)));

        return { success: true };
      } finally {
        await conn.end();
      }
    }),
});
